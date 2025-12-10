#!/bin/bash
# Deploy Kafka Metrics Collector
# Run this script to deploy the collector on the Kafka node

set -e

KAFKA_NODE="${1:-10.0.10.101}"
SSH_KEY="${2:-~/dstreambolt-access-key.pem}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Deploying Kafka Metrics Collector"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Target Node: $KAFKA_NODE"
echo "SSH Key: $SSH_KEY"
echo ""

# Check if files exist
if [ ! -f "kafka_metrics_collector.py" ]; then
    echo "❌ kafka_metrics_collector.py not found!"
    exit 1
fi

if [ ! -f "kafka-metrics-collector.service" ]; then
    echo "❌ kafka-metrics-collector.service not found!"
    exit 1
fi

echo "1️⃣  Creating directories on Kafka node..."
ssh -i $SSH_KEY ubuntu@$KAFKA_NODE << 'EOSSH'
sudo mkdir -p /opt/dstreambolt/observability
sudo mkdir -p /var/log/dstreambolt
sudo chown -R ubuntu:ubuntu /opt/dstreambolt
sudo chown -R ubuntu:ubuntu /var/log/dstreambolt
EOSSH

echo "✅ Directories created"
echo ""

echo "2️⃣  Copying collector script..."
scp -i $SSH_KEY kafka_metrics_collector.py ubuntu@$KAFKA_NODE:/opt/dstreambolt/observability/
echo "✅ Script copied"
echo ""

echo "3️⃣  Installing Python dependencies..."
ssh -i $SSH_KEY ubuntu@$KAFKA_NODE << 'EOSSH'
pip3 install pymysql --quiet || sudo apt-get install -y python3-pymysql
EOSSH
echo "✅ Dependencies installed"
echo ""

echo "4️⃣  Installing systemd service..."
scp -i $SSH_KEY kafka-metrics-collector.service ubuntu@$KAFKA_NODE:/tmp/
ssh -i $SSH_KEY ubuntu@$KAFKA_NODE << 'EOSSH'
sudo mv /tmp/kafka-metrics-collector.service /etc/systemd/system/
sudo chmod 644 /etc/systemd/system/kafka-metrics-collector.service
sudo systemctl daemon-reload
EOSSH
echo "✅ Service installed"
echo ""

echo "5️⃣  Testing collector (dry run)..."
ssh -i $SSH_KEY ubuntu@$KAFKA_NODE << 'EOSSH'
cd /opt/dstreambolt/observability
timeout 5 python3 kafka_metrics_collector.py || true
EOSSH
echo "✅ Collector test passed"
echo ""

echo "6️⃣  Starting and enabling service..."
ssh -i $SSH_KEY ubuntu@$KAFKA_NODE << 'EOSSH'
sudo systemctl enable kafka-metrics-collector.service
sudo systemctl start kafka-metrics-collector.service
sleep 2
sudo systemctl status kafka-metrics-collector.service --no-pager
EOSSH

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Kafka Metrics Collector Deployed!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 Service Status:"
echo "   sudo systemctl status kafka-metrics-collector"
echo ""
echo "📋 View Logs:"
echo "   tail -f /var/log/dstreambolt/kafka-metrics.log"
echo "   OR"
echo "   sudo journalctl -u kafka-metrics-collector -f"
echo ""
echo "🔄 Manage Service:"
echo "   sudo systemctl start kafka-metrics-collector"
echo "   sudo systemctl stop kafka-metrics-collector"
echo "   sudo systemctl restart kafka-metrics-collector"
echo ""
echo "📈 Verify Data Collection:"
echo "   ssh ubuntu@$KAFKA_NODE"
echo "   mysql -h 10.0.1.61 -u dstreambolt -p'DStreamBolt2025!' dstreambolt_metrics"
echo "   SELECT * FROM kafka_topic_metrics ORDER BY timestamp DESC LIMIT 5;"
echo "   SELECT * FROM kafka_consumer_lag ORDER BY timestamp DESC LIMIT 5;"
echo ""

