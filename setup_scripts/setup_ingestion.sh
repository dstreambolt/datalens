#!/bin/bash

###############################################################################
# Ingestion Service Setup Script
# Installs and configures DStreamBolt Ingestion API
###############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/ingestion-setup.log"

# Configuration
KAFKA_BROKER="${KAFKA_BROKER:-}"
MYSQL_HOST="${MYSQL_HOST:-}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN:${NC} $1" | tee -a "$LOG_FILE"; }

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         Ingestion Service Setup Script                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

if [ "$EUID" -ne 0 ]; then error "Please run as root or with sudo"; exit 1; fi

# Prompt for required config
if [ -z "$KAFKA_BROKER" ]; then
    read -p "Enter Kafka Broker (e.g., 10.0.10.248:9092): " KAFKA_BROKER
fi

if [ -z "$MYSQL_HOST" ]; then
    read -p "Enter MySQL Host (e.g., 10.0.1.61): " MYSQL_HOST
fi

if [ -z "$MYSQL_PASSWORD" ]; then
    read -sp "Enter MySQL Password: " MYSQL_PASSWORD
    echo
fi

if systemctl is-active --quiet dstreambolt-ingest 2>/dev/null; then
    log "✅ Ingestion service already running"
    read -p "Reinstall? (y/n): " -n 1 -r; echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && systemctl stop dstreambolt-ingest
fi

log "📦 Installing Python and dependencies..."
apt-get update -qq
apt-get install -y python3 python3-pip python3-venv

log "🔧 Setting up application directory..."
mkdir -p /opt/dstreambolt/ingest /opt/dstreambolt/queue
chown -R ubuntu:ubuntu /opt/dstreambolt

# Check if app.py exists in ingestion directory
SOURCE_APP="${SCRIPT_DIR}/../ingestion/app.py"
if [ -f "$SOURCE_APP" ]; then
    log "📋 Copying application files..."
    cp "$SOURCE_APP" /opt/dstreambolt/ingest/
    if [ -f "${SCRIPT_DIR}/../ingestion/requirements.txt" ]; then
        cp "${SCRIPT_DIR}/../ingestion/requirements.txt" /opt/dstreambolt/ingest/
    fi
else
    error "app.py not found at $SOURCE_APP"
    exit 1
fi

log "📦 Installing Python packages..."
cd /opt/dstreambolt/ingest
sudo -u ubuntu python3 -m venv venv
sudo -u ubuntu venv/bin/pip install --upgrade pip
sudo -u ubuntu venv/bin/pip install gunicorn flask kafka-python pymysql boto3 cryptography

log "🔧 Configuring environment..."
cat > /opt/dstreambolt/ingest/.env << EOFENV
KAFKA_BROKER=${KAFKA_BROKER}
KAFKA_TOPIC=dstreambolt-logs
MYSQL_HOST=${MYSQL_HOST}
MYSQL_PORT=3306
MYSQL_DATABASE=dstreambolt_metrics
MYSQL_USER=dstreambolt
MYSQL_PASSWORD=${MYSQL_PASSWORD}
QUEUE_DIR=/opt/dstreambolt/queue
LOG_LEVEL=INFO
EOFENV

chmod 600 /opt/dstreambolt/ingest/.env
chown ubuntu:ubuntu /opt/dstreambolt/ingest/.env

log "🔧 Creating systemd service..."
cat > /etc/systemd/system/dstreambolt-ingest.service << 'EOFSVC'
[Unit]
Description=DStreamBolt Ingestion Service
After=network.target

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=/opt/dstreambolt/ingest
Environment="PATH=/opt/dstreambolt/ingest/venv/bin"
EnvironmentFile=/opt/dstreambolt/ingest/.env
ExecStart=/opt/dstreambolt/ingest/venv/bin/gunicorn \
    -w 4 \
    -b 0.0.0.0:5000 \
    --timeout 120 \
    --access-logfile /var/log/dstreambolt-ingest-access.log \
    --error-logfile /var/log/dstreambolt-ingest-error.log \
    app:app
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOFSVC

systemctl daemon-reload
systemctl enable dstreambolt-ingest
systemctl start dstreambolt-ingest

log "⏳ Waiting for service to start..."
for i in {1..20}; do
    if systemctl is-active --quiet dstreambolt-ingest && curl -s http://localhost:5000/health > /dev/null 2>&1; then
        break
    fi
    sleep 2
done

if ! systemctl is-active --quiet dstreambolt-ingest; then
    error "Ingestion service failed to start"
    journalctl -u dstreambolt-ingest -n 50 --no-pager
    exit 1
fi

log "✅ Ingestion service running"

# Test health endpoint
HEALTH_RESPONSE=$(curl -s http://localhost:5000/health || echo "Failed")
log "Health Check: $HEALTH_RESPONSE"

systemctl status dstreambolt-ingest --no-pager -l | head -20 | tee -a "$LOG_FILE"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Ingestion Service Setup Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🔗 Service Endpoints:"
echo "   Health: http://localhost:5000/health"
echo "   Ingest: http://localhost:5000/ingest (POST)"
echo ""
echo "⚙️  Configuration:"
echo "   Kafka: $KAFKA_BROKER"
echo "   MySQL: $MYSQL_HOST"
echo "   Queue: /opt/dstreambolt/queue"
echo ""
echo "💡 Test ingestion:"
echo "   curl -X POST http://localhost:5000/ingest \\"
echo "     -H 'Content-Type: application/gzip' \\"
echo "     --data-binary @test.gz"
echo ""
echo "📝 Logs:"
echo "   Service: journalctl -u dstreambolt-ingest -f"
echo "   Access: tail -f /var/log/dstreambolt-ingest-access.log"
echo "   Error: tail -f /var/log/dstreambolt-ingest-error.log"
echo ""
echo "📝 Setup log: $LOG_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

