#!/bin/bash

###############################################################################
# AKHQ Username/Password Configuration Script
# Run this on the DevOps node to set AKHQ authentication
###############################################################################

set -e

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     AKHQ Authentication Configuration                        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Check if running as root or sudo
if [ "$EUID" -ne 0 ]; then
    echo "❌ Please run as root or with sudo"
    echo "Usage: sudo bash set_akhq_credentials.sh"
    exit 1
fi

# Get credentials from user
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Enter AKHQ Admin Credentials"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

read -p "Admin username [default: admin]: " ADMIN_USER
ADMIN_USER=${ADMIN_USER:-admin}

read -sp "Admin password [default: DStreamBolt2025!]: " ADMIN_PASS
echo ""
ADMIN_PASS=${ADMIN_PASS:-DStreamBolt2025!}

echo ""
read -p "Read-only username [default: user]: " READONLY_USER
READONLY_USER=${READONLY_USER:-user}

read -sp "Read-only password [default: user123]: " READONLY_PASS
echo ""
READONLY_PASS=${READONLY_PASS:-user123}

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Configuration Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Admin User:"
echo "  Username: $ADMIN_USER"
echo "  Password: ********"
echo ""
echo "Read-Only User:"
echo "  Username: $READONLY_USER"
echo "  Password: ********"
echo ""

read -p "Continue with this configuration? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "❌ Configuration cancelled"
    exit 0
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 1: Backing up current configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -f /opt/akhq/application.yml ]; then
    BACKUP_FILE="/opt/akhq/application.yml.backup.$(date +%Y%m%d_%H%M%S)"
    cp /opt/akhq/application.yml "$BACKUP_FILE"
    echo "✅ Backup created: $BACKUP_FILE"
else
    echo "⚠️  No existing configuration found"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 2: Creating new configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Get Kafka broker IP (detect from existing config or use default)
KAFKA_BROKER="10.0.10.248:9092"
if [ -f /opt/akhq/application.yml ]; then
    EXISTING_BROKER=$(grep "bootstrap.servers:" /opt/akhq/application.yml | awk '{print $2}' | tr -d '"' || echo "")
    if [ ! -z "$EXISTING_BROKER" ]; then
        KAFKA_BROKER="$EXISTING_BROKER"
    fi
fi

echo "Using Kafka broker: $KAFKA_BROKER"

# Create new configuration
cat > /opt/akhq/application.yml << EOF
akhq:
  server:
    base-path: "/kafkamgr"

  connections:
    dstreambolt:
      properties:
        bootstrap.servers: "$KAFKA_BROKER"

  security:
    default-group: admin
    basic-auth:
      - username: $ADMIN_USER
        password: $ADMIN_PASS
        groups:
          - admin
      - username: $READONLY_USER
        password: $READONLY_PASS
        groups:
          - reader

micronaut:
  server:
    port: 8085
    context-path: /kafkamgr

  security:
    enabled: true
    authentication: session

    token:
      jwt:
        enabled: false
EOF

echo "✅ Configuration file created"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 3: Setting correct permissions"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

chown root:root /opt/akhq/application.yml
chmod 644 /opt/akhq/application.yml
echo "✅ Permissions set"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 4: Restarting AKHQ service"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

systemctl restart akhq
echo "⏳ Waiting for AKHQ to start..."
sleep 15

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 5: Verifying service status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if systemctl is-active --quiet akhq; then
    echo "✅ AKHQ service is running"

    # Test endpoint
    echo ""
    echo "Testing endpoint..."
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8085/kafkamgr/ui 2>/dev/null || echo "000")

    if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "302" ]; then
        echo "✅ AKHQ is responding (HTTP $HTTP_STATUS)"
    else
        echo "⚠️  AKHQ returned HTTP $HTTP_STATUS"
        echo "This may be normal during startup. Wait a moment and try accessing."
    fi
else
    echo "❌ AKHQ service is not running"
    echo ""
    echo "Checking logs..."
    journalctl -u akhq -n 20 --no-pager
    exit 1
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              ✅ Configuration Complete!                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "AKHQ authentication has been configured successfully!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Access Information"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Get public IP
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "YOUR_PUBLIC_IP")

echo "URL: http://$PUBLIC_IP/kafkamgr/"
echo ""
echo "Admin Credentials (Full Access):"
echo "  Username: $ADMIN_USER"
echo "  Password: $ADMIN_PASS"
echo ""
echo "Read-Only Credentials:"
echo "  Username: $READONLY_USER"
echo "  Password: $READONLY_PASS"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📝 Save these credentials in a secure location!"
echo ""
echo "To view logs:"
echo "  sudo journalctl -u akhq -f"
echo ""
echo "To restart AKHQ:"
echo "  sudo systemctl restart akhq"
echo ""
echo "Configuration file:"
echo "  /opt/akhq/application.yml"
echo ""
echo "Backup file:"
echo "  $BACKUP_FILE"
echo ""

