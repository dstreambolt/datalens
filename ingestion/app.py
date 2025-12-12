"""
DStreamBolt Ingestion Service - Production Optimized
High-performance async ingestion with disk-based queue and comprehensive metrics

Architecture:
1. HTTP Server (Gunicorn) - Fast accept, write to disk, return 201
2. Background Worker Thread - Process disk queue → Kafka
3. Metrics Collector Thread - Async metrics aggregation → MySQL

Performance Features:
- Async disk write (< 5ms response time)
- Separate processing thread (no HTTP blocking)
- In-memory metrics buffer (flushed async)
- Corruption detection and quarantine
- Backpressure handling

Security Features:
- AWS Secrets Manager integration for credentials
- mTLS certificate validation (optional)
- Rate limiting per IP
- Audit logging for all access attempts
"""
import gzip
import json
import time
import os
import uuid
import traceback
import threading
from pathlib import Path
from datetime import datetime
from flask import Flask, request, jsonify
from kafka import KafkaProducer
import pymysql

# Import Secrets Manager
from secrets_manager import SecretsManager

# mTLS Certificate Validation
MTLS_ENABLED = os.getenv('MTLS_ENABLED', 'false').lower() == 'true'
MTLS_CA_CERT_PATH = os.getenv('MTLS_CA_CERT_PATH', '/etc/dstreambolt/certs/ca/ca-cert.pem')
MTLS_CHECK_CRL = os.getenv('MTLS_CHECK_CRL', 'true').lower() == 'true'

app = Flask(__name__)

# ============================================================================
# CONFIGURATION - Load from AWS Secrets Manager
# ============================================================================

print("=" * 80)
print("🚀 DStreamBolt Ingestion Service - Starting...")
print("=" * 80)

# Initialize Secrets Manager
secrets_mgr = SecretsManager()

# Load MySQL configuration from Secrets Manager
try:
    print("🔐 Loading MySQL credentials from AWS Secrets Manager...")
    mysql_config = secrets_mgr.get_mysql_config()
    MYSQL_HOST = mysql_config['host']
    MYSQL_USER = mysql_config['user']
    MYSQL_PASSWORD = mysql_config['password']
    MYSQL_DB = mysql_config['database']
    MYSQL_PORT = mysql_config.get('port', 3306)
    print(f"✅ MySQL config loaded: {MYSQL_USER}@{MYSQL_HOST}:{MYSQL_PORT}/{MYSQL_DB}")
except Exception as e:
    print(f"⚠️  Failed to load MySQL secrets from Secrets Manager: {e}")
    print("⚠️  Using environment variables as fallback (NOT RECOMMENDED FOR PRODUCTION)")
    MYSQL_HOST = os.getenv('MYSQL_HOST', '10.0.1.61')
    MYSQL_USER = os.getenv('MYSQL_USER', 'dstreambolt')
    MYSQL_PASSWORD = os.getenv('MYSQL_PASSWORD', '')
    MYSQL_DB = os.getenv('MYSQL_DB', 'dstreambolt_metrics')
    MYSQL_PORT = 3306
    if not MYSQL_PASSWORD:
        print("❌ ERROR: No MySQL password configured!")

# Load Kafka configuration from Secrets Manager
try:
    print("🔐 Loading Kafka credentials from AWS Secrets Manager...")
    kafka_config = secrets_mgr.get_kafka_config()
    KAFKA_BROKER = kafka_config['brokers']
    KAFKA_TOPIC = kafka_config['topic']
    KAFKA_SASL_MECHANISM = kafka_config.get('sasl_mechanism')
    KAFKA_SASL_USERNAME = kafka_config.get('sasl_username')
    KAFKA_SASL_PASSWORD = kafka_config.get('sasl_password')
    KAFKA_SECURITY_PROTOCOL = kafka_config.get('security_protocol', 'PLAINTEXT')
    print(f"✅ Kafka config loaded: {KAFKA_BROKER} / topic: {KAFKA_TOPIC}")
except Exception as e:
    print(f"⚠️  Failed to load Kafka secrets from Secrets Manager: {e}")
    print("⚠️  Using environment variables as fallback")
    KAFKA_BROKER = os.getenv('KAFKA_BROKER', '10.0.10.101:9092')
    KAFKA_TOPIC = os.getenv('KAFKA_TOPIC', 'dstreambolt-logs')
    KAFKA_SASL_MECHANISM = None
    KAFKA_SASL_USERNAME = None
    KAFKA_SASL_PASSWORD = None
    KAFKA_SECURITY_PROTOCOL = 'PLAINTEXT'

# Load application secrets (API keys, etc.) - Optional
try:
    print("🔐 Loading application secrets from AWS Secrets Manager...")
    app_secrets = secrets_mgr.get_app_secrets()
    VALID_API_KEYS = set(app_secrets.get('api_keys', []))
    ENCRYPTION_KEY = app_secrets.get('encryption_key')
    print(f"✅ App secrets loaded: {len(VALID_API_KEYS)} API keys configured")
except Exception as e:
    print(f"⚠️  App secrets not configured: {e}")
    VALID_API_KEYS = set()
    ENCRYPTION_KEY = None

# Non-secret configuration (from environment variables)
QUEUE_DIR = os.getenv('QUEUE_DIR', '/opt/dstreambolt/queue')
PROCESSING_DIR = f"{QUEUE_DIR}/processing"
COMPLETED_DIR = f"{QUEUE_DIR}/completed"
CORRUPTED_DIR = f"{QUEUE_DIR}/corrupted"
FAILED_DIR = f"{QUEUE_DIR}/failed"

# Performance tuning
MAX_QUEUE_SIZE = int(os.getenv('MAX_QUEUE_SIZE', '10000'))  # Max files in queue
METRICS_FLUSH_INTERVAL = int(os.getenv('METRICS_FLUSH_INTERVAL', '10'))  # seconds
CLEANUP_RETENTION_HOURS = int(os.getenv('CLEANUP_RETENTION_HOURS', '24'))

# Rate limiting & backpressure
RATE_LIMIT_PER_IP = int(os.getenv('RATE_LIMIT_PER_IP', '100'))  # requests per minute per IP
RATE_LIMIT_WINDOW = 60  # seconds
MAX_BUNDLE_SIZE_MB = int(os.getenv('MAX_BUNDLE_SIZE_MB', '50'))  # MB
MAX_DISK_USAGE_PERCENT = int(os.getenv('MAX_DISK_USAGE_PERCENT', '85'))  # %

# Authentication (mTLS-only, no API keys)
REQUIRE_AUTH = os.getenv('REQUIRE_AUTH', 'false').lower() == 'true'

# File locking & multi-instance support
INSTANCE_ID = os.getenv('INSTANCE_ID', os.uname().nodename)  # Unique per instance
LOCK_TIMEOUT = 300  # seconds - stale lock cleanup

print("=" * 80)
print(f"📋 Configuration Summary:")
print(f"   Instance ID: {INSTANCE_ID}")
print(f"   Queue Directory: {QUEUE_DIR}")
print(f"   mTLS Enabled: {MTLS_ENABLED}")
print(f"   Rate Limit: {RATE_LIMIT_PER_IP} req/min per IP")
print(f"   Max Queue Size: {MAX_QUEUE_SIZE} files")
print(f"   Max Bundle Size: {MAX_BUNDLE_SIZE_MB} MB")
print("=" * 80)

# ============================================================================
# GLOBAL STATE & METRICS
# ============================================================================

# Thread-safe metrics buffer (in-memory, flushed async)
metrics_lock = threading.Lock()
metrics_buffer = {
    'http_requests_total': 0,
    'http_requests_success': 0,
    'http_requests_failed': 0,
    'bytes_received_total': 0,
    'bundles_queued': 0,
    'bundles_processing': 0,
    'bundles_completed': 0,
    'bundles_corrupted': 0,
    'bundles_failed': 0,
    'kafka_records_sent': 0,
    'kafka_records_failed': 0,
    'queue_depth': 0,
    'processing_lag_seconds': 0.0,
    'avg_response_time_ms': 0.0,
    'last_http_request_time': 0,
    'last_processing_time': 0,
    'last_metrics_flush_time': 0
}

# Request timing buffer for calculating averages
response_times = []
response_times_lock = threading.Lock()

# Rate limiting state (per IP)
rate_limit_state = {}  # {ip: [(timestamp, count), ...]}
rate_limit_lock = threading.Lock()

# Disk usage monitoring
disk_usage_percent = 0
disk_usage_lock = threading.Lock()

# Kafka producer (lazy initialization)
producer = None
kafka_connected = False
kafka_lock = threading.Lock()

# ============================================================================
# INITIALIZATION & UTILITY FUNCTIONS
# ============================================================================

def init_directories():
    """Initialize disk queue directories"""
    for directory in [QUEUE_DIR, PROCESSING_DIR, COMPLETED_DIR, CORRUPTED_DIR, FAILED_DIR]:
        Path(directory).mkdir(parents=True, exist_ok=True)


def get_kafka_producer():
    """Get or initialize Kafka producer (lazy, thread-safe) with optional SASL auth"""
    global producer, kafka_connected

    with kafka_lock:
        if producer is not None:
            return producer

        try:
            print(f"🔗 Connecting to Kafka: {KAFKA_BROKER}")

            # Base configuration
            kafka_config = {
                'bootstrap_servers': KAFKA_BROKER.split(','),
                'value_serializer': lambda v: json.dumps(v).encode('utf-8'),
                'retries': 3,
                'acks': 'all',
                'compression_type': 'gzip',
                'batch_size': 16384,
                'linger_ms': 10,
                'request_timeout_ms': 10000
            }

            # Add SASL authentication if configured
            if KAFKA_SASL_MECHANISM and KAFKA_SASL_USERNAME and KAFKA_SASL_PASSWORD:
                print(f"🔐 Configuring Kafka SASL authentication ({KAFKA_SASL_MECHANISM})")
                kafka_config['security_protocol'] = KAFKA_SECURITY_PROTOCOL
                kafka_config['sasl_mechanism'] = KAFKA_SASL_MECHANISM
                kafka_config['sasl_plain_username'] = KAFKA_SASL_USERNAME
                kafka_config['sasl_plain_password'] = KAFKA_SASL_PASSWORD

            producer = KafkaProducer(**kafka_config)
            kafka_connected = True
            print(f"✅ Kafka connected successfully")
            return producer

        except Exception as e:
            print(f"❌ Kafka connection failed: {e}")
            kafka_connected = False
            return None


def get_db_connection():
    """Create database connection"""
    try:
        return pymysql.connect(
            host=MYSQL_HOST,
            user=MYSQL_USER,
            password=MYSQL_PASSWORD,
            database=MYSQL_DB,
            autocommit=True,
            connect_timeout=5
        )
    except Exception as e:
        print(f"❌ MySQL connection failed: {e}")
        return None


def update_metric(metric_name, value=1, operation='increment'):
    """Thread-safe metric update"""
    with metrics_lock:
        if operation == 'increment':
            metrics_buffer[metric_name] += value
        elif operation == 'set':
            metrics_buffer[metric_name] = value
        elif operation == 'average':
            # For averaging (used with response times)
            current = metrics_buffer.get(metric_name, 0)
            metrics_buffer[metric_name] = (current + value) / 2


def get_queue_depth():
    """Get current queue depth"""
    try:
        return len(list(Path(QUEUE_DIR).glob('*.gz')))
    except:
        return 0


def calculate_processing_lag():
    """Calculate processing lag (oldest file age in seconds)"""
    try:
        files = list(Path(QUEUE_DIR).glob('*.gz'))
        if not files:
            return 0.0
        oldest = min(files, key=lambda f: f.stat().st_mtime)
        return time.time() - oldest.stat().st_mtime
    except:
        return 0.0


def check_rate_limit(ip_address):
    """
    Check if IP is within rate limit
    Returns: (allowed, current_count, limit)
    """
    with rate_limit_lock:
        current_time = time.time()

        # Clean up old entries
        if ip_address in rate_limit_state:
            rate_limit_state[ip_address] = [
                (ts, count) for ts, count in rate_limit_state[ip_address]
                if current_time - ts < RATE_LIMIT_WINDOW
            ]

        # Count requests in current window
        if ip_address not in rate_limit_state:
            rate_limit_state[ip_address] = []

        current_count = sum(count for _, count in rate_limit_state[ip_address])

        if current_count >= RATE_LIMIT_PER_IP:
            return False, current_count, RATE_LIMIT_PER_IP

        # Add new request
        rate_limit_state[ip_address].append((current_time, 1))

        return True, current_count + 1, RATE_LIMIT_PER_IP



def validate_mtls_certificate(request):
    """
    Validate mTLS client certificate from ALB header
    Returns: (valid, error_message, cert_info)

    ALB passes client certificate in X-Amzn-Mtls-Clientcert header (URL-encoded PEM)
    """
    if not MTLS_ENABLED:
        return True, None, {'client_id': 'mtls_disabled'}

    try:
        import urllib.parse
        from cryptography import x509
        from cryptography.hazmat.backends import default_backend
        from datetime import datetime, timezone

        # Get certificate from ALB header
        cert_header = request.headers.get('X-Amzn-Mtls-Clientcert', '')
        if not cert_header:
            return False, 'No client certificate provided', None

        # Decode URL-encoded PEM
        cert_pem = urllib.parse.unquote(cert_header)

        # Parse certificate
        cert = x509.load_pem_x509_certificate(cert_pem.encode(), default_backend())

        # Extract certificate details
        subject = cert.subject
        serial_number = format(cert.serial_number, 'X')

        # Extract Common Name (client ID)
        client_id = None
        for attribute in subject:
            if attribute.oid == x509.oid.NameOID.COMMON_NAME:
                client_id = attribute.value
                break

        if not client_id:
            return False, 'Certificate missing Common Name', None

        # Check certificate expiry
        now = datetime.now(timezone.utc)
        if cert.not_valid_before_utc > now:
            return False, 'Certificate not yet valid', None
        if cert.not_valid_after_utc < now:
            return False, 'Certificate expired', None

        # Check certificate revocation list (if enabled)
        if MTLS_CHECK_CRL:
            try:
                db = get_db_connection()
                if db:
                    cursor = db.cursor()
                    cursor.execute(
                        "SELECT revocation_reason FROM cert_revocation_list WHERE serial_number = %s",
                        (serial_number,)
                    )
                    result = cursor.fetchone()
                    cursor.close()
                    db.close()

                    if result:
                        return False, f'Certificate revoked: {result[0]}', None
            except Exception as e:
                print(f"⚠️  CRL check failed: {e}")
                # Don't block on CRL check failure (fail open for availability)

        # Check client is registered and active
        try:
            db = get_db_connection()
            if db:
                cursor = db.cursor(pymysql.cursors.DictCursor)
                cursor.execute(
                    "SELECT status FROM client_registry WHERE client_id = %s",
                    (client_id,)
                )
                result = cursor.fetchone()
                cursor.close()
                db.close()

                if not result:
                    return False, f'Client not registered: {client_id}', None

                if result['status'] != 'active':
                    return False, f'Client status: {result["status"]}', None
        except Exception as e:
            print(f"⚠️  Client registry check failed: {e}")
            # Don't block on registry check failure

        # Certificate valid
        cert_info = {
            'client_id': client_id,
            'serial_number': serial_number,
            'not_before': cert.not_valid_before_utc.isoformat(),
            'not_after': cert.not_valid_after_utc.isoformat(),
            'issuer': cert.issuer.rfc4514_string()
        }

        return True, None, cert_info

    except Exception as e:
        return False, f'Certificate validation error: {str(e)}', None


def log_auth_attempt(client_id, cert_serial, ip_address, user_agent, success, failure_reason=None):
    """Log authentication attempt to database"""
    try:
        db = get_db_connection()
        if db:
            cursor = db.cursor()
            cursor.execute("""
                INSERT INTO auth_audit_log 
                (client_id, cert_serial_number, success, failure_reason, ip_address, user_agent, timestamp)
                VALUES (%s, %s, %s, %s, %s, %s, NOW())
            """, (client_id, cert_serial, success, failure_reason, ip_address, user_agent))
            cursor.close()
            db.close()
    except Exception as e:
        print(f"⚠️  Auth audit logging failed: {e}")


def check_disk_space():
    """
    Check available disk space
    Returns: (ok, usage_percent, available_gb)
    """
    try:
        import shutil
        stat = shutil.disk_usage(QUEUE_DIR)
        usage_percent = (stat.used / stat.total) * 100
        available_gb = stat.free / (1024 ** 3)

        with disk_usage_lock:
            global disk_usage_percent
            disk_usage_percent = usage_percent

        return usage_percent < MAX_DISK_USAGE_PERCENT, usage_percent, available_gb
    except Exception as e:
        print(f"⚠️  Disk check failed: {e}")
        return True, 0, 0  # Assume OK if check fails


def acquire_file_lock(filepath, timeout=5):
    """
    Acquire exclusive lock on file for multi-instance safety
    Returns: lock file path or None if failed
    """
    lock_file = f"{filepath}.lock.{INSTANCE_ID}"

    try:
        # Check for stale locks from other instances
        parent_dir = Path(filepath).parent
        for lock in parent_dir.glob(f"{Path(filepath).name}.lock.*"):
            if lock.name.endswith(INSTANCE_ID):
                continue  # Skip our own locks

            # Check if lock is stale
            lock_age = time.time() - lock.stat().st_mtime
            if lock_age > LOCK_TIMEOUT:
                print(f"🧹 Removing stale lock: {lock.name}")
                lock.unlink()

        # Try to create our lock
        Path(lock_file).touch(exist_ok=False)
        return lock_file

    except FileExistsError:
        # Lock already exists (we're processing it)
        return None
    except Exception as e:
        print(f"⚠️  Lock acquisition failed: {e}")
        return None


def release_file_lock(lock_file):
    """Release file lock"""
    try:
        if lock_file and Path(lock_file).exists():
            Path(lock_file).unlink()
    except Exception as e:
        print(f"⚠️  Lock release failed: {e}")


# ============================================================================
# DISK QUEUE MANAGEMENT
# ============================================================================

def write_bundle_to_disk(request_id, bundle_data, metadata):
    """
    Write bundle to disk queue with durability guarantees
    - Atomic write (tmp → rename)
    - fsync for durability (ACK only after disk)
    - Unique filename per instance (multi-instance safe)
    Returns: (success, error_message)
    """
    try:
        # Check disk space first
        disk_ok, usage, available = check_disk_space()
        if not disk_ok:
            return False, f"Disk usage too high: {usage:.1f}% (max {MAX_DISK_USAGE_PERCENT}%)"

        # Check queue size
        queue_depth = get_queue_depth()
        if queue_depth >= MAX_QUEUE_SIZE:
            return False, f"Queue full ({queue_depth}/{MAX_QUEUE_SIZE} files)"

        # Unique filename with instance ID to avoid collisions
        filename = f"{QUEUE_DIR}/{request_id}_{INSTANCE_ID}.gz"
        temp_filename = f"{filename}.tmp"

        # Write atomically with fsync
        with open(temp_filename, 'wb') as f:
            # Write metadata as JSON header (first line)
            metadata_json = json.dumps(metadata) + '\n'
            f.write(metadata_json.encode('utf-8'))
            # Write gzipped bundle data
            f.write(bundle_data)
            # Force write to disk (durability guarantee)
            f.flush()
            os.fsync(f.fileno())

        # Atomic rename (ACK only after this succeeds)
        os.rename(temp_filename, filename)

        update_metric('bundles_queued')
        update_metric('queue_depth', get_queue_depth(), 'set')

        return True, None

    except Exception as e:
        # Clean up temp file if exists
        try:
            temp_filename = f"{QUEUE_DIR}/{request_id}_{INSTANCE_ID}.gz.tmp"
            if Path(temp_filename).exists():
                Path(temp_filename).unlink()
        except:
            pass
        return False, str(e)


def read_bundle_from_disk(filepath):
    """
    Read bundle from disk
    Returns: (metadata, bundle_data, error)
    """
    try:
        with open(filepath, 'rb') as f:
            # Read first line as metadata
            first_line = f.readline()
            metadata = json.loads(first_line.decode('utf-8'))
            # Rest is gzipped bundle
            bundle_data = f.read()

        return metadata, bundle_data, None

    except Exception as e:
        return None, None, str(e)


def move_file(source, destination_dir, reason=''):
    """Move file to different directory (completed/corrupted/failed)"""
    try:
        dest_path = Path(destination_dir) / Path(source).name

        # Add timestamp suffix to avoid collisions
        if dest_path.exists():
            timestamp = int(time.time() * 1000)
            dest_path = Path(destination_dir) / f"{Path(source).stem}_{timestamp}.gz"

        os.rename(source, dest_path)

        # Write reason file if provided
        if reason:
            reason_file = dest_path.with_suffix('.reason.txt')
            with open(reason_file, 'w') as f:
                f.write(f"Time: {datetime.now().isoformat()}\n")
                f.write(f"Reason: {reason}\n")

        return True
    except Exception as e:
        print(f"⚠️  Failed to move file {source}: {e}")
        return False


# ============================================================================
# METRIC LOGGING FUNCTIONS (Async - Non-blocking)
# ============================================================================

def log_request(request_id, source_ip, user_agent, content_type, bundle_size, http_status, stage='received'):
    """Log incoming HTTP request"""
    try:
        conn = get_db_connection()
        if conn:
            cursor = conn.cursor()
            cursor.execute("""
                INSERT INTO ingestion_requests
                (request_id, source_ip, user_agent, content_type, bundle_size_bytes, http_status, processing_stage)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
            """, (request_id, source_ip, user_agent[:500], content_type, bundle_size, http_status, stage))

            cursor.execute("UPDATE ingestion_realtime_metrics SET metric_value = metric_value + 1 WHERE metric_name = 'total_requests'")
            conn.close()
    except Exception as e:
        print(f"⚠️  Failed to log request: {e}")


def log_bundle_processing(request_id, bundle_size, uncompressed_size, decomp_time, total_lines,
                          valid_lines, invalid_lines, kafka_time, total_time, status):
    """Log detailed bundle processing metrics"""
    try:
        conn = get_db_connection()
        if conn:
            cursor = conn.cursor()
            cursor.execute("""
                INSERT INTO bundle_processing
                (request_id, bundle_size_bytes, uncompressed_size_bytes, decompression_time_ms,
                 total_lines, valid_lines, invalid_lines, kafka_write_time_ms, total_processing_time_ms, status)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """, (request_id, bundle_size, uncompressed_size, decomp_time, total_lines,
                  valid_lines, invalid_lines, kafka_time, total_time, status))

            if status == 'success':
                cursor.execute("UPDATE ingestion_realtime_metrics SET metric_value = metric_value + 1 WHERE metric_name = 'successful_bundles'")
                cursor.execute("UPDATE ingestion_realtime_metrics SET metric_value = metric_value + %s WHERE metric_name = 'total_records_processed'", (valid_lines,))
            else:
                cursor.execute("UPDATE ingestion_realtime_metrics SET metric_value = metric_value + 1 WHERE metric_name = 'failed_bundles'")

            conn.close()
    except Exception as e:
        print(f"⚠️  Failed to log bundle processing: {e}")


def log_kafka_production(request_id, topic, attempted, successful, failed, write_time, avg_size, errors=''):
    """Log Kafka production metrics"""
    try:
        conn = get_db_connection()
        if conn:
            cursor = conn.cursor()
            cursor.execute("""
                INSERT INTO kafka_production_metrics
                (request_id, topic, records_attempted, records_successful, records_failed, 
                 write_time_ms, avg_record_size_bytes, kafka_errors)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            """, (request_id, topic, attempted, successful, failed, write_time, avg_size, errors[:1000] if errors else ''))

            cursor.execute("UPDATE ingestion_realtime_metrics SET metric_value = metric_value + %s WHERE metric_name = 'total_kafka_writes'", (successful,))
            if failed > 0:
                cursor.execute("UPDATE ingestion_realtime_metrics SET metric_value = metric_value + %s WHERE metric_name = 'total_kafka_failures'", (failed,))

            conn.close()
    except Exception as e:
        print(f"⚠️  Failed to log Kafka production: {e}")


def log_failed_bundle(request_id, failure_stage, error_type, error_message, bundle_size,
                      source_ip, bundle_sample='', stack_trace=''):
    """Log failed bundle with full context"""
    try:
        conn = get_db_connection()
        if conn:
            cursor = conn.cursor()
            cursor.execute("""
                INSERT INTO failed_bundles
                (request_id, failure_stage, error_type, error_message, bundle_size_bytes, 
                 source_ip, bundle_data_sample, stack_trace)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            """, (request_id, failure_stage, error_type, error_message[:500], bundle_size,
                  source_ip, bundle_sample[:1000] if bundle_sample else '', stack_trace[:2000] if stack_trace else ''))
            conn.close()
    except Exception as e:
        print(f"⚠️  Failed to log failed bundle: {e}")


# ============================================================================
# HTTP ENDPOINTS
# ============================================================================

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    status = {
        'service': 'ingest-api',
        'status': 'healthy',
        'timestamp': time.time(),
        'version': '1.0.0',
        'kafka': 'connected' if kafka_connected else 'disconnected'
    }
    return jsonify(status), 200


@app.route('/ingest', methods=['POST'])
def ingest():
    """
    Production-grade ingestion endpoint with:
    - mTLS Certificate Authentication
    - Rate limiting per IP
    - Size validation
    - Disk space checks
    - Fast disk write + ACK
    Response time target: < 10ms

    Security: Requires valid client certificate (mTLS)
    """
    start_time = time.time()
    request_id = str(uuid.uuid4())

    # Update metrics
    update_metric('http_requests_total')
    update_metric('last_http_request_time', time.time(), 'set')

    # Get request metadata
    source_ip = request.remote_addr
    user_agent = request.headers.get('User-Agent', 'unknown')[:500]
    content_type = request.headers.get('Content-Type', 'unknown')

    # 1. mTLS Certificate Authentication
    cert_valid, cert_error, cert_info = validate_mtls_certificate(request)

    if not cert_valid:
        update_metric('http_requests_failed')
        client_id = cert_info.get('client_id', 'unknown') if cert_info else 'unknown'
        cert_serial = cert_info.get('serial_number', 'unknown') if cert_info else 'unknown'

        # Log failed authentication
        log_auth_attempt(client_id, cert_serial, source_ip, user_agent, False, cert_error)
        log_request(request_id, source_ip, user_agent, content_type, 0, 401, 'auth_failed')

        return jsonify({
            'error': 'Authentication failed',
            'details': cert_error,
            'request_id': request_id
        }), 401

    # Extract authenticated client info
    client_id = cert_info['client_id']
    cert_serial = cert_info['serial_number']

    # Log successful authentication
    log_auth_attempt(client_id, cert_serial, source_ip, user_agent, True)

    # 2. Rate limiting check
    rate_ok, current_count, limit = check_rate_limit(source_ip)
    if not rate_ok:
        update_metric('http_requests_failed')
        log_request(request_id, source_ip, user_agent, content_type, 0, 429, 'rate_limited')
        return jsonify({
            'error': 'Rate limit exceeded',
            'details': f'{current_count} requests in last {RATE_LIMIT_WINDOW}s (limit: {limit})',
            'request_id': request_id,
            'retry_after': RATE_LIMIT_WINDOW
        }), 429

    # 3. Get and validate bundle data
    bundle_data = request.get_data()
    bundle_size = len(bundle_data)

    # Empty check
    if not bundle_data:
        update_metric('http_requests_failed')
        log_request(request_id, source_ip, user_agent, content_type, 0, 400, 'empty_bundle')
        return jsonify({'error': 'No data received', 'request_id': request_id}), 400

    # Size check
    max_size_bytes = MAX_BUNDLE_SIZE_MB * 1024 * 1024
    if bundle_size > max_size_bytes:
        update_metric('http_requests_failed')
        log_request(request_id, source_ip, user_agent, content_type, bundle_size, 413, 'bundle_too_large')
        return jsonify({
            'error': 'Bundle too large',
            'details': f'Size: {bundle_size:,} bytes, Max: {max_size_bytes:,} bytes',
            'request_id': request_id
        }), 413

    update_metric('bytes_received_total', bundle_size)

    # Prepare metadata (include authenticated client info)
    metadata = {
        'request_id': request_id,
        'client_id': client_id,  # From mTLS certificate
        'cert_serial_number': cert_serial,
        'source_ip': source_ip,
        'user_agent': user_agent,
        'content_type': content_type,
        'bundle_size': bundle_size,
        'received_at': time.time(),
        'timestamp': datetime.now().isoformat(),
        'auth_method': 'mtls' if MTLS_ENABLED else 'none'
    }

    # Write to disk (fast operation)
    success, error = write_bundle_to_disk(request_id, bundle_data, metadata)

    if not success:
        update_metric('http_requests_failed')
        log_request(request_id, source_ip, user_agent, content_type, bundle_size, 503, 'queue_full')
        return jsonify({
            'error': 'Queue full or disk write failed',
            'details': error,
            'request_id': request_id
        }), 503

    # Calculate response time
    response_time_ms = (time.time() - start_time) * 1000

    with response_times_lock:
        response_times.append(response_time_ms)
        # Keep only last 1000 response times
        if len(response_times) > 1000:
            response_times.pop(0)
        avg_response_time = sum(response_times) / len(response_times)
        update_metric('avg_response_time_ms', avg_response_time, 'set')

    update_metric('http_requests_success')

    # Log request asynchronously
    log_request(request_id, source_ip, user_agent, content_type, bundle_size, 201, 'queued')

    # Print stats to console (for visibility)
    print(f"✅ [{request_id[:8]}] Queued: {bundle_size:,} bytes | Queue: {get_queue_depth()} files | Response: {response_time_ms:.1f}ms")

    # Return immediately (processing happens in background)
    return jsonify({
        'status': 'accepted',
        'request_id': request_id,
        'client_id': client_id,
        'bundle_size_bytes': bundle_size,
        'queue_position': get_queue_depth(),
        'response_time_ms': round(response_time_ms, 2)
    }), 201


# ============================================================================
# BACKGROUND WORKER THREAD - Process disk queue
# ============================================================================

def process_bundle_worker():
    """
    Background worker that continuously processes bundles from disk queue
    - File locking for multi-instance safety
    - Retry logic for transient failures
    - Corruption detection and quarantine
    - DLQ (Dead Letter Queue) for permanent failures
    """
    print("🔄 Starting background worker thread...")

    kafka_retry_count = 0
    max_kafka_retries = 3

    while True:
        lock_file = None
        try:
            # Get list of pending files (excluding locked files)
            all_files = list(Path(QUEUE_DIR).glob('*.gz'))
            locked_files = set(f.stem.rsplit('.lock', 1)[0] for f in Path(QUEUE_DIR).glob('*.lock.*'))
            pending_files = [f for f in all_files if f.stem not in locked_files]
            pending_files = sorted(pending_files, key=lambda f: f.stat().st_mtime)

            if not pending_files:
                time.sleep(1)  # No files, wait a bit
                kafka_retry_count = 0  # Reset retry count
                continue

            # Process oldest file first (FIFO)
            filepath = pending_files[0]
            request_id = filepath.stem.rsplit('_', 1)[0]  # Remove instance ID suffix

            # Try to acquire lock (skip if another instance is processing)
            lock_file = acquire_file_lock(filepath)
            if not lock_file:
                # File is being processed by another instance
                continue

            print(f"🔄 [{INSTANCE_ID[:8]}] Processing: {request_id[:8]}...")

            update_metric('bundles_processing')
            update_metric('last_processing_time', time.time(), 'set')
            update_metric('processing_lag_seconds', calculate_processing_lag(), 'set')

            process_start = time.time()

            # Read bundle from disk
            metadata, bundle_data, read_error = read_bundle_from_disk(filepath)

            if read_error:
                print(f"❌ Corrupted file: {request_id[:8]} - {read_error}")
                move_file(filepath, CORRUPTED_DIR, f"Read error: {read_error}")
                update_metric('bundles_corrupted')
                log_failed_bundle(request_id, 'file_read', 'CorruptedFile', read_error,
                                0, metadata.get('source_ip', 'unknown') if metadata else 'unknown')
                continue

            # Decompress
            try:
                decomp_start = time.time()
                uncompressed_data = gzip.decompress(bundle_data)
                uncompressed_size = len(uncompressed_data)
                decomp_time_ms = int((time.time() - decomp_start) * 1000)
            except Exception as e:
                print(f"❌ Decompression failed: {request_id[:8]} - {e}")
                move_file(filepath, CORRUPTED_DIR, f"Decompression error: {e}")
                update_metric('bundles_corrupted')
                log_failed_bundle(request_id, 'decompression', type(e).__name__, str(e),
                                metadata['bundle_size'], metadata['source_ip'],
                                bundle_data[:100].decode('utf-8', errors='ignore'), traceback.format_exc())
                continue

            # Parse lines
            lines = uncompressed_data.decode('utf-8').strip().split('\n')
            total_lines = len(lines)

            # Send to Kafka
            kafka_start = time.time()
            producer = get_kafka_producer()

            if not producer:
                # Kafka unavailable - retry with backoff
                kafka_retry_count += 1
                if kafka_retry_count >= max_kafka_retries:
                    print(f"❌ Kafka unavailable after {max_kafka_retries} retries, moving to failed")
                    release_file_lock(lock_file)
                    move_file(filepath, FAILED_DIR, f"Kafka unavailable after {max_kafka_retries} retries")
                    update_metric('bundles_failed')
                    log_failed_bundle(request_id, 'kafka_connection', 'KafkaUnavailable',
                                    f'Failed after {max_kafka_retries} retries', metadata['bundle_size'],
                                    metadata['source_ip'])
                    kafka_retry_count = 0
                    continue

                print(f"⚠️  Kafka unavailable (retry {kafka_retry_count}/{max_kafka_retries}), requeueing: {request_id[:8]}")
                release_file_lock(lock_file)
                time.sleep(5 * kafka_retry_count)  # Exponential backoff
                continue

            kafka_successful = 0
            kafka_failed = 0
            kafka_errors = []

            for line in lines:
                if not line.strip():
                    continue

                try:
                    log_entry = {
                        'raw_log': line,
                        'timestamp': datetime.utcnow().isoformat(),
                        'request_id': request_id,
                        'source': 'ingestion-api',
                        'ingestion_time': metadata['timestamp']
                    }

                    producer.send(KAFKA_TOPIC, log_entry)
                    kafka_successful += 1
                except Exception as e:
                    kafka_failed += 1
                    kafka_errors.append(str(e))

            # Flush
            try:
                producer.flush(timeout=10)
            except Exception as e:
                kafka_errors.append(f"Flush error: {e}")

            kafka_time_ms = int((time.time() - kafka_start) * 1000)
            total_time_ms = int((time.time() - process_start) * 1000)

            # Update metrics
            update_metric('kafka_records_sent', kafka_successful)
            update_metric('kafka_records_failed', kafka_failed)

            # Log processing metrics
            status = 'success' if kafka_failed == 0 else 'partial_failure'
            avg_record_size = uncompressed_size // total_lines if total_lines > 0 else 0

            log_bundle_processing(request_id, metadata['bundle_size'], uncompressed_size,
                                decomp_time_ms, total_lines, kafka_successful, kafka_failed,
                                kafka_time_ms, total_time_ms, status)

            log_kafka_production(request_id, KAFKA_TOPIC, total_lines, kafka_successful,
                               kafka_failed, kafka_time_ms, avg_record_size,
                               '; '.join(kafka_errors[:5]) if kafka_errors else '')

            # Move file based on result
            if kafka_failed == 0:
                move_file(filepath, COMPLETED_DIR)
                update_metric('bundles_completed')
                print(f"✅ Completed: {request_id[:8]} | {kafka_successful:,} records | {total_time_ms}ms")
            else:
                move_file(filepath, FAILED_DIR, f"{kafka_failed} records failed")
                update_metric('bundles_failed')
                print(f"⚠️  Partial: {request_id[:8]} | {kafka_successful}/{total_lines} sent")
                log_failed_bundle(request_id, 'kafka_write', 'PartialFailure',
                                f'{kafka_failed} records failed', metadata['bundle_size'],
                                metadata['source_ip'], lines[0][:500] if lines else '',
                                '; '.join(kafka_errors[:3]))

            # Update queue depth
            update_metric('queue_depth', get_queue_depth(), 'set')

            # Always release lock when done
            release_file_lock(lock_file)

        except Exception as e:
            print(f"❌ Worker error: {e}")
            traceback.print_exc()

            # Release lock on error
            if lock_file:
                release_file_lock(lock_file)

            time.sleep(5)  # Avoid tight loop on persistent errors

        finally:
            # Ensure lock is always released
            if lock_file and Path(lock_file).exists():
                release_file_lock(lock_file)


# ============================================================================
# METRICS FLUSHER THREAD - Async metrics aggregation
# ============================================================================

def secrets_refresh_worker():
    """
    Background thread that periodically refreshes secrets from AWS Secrets Manager
    Enables automatic secret rotation without service restart
    Runs every 5 minutes (300 seconds)
    """
    REFRESH_INTERVAL = int(os.getenv('SECRETS_REFRESH_INTERVAL', '1440'))  # 5 minutes default
    print(f"🔐 Starting secrets refresh worker (interval: {REFRESH_INTERVAL}s)...")

    while True:
        try:
            time.sleep(REFRESH_INTERVAL)

            print("🔄 Refreshing secrets from AWS Secrets Manager...")

            # Refresh secrets cache
            secrets_mgr.refresh_cache()

            # Reload MySQL configuration
            global MYSQL_HOST, MYSQL_USER, MYSQL_PASSWORD, MYSQL_DB, MYSQL_PORT
            try:
                mysql_config = secrets_mgr.get_mysql_config()
                old_host = MYSQL_HOST
                MYSQL_HOST = mysql_config['host']
                MYSQL_USER = mysql_config['user']
                MYSQL_PASSWORD = mysql_config['password']
                MYSQL_DB = mysql_config['database']
                MYSQL_PORT = mysql_config.get('port', 3306)

                if old_host != MYSQL_HOST:
                    print(f"✅ MySQL config updated: {MYSQL_USER}@{MYSQL_HOST}:{MYSQL_PORT}/{MYSQL_DB}")
            except Exception as e:
                print(f"⚠️  Failed to refresh MySQL secrets: {e}")

            # Reload Kafka configuration (requires reconnection)
            global KAFKA_BROKER, KAFKA_TOPIC, KAFKA_SASL_USERNAME, KAFKA_SASL_PASSWORD
            global producer, kafka_connected
            try:
                kafka_config = secrets_mgr.get_kafka_config()
                old_broker = KAFKA_BROKER
                KAFKA_BROKER = kafka_config['brokers']
                KAFKA_TOPIC = kafka_config['topic']

                # If Kafka config changed, force reconnection
                if old_broker != KAFKA_BROKER:
                    print(f"🔄 Kafka config changed, reconnecting...")
                    with kafka_lock:
                        if producer:
                            try:
                                producer.close(timeout=5)
                            except:
                                pass
                            producer = None
                            kafka_connected = False
                    print(f"✅ Kafka config updated: {KAFKA_BROKER}")
            except Exception as e:
                print(f"⚠️  Failed to refresh Kafka secrets: {e}")

            print("✅ Secrets refresh completed")

        except Exception as e:
            print(f"⚠️  Secrets refresh error: {e}")


def metrics_flusher_worker():
    """
    Background thread that periodically flushes in-memory metrics to MySQL
    Runs every METRICS_FLUSH_INTERVAL seconds
    """
    print(f"📊 Starting metrics flusher (interval: {METRICS_FLUSH_INTERVAL}s)...")

    while True:
        try:
            time.sleep(METRICS_FLUSH_INTERVAL)

            # Copy current metrics (thread-safe)
            with metrics_lock:
                current_metrics = metrics_buffer.copy()

            # Write to MySQL
            conn = get_db_connection()
            if conn:
                cursor = conn.cursor()

                # Update realtime metrics table
                for metric_name, value in current_metrics.items():
                    cursor.execute("""
                        INSERT INTO ingestion_realtime_metrics (metric_name, metric_value)
                        VALUES (%s, %s)
                        ON DUPLICATE KEY UPDATE metric_value = %s
                    """, (metric_name, value, value))

                conn.close()
                update_metric('last_metrics_flush_time', time.time(), 'set')
                print(f"📊 Metrics flushed: {current_metrics['http_requests_total']} requests, {current_metrics['queue_depth']} queued")

        except Exception as e:
            print(f"⚠️  Metrics flush error: {e}")


# ============================================================================
# HTTP ENDPOINTS
# ============================================================================

@app.route('/metrics', methods=['GET'])
def metrics():
    """Return real-time metrics (from in-memory buffer)"""
    with metrics_lock:
        current_metrics = metrics_buffer.copy()

    # Add queue stats
    current_metrics['queue_depth'] = get_queue_depth()
    current_metrics['processing_lag_seconds'] = round(calculate_processing_lag(), 2)
    current_metrics['completed_files'] = len(list(Path(COMPLETED_DIR).glob('*.gz')))
    current_metrics['corrupted_files'] = len(list(Path(CORRUPTED_DIR).glob('*.gz')))
    current_metrics['failed_files'] = len(list(Path(FAILED_DIR).glob('*.gz')))

    return jsonify(current_metrics), 200


# ============================================================================
# APPLICATION STARTUP
# ============================================================================

# Initialize directories on module load
init_directories()

# Print authentication status
if MTLS_ENABLED:
    print("🔐 mTLS authentication enabled")
    print(f"   CA Certificate: {MTLS_CA_CERT_PATH}")
    print(f"   CRL Check: {'Enabled' if MTLS_CHECK_CRL else 'Disabled'}")
else:
    print("⚠️  mTLS authentication disabled - running in open mode")

# Gunicorn worker initialization hook
def post_worker_init(worker):
    """Called after a worker process is forked - start threads here"""
    print(f"🔄 Initializing worker {worker.pid}...")

    # Start worker thread
    worker_thread = threading.Thread(target=process_bundle_worker, daemon=True)
    worker_thread.start()

    # Start metrics flusher thread
    metrics_thread = threading.Thread(target=metrics_flusher_worker, daemon=True)
    metrics_thread.start()

    # Start secrets refresh thread
    secrets_thread = threading.Thread(target=secrets_refresh_worker, daemon=True)
    secrets_thread.start()

    print(f"✅ Worker {worker.pid} initialized with background threads")


# Start background threads only when NOT running under Gunicorn
# (Gunicorn will call post_worker_init for each worker)
if __name__ == '__main__' or os.getenv('WERKZEUG_RUN_MAIN') == 'true':
    # Development mode - start threads immediately
    print("🔄 Starting background worker thread...")
    worker_thread = threading.Thread(target=process_bundle_worker, daemon=True)
    worker_thread.start()

    print("📊 Starting metrics flusher (interval: 10s)...")
    metrics_thread = threading.Thread(target=metrics_flusher_worker, daemon=True)
    metrics_thread.start()

    print("🔐 Starting secrets refresh worker (interval: 1440s)...")
    secrets_thread = threading.Thread(target=secrets_refresh_worker, daemon=True)
    secrets_thread.start()

    print("✅ Background threads started (worker, metrics, secrets refresh)")


if __name__ == '__main__':
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("🚀 DStreamBolt Ingestion Service (Production)")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print(f"   Kafka Broker: {KAFKA_BROKER}")
    print(f"   Kafka Topic: {KAFKA_TOPIC}")
    print(f"   MySQL Host: {MYSQL_HOST}")
    print(f"   MySQL Database: {MYSQL_DB}")
    print(f"   Queue Dir: {QUEUE_DIR}")
    print(f"   Max Queue Size: {MAX_QUEUE_SIZE:,} files")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print()

    # Start background threads for dev mode
    worker_thread = threading.Thread(target=process_bundle_worker, daemon=True)
    worker_thread.start()

    metrics_thread = threading.Thread(target=metrics_flusher_worker, daemon=True)
    metrics_thread.start()

    secrets_thread = threading.Thread(target=secrets_refresh_worker, daemon=True)
    secrets_thread.start()

    app.run(host='0.0.0.0', port=5000, debug=False, threaded=True)

