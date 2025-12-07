"""
DStreamBolt Ingestion Service
Lightweight Flask application for receiving gzipped log bundles
"""
import gzip
import json
import time
import os
from datetime import datetime
from flask import Flask, request, jsonify
from kafka import KafkaProducer
import pymysql
from functools import wraps

app = Flask(__name__)

# Configuration from environment variables
MYSQL_HOST = os.getenv('MYSQL_HOST', 'localhost')
MYSQL_USER = os.getenv('MYSQL_USER', 'root')
MYSQL_PASSWORD = os.getenv('MYSQL_PASSWORD', '')
MYSQL_DB = os.getenv('MYSQL_DB', 'dstreambolt_metrics')

KAFKA_BROKER = os.getenv('KAFKA_BROKER', 'localhost:9092')
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


def init_db():
    """Initialize database schema"""
    time.sleep(30)  # Wait for MySQL to be ready
    conn = get_db_connection()
    if conn:
        cursor = conn.cursor()

        # Create database if not exists
        cursor.execute(f"""
            CREATE DATABASE IF NOT EXISTS {MYSQL_DB}
        """)
        cursor.execute(f"USE {MYSQL_DB}")

        # Create ingestion metrics table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS ingestion_metrics (
                id INT AUTO_INCREMENT PRIMARY KEY,
                timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                request_id VARCHAR(255),
                bundle_size_bytes INT,
                uncompressed_size_bytes INT,
                status VARCHAR(50),
                processing_time_ms INT,
                kafka_topic VARCHAR(255),
                error_message TEXT,
                INDEX(request_id),
                INDEX(timestamp),
                INDEX(status)
            )
        """)

        # Create bundle status table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS bundle_status (
                id INT AUTO_INCREMENT PRIMARY KEY,
                request_id VARCHAR(255) UNIQUE,
                status VARCHAR(50),
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                INDEX(request_id),
                INDEX(status)
            )
        """)

        conn.close()
        print("✅ Database initialized successfully")
    else:
        print("⚠️  Warning: Could not initialize database")


def log_metric(request_id, bundle_size, uncompressed_size, status, processing_time, kafka_topic='', error=''):
    """Log metrics to MySQL"""
    try:
        conn = get_db_connection()
        if conn:
            cursor = conn.cursor()
            cursor.execute("""
                INSERT INTO ingestion_metrics
                (request_id, bundle_size_bytes, uncompressed_size_bytes, status, processing_time_ms, kafka_topic, error_message)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
            """, (request_id, bundle_size, uncompressed_size, status, processing_time, kafka_topic, error))
            conn.close()
    except Exception as e:
        print(f"⚠️  Failed to log metric: {e}")


def update_bundle_status(request_id, status):
    """Update bundle processing status"""
    try:
        conn = get_db_connection()
        if conn:
            cursor = conn.cursor()
            cursor.execute("""
                INSERT INTO bundle_status (request_id, status)
                VALUES (%s, %s)
                ON DUPLICATE KEY UPDATE status=%s, updated_at=CURRENT_TIMESTAMP
            """, (request_id, status, status))
            conn.close()
    except Exception as e:
        print(f"⚠️  Failed to update bundle status: {e}")


@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    # Try to connect to Kafka if not already connected
    if not kafka_connected:
        get_kafka_producer()

    return jsonify({
        'status': 'healthy',
        'service': 'ingestion-api',
        'version': '1.0.0',
        'kafka': 'connected' if kafka_connected else 'disconnected',
        'timestamp': time.time()
    }), 200


@app.route('/ingest', methods=['POST'])
def ingest():
    """
    Ingestion endpoint
    Accepts gzipped log bundles, decompresses, and sends to Kafka
    """
    start_time = time.time()
    request_id = request.headers.get('X-Request-ID', f"req_{int(time.time() * 1000)}")

    try:
        # Get compressed data
        compressed_data = request.data
        bundle_size = len(compressed_data)

        if bundle_size == 0:
            return jsonify({'error': 'No data received'}), 400

        # Decompress
        try:
            uncompressed_data = gzip.decompress(compressed_data)
            uncompressed_size = len(uncompressed_data)
        except Exception as e:
            error_msg = f"Failed to decompress: {str(e)}"
            processing_time = int((time.time() - start_time) * 1000)
            log_metric(request_id, bundle_size, 0, 'failed', processing_time, error=error_msg)
            update_bundle_status(request_id, 'failed')
            return jsonify({'error': error_msg}), 400

        # Parse JSON logs
        try:
            logs = json.loads(uncompressed_data.decode('utf-8'))
            if not isinstance(logs, list):
                logs = [logs]
        except Exception as e:
            error_msg = f"Failed to parse JSON: {str(e)}"
            processing_time = int((time.time() - start_time) * 1000)
            log_metric(request_id, bundle_size, uncompressed_size, 'failed', processing_time, error=error_msg)
            update_bundle_status(request_id, 'failed')
            return jsonify({'error': error_msg}), 400

        # Send to Kafka (initialize producer if needed)
        kafka_producer = get_kafka_producer()

        if kafka_producer is None:
            error_msg = "Kafka producer not available"
            processing_time = int((time.time() - start_time) * 1000)
            log_metric(request_id, bundle_size, uncompressed_size, 'kafka_unavailable', processing_time, KAFKA_TOPIC, error_msg)
            update_bundle_status(request_id, 'kafka_unavailable')
            return jsonify({'error': error_msg}), 503

        try:
            for log_entry in logs:
                log_entry['request_id'] = request_id
                log_entry['ingestion_timestamp'] = datetime.utcnow().isoformat()
                kafka_producer.send(KAFKA_TOPIC, value=log_entry)
            kafka_producer.flush()
        except Exception as e:
            error_msg = f"Kafka send failed: {str(e)}"
            processing_time = int((time.time() - start_time) * 1000)
            log_metric(request_id, bundle_size, uncompressed_size, 'kafka_failed', processing_time, KAFKA_TOPIC, error_msg)
            update_bundle_status(request_id, 'kafka_failed')
            return jsonify({'error': error_msg}), 500

        # Log success metrics
        processing_time = int((time.time() - start_time) * 1000)
        log_metric(request_id, bundle_size, uncompressed_size, 'success', processing_time, KAFKA_TOPIC)
        update_bundle_status(request_id, 'success')

        return jsonify({
            'status': 'accepted',
            'request_id': request_id,
            'logs_count': len(logs),
            'processing_time_ms': processing_time
        }), 201

    except Exception as e:
        processing_time = int((time.time() - start_time) * 1000)
        error_msg = str(e)
        log_metric(request_id, 0, 0, 'error', processing_time, error=error_msg)
        update_bundle_status(request_id, 'error')
        return jsonify({'error': error_msg}), 500


if __name__ == '__main__':
    # Initialize database on startup
    init_db()

    # Run the application
    app.run(
        host='0.0.0.0',
        port=int(os.getenv('PORT', 5000)),
        debug=os.getenv('DEBUG', 'False').lower() == 'true'
    )

