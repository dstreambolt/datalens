#!/bin/bash

###############################################################################
# Kafka Setup Script
# Installs and configures Kafka + Zookeeper with topics
###############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/kafka-setup.log"

# Configuration
KAFKA_VERSION="${KAFKA_VERSION:-3.8.1}"
KAFKA_SCALA_VERSION="2.13"
PRIVATE_IP=$(hostname -I | awk '{print $1}')

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN:${NC} $1" | tee -a "$LOG_FILE"
}

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              Kafka Setup Script                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

if [ "$EUID" -ne 0 ]; then
    error "Please run as root or with sudo"
    exit 1
fi

# Check if Kafka is already running
if systemctl is-active --quiet kafka 2>/dev/null; then
    log "✅ Kafka is already running"
    read -p "Do you want to reinstall? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Skipping installation..."
        SKIP_INSTALL=true
    else
        systemctl stop kafka zookeeper 2>/dev/null || true
        SKIP_INSTALL=false
    fi
else
    SKIP_INSTALL=false
fi

if [ "$SKIP_INSTALL" != "true" ]; then
    log "📦 Installing Java..."
    apt-get update -qq
    apt-get install -y openjdk-11-jdk wget netcat

    log "📦 Downloading Kafka ${KAFKA_VERSION}..."

    # Try multiple mirrors
    MIRRORS=(
        "https://downloads.apache.org/kafka/${KAFKA_VERSION}/kafka_${KAFKA_SCALA_VERSION}-${KAFKA_VERSION}.tgz"
        "https://archive.apache.org/dist/kafka/${KAFKA_VERSION}/kafka_${KAFKA_SCALA_VERSION}-${KAFKA_VERSION}.tgz"
        "https://dlcdn.apache.org/kafka/${KAFKA_VERSION}/kafka_${KAFKA_SCALA_VERSION}-${KAFKA_VERSION}.tgz"
    )

    DOWNLOADED=false
    for mirror in "${MIRRORS[@]}"; do
        log "Trying: $mirror"
        if wget -q --timeout=30 "$mirror" -O /tmp/kafka.tgz 2>/dev/null; then
            DOWNLOADED=true
            break
        fi
    done

    if [ "$DOWNLOADED" != "true" ]; then
        # Try older versions as fallback
        for ver in 3.8.0 3.7.1 3.6.2 3.6.1; do
            warn "Trying fallback version: $ver"
            if wget -q --timeout=30 "https://archive.apache.org/dist/kafka/${ver}/kafka_${KAFKA_SCALA_VERSION}-${ver}.tgz" -O /tmp/kafka.tgz 2>/dev/null; then
                KAFKA_VERSION=$ver
                DOWNLOADED=true
                break
            fi
        done
    fi

    if [ "$DOWNLOADED" != "true" ]; then
        error "Failed to download Kafka from any mirror"
        exit 1
    fi

    log "📦 Installing Kafka..."
    mkdir -p /opt/kafka
    tar -xzf /tmp/kafka.tgz -C /opt/kafka --strip-components=1
    rm /tmp/kafka.tgz

    log "✅ Kafka ${KAFKA_VERSION} installed"
fi

log "🔧 Configuring Zookeeper..."
cat > /opt/kafka/config/zookeeper.properties << EOFZK
dataDir=/var/lib/zookeeper
clientPort=2181
maxClientCnxns=0
admin.enableServer=false
tickTime=2000
initLimit=5
syncLimit=2
EOFZK

mkdir -p /var/lib/zookeeper
chown -R ubuntu:ubuntu /var/lib/zookeeper

log "🔧 Configuring Kafka..."
cat > /opt/kafka/config/server.properties << EOFKAFKA
broker.id=1
listeners=PLAINTEXT://${PRIVATE_IP}:9092
advertised.listeners=PLAINTEXT://${PRIVATE_IP}:9092
num.network.threads=3
num.io.threads=8
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600
log.dirs=/var/lib/kafka-logs
num.partitions=3
num.recovery.threads.per.data.dir=1
offsets.topic.replication.factor=1
transaction.state.log.replication.factor=1
transaction.state.log.min.isr=1
log.retention.hours=168
log.segment.bytes=1073741824
log.retention.check.interval.ms=300000
zookeeper.connect=localhost:2181
zookeeper.connection.timeout.ms=18000
group.initial.rebalance.delay.ms=0
EOFKAFKA

mkdir -p /var/lib/kafka-logs
chown -R ubuntu:ubuntu /var/lib/kafka-logs /opt/kafka

log "🔧 Creating systemd services..."

# Zookeeper service
cat > /etc/systemd/system/zookeeper.service << 'EOFZKSVC'
[Unit]
Description=Apache Zookeeper
After=network.target

[Service]
Type=simple
User=ubuntu
Group=ubuntu
Environment="KAFKA_HEAP_OPTS=-Xmx256M -Xms128M"
ExecStart=/opt/kafka/bin/zookeeper-server-start.sh /opt/kafka/config/zookeeper.properties
ExecStop=/opt/kafka/bin/zookeeper-server-stop.sh
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOFZKSVC

# Kafka service
cat > /etc/systemd/system/kafka.service << 'EOFKAFKASVC'
[Unit]
Description=Apache Kafka
After=zookeeper.service network.target
Requires=zookeeper.service

[Service]
Type=simple
User=ubuntu
Group=ubuntu
Environment="KAFKA_HEAP_OPTS=-Xmx512M -Xms256M"
ExecStart=/opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/server.properties
ExecStop=/opt/kafka/bin/kafka-server-stop.sh
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOFKAFKASVC

systemctl daemon-reload

log "🚀 Starting services..."
systemctl enable zookeeper kafka
systemctl start zookeeper

# Wait for Zookeeper
log "⏳ Waiting for Zookeeper..."
for i in {1..30}; do
    if echo ruok | nc localhost 2181 2>/dev/null | grep -q imok; then
        break
    fi
    sleep 2
done

systemctl start kafka

# Wait for Kafka
log "⏳ Waiting for Kafka..."
for i in {1..60}; do
    if systemctl is-active --quiet kafka && nc -zv localhost 9092 2>/dev/null; then
        sleep 5
        break
    fi
    sleep 2
done

if ! systemctl is-active --quiet kafka; then
    error "Kafka failed to start"
    journalctl -u kafka -n 50 --no-pager
    exit 1
fi

log "✅ Kafka is running"

# Create topics
log "📝 Creating topics..."
KAFKA_BROKER="${PRIVATE_IP}:9092"

/opt/kafka/bin/kafka-topics.sh --create \
  --bootstrap-server ${KAFKA_BROKER} \
  --replication-factor 1 \
  --partitions 3 \
  --topic dstreambolt-logs \
  --if-not-exists 2>/dev/null && log "✅ Topic: dstreambolt-logs" || log "⚠️  Topic dstreambolt-logs exists"

/opt/kafka/bin/kafka-topics.sh --create \
  --bootstrap-server ${KAFKA_BROKER} \
  --replication-factor 1 \
  --partitions 1 \
  --topic dstreambolt-metrics \
  --if-not-exists 2>/dev/null && log "✅ Topic: dstreambolt-metrics" || log "⚠️  Topic dstreambolt-metrics exists"

log "📊 Service Status:"
systemctl status kafka --no-pager -l | head -20 | tee -a "$LOG_FILE"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Kafka Setup Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🔗 Kafka Broker:"
echo "   Internal: ${PRIVATE_IP}:9092"
echo "   Zookeeper: localhost:2181"
echo ""
echo "📋 Topics:"
/opt/kafka/bin/kafka-topics.sh --list --bootstrap-server ${KAFKA_BROKER} 2>/dev/null | while read topic; do
    echo "   • $topic"
done
echo ""
echo "💡 Useful commands:"
echo "   List topics:"
echo "     /opt/kafka/bin/kafka-topics.sh --list --bootstrap-server ${PRIVATE_IP}:9092"
echo ""
echo "   Describe topic:"
echo "     /opt/kafka/bin/kafka-topics.sh --describe --topic dstreambolt-logs --bootstrap-server ${PRIVATE_IP}:9092"
echo ""
echo "   Consume messages:"
echo "     /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server ${PRIVATE_IP}:9092 --topic dstreambolt-logs --from-beginning"
echo ""
echo "📝 Log file: $LOG_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

