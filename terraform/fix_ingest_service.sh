#!/bin/bash

# Quick fix deployment script for ingestion service
# Fixes the Kafka producer NameError issue

INGEST_IP="3.109.132.244"
SSH_KEY="$HOME/dstreambolt-access-key.pem"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 Deploying Fixed Ingestion Service"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Target: $INGEST_IP"
echo ""

# Copy the updated app.py to the server
echo "📤 Uploading fixed app.py..."
scp -o StrictHostKeyChecking=no -i "$SSH_KEY" \
    ../ingestion/app.py \
    ubuntu@${INGEST_IP}:/tmp/app.py

# Restart the service with the new code
echo ""
echo "🔄 Deploying and restarting service..."
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" ubuntu@${INGEST_IP} << 'ENDSSH'
set -e

# Backup current app.py
if [ -f /opt/dstreambolt/agent/app.py ]; then
    sudo cp /opt/dstreambolt/agent/app.py /opt/dstreambolt/agent/app.py.backup-$(date +%Y%m%d-%H%M%S)
    echo "✅ Backed up existing app.py"
fi

# Replace with new version
sudo mv /tmp/app.py /opt/dstreambolt/agent/app.py
sudo chown ubuntu:ubuntu /opt/dstreambolt/agent/app.py

# Restart the service
sudo systemctl restart dstreambolt-ingest

# Wait a moment for service to start
sleep 3

# Check service status
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Service Status:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sudo systemctl status dstreambolt-ingest --no-pager -l | head -20

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📄 Recent Logs:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sudo journalctl -u dstreambolt-ingest -n 30 --no-pager

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 Testing Health Endpoint:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
curl -s http://localhost:5000/health | python3 -m json.tool || echo "❌ Health check failed"

ENDSSH

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Deployment Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Test with:"
echo "  python3 ../examples/02-send-to-ingest.py \\"
echo "    --alb-url https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/ingest \\"
echo "    --no-verify \\"
echo "    ../examples/logs/access.log"

