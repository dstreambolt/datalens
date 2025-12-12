#!/bin/bash
# EMERGENCY FIX - Run on Kafka server (root@10.0.10.101)
# This changes Kafka to listen on all interfaces while advertising the private IP

PRIVATE_IP=$(hostname -I | awk '{print $1}')

echo "Current Kafka configuration:"
grep "^listeners=" /opt/kafka/config/server.properties
grep "^advertised.listeners=" /opt/kafka/config/server.properties

echo ""
echo "Fixing Kafka to listen on all interfaces..."

# Backup
cp /opt/kafka/config/server.properties /opt/kafka/config/server.properties.backup

# Fix: Listen on all interfaces (0.0.0.0), advertise private IP
sed -i "s|^listeners=.*|listeners=PLAINTEXT://0.0.0.0:9092|" /opt/kafka/config/server.properties
sed -i "s|^advertised.listeners=.*|advertised.listeners=PLAINTEXT://${PRIVATE_IP}:9092|" /opt/kafka/config/server.properties

echo "New configuration:"
grep "^listeners=" /opt/kafka/config/server.properties
grep "^advertised.listeners=" /opt/kafka/config/server.properties

echo ""
echo "Restarting Kafka..."
systemctl restart kafka

echo "Waiting 15 seconds for Kafka to start..."
sleep 15

if systemctl is-active --quiet kafka; then
    echo "✅ Kafka is running"

    # Check listening port
    echo ""
    echo "Kafka listening on:"
    netstat -tlnp | grep 9092 || ss -tlnp | grep 9092

    echo ""
    echo "✅ Fix complete!"
    echo ""
    echo "Kafka now:"
    echo "  - Listens on: 0.0.0.0:9092 (all interfaces)"
    echo "  - Advertises: ${PRIVATE_IP}:9092 (to clients)"
    echo ""
    echo "Test from ingestion server with:"
    echo "  nc -zv ${PRIVATE_IP} 9092"
else
    echo "❌ Kafka failed to start!"
    echo ""
    echo "Check logs:"
    journalctl -u kafka --since "2 minutes ago" | tail -50
fi

