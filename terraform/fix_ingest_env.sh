#!/bin/bash

# Fix environment variables for ingestion service

INGEST_IP="3.109.132.244"
SSH_KEY="$HOME/dstreambolt-access-key.pem"
KAFKA_BROKER="10.0.10.101:9092"
MYSQL_HOST="13.232.132.240"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 Fixing Ingestion Service Environment"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Target: $INGEST_IP"
echo "Kafka:  $KAFKA_BROKER"
echo "MySQL:  $MYSQL_HOST"
echo ""

ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" ubuntu@${INGEST_IP} << EOF
set -e

echo "📝 Updating systemd service file with environment variables..."

sudo tee /etc/systemd/system/dstreambolt-ingest.service > /dev/null << 'SERVICEEOF'
[Unit]
Description=DStreamBolt Ingestion Service
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/dstreambolt/agent
Environment="PATH=/opt/dstreambolt/agent/venv/bin"
Environment="KAFKA_BROKER=${KAFKA_BROKER}"
Environment="MYSQL_HOST=${MYSQL_HOST}"
Environment="MYSQL_USER=root"
Environment="MYSQL_PASSWORD=DStreamBolt2025!"
Environment="MYSQL_DB=dstreambolt_metrics"
Environment="KAFKA_TOPIC=dstreambolt-logs"
ExecStart=/opt/dstreambolt/agent/venv/bin/gunicorn -w 4 -b 0.0.0.0:5000 --timeout 120 app:app
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICEEOF

echo "✅ Service file updated"

# Reload systemd and restart service
echo "🔄 Reloading systemd and restarting service..."
sudo systemctl daemon-reload
sudo systemctl restart dstreambolt-ingest
sleep 3

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Service Status:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sudo systemctl status dstreambolt-ingest --no-pager -l | head -20

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📄 Recent Logs (with Kafka messages):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sudo journalctl -u dstreambolt-ingest -n 40 --no-pager | grep -E "Kafka|kafka|MySQL|Starting|Booting"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 Testing Health Endpoint:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sleep 2
curl -s http://localhost:5000/health | python3 -m json.tool

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 Testing via ALB:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
curl -s https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/health -k | python3 -m json.tool || echo "❌ ALB health check failed"

EOF

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Environment Fix Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Now test ingestion with:"
echo "  cd ../examples"
echo "  python3 02-send-to-ingest.py \\"
echo "    --alb-url https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/ingest \\"
echo "    --no-verify \\"
echo "    logs/access.log"

