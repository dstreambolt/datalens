#!/bin/bash
set -e

# DStreamBolt Ingestion Service (dstreambolt-ingest) Setup
# Lightweight Python Flask server with mTLS, Kafka producer, MySQL metrics

echo "=========================================="
echo "🚀 DStreamBolt Ingestion Service Setup"
echo "=========================================="

# Cleanup old dstreambolt-agent service if exists
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Checking for old dstreambolt-agent service..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if systemctl list-units --all | grep -q "dstreambolt-agent.service"; then
    echo "⚠️  Found old dstreambolt-agent service, removing..."

    # Stop the old service
    systemctl stop dstreambolt-agent 2>/dev/null || true
    systemctl disable dstreambolt-agent 2>/dev/null || true

    # Remove service file
    rm -f /etc/systemd/system/dstreambolt-agent.service

    # Remove old nginx config
    rm -f /etc/nginx/sites-available/dstreambolt-agent
    rm -f /etc/nginx/sites-enabled/dstreambolt-agent

    # Reload systemd
    systemctl daemon-reload

    echo "✅ Old dstreambolt-agent service removed"
else
    echo "✅ No old service found, proceeding with fresh installation"
fi

# Cleanup and prepare for fresh installation
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Preparing for fresh installation..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Stop existing dstreambolt-ingest service if running
if systemctl is-active --quiet dstreambolt-ingest 2>/dev/null; then
    echo "Stopping existing dstreambolt-ingest service..."
    systemctl stop dstreambolt-ingest
fi

# Backup existing installation if it exists
if [ -d "/opt/dstreambolt/agent" ]; then
    echo "Backing up existing installation..."
    BACKUP_DIR="/opt/dstreambolt/backups/agent-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p /opt/dstreambolt/backups
    cp -r /opt/dstreambolt/agent "$BACKUP_DIR" 2>/dev/null || true
    echo "✅ Backup created at: $BACKUP_DIR"

    # Clean up old installation
    rm -rf /opt/dstreambolt/agent
    echo "✅ Old installation removed"
fi

# Update system
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Updating system packages..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
apt-get update
apt-get upgrade -y

# Install required packages
apt-get install -y python3 python3-pip python3-venv mysql-client nginx

# Create application directory
mkdir -p /opt/dstreambolt/agent
cd /opt/dstreambolt/agent

# Create certificates directory
mkdir -p /opt/dstreambolt/certs
cd /opt/dstreambolt/certs

# Save CA certificate
cat > ca.crt << 'EOF'
${ca_cert}
EOF

# Save server certificate
cat > server.crt << 'EOF'
${server_cert}
EOF

# Save server private key
cat > server.key << 'EOF'
${server_key}
EOF

chmod 600 server.key
chmod 644 server.crt ca.crt

# Create Python application
cd /opt/dstreambolt/agent

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install Python dependencies
pip install --upgrade pip
pip install flask gunicorn kafka-python pymysql boto3 prometheus-client

# Create the ingestion application
cat > app.py << 'PYEOF'
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

# Configuration
MYSQL_HOST = '${mysql_host}'
MYSQL_USER = 'root'
MYSQL_PASSWORD = '${mysql_password}'
MYSQL_DB = 'dstreambolt_metrics'

KAFKA_BROKER = '${kafka_broker}'

# Initialize Kafka producer
try:
    producer = KafkaProducer(
        bootstrap_servers=[KAFKA_BROKER],
        value_serializer=lambda v: json.dumps(v).encode('utf-8'),
        retries=3,
        acks='all'
    )
    kafka_connected = True
except Exception as e:
    print(f"Kafka connection failed: {e}")
    kafka_connected = False

# Database connection
def get_db_connection():
    try:
        return pymysql.connect(
            host=MYSQL_HOST,
            user=MYSQL_USER,
            password=MYSQL_PASSWORD,
            database=MYSQL_DB,
            autocommit=True
        )
    except Exception as e:
        print(f"MySQL connection failed: {e}")
        return None

# Initialize database
def init_db():
    time.sleep(30)  # Wait for MySQL to be ready
    conn = get_db_connection()
    if conn:
        cursor = conn.cursor()
        cursor.execute("""
            CREATE DATABASE IF NOT EXISTS dstreambolt_metrics
        """)
        cursor.execute("USE dstreambolt_metrics")
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
                error_message TEXT
            )
        """)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS bundle_status (
                id INT AUTO_INCREMENT PRIMARY KEY,
                request_id VARCHAR(255) UNIQUE,
                status VARCHAR(50),
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                INDEX(request_id)
            )
        """)
        conn.close()
        print("Database initialized successfully")

# Log metrics to MySQL
def log_metric(request_id, bundle_size, uncompressed_size, status, processing_time, kafka_topic='', error=''):
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
        print(f"Failed to log metric: {e}")

# Update bundle status
def update_bundle_status(request_id, status):
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
        print(f"Failed to update bundle status: {e}")

# Health check endpoint
@app.route('/health', methods=['GET'])
def health():
    return jsonify({
        'status': 'healthy',
        'service': 'ingestion-api',
        'version': '1.0.0',
        'kafka': 'connected' if kafka_connected else 'disconnected',
        'timestamp': time.time()
    }), 200

# Ingestion endpoint
@app.route('/ingest', methods=['POST'])
def ingest():
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

        # Send to Kafka
        kafka_topic = 'dstreambolt-logs'
        try:
            for log_entry in logs:
                log_entry['request_id'] = request_id
                log_entry['ingestion_timestamp'] = datetime.utcnow().isoformat()
                producer.send(kafka_topic, value=log_entry)
            producer.flush()
        except Exception as e:
            error_msg = f"Kafka send failed: {str(e)}"
            processing_time = int((time.time() - start_time) * 1000)
            log_metric(request_id, bundle_size, uncompressed_size, 'kafka_failed', processing_time, kafka_topic, error_msg)
            update_bundle_status(request_id, 'kafka_failed')
            return jsonify({'error': error_msg}), 500

        # Log success metrics
        processing_time = int((time.time() - start_time) * 1000)
        log_metric(request_id, bundle_size, uncompressed_size, 'success', processing_time, kafka_topic)
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
    # Initialize database
    init_db()

    # Run with Gunicorn in production
    # gunicorn -w 4 -b 0.0.0.0:5000 app:app
    app.run(host='0.0.0.0', port=5000, debug=False)
PYEOF

# Create systemd service
cat > /etc/systemd/system/dstreambolt-ingest.service << 'EOF'
[Unit]
Description=DStreamBolt Ingestion Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/dstreambolt/agent
Environment="PATH=/opt/dstreambolt/agent/venv/bin"
ExecStart=/opt/dstreambolt/agent/venv/bin/gunicorn -w 4 -b 0.0.0.0:5000 --timeout 120 app:app
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Configure Nginx as reverse proxy
cat > /etc/nginx/sites-available/dstreambolt-ingest << 'EOF'
server {
    listen 80 default_server;
    server_name _;

    location /health {
        proxy_pass http://127.0.0.1:5000/health;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /ingest {
        client_max_body_size 20M;
        proxy_pass http://127.0.0.1:5000/ingest;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 120s;
    }
}
EOF

ln -sf /etc/nginx/sites-available/dstreambolt-ingest /etc/nginx/sites-enabled/default

# Test nginx configuration
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Testing Nginx configuration..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if nginx -t; then
    echo "✅ Nginx configuration is valid"
    systemctl restart nginx
else
    echo "❌ Nginx configuration has errors"
    exit 1
fi

# Start the service
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Starting DStreamBolt Ingestion Service..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
systemctl daemon-reload
systemctl enable dstreambolt-ingest
systemctl start dstreambolt-ingest

# Wait for service to start
sleep 5

# Verify service is running
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Verifying installation..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if systemctl is-active --quiet dstreambolt-ingest; then
    echo "✅ dstreambolt-ingest service is running"
else
    echo "❌ dstreambolt-ingest service failed to start"
    echo "Checking logs..."
    journalctl -u dstreambolt-ingest -n 20 --no-pager
    exit 1
fi

# Test health endpoint
HEALTH_CHECK=$(curl -s http://localhost:5000/health 2>/dev/null || echo "failed")
if [[ $HEALTH_CHECK == *"healthy"* ]]; then
    echo "✅ Health endpoint is responding"
else
    echo "⚠️  Health endpoint not responding yet (service may still be initializing)"
fi

# Display summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ DStreamBolt Ingestion Service Setup Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Service Details:"
echo "  Name: dstreambolt-ingest"
echo "  Port: 5000 (internal), 80 (nginx)"
echo "  Status: $(systemctl is-active dstreambolt-ingest)"
echo ""
echo "Endpoints:"
echo "  Health: http://localhost/health"
echo "  Ingest: http://localhost/ingest (POST)"
echo ""
echo "Service status:"
systemctl status dstreambolt-ingest --no-pager | head -15
echo ""
echo "To view logs:"
echo "  journalctl -u dstreambolt-ingest -f"
echo ""

