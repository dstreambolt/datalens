#!/bin/bash
set -e

# DStreamBolt Ingestion Service Setup - Production Version
# High-performance ingestion with AWS Secrets Manager integration

echo "================================================================================"
echo "🚀 DStreamBolt Ingestion Service - Production Setup"
echo "================================================================================"

# Get instance metadata
INSTANCE_ID=$(ec2-metadata --instance-id | cut -d " " -f 2)
echo "Instance ID: $INSTANCE_ID"

# Cleanup old installations
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1️⃣  Cleaning up old installations..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Stop and remove old dstreambolt-agent service
if systemctl list-units --all | grep -q "dstreambolt-agent.service"; then
    echo "⚠️  Removing old dstreambolt-agent service..."
    systemctl stop dstreambolt-agent 2>/dev/null || true
    systemctl disable dstreambolt-agent 2>/dev/null || true
    rm -f /etc/systemd/system/dstreambolt-agent.service
    echo "✅ Old dstreambolt-agent removed"
fi

# Stop existing dstreambolt-ingest service
if systemctl is-active --quiet dstreambolt-ingest 2>/dev/null; then
    echo "Stopping existing dstreambolt-ingest service..."
    systemctl stop dstreambolt-ingest
fi

# Backup and remove old installations
for OLD_DIR in "/opt/dstreambolt/agent" "/opt/dstreambolt/ingest"; do
    if [ -d "$OLD_DIR" ]; then
        BACKUP_DIR="/opt/dstreambolt/backups/backup-$(basename $OLD_DIR)-$(date +%Y%m%d-%H%M%S)"
        mkdir -p /opt/dstreambolt/backups
        cp -r "$OLD_DIR" "$BACKUP_DIR" 2>/dev/null || true
        rm -rf "$OLD_DIR"
        echo "✅ Backed up and removed: $OLD_DIR"
    fi
done

# Update system
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2️⃣  Updating system packages..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y
apt-get install -y python3 python3-pip python3-venv mysql-client awscli jq

# Create application directory with proper ownership
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3️⃣  Creating application structure..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
mkdir -p /opt/dstreambolt/ingest
mkdir -p /opt/dstreambolt/queue
mkdir -p /opt/dstreambolt/queue/processing
mkdir -p /opt/dstreambolt/queue/failed
mkdir -p /opt/dstreambolt/queue/corrupted
mkdir -p /etc/dstreambolt/certs/ca
chown -R ubuntu:ubuntu /opt/dstreambolt
chown -R ubuntu:ubuntu /etc/dstreambolt

cd /opt/dstreambolt/ingest

# Create virtual environment
echo "Creating Python virtual environment..."
sudo -u ubuntu python3 -m venv venv
sudo -u ubuntu /opt/dstreambolt/ingest/venv/bin/pip install --upgrade pip --quiet

# Install Python dependencies
echo "Installing Python packages..."
sudo -u ubuntu /opt/dstreambolt/ingest/venv/bin/pip install \
  flask>=3.0.0 \
  gunicorn>=21.2.0 \
  kafka-python>=2.0.2 \
  pymysql>=1.1.0 \
  boto3>=1.34.0 \
  prometheus-client>=0.19.0 \
  cryptography>=41.0.0 \
  --quiet

echo "✅ Python environment ready"

# Fetch configuration from Terraform variables (injected at instance launch)
MYSQL_HOST="${mysql_host}"
KAFKA_BROKER="${kafka_broker}"

echo "Configuration:"
echo "  MySQL Host: $MYSQL_HOST"
echo "  Kafka Broker: $KAFKA_BROKER"

# Deploy application files via Jenkins after instance is ready
# For now, create placeholder that will be replaced by deployment
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "4️⃣  Application will be deployed via Jenkins..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Directory structure created"
echo "✅ Python environment ready"
echo ""
echo "Next steps:"
echo "1. Run Jenkins job 'DStreamBolt-Deploy-Ingestion'"
echo "2. Service will be started automatically by deployment"
echo ""

# Create systemd service file (will be activated by deployment)
cat > /etc/systemd/system/dstreambolt-ingest.service << 'EOF'
[Unit]
Description=DStreamBolt Ingestion Service
After=network.target

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=/opt/dstreambolt/ingest
Environment="PATH=/opt/dstreambolt/ingest/venv/bin"
Environment="PYTHONUNBUFFERED=1"
ExecStart=/opt/dstreambolt/ingest/venv/bin/gunicorn -w 4 -b 0.0.0.0:5000 --timeout 120 --config gunicorn_config.py app:app
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
systemctl daemon-reload
systemctl enable dstreambolt-ingest

echo "✅ Systemd service configured"

# Install and configure Nginx as reverse proxy
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "5️⃣  Configuring Nginx..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Install Nginx if not already installed
if ! command -v nginx &> /dev/null; then
    apt-get install -y nginx
fi

# Create Nginx configuration for the ingestion service
cat > /etc/nginx/sites-available/dstreambolt-ingest << 'EOF'
server {
    listen 80 default_server;
    server_name _;

    client_max_body_size 50M;
    client_body_timeout 120s;

    # Health check endpoint
    location /health {
        proxy_pass http://127.0.0.1:5000/health;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 10s;
    }

    # Ingestion endpoint
    location /ingest {
        proxy_pass http://127.0.0.1:5000/ingest;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Pass ALB mTLS headers
        proxy_set_header X-Amzn-Mtls-Clientcert $http_x_amzn_mtls_clientcert;
        proxy_set_header X-Amzn-Mtls-Clientcert-Serial-Number $http_x_amzn_mtls_clientcert_serial_number;
        proxy_set_header X-Amzn-Mtls-Clientcert-Subject $http_x_amzn_mtls_clientcert_subject;

        proxy_read_timeout 120s;
        proxy_send_timeout 120s;
    }

    # Metrics endpoint
    location /metrics {
        proxy_pass http://127.0.0.1:5000/metrics;
        proxy_set_header Host $host;
        proxy_read_timeout 10s;
    }
}
EOF

# Enable the site
ln -sf /etc/nginx/sites-available/dstreambolt-ingest /etc/nginx/sites-enabled/default

# Test Nginx configuration
if nginx -t 2>&1; then
    echo "✅ Nginx configuration valid"
    systemctl restart nginx
    systemctl enable nginx
    echo "✅ Nginx restarted"
else
    echo "❌ Nginx configuration has errors"
    nginx -t
fi

echo ""
echo "================================================================================"
echo "✅ DStreamBolt Ingestion Service - Bootstrap Complete"
echo "================================================================================"
echo ""
echo "Status:"
echo "  ✅ Python environment created"
echo "  ✅ Directory structure ready"
echo "  ✅ Systemd service configured"
echo "  ✅ Nginx configured and running"
echo ""
echo "Next Steps:"
echo "  1. Deploy application code via Jenkins"
echo "     Job: DStreamBolt-Deploy-Ingestion"
echo "     Target IP: $(hostname -I | awk '{print $1}')"
echo ""
echo "  2. Service will start automatically after deployment"
echo ""
echo "Verification Commands:"
echo "  systemctl status dstreambolt-ingest"
echo "  journalctl -u dstreambolt-ingest -f"
echo "  curl http://localhost/health"
echo ""
echo "Configuration:"
echo "  Working Directory: /opt/dstreambolt/ingest"
echo "  Queue Directory: /opt/dstreambolt/queue"
echo "  Service User: ubuntu"
echo "  Nginx Port: 80"
echo "  Application Port: 5000"
echo ""

