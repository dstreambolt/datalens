#!/bin/bash
set -e

# DStreamBolt Kafka Instance (dstreambolt-kafka) Setup
# Single node Kafka + Zookeeper in private subnet

echo "=========================================="
echo "🚀 DStreamBolt Kafka Setup"
echo "=========================================="

# Update system
apt-get update
apt-get upgrade -y

# Install Java
apt-get install -y openjdk-11-jdk wget

# Download and install Kafka
KAFKA_VERSION="3.6.1"
SCALA_VERSION="2.13"
cd /opt
wget https://downloads.apache.org/kafka/${KAFKA_VERSION}/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz
tar -xzf kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz
ln -s kafka_${SCALA_VERSION}-${KAFKA_VERSION} kafka
rm kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz

# Get private IP
PRIVATE_IP=$(hostname -I | awk '{print $1}')

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
cat > /etc/systemd/system/zookeeper.service << 'EOF'
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
EOF

# Create Kafka systemd service
cat > /etc/systemd/system/kafka.service << 'EOF'
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
EOF

# Start services
systemctl daemon-reload
systemctl enable zookeeper
systemctl enable kafka
systemctl start zookeeper

# Wait for Zookeeper to start
sleep 10

systemctl start kafka

# Wait for Kafka to start
sleep 20

# Create default topics
/opt/kafka/bin/kafka-topics.sh --create \
  --bootstrap-server localhost:9092 \
  --replication-factor 1 \
  --partitions 3 \
  --topic dstreambolt-logs \
  --if-not-exists

/opt/kafka/bin/kafka-topics.sh --create \
  --bootstrap-server localhost:9092 \
  --replication-factor 1 \
  --partitions 1 \
  --topic dstreambolt-metrics \
  --if-not-exists

echo "✅ DStreamBolt Kafka setup complete!"
echo ""
echo "Kafka Status:"
systemctl status kafka --no-pager | head -15
echo ""
echo "Available Topics:"
/opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092

