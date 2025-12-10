"""
DStreamBolt Ingestion Service - Optimized
Lightweight Flask application for receiving gzipped log bundles
Note: Run observability/setup_observability.sh to create required tables before starting
"""
import gzip
import json
import time
import os
import uuid
import traceback
from datetime import datetime
from flask import Flask, request, jsonify
from kafka import KafkaProducer
import pymysql

app = Flask(__name__)

# Configuration from environment variables
MYSQL_HOST = os.getenv('MYSQL_HOST', '10.0.1.61')
MYSQL_USER = os.getenv('MYSQL_USER', 'dstreambolt')
MYSQL_PASSWORD = os.getenv('MYSQL_PASSWORD', 'DStreamBolt2025!')
MYSQL_DB = os.getenv('MYSQL_DB', 'dstreambolt_metrics')

KAFKA_BROKER = os.getenv('KAFKA_BROKER', '10.0.10.101:9092')
KAFKA_TOPIC = os.getenv('KAFKA_TOPIC', 'dstreambolt-logs')

# Kafka producer (lazy initialization)
producer = None
kafka_connected = False
kafka_init_attempted = False

def get_kafka_producer():
    """Get or initialize Kafka producer (lazy loading)"""
    global producer, kafka_connected, kafka_init_attempted

    if kafka_init_attempted:
        return producer

    kafka_init_attempted = True

    try:
        print(f"🔗 Connecting to Kafka broker: {KAFKA_BROKER}")
        producer = KafkaProducer(
            bootstrap_servers=[KAFKA_BROKER],
            value_serializer=lambda v: json.dumps(v).encode('utf-8'),
            retries=3,
            acks='all',
            request_timeout_ms=5000,
            max_block_ms=5000,
            api_version_auto_timeout_ms=3000
        )
        kafka_connected = True
        print(f"✅ Connected to Kafka broker: {KAFKA_BROKER}")
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
            autocommit=True
        )
    except Exception as e:
        print(f"❌ MySQL connection failed: {e}")
        return None


# ============================================================================
# METRIC LOGGING FUNCTIONS
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
    Ingest gzipped log bundles and send to Kafka
    Captures comprehensive metrics at each stage
    """
    start_time = time.time()
    request_id = str(uuid.uuid4())

    # Get request metadata
    source_ip = request.remote_addr
    user_agent = request.headers.get('User-Agent', 'unknown')
    content_type = request.headers.get('Content-Type', 'unknown')
    bundle_data = request.get_data()
    bundle_size = len(bundle_data)

    # Log incoming request
    log_request(request_id, source_ip, user_agent, content_type, bundle_size, 0, 'received')

    # Validate request
    if not bundle_data:
        log_request(request_id, source_ip, user_agent, content_type, 0, 400, 'validation_failed')
        log_failed_bundle(request_id, 'validation', 'EmptyBundle', 'No data received', 0, source_ip)
        return jsonify({'error': 'No data received'}), 400

    try:
        # Stage 1: Decompression
        decomp_start = time.time()
        try:
            uncompressed_data = gzip.decompress(bundle_data)
            uncompressed_size = len(uncompressed_data)
            decomp_time = int((time.time() - decomp_start) * 1000)
        except Exception as e:
            error_msg = f"Decompression failed: {e}"
            log_request(request_id, source_ip, user_agent, content_type, bundle_size, 400, 'decompression_failed')
            log_failed_bundle(request_id, 'decompression', type(e).__name__, str(e), bundle_size, source_ip,
                            bundle_data[:100].decode('utf-8', errors='ignore'), traceback.format_exc())
            return jsonify({'error': error_msg}), 400

        # Stage 2: Parse lines
        lines = uncompressed_data.decode('utf-8').strip().split('\n')
        total_lines = len(lines)
        valid_lines = 0
        invalid_lines = 0

        # Stage 3: Write to Kafka
        kafka_start = time.time()
        producer = get_kafka_producer()

        if not producer:
            error_msg = "Kafka producer not available"
            log_request(request_id, source_ip, user_agent, content_type, bundle_size, 500, 'kafka_unavailable')
            log_failed_bundle(request_id, 'kafka_connection', 'KafkaUnavailable', error_msg, bundle_size, source_ip)
            return jsonify({'error': error_msg}), 500

        kafka_successful = 0
        kafka_failed = 0
        kafka_errors = []

        for line in lines:
            if not line.strip():
                invalid_lines += 1
                continue

            try:
                # Parse log line and create JSON message
                log_entry = {
                    'raw_log': line,
                    'timestamp': datetime.utcnow().isoformat(),
                    'request_id': request_id,
                    'source': 'ingestion-api'
                }

                producer.send(KAFKA_TOPIC, log_entry)
                kafka_successful += 1
                valid_lines += 1
            except Exception as e:
                kafka_failed += 1
                invalid_lines += 1
                kafka_errors.append(str(e))

        # Flush Kafka producer
        try:
            producer.flush(timeout=5)
        except Exception as e:
            kafka_errors.append(f"Flush error: {e}")

        kafka_time = int((time.time() - kafka_start) * 1000)
        total_time = int((time.time() - start_time) * 1000)

        # Calculate average record size
        avg_record_size = uncompressed_size // total_lines if total_lines > 0 else 0

        # Log all metrics
        status = 'success' if kafka_failed == 0 else 'partial_failure'

        log_request(request_id, source_ip, user_agent, content_type, bundle_size, 201, 'completed')
        log_bundle_processing(request_id, bundle_size, uncompressed_size, decomp_time,
                            total_lines, valid_lines, invalid_lines, kafka_time, total_time, status)
        log_kafka_production(request_id, KAFKA_TOPIC, total_lines, kafka_successful, kafka_failed,
                           kafka_time, avg_record_size, '; '.join(kafka_errors[:5]))

        # Log failures if any
        if kafka_failed > 0:
            log_failed_bundle(request_id, 'kafka_write', 'PartialFailure',
                            f'{kafka_failed} records failed to write',
                            bundle_size, source_ip, lines[0][:500] if lines else '',
                            '; '.join(kafka_errors[:3]))

        # Return success response
        response = {
            'status': 'accepted',
            'request_id': request_id,
            'bundle_size_bytes': bundle_size,
            'uncompressed_size_bytes': uncompressed_size,
            'total_lines': total_lines,
            'valid_lines': valid_lines,
            'invalid_lines': invalid_lines,
            'kafka_successful': kafka_successful,
            'kafka_failed': kafka_failed,
            'processing_time_ms': total_time
        }

        return jsonify(response), 201

    except Exception as e:
        # Catch-all error handler
        error_msg = f"Processing failed: {e}"
        total_time = int((time.time() - start_time) * 1000)

        log_request(request_id, source_ip, user_agent, content_type, bundle_size, 500, 'processing_failed')
        log_failed_bundle(request_id, 'processing', type(e).__name__, str(e),
                         bundle_size, source_ip, bundle_data[:100].decode('utf-8', errors='ignore'),
                         traceback.format_exc())

        return jsonify({'error': error_msg, 'request_id': request_id}), 500


@app.route('/metrics', methods=['GET'])
def metrics():
    """Return real-time metrics"""
    try:
        conn = get_db_connection()
        if conn:
            cursor = conn.cursor()
            cursor.execute("SELECT metric_name, metric_value FROM ingestion_realtime_metrics")
            rows = cursor.fetchall()
            conn.close()

            metrics_dict = {row[0]: row[1] for row in rows}
            return jsonify(metrics_dict), 200
        else:
            return jsonify({'error': 'Database unavailable'}), 500
    except Exception as e:
        return jsonify({'error': str(e)}), 500


if __name__ == '__main__':
    print("🚀 Starting DStreamBolt Ingestion Service (Optimized)")
    print(f"   Kafka Broker: {KAFKA_BROKER}")
    print(f"   Kafka Topic: {KAFKA_TOPIC}")
    print(f"   MySQL Host: {MYSQL_HOST}")
    print(f"   MySQL Database: {MYSQL_DB}")
    print("   Note: Tables must be created using observability/setup_observability.sh")
    print()

    app.run(host='0.0.0.0', port=5000, debug=False)

