#!/bin/bash
# Quick deployment checklist for mTLS-enabled ingestion service

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     DStreamBolt Ingestion mTLS Deployment Checklist         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

INGEST_IP="${1:-}"

if [ -z "$INGEST_IP" ]; then
    echo "Usage: $0 <ingestion-server-ip>"
    echo ""
    echo "Example: $0 3.109.132.244"
    exit 1
fi

echo "Target: $INGEST_IP"
echo ""

# Function to check status
check_status() {
    if [ $? -eq 0 ]; then
        echo "  ✅ PASS"
    else
        echo "  ❌ FAIL"
        FAILED=1
    fi
}

FAILED=0

echo "1️⃣  Checking local files..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo -n "app.py syntax..."
python3 -m py_compile ingestion/app.py 2>/dev/null
check_status

echo -n "certificates generated..."
[ -f "certs/ca/ca-cert.pem" ] && [ -f "certs/client/client-cert.pem" ]
check_status

echo -n "enable_mtls.sh exists..."
[ -f "enable_mtls.sh" ] && [ -x "enable_mtls.sh" ]
check_status

echo ""

echo "2️⃣  Checking SSH connectivity..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo -n "Can reach server..."
ssh -o ConnectTimeout=5 -o BatchMode=yes ubuntu@$INGEST_IP exit 2>/dev/null
check_status

echo ""

if [ $FAILED -eq 1 ]; then
    echo "❌ Pre-flight checks failed!"
    echo ""
    echo "Fix the issues above before deploying."
    exit 1
fi

echo "✅ All pre-flight checks passed!"
echo ""

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                  Deployment Steps                           ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

echo "Run these commands to deploy:"
echo ""

echo "# 1. Deploy code via Jenkins"
echo "   Go to: http://jenkins.dstreambolt.dashbird.com/jenkins"
echo "   Job: DStreamBolt-Deploy-Ingestion"
echo "   Parameters:"
echo "     TARGET_IPS: $INGEST_IP"
echo "     GIT_BRANCH: release/v1.0.1"
echo ""

echo "# 2. Copy certificates to server"
echo "   scp -r certs/ca certs/server ubuntu@$INGEST_IP:/etc/dstreambolt/certs/"
echo ""

echo "# 3. Copy enable script"
echo "   scp enable_mtls.sh ubuntu@$INGEST_IP:/tmp/"
echo ""

echo "# 4. Enable mTLS"
echo "   ssh ubuntu@$INGEST_IP 'sudo bash /tmp/enable_mtls.sh'"
echo ""

echo "# 5. Verify"
echo "   ssh ubuntu@$INGEST_IP 'sudo journalctl -u dstreambolt-ingest -n 50 | grep mTLS'"
echo ""

echo "# 6. Test"
echo "   python3 examples/02-send-to-ingest.py logs/access.log \\"
echo "     --alb-url https://ingest.dstreambolt.dashbird.com \\"
echo "     --client-cert certs/client/client-cert.pem \\"
echo "     --client-key certs/client/client-key.pem \\"
echo "     --ca-cert certs/ca/ca-cert.pem"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Quick deploy (automatic):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "# Copy and enable in one step"
echo "scp -r certs/ca certs/server enable_mtls.sh ubuntu@$INGEST_IP:/tmp/ && \\"
echo "ssh ubuntu@$INGEST_IP 'sudo mv /tmp/ca /tmp/server /etc/dstreambolt/certs/ && sudo bash /tmp/enable_mtls.sh'"
echo ""

