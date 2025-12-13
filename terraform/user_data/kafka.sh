#!/bin/bash
set -e

# DStreamBolt Kafka Instance (dstreambolt-kafka) Setup
# Single node Kafka + Zookeeper in private subnet

echo "=========================================="
echo "🚀 DStreamBolt Kafka Setup"
echo "=========================================="

# Get private IP
PRIVATE_IP=$(hostname -I | awk '{print $1}')

# Check if Kafka is already installed and running
if [ -d "/opt/kafka" ] && systemctl is-active --quiet kafka && systemctl is-active --quiet zookeeper; then
    echo "✅ Kafka is already installed and running"
    echo "   Skipping installation steps..."
    echo ""
    echo "📊 Current Status:"
    echo "   Zookeeper: $(systemctl is-active zookeeper)"
    echo "   Kafka: $(systemctl is-active kafka)"
    echo "   Private IP: $PRIVATE_IP"
    echo ""

    # Skip to topic creation
    SKIP_INSTALL=true
else
    echo "📦 Installing Kafka..."
    SKIP_INSTALL=false

    # Update system
    apt-get update
    apt-get upgrade -y

    # Install Java
    apt-get install -y openjdk-11-jdk wget

    # Download and install Kafka
    SCALA_VERSION="2.13"
    cd /opt

    if [ ! -d "/opt/kafka" ]; then
        # Try multiple Kafka versions (newest first)
        KAFKA_VERSIONS=("3.8.1" "3.8.0" "3.7.1" "3.7.0" "3.6.2")
        DOWNLOAD_SUCCESS=false

        for KAFKA_VERSION in "${KAFKA_VERSIONS[@]}"; do
            echo "📥 Attempting to download Kafka ${KAFKA_VERSION}..."
            if wget -q --spider https://downloads.apache.org/kafka/${KAFKA_VERSION}/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz 2>/dev/null; then
                echo "   ✅ Version ${KAFKA_VERSION} is available, downloading..."
                wget https://downloads.apache.org/kafka/${KAFKA_VERSION}/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz
                tar -xzf kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz
                ln -s kafka_${SCALA_VERSION}-${KAFKA_VERSION} kafka
                rm kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz
                echo "✅ Kafka ${KAFKA_VERSION} downloaded and extracted"
                DOWNLOAD_SUCCESS=true
                break
            else
                echo "   ⚠️  Version ${KAFKA_VERSION} not available, trying next..."
            fi
        done

        if [ "$DOWNLOAD_SUCCESS" = false ]; then
            echo "❌ Failed to download any Kafka version"
            echo "   Trying archive.apache.org..."
            KAFKA_VERSION="3.6.0"
            wget https://archive.apache.org/dist/kafka/${KAFKA_VERSION}/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz
            tar -xzf kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz
            ln -s kafka_${SCALA_VERSION}-${KAFKA_VERSION} kafka
            rm kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz
            echo "✅ Kafka ${KAFKA_VERSION} downloaded from archive"
        fi
    else
        echo "✅ Kafka directory already exists"
        # Detect installed version
        if [ -L "/opt/kafka" ]; then
            INSTALLED_VERSION=$(readlink /opt/kafka | sed 's/kafka_.*-//' || echo "unknown")
            echo "   Installed version: ${INSTALLED_VERSION}"
        fi
    fi

    # Configure Zookeeper
    mkdir -p /var/lib/zookeeper
    cat > /opt/kafka/config/zookeeper.properties << EOF
dataDir=/var/lib/zookeeper
clientPort=2181
maxClientCnxns=0
admin.enableServer=false
EOF

    # Configure Kafka
    mkdir -p /var/lib/kafka-logs
    cat > /opt/kafka/config/server.properties << EOF
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
EOF

    # Create Zookeeper systemd service
    cat > /etc/systemd/system/zookeeper.service << 'EOFZK'
[Unit]
Description=Apache Zookeeper
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/kafka/bin/zookeeper-server-start.sh /opt/kafka/config/zookeeper.properties
ExecStop=/opt/kafka/bin/zookeeper-server-stop.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOFZK

    # Create Kafka systemd service
    cat > /etc/systemd/system/kafka.service << 'EOFKAFKA'
[Unit]
Description=Apache Kafka
After=network.target zookeeper.service
Requires=zookeeper.service

[Service]
Type=simple
User=root
Environment="KAFKA_HEAP_OPTS=-Xmx512M -Xms256M"
ExecStart=/opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/server.properties
ExecStop=/opt/kafka/bin/kafka-server-stop.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOFKAFKA

    # Start services
    echo "🔄 Starting Zookeeper and Kafka services..."
    systemctl daemon-reload
    systemctl enable zookeeper
    systemctl enable kafka
    systemctl start zookeeper

    # Wait for Zookeeper to start
    echo "⏳ Waiting for Zookeeper to start..."
    sleep 10

    systemctl start kafka

    # Wait for Kafka to start
    echo "⏳ Waiting for Kafka to start..."
    sleep 20

    echo "✅ Kafka installation complete"
fi

# Ensure services are running
if ! systemctl is-active --quiet zookeeper; then
    echo "⚠️  Zookeeper not running, starting..."
    systemctl start zookeeper
    sleep 10
fi

if ! systemctl is-active --quiet kafka; then
    echo "⚠️  Kafka not running, starting..."
    systemctl start kafka
    sleep 20
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Creating/Verifying Kafka Topics"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Wait a moment for Kafka to be fully ready
sleep 5

# Use private IP for Kafka connection (matches listener configuration)
KAFKA_BROKER="${PRIVATE_IP}:9092"

# Create/verify default topics
echo "📝 Creating topic: dstreambolt-logs (3 partitions)..."
/opt/kafka/bin/kafka-topics.sh --create \
  --bootstrap-server ${KAFKA_BROKER} \
  --replication-factor 1 \
  --partitions 3 \
  --topic dstreambolt-logs \
  --if-not-exists 2>/dev/null && echo "   ✅ Topic 'dstreambolt-logs' ready" || echo "   ✅ Topic 'dstreambolt-logs' already exists"

echo "📝 Creating topic: dstreambolt-metrics (1 partition)..."
/opt/kafka/bin/kafka-topics.sh --create \
  --bootstrap-server ${KAFKA_BROKER} \
  --replication-factor 1 \
  --partitions 1 \
  --topic dstreambolt-metrics \
  --if-not-exists 2>/dev/null && echo "   ✅ Topic 'dstreambolt-metrics' ready" || echo "   ✅ Topic 'dstreambolt-metrics' already exists"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ DStreamBolt Kafka Setup Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 Service Status:"
echo "   Zookeeper: $(systemctl is-active zookeeper) (port 2181)"
echo "   Kafka: $(systemctl is-active kafka) (port 9092)"
echo "   Broker IP: ${KAFKA_BROKER}"
echo ""
echo "📋 Available Topics:"
/opt/kafka/bin/kafka-topics.sh --list --bootstrap-server ${KAFKA_BROKER} 2>/dev/null | while read topic; do
    echo "   • $topic"
done
echo ""
echo "🔍 Topic Details:"
/opt/kafka/bin/kafka-topics.sh --describe \
  --bootstrap-server ${KAFKA_BROKER} \
  --topic dstreambolt-logs 2>/dev/null | grep -E "Topic:|PartitionCount:|ReplicationFactor:" || true
echo ""

if [ "$SKIP_INSTALL" = "true" ]; then
    echo "ℹ️  Installation was skipped (Kafka already running)"
else
    echo "ℹ️  Fresh installation completed"
fi
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

