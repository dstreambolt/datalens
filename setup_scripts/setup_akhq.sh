#!/bin/bash

###############################################################################
# AKHQ (Kafka UI) Setup Script
# Installs and configures AKHQ for Kafka management
###############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/akhq-setup.log"

AKHQ_VERSION="${AKHQ_VERSION:-0.24.0}"
KAFKA_BROKER="${KAFKA_BROKER:-}"
ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-DStreamBolt2025!}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"; }

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              AKHQ (Kafka UI) Setup Script                    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

if [ "$EUID" -ne 0 ]; then error "Please run as root or with sudo"; exit 1; fi

if [ -z "$KAFKA_BROKER" ]; then
    read -p "Enter Kafka Broker (e.g., 10.0.10.248:9092): " KAFKA_BROKER
fi

if systemctl is-active --quiet akhq 2>/dev/null; then
    log "✅ AKHQ already running"
    read -p "Reinstall? (y/n): " -n 1 -r; echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
    systemctl stop akhq 2>/dev/null || true
fi

log "📦 Installing Java 17..."
apt-get update -qq
apt-get install -y openjdk-17-jdk wget

log "📦 Downloading AKHQ ${AKHQ_VERSION}..."
mkdir -p /opt/akhq
wget -q https://github.com/tchiotludo/akhq/releases/download/${AKHQ_VERSION}/akhq-${AKHQ_VERSION}-all.jar -O /opt/akhq/akhq.jar

log "🔧 Configuring AKHQ..."

# Generate bcrypt password hash (simplified - using plain password for now)
cat > /opt/akhq/application.yml << EOFAKHQ
micronaut:
  application:
    name: akhq
  server:
    port: 8081
    context-path: /kafkamgr
  security:
    enabled: true

akhq:
  server:
    base-path: "/kafkamgr"

  connections:
    dstreambolt-kafka:
      properties:
        bootstrap.servers: "${KAFKA_BROKER}"
      schema-registry:
        url: ""
      connect:
        - name: "connect"
          url: ""

  security:
    default-group: no-roles
    basic-auth:
      - username: ${ADMIN_USERNAME}
        password: ${ADMIN_PASSWORD}
        groups:
          - admin
      - username: user
        password: user123
        groups:
          - reader

    groups:
      admin:
        name: admin
        roles:
          - topic/read
          - topic/insert
          - topic/delete
          - topic/config/update
          - node/read
          - node/config/update
          - group/read
          - group/delete
          - group/offsets/update
          - registry/read
          - registry/insert
          - registry/update
          - registry/delete
          - registry/version/delete
          - acls/read
          - connect/read
          - connect/insert
          - connect/update
          - connect/delete
          - connect/state/update
      reader:
        name: reader
        roles:
          - topic/read
          - node/read
          - group/read
          - registry/read
          - acls/read
          - connect/read

  pagination:
    page-size: 25

  topic:
    default-view: ALL
    skip-consumer-groups: false
    skip-last-record: false

  topic-data:
    size: 50
    poll-timeout: 1000
EOFAKHQ

chown -R ubuntu:ubuntu /opt/akhq

log "🔧 Creating systemd service..."
cat > /etc/systemd/system/akhq.service << 'EOFSVC'
[Unit]
Description=AKHQ (Kafka UI)
After=network.target

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=/opt/akhq
ExecStart=/usr/bin/java \
    -Dmicronaut.config.files=/opt/akhq/application.yml \
    -Xms256M \
    -Xmx512M \
    -jar /opt/akhq/akhq.jar
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOFSVC

systemctl daemon-reload
systemctl enable akhq
systemctl start akhq

log "⏳ Waiting for AKHQ to start..."
for i in {1..60}; do
    if systemctl is-active --quiet akhq && curl -s http://localhost:8081/kafkamgr/ > /dev/null 2>&1; then
        break
    fi
    sleep 2
done

if ! systemctl is-active --quiet akhq; then
    error "AKHQ failed to start"
    journalctl -u akhq -n 50 --no-pager
    exit 1
fi

log "✅ AKHQ is running"
systemctl status akhq --no-pager -l | head -20 | tee -a "$LOG_FILE"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ AKHQ Setup Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🔗 Access AKHQ:"
echo "   Local:  http://localhost:8081/kafkamgr"
echo "   Public: http://$(curl -s ifconfig.me):8081/kafkamgr"
echo ""
echo "🔑 Credentials:"
echo "   Admin: ${ADMIN_USERNAME} / ${ADMIN_PASSWORD}"
echo "   Reader: user / user123"
echo ""
echo "⚙️  Kafka Connection:"
echo "   Broker: $KAFKA_BROKER"
echo ""
echo "📝 Logs:"
echo "   journalctl -u akhq -f"
echo ""
echo "📝 Setup log: $LOG_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

