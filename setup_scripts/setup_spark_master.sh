#!/bin/bash

###############################################################################
# Spark Master Setup Script
# Installs and configures Spark Master
###############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/spark-master-setup.log"

SPARK_VERSION="${SPARK_VERSION:-3.5.0}"
PRIVATE_IP=$(hostname -I | awk '{print $1}')

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN:${NC} $1" | tee -a "$LOG_FILE"; }

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          Spark Master Setup Script                          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

if [ "$EUID" -ne 0 ]; then error "Please run as root or with sudo"; exit 1; fi

if systemctl is-active --quiet spark-master 2>/dev/null; then
    log "✅ Spark Master already running"
    read -p "Reinstall? (y/n): " -n 1 -r; echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
    systemctl stop spark-master spark-worker 2>/dev/null || true
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

log "🔧 Configuring Spark..."
cat > /opt/spark/conf/spark-defaults.conf << EOFSPARK
spark.master                     spark://${PRIVATE_IP}:7077
spark.eventLog.enabled           true
spark.eventLog.dir               file:///opt/spark/spark-events
spark.history.fs.logDirectory    file:///opt/spark/spark-events
spark.sql.warehouse.dir          file:///opt/spark/spark-warehouse
spark.driver.memory              1g
spark.executor.memory            1g
spark.executor.cores             2
EOFSPARK

cat > /opt/spark/conf/spark-env.sh << 'EOFENV'
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export SPARK_MASTER_HOST=$PRIVATE_IP
export SPARK_MASTER_PORT=7077
export SPARK_MASTER_WEBUI_PORT=8080
export SPARK_WORKER_WEBUI_PORT=8081
export SPARK_LOG_DIR=/opt/spark/logs
EOFENV

chmod +x /opt/spark/conf/spark-env.sh
mkdir -p /opt/spark/logs /opt/spark/spark-events /opt/spark/spark-warehouse
chown -R ubuntu:ubuntu /opt/spark

log "🔧 Creating systemd service..."
cat > /etc/systemd/system/spark-master.service << EOFSVC
[Unit]
Description=Apache Spark Master
After=network.target

[Service]
Type=forking
User=ubuntu
Group=ubuntu
Environment="SPARK_HOME=/opt/spark"
Environment="JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64"
ExecStart=/opt/spark/sbin/start-master.sh --host ${PRIVATE_IP} --port 7077 --webui-port 8080
ExecStop=/opt/spark/sbin/stop-master.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOFSVC

systemctl daemon-reload
systemctl enable spark-master
systemctl start spark-master

log "⏳ Waiting for Spark Master..."
for i in {1..30}; do
    if nc -zv localhost 7077 2>/dev/null && nc -zv localhost 8080 2>/dev/null; then
        break
    fi
    sleep 2
done

if ! systemctl is-active --quiet spark-master; then
    error "Spark Master failed to start"
    journalctl -u spark-master -n 50 --no-pager
    exit 1
fi

log "✅ Spark Master running"
systemctl status spark-master --no-pager -l | head -20 | tee -a "$LOG_FILE"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Spark Master Setup Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🔗 Spark Master:"
echo "   URL: spark://${PRIVATE_IP}:7077"
echo "   Web UI: http://${PRIVATE_IP}:8080"
echo ""
echo "💡 Submit job:"
echo "   /opt/spark/bin/spark-submit --master spark://${PRIVATE_IP}:7077 your-job.py"
echo ""
echo "📝 Log file: $LOG_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

