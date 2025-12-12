#!/bin/bash
# Deep diagnostic of Kafka connection issue

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         Deep Kafka Connection Diagnostics                   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

echo "1️⃣  Checking detailed connection logs..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sudo journalctl -u dstreambolt-ingest --since "2 minutes ago" | grep -A 5 "Connecting to Kafka"

echo ""
echo "2️⃣  Looking for error messages..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sudo journalctl -u dstreambolt-ingest --since "2 minutes ago" | grep -i "error\|failed\|timeout" | tail -20

echo ""
echo "3️⃣  Testing Python Kafka connection directly..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
/opt/dstreambolt/ingest/venv/bin/python3 << 'PYEOF'
from kafka import KafkaProducer
import json
import sys

print("Attempting to connect to Kafka at 10.0.10.101:9092...")
print("This may take up to 30 seconds...")

try:
    producer = KafkaProducer(
        bootstrap_servers=['10.0.10.101:9092'],
        value_serializer=lambda v: json.dumps(v).encode('utf-8'),
        retries=3,
        request_timeout_ms=30000,
        api_version_auto_timeout_ms=10000,
        connections_max_idle_ms=180000
    )
    print("✅ Connection successful!")
    print(f"Producer created: {producer}")

    # Try to get metadata
    metadata = producer.bootstrap_connected()
    print(f"Bootstrap connected: {metadata}")

    producer.close()
    sys.exit(0)

except Exception as e:
    print(f"❌ Connection failed!")
    print(f"Error type: {type(e).__name__}")
    print(f"Error message: {e}")

    import traceback
    print("\nFull traceback:")
    traceback.print_exc()
    sys.exit(1)
PYEOF

TEST_RESULT=$?

echo ""
echo "4️⃣  Checking Kafka server status from here..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
nc -zv 10.0.10.101 9092

echo ""
echo "5️⃣  Testing with kafkacat (if available)..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if command -v kafkacat >/dev/null 2>&1; then
    echo "Testing with kafkacat..."
    timeout 10 kafkacat -L -b 10.0.10.101:9092
else
    echo "⚠️  kafkacat not installed"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                     Diagnosis Summary                        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

if [ $TEST_RESULT -eq 0 ]; then
    echo "✅ Python test succeeded - Kafka is working!"
    echo ""
    echo "The issue may be:"
    echo "  1. Race condition during service startup"
    echo "  2. Connection timeout too short (10s)"
    echo "  3. Service not retrying connection"
    echo ""
    echo "Try restarting the ingestion service:"
    echo "  sudo systemctl restart dstreambolt-ingest"
    echo "  sleep 10"
    echo "  curl http://localhost:5000/health | python3 -m json.tool"
else
    echo "❌ Python test failed - Kafka is NOT working from Python"
    echo ""
    echo "Possible issues:"
    echo "  1. Kafka advertising wrong address"
    echo "  2. Python kafka library version mismatch"
    echo "  3. Network routing issue"
    echo ""
    echo "Check Kafka server advertised.listeners:"
    echo "  SSH to 10.0.10.101 and run:"
    echo "  grep advertised.listeners /opt/kafka/config/server.properties"
fi

