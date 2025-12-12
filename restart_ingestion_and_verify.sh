#!/bin/bash
# Run on INGESTION server to restart and verify Kafka connection

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       Restart Ingestion Service & Verify Kafka              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

echo "1️⃣  Restarting ingestion service..."
sudo systemctl restart dstreambolt-ingest

echo "Waiting 5 seconds for service to start..."
sleep 5

echo ""
echo "2️⃣  Checking service status..."
if systemctl is-active --quiet dstreambolt-ingest; then
    echo "✅ Service is running"
else
    echo "❌ Service failed to start"
    sudo systemctl status dstreambolt-ingest --no-pager
    exit 1
fi

echo ""
echo "3️⃣  Checking Kafka connection in logs..."
sudo journalctl -u dstreambolt-ingest --since "10 seconds ago" | grep -i kafka | tail -10

echo ""
echo "4️⃣  Testing health endpoint..."
HEALTH=$(curl -s http://localhost:5000/health)
echo "$HEALTH" | python3 -m json.tool

KAFKA_STATUS=$(echo "$HEALTH" | python3 -c "import sys, json; print(json.load(sys.stdin).get('kafka', 'unknown'))" 2>/dev/null)

echo ""
if [ "$KAFKA_STATUS" = "connected" ]; then
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                  ✅ SUCCESS - Kafka Connected!               ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "The ingestion service is now connected to Kafka."
    echo ""
    echo "Test ingestion with:"
    echo "  curl -X POST http://localhost:5000/ingest \\"
    echo "    -H 'Content-Type: application/gzip' \\"
    echo "    --data-binary @test.gz"
elif [ "$KAFKA_STATUS" = "disconnected" ]; then
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║             ❌ FAILED - Kafka Still Disconnected             ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Network connectivity is OK, but Kafka handshake is failing."
    echo ""
    echo "Checking detailed logs..."
    echo ""
    sudo journalctl -u dstreambolt-ingest --since "1 minute ago" | tail -30
    echo ""
    echo "Possible issues:"
    echo "  1. Kafka advertising wrong address"
    echo "  2. Kafka not fully started"
    echo "  3. Zookeeper connection issue"
    echo ""
    echo "On Kafka server, check:"
    echo "  journalctl -u kafka --since '5 minutes ago' | tail -50"
else
    echo "⚠️  Unexpected Kafka status: $KAFKA_STATUS"
fi

