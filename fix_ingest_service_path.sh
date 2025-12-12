#!/bin/bash
# Quick fix for current dstreambolt-ingest service issue
# Run this on the ingestion server: ubuntu@ip-10-0-1-72

set -e

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       Quick Fix: dstreambolt-ingest Service Path            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Stop the broken service
echo "1️⃣  Stopping broken service..."
sudo systemctl stop dstreambolt-ingest || true

# Create correct systemd service file
echo "2️⃣  Creating correct systemd service file..."
sudo tee /etc/systemd/system/dstreambolt-ingest.service > /dev/null << 'EOF'
[Unit]
Description=DStreamBolt Ingestion Service
After=network.target

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=/opt/dstreambolt/ingest
Environment="PATH=/opt/dstreambolt/ingest/venv/bin"
ExecStart=/opt/dstreambolt/ingest/venv/bin/gunicorn -w 4 -b 0.0.0.0:5000 --timeout 120 app:app
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=dstreambolt-ingest

# Security settings
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
echo "3️⃣  Reloading systemd..."
sudo systemctl daemon-reload

# Enable service
echo "4️⃣  Enabling service..."
sudo systemctl enable dstreambolt-ingest

# Check if deployment path exists
echo "5️⃣  Checking deployment path..."
if [ ! -d /opt/dstreambolt/ingest ]; then
    echo "⚠️  WARNING: /opt/dstreambolt/ingest does not exist!"
    echo "   Creating directory..."
    sudo mkdir -p /opt/dstreambolt/ingest
    sudo chown ubuntu:ubuntu /opt/dstreambolt/ingest
fi

# Check if venv exists
if [ ! -d /opt/dstreambolt/ingest/venv ]; then
    echo "⚠️  WARNING: Python venv not found!"
    echo "   You need to deploy the application first via Jenkins job"
    echo "   Or manually create venv and install dependencies"
    exit 1
fi

# Check if app.py exists
if [ ! -f /opt/dstreambolt/ingest/app.py ]; then
    echo "⚠️  WARNING: app.py not found!"
    echo "   You need to deploy the application first via Jenkins job"
    exit 1
fi

# Start service
echo "6️⃣  Starting service..."
sudo systemctl start dstreambolt-ingest

# Wait a moment
sleep 3

# Check status
echo "7️⃣  Checking service status..."
sudo systemctl status dstreambolt-ingest --no-pager

# Test health endpoint
echo ""
echo "8️⃣  Testing health endpoint..."
if curl -s http://localhost:5000/health | grep -q "healthy"; then
    echo "✅ Service is healthy!"
else
    echo "⚠️  Service may not be fully ready yet, check logs:"
    echo "   sudo journalctl -u dstreambolt-ingest -f"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    Fix Complete! ✅                           ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Service should now be running correctly at /opt/dstreambolt/ingest"
echo ""
echo "Useful commands:"
echo "  Status:  sudo systemctl status dstreambolt-ingest"
echo "  Logs:    sudo journalctl -u dstreambolt-ingest -f"
echo "  Restart: sudo systemctl restart dstreambolt-ingest"
echo "  Health:  curl http://localhost:5000/health"
echo ""

