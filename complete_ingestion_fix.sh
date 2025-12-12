#!/bin/bash
# Complete fix for ingestion service deployment and Kafka connectivity
# Run on INGESTION server

set -e

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║    Complete Ingestion Service Fix & Kafka Connection        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Find where service is actually running from
echo "1️⃣  Locating current deployment..."
WORKING_DIR=$(systemctl show dstreambolt-ingest -p WorkingDirectory --value 2>/dev/null)
echo "Service WorkingDirectory: ${WORKING_DIR:-not found}"

# Check actual deployment paths
DEPLOY_PATH=""
for path in /opt/dstreambolt/ingest /opt/dstreambolt/ingestion /opt/dstreambolt/agent; do
    if [ -d "$path" ] && [ -f "$path/app.py" ]; then
        DEPLOY_PATH="$path"
        echo "✅ Found deployment at: $DEPLOY_PATH"
        break
    fi
done

if [ -z "$DEPLOY_PATH" ]; then
    echo "❌ No deployment found! Service needs to be deployed first."
    echo ""
    echo "Deploy via Jenkins job: DStreamBolt-Deploy-Ingestion"
    exit 1
fi

# Check if venv exists
echo ""
echo "2️⃣  Checking Python environment..."
if [ ! -d "$DEPLOY_PATH/venv" ]; then
    echo "⚠️  Virtual environment not found, creating..."
    cd "$DEPLOY_PATH"
    python3 -m venv venv
    source venv/bin/activate
    pip install --upgrade pip
    pip install -r requirements.txt
    echo "✅ Virtual environment created"
else
    echo "✅ Virtual environment exists"
fi

# Ensure gunicorn config exists
if [ ! -f "$DEPLOY_PATH/gunicorn_config.py" ]; then
    echo "⚠️  Creating gunicorn config..."
    cat > "$DEPLOY_PATH/gunicorn_config.py" << 'GUNICORN_EOF'
# Gunicorn configuration for DStreamBolt Ingestion Service
bind = "0.0.0.0:5000"
workers = 4
worker_class = "sync"
timeout = 120
keepalive = 5
max_requests = 10000
max_requests_jitter = 100
accesslog = "-"
errorlog = "-"
loglevel = "info"
proc_name = "dstreambolt-ingest"

def post_worker_init(worker):
    """Initialize worker after fork - start background threads"""
    from app import post_worker_init as app_init
    app_init(worker)
GUNICORN_EOF
    echo "✅ Gunicorn config created"
fi

# Test Kafka connection with Python
echo ""
echo "3️⃣  Testing Kafka connection with Python..."
$DEPLOY_PATH/venv/bin/python3 << 'PYEOF'
from kafka import KafkaProducer
import json
import sys

try:
    print("Connecting to Kafka at 10.0.10.101:9092...")
    producer = KafkaProducer(
        bootstrap_servers=['10.0.10.101:9092'],
        value_serializer=lambda v: json.dumps(v).encode('utf-8'),
        request_timeout_ms=30000,
        api_version_auto_timeout_ms=10000
    )
    print("✅ Kafka connection successful!")

    # Test sending a message
    producer.send('dstreambolt-logs', {'test': 'connection', 'status': 'ok'})
    producer.flush()
    print("✅ Test message sent successfully")

    producer.close()
    sys.exit(0)
except Exception as e:
    print(f"❌ Kafka connection failed: {e}")
    sys.exit(1)
PYEOF

KAFKA_TEST=$?

if [ $KAFKA_TEST -ne 0 ]; then
    echo ""
    echo "❌ Python cannot connect to Kafka"
    echo ""
    echo "Check Kafka server:"
    echo "  1. Is Kafka running? systemctl status kafka"
    echo "  2. Check advertised.listeners: grep advertised.listeners /opt/kafka/config/server.properties"
    echo "  3. Restart Kafka: systemctl restart kafka"
    exit 1
fi

# Update service file if needed
echo ""
echo "4️⃣  Checking service configuration..."
SERVICE_FILE="/etc/systemd/system/dstreambolt-ingest.service"
if [ ! -f "$SERVICE_FILE" ]; then
    echo "⚠️  Service file not found, creating..."
    sudo tee $SERVICE_FILE > /dev/null << EOF
[Unit]
Description=DStreamBolt Ingestion Service
After=network.target

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=$DEPLOY_PATH
Environment="PATH=$DEPLOY_PATH/venv/bin"
ExecStart=$DEPLOY_PATH/venv/bin/gunicorn -c gunicorn_config.py app:app
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=dstreambolt-ingest
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable dstreambolt-ingest
    echo "✅ Service file created"
else
    # Update WorkingDirectory and ExecStart if they're wrong
    CURRENT_DIR=$(grep "^WorkingDirectory=" $SERVICE_FILE | cut -d= -f2)
    if [ "$CURRENT_DIR" != "$DEPLOY_PATH" ]; then
        echo "⚠️  Service file has wrong path, fixing..."
        sudo sed -i "s|^WorkingDirectory=.*|WorkingDirectory=$DEPLOY_PATH|" $SERVICE_FILE
        sudo sed -i "s|^Environment=\"PATH=.*|Environment=\"PATH=$DEPLOY_PATH/venv/bin\"|" $SERVICE_FILE
        sudo sed -i "s|^ExecStart=.*|ExecStart=$DEPLOY_PATH/venv/bin/gunicorn -c gunicorn_config.py app:app|" $SERVICE_FILE
        sudo systemctl daemon-reload
        echo "✅ Service file updated"
    else
        echo "✅ Service file is correct"
    fi
fi

# Restart service
echo ""
echo "5️⃣  Restarting ingestion service..."
sudo systemctl restart dstreambolt-ingest

echo "Waiting for service to start..."
sleep 10

if systemctl is-active --quiet dstreambolt-ingest; then
    echo "✅ Service is running"
else
    echo "❌ Service failed to start"
    sudo systemctl status dstreambolt-ingest --no-pager
    exit 1
fi

# Check Kafka connection in logs
echo ""
echo "6️⃣  Checking Kafka connection status..."
sleep 3

if sudo journalctl -u dstreambolt-ingest --since "15 seconds ago" | grep -q "Kafka connected successfully"; then
    echo "✅ Kafka connected successfully!"
else
    echo "⚠️  Checking connection status..."
    sudo journalctl -u dstreambolt-ingest --since "15 seconds ago" | grep -i kafka | tail -10
fi

# Test health endpoint
echo ""
echo "7️⃣  Testing health endpoint..."
HEALTH=$(curl -s http://localhost:5000/health 2>/dev/null)

if [ -z "$HEALTH" ]; then
    echo "❌ Health endpoint not responding"
    exit 1
fi

echo "$HEALTH" | python3 -m json.tool

KAFKA_STATUS=$(echo "$HEALTH" | python3 -c "import sys, json; print(json.load(sys.stdin).get('kafka', 'unknown'))" 2>/dev/null)

echo ""
if [ "$KAFKA_STATUS" = "connected" ]; then
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║               ✅ SUCCESS - Everything Working!               ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Ingestion service is running and connected to Kafka."
    echo ""
    echo "Test ingestion:"
    echo "  curl -X POST http://localhost:5000/ingest \\"
    echo "    -H 'Content-Type: application/gzip' \\"
    echo "    --data-binary @test.gz"
else
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║            ⚠️  Service Running but Kafka Disconnected        ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "The service is running but cannot connect to Kafka."
    echo "This should not happen since Python test passed."
    echo ""
    echo "Check logs:"
    sudo journalctl -u dstreambolt-ingest --since "1 minute ago" | tail -30
fi

