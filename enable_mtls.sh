#!/bin/bash
# Enable mTLS on DStreamBolt Ingestion Service
# Run this script on the ingestion server

set -e

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       Enable mTLS on DStreamBolt Ingestion Service          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

CERT_DIR="/etc/dstreambolt/certs"
SERVICE_NAME="dstreambolt-ingest"

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ] && [ -z "$SUDO_USER" ]; then
    echo "❌ This script must be run as root or with sudo"
    echo "   Usage: sudo bash $0"
    exit 1
fi

echo "1️⃣  Checking certificate files..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check if certificates exist
CA_CERT="$CERT_DIR/ca/ca-cert.pem"
SERVER_CERT="$CERT_DIR/server/server-cert.pem"
SERVER_KEY="$CERT_DIR/server/server-key.pem"

if [ ! -f "$CA_CERT" ]; then
    echo "❌ CA certificate not found: $CA_CERT"
    echo ""
    echo "Please copy certificates to this server first:"
    echo "  scp -r certs/ca ubuntu@$(hostname -I | awk '{print $1}'):/etc/dstreambolt/certs/"
    echo "  scp -r certs/server ubuntu@$(hostname -I | awk '{print $1}'):/etc/dstreambolt/certs/"
    exit 1
fi

echo "✅ CA certificate found: $CA_CERT"

if [ -f "$SERVER_CERT" ]; then
    echo "✅ Server certificate found: $SERVER_CERT"
fi

if [ -f "$SERVER_KEY" ]; then
    echo "✅ Server key found: $SERVER_KEY"
fi

# Verify certificate is valid PEM
if ! openssl x509 -in "$CA_CERT" -text -noout > /dev/null 2>&1; then
    echo "❌ CA certificate is not a valid X.509 certificate"
    exit 1
fi

echo "✅ CA certificate is valid"
echo ""

echo "2️⃣  Checking cryptography library..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Find Python and venv
DEPLOY_PATH=$(systemctl show $SERVICE_NAME -p WorkingDirectory --value 2>/dev/null)
if [ -z "$DEPLOY_PATH" ]; then
    echo "⚠️  Could not determine service working directory"
    DEPLOY_PATH="/opt/dstreambolt/ingest"
fi

echo "Service working directory: $DEPLOY_PATH"

if [ -f "$DEPLOY_PATH/venv/bin/python3" ]; then
    echo "✅ Virtual environment found"

    # Check if cryptography is installed
    if $DEPLOY_PATH/venv/bin/python3 -c "import cryptography" 2>/dev/null; then
        CRYPTO_VERSION=$($DEPLOY_PATH/venv/bin/python3 -c "import cryptography; print(cryptography.__version__)")
        echo "✅ cryptography library installed (version $CRYPTO_VERSION)"
    else
        echo "⚠️  cryptography library not found, installing..."
        $DEPLOY_PATH/venv/bin/pip install cryptography>=41.0.0 --quiet
        echo "✅ cryptography library installed"
    fi
else
    echo "❌ Virtual environment not found at $DEPLOY_PATH/venv"
    exit 1
fi

echo ""

echo "3️⃣  Configuring systemd service..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Create systemd override directory
OVERRIDE_DIR="/etc/systemd/system/${SERVICE_NAME}.service.d"
mkdir -p "$OVERRIDE_DIR"

# Create mTLS configuration
cat > "$OVERRIDE_DIR/mtls.conf" << EOF
[Service]
# Enable mTLS authentication
Environment="MTLS_ENABLED=true"
Environment="MTLS_CA_CERT_PATH=$CA_CERT"
Environment="MTLS_CHECK_CRL=false"

# Optional: Set server certificates (if using native HTTPS)
# Environment="MTLS_SERVER_CERT_PATH=$SERVER_CERT"
# Environment="MTLS_SERVER_KEY_PATH=$SERVER_KEY"
EOF

echo "✅ mTLS configuration created: $OVERRIDE_DIR/mtls.conf"
cat "$OVERRIDE_DIR/mtls.conf"

echo ""

echo "4️⃣  Reloading systemd and restarting service..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

systemctl daemon-reload
echo "✅ systemd configuration reloaded"

echo "Restarting $SERVICE_NAME..."
systemctl restart $SERVICE_NAME

echo "Waiting for service to start..."
sleep 5

if systemctl is-active --quiet $SERVICE_NAME; then
    echo "✅ Service is running"
else
    echo "❌ Service failed to start"
    echo ""
    echo "Check logs:"
    echo "  sudo journalctl -u $SERVICE_NAME -n 50"
    exit 1
fi

echo ""

echo "5️⃣  Verifying mTLS configuration..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check logs for mTLS messages
sleep 2

if journalctl -u $SERVICE_NAME --since "10 seconds ago" | grep -q "mTLS authentication enabled"; then
    echo "✅ mTLS is enabled in service logs"

    # Show mTLS configuration from logs
    echo ""
    echo "Service configuration:"
    journalctl -u $SERVICE_NAME --since "10 seconds ago" | grep -A 3 "mTLS authentication enabled" | head -5
else
    echo "⚠️  Could not confirm mTLS from logs"
    echo ""
    echo "Recent logs:"
    journalctl -u $SERVICE_NAME --since "10 seconds ago" | tail -10
fi

echo ""

echo "6️⃣  Testing health endpoint..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if curl -s http://localhost:5000/health > /dev/null 2>&1; then
    echo "✅ Health endpoint responding"
    curl -s http://localhost:5000/health | python3 -m json.tool 2>/dev/null || curl -s http://localhost:5000/health
else
    echo "⚠️  Health endpoint not responding"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                  mTLS Configuration Complete                ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "✅ mTLS is now ENABLED on the ingestion service"
echo ""
echo "Important Notes:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Clients MUST now provide valid client certificates"
echo "2. Client certificates must be signed by: $CA_CERT"
echo "3. Requests without certificates will be REJECTED"
echo ""
echo "Testing:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "# Without certificate (will fail):"
echo "  curl -X POST http://localhost:5000/ingest -H 'Content-Type: application/gzip'"
echo ""
echo "# With certificate (via ALB with mTLS):"
echo "  python3 examples/02-send-to-ingest.py logs/access.log \\"
echo "    --alb-url https://ingest.dstreambolt.dashbird.com \\"
echo "    --client-cert certs/client/client-cert.pem \\"
echo "    --client-key certs/client/client-key.pem \\"
echo "    --ca-cert certs/ca/ca-cert.pem"
echo ""
echo "View logs:"
echo "  sudo journalctl -u $SERVICE_NAME -f"
echo ""
echo "To DISABLE mTLS:"
echo "  sudo rm $OVERRIDE_DIR/mtls.conf"
echo "  sudo systemctl daemon-reload"
echo "  sudo systemctl restart $SERVICE_NAME"
echo ""

