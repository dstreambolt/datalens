#!/bin/bash

###############################################################################
# Test Kafka Topics Creation Script
# Tests topic creation/listing on Kafka instance using correct broker address
###############################################################################

DEVOPS_IP="13.235.238.208"
KAFKA_PRIVATE_IP="10.0.10.248"
SSH_KEY="$HOME/dstreambolt-access-key.pem"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     Testing Kafka Topics with Correct Broker Address        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

ssh -i "$SSH_KEY" ubuntu@$DEVOPS_IP << EOFDEVOPS
echo "Connecting to Kafka instance at ${KAFKA_PRIVATE_IP}..."
echo ""

ssh -i ~/dstreambolt-access-key.pem ubuntu@${KAFKA_PRIVATE_IP} << 'EOFKAFKA'
#!/bin/bash

PRIVATE_IP=\$(hostname -I | awk '{print \$1}')
KAFKA_BROKER="\${PRIVATE_IP}:9092"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 Testing Kafka Connection"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Private IP: \${PRIVATE_IP}"
echo "Kafka Broker: \${KAFKA_BROKER}"
echo ""

echo "1️⃣  Service Status:"
echo "   Zookeeper: \$(systemctl is-active zookeeper 2>/dev/null || echo 'not running')"
echo "   Kafka: \$(systemctl is-active kafka 2>/dev/null || echo 'not running')"
echo ""

echo "2️⃣  Listening Ports:"
sudo netstat -tlnp 2>/dev/null | grep -E "(2181|9092)" | awk '{print "   " \$4 " -> " \$7}'
echo ""

echo "3️⃣  Listing Topics (using \${KAFKA_BROKER}):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if /opt/kafka/bin/kafka-topics.sh --list --bootstrap-server \${KAFKA_BROKER} 2>&1 | grep -v WARN; then
    echo ""
    echo "✅ Successfully connected to Kafka!"
else
    echo "❌ Failed to connect to Kafka"
    echo ""
    echo "Checking Kafka logs for errors..."
    tail -20 /opt/kafka/logs/server.log 2>/dev/null | tail -10
fi
echo ""

echo "4️⃣  Creating Test Topics:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Create dstreambolt-logs topic
echo "Creating topic: dstreambolt-logs..."
if /opt/kafka/bin/kafka-topics.sh --create \
  --bootstrap-server \${KAFKA_BROKER} \
  --replication-factor 1 \
  --partitions 3 \
  --topic dstreambolt-logs \
  --if-not-exists 2>&1 | grep -v WARN; then
    echo "✅ Topic 'dstreambolt-logs' ready"
else
    echo "⚠️  Topic may already exist or error occurred"
fi
echo ""

# Create dstreambolt-metrics topic
echo "Creating topic: dstreambolt-metrics..."
if /opt/kafka/bin/kafka-topics.sh --create \
  --bootstrap-server \${KAFKA_BROKER} \
  --replication-factor 1 \
  --partitions 1 \
  --topic dstreambolt-metrics \
  --if-not-exists 2>&1 | grep -v WARN; then
    echo "✅ Topic 'dstreambolt-metrics' ready"
else
    echo "⚠️  Topic may already exist or error occurred"
fi
echo ""

echo "5️⃣  Verifying Topics:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Available topics:"
/opt/kafka/bin/kafka-topics.sh --list --bootstrap-server \${KAFKA_BROKER} 2>/dev/null | while read topic; do
    echo "   • \$topic"
done
echo ""

echo "6️⃣  Topic Details:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
/opt/kafka/bin/kafka-topics.sh --describe \
  --bootstrap-server \${KAFKA_BROKER} \
  --topic dstreambolt-logs 2>/dev/null
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Test Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

EOFKAFKA

EOFDEVOPS

