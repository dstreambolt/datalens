#!/bin/bash
# Run this on the KAFKA server (root@ip-10-0-10-101)
# Fixes Kafka advertised listeners and security configuration

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       Kafka Server Configuration Check & Fix                ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Get current private IP
PRIVATE_IP=$(hostname -I | awk '{print $1}')
echo "1️⃣  Current Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Private IP: $PRIVATE_IP"
echo ""

# Check current Kafka config
echo "Current Kafka listeners config:"
grep -E "^(listeners|advertised.listeners)" /opt/kafka/config/server.properties
echo ""

# Check if Kafka is listening on the right interface
echo "2️⃣  Network Listening Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
netstat -tlnp | grep 9092 || ss -tlnp | grep 9092
echo ""

# Check if port is accessible from other hosts
echo "3️⃣  Testing if port 9092 is accessible..."
if timeout 2 bash -c "echo > /dev/tcp/${PRIVATE_IP}/9092" 2>/dev/null; then
    echo "✅ Port 9092 is accessible on ${PRIVATE_IP}"
else
    echo "❌ Port 9092 is NOT accessible on ${PRIVATE_IP}"
fi
echo ""

# Fix configuration if needed
EXPECTED_LISTENER="PLAINTEXT://0.0.0.0:9092"
EXPECTED_ADVERTISED="PLAINTEXT://${PRIVATE_IP}:9092"
CURRENT_LISTENER=$(grep "^listeners=" /opt/kafka/config/server.properties | cut -d= -f2)
CURRENT_ADVERTISED=$(grep "^advertised.listeners=" /opt/kafka/config/server.properties | cut -d= -f2)

if [ "$CURRENT_LISTENER" != "$EXPECTED_LISTENER" ] || [ "$CURRENT_ADVERTISED" != "$EXPECTED_ADVERTISED" ]; then
    echo "4️⃣  Fixing Kafka configuration..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Current Listener: $CURRENT_LISTENER"
    echo "Expected Listener: $EXPECTED_LISTENER"
    echo "Current Advertised: $CURRENT_ADVERTISED"
    echo "Expected Advertised: $EXPECTED_ADVERTISED"
    echo ""

    # Backup config
    cp /opt/kafka/config/server.properties /opt/kafka/config/server.properties.backup.$(date +%Y%m%d_%H%M%S)

    # Update config - listen on all interfaces, advertise private IP
    sed -i "s|^listeners=.*|listeners=PLAINTEXT://0.0.0.0:9092|" /opt/kafka/config/server.properties
    sed -i "s|^advertised.listeners=.*|advertised.listeners=PLAINTEXT://${PRIVATE_IP}:9092|" /opt/kafka/config/server.properties

    echo "✅ Configuration updated"
    echo ""
    echo "New configuration:"
    grep -E "^(listeners|advertised.listeners)" /opt/kafka/config/server.properties
    echo ""

    # Restart Kafka
    echo "5️⃣  Restarting Kafka..."
    systemctl restart kafka

    echo "Waiting for Kafka to start..."
    sleep 15

    if systemctl is-active --quiet kafka; then
        echo "✅ Kafka restarted successfully"
    else
        echo "❌ Kafka failed to start"
        journalctl -u kafka --since "1 minute ago" | tail -30
        exit 1
    fi
else
    echo "4️⃣  Configuration Check"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ Kafka listeners already configured correctly"
fi

# Verify topics
echo ""
echo "5️⃣  Verifying Topics"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
/opt/kafka/bin/kafka-topics.sh --list --bootstrap-server ${PRIVATE_IP}:9092
echo ""

# Check topic details
echo "Topic 'dstreambolt-logs' details:"
/opt/kafka/bin/kafka-topics.sh --describe --topic dstreambolt-logs --bootstrap-server ${PRIVATE_IP}:9092
echo ""

# Test message production
echo "6️⃣  Testing Message Production"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo '{"test":"message","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' | \
    /opt/kafka/bin/kafka-console-producer.sh \
        --broker-list ${PRIVATE_IP}:9092 \
        --topic dstreambolt-logs 2>/dev/null

if [ $? -eq 0 ]; then
    echo "✅ Test message sent successfully"
else
    echo "❌ Failed to send test message"
fi
echo ""

# Check consumer lag
echo "7️⃣  Checking Consumer Groups"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
/opt/kafka/bin/kafka-consumer-groups.sh --list --bootstrap-server ${PRIVATE_IP}:9092
echo ""

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                Configuration Summary                         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Kafka Broker: ${PRIVATE_IP}:9092"
echo "Status: $(systemctl is-active kafka)"
echo ""
echo "Clients should connect to: ${PRIVATE_IP}:9092"
echo ""
echo "To test from another server:"
echo "  telnet ${PRIVATE_IP} 9092"
echo "  nc -zv ${PRIVATE_IP} 9092"
echo ""

