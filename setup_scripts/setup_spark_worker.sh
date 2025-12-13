#!/bin/bash

###############################################################################
# Spark Worker Setup Script
# Installs and configures Spark Worker
###############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/spark-worker-setup.log"

SPARK_VERSION="${SPARK_VERSION:-3.5.0}"
SPARK_MASTER_HOST="${SPARK_MASTER_HOST:-}"
PRIVATE_IP=$(hostname -I | awk '{print $1}')

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"; }

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          Spark Worker Setup Script                          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

if [ "$EUID" -ne 0 ]; then error "Please run as root or with sudo"; exit 1; fi

if [ -z "$SPARK_MASTER_HOST" ]; then
    read -p "Enter Spark Master IP: " SPARK_MASTER_HOST
fi

if systemctl is-active --quiet spark-worker 2>/dev/null; then
    log "✅ Spark Worker already running"
    read -p "Reinstall? (y/n): " -n 1 -r; echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
    systemctl stop spark-worker 2>/dev/null || true
fi

log "📦 Installing Java 11..."
apt-get update -qq && apt-get install -y openjdk-11-jdk wget

log "📦 Downloading Spark ${SPARK_VERSION}..."
if [ ! -f /tmp/spark-${SPARK_VERSION}.tgz ]; then
    wget -q https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop3.tgz -O /tmp/spark-${SPARK_VERSION}.tgz
fi

log "📦 Installing Spark..."
rm -rf /opt/spark
mkdir -p /opt/spark
tar -xzf /tmp/spark-${SPARK_VERSION}.tgz -C /opt/spark --strip-components=1
chown -R ubuntu:ubuntu /opt/spark

log "🔧 Configuring Spark Worker..."
cat > /opt/spark/conf/spark-env.sh << EOFENV
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export SPARK_MASTER=spark://${SPARK_MASTER_HOST}:7077
export SPARK_WORKER_WEBUI_PORT=8081
export SPARK_WORKER_CORES=2
export SPARK_WORKER_MEMORY=1g
export SPARK_LOG_DIR=/opt/spark/logs
EOFENV

chmod +x /opt/spark/conf/spark-env.sh
mkdir -p /opt/spark/logs
chown -R ubuntu:ubuntu /opt/spark

log "🔧 Creating systemd service..."
cat > /etc/systemd/system/spark-worker.service << EOFSVC
[Unit]
Description=Apache Spark Worker
After=network.target

[Service]
Type=forking
User=ubuntu
Group=ubuntu
Environment="SPARK_HOME=/opt/spark"
Environment="JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64"
ExecStart=/opt/spark/sbin/start-worker.sh spark://${SPARK_MASTER_HOST}:7077
ExecStop=/opt/spark/sbin/stop-worker.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOFSVC

systemctl daemon-reload
systemctl enable spark-worker
systemctl start spark-worker

log "⏳ Waiting for Spark Worker..."
sleep 10

if ! systemctl is-active --quiet spark-worker; then
    error "Spark Worker failed to start"
    journalctl -u spark-worker -n 50 --no-pager
    exit 1
fi

log "✅ Spark Worker running"
systemctl status spark-worker --no-pager -l | head -20 | tee -a "$LOG_FILE"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Spark Worker Setup Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🔗 Connected to Master: spark://${SPARK_MASTER_HOST}:7077"
echo "   Worker UI: http://${PRIVATE_IP}:8081"
echo ""
echo "📝 Log file: $LOG_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

