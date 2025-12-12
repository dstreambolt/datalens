#!/bin/bash
# Quick fix for ingestion service MySQL schema error
# Run this on the ingestion server: ubuntu@ip-10-0-1-72

set -e

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   Quick Fix: Ingestion MySQL Schema Error                   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

echo "Error being fixed:"
echo "  Unknown column 'updated_at' in 'field list'"
echo ""
echo "Solution:"
echo "  Updated app.py to use correct column name (last_updated)"
echo ""

# Check if deployment path exists
if [ ! -d /opt/dstreambolt/ingest ]; then
    echo "❌ ERROR: /opt/dstreambolt/ingest not found!"
    echo "   Please deploy the application first via Jenkins"
    exit 1
fi

# Stop service
echo "1️⃣  Stopping service..."
sudo systemctl stop dstreambolt-ingest

# Backup current app.py
echo "2️⃣  Backing up current app.py..."
cp /opt/dstreambolt/ingest/app.py /opt/dstreambolt/ingest/app.py.backup.$(date +%Y%m%d_%H%M%S)

# Fix the code (replace updated_at with correct approach)
echo "3️⃣  Applying fix to app.py..."

# Create the fixed version
cat > /tmp/fix_metrics.py << 'PYTHON_EOF'
import sys
import re

# Read the file
with open('/opt/dstreambolt/ingest/app.py', 'r') as f:
    content = f.read()

# Pattern 1: Fix INSERT with updated_at
content = re.sub(
    r'INSERT INTO ingestion_realtime_metrics \(metric_name, metric_value, updated_at\)',
    'INSERT INTO ingestion_realtime_metrics (metric_name, metric_value)',
    content
)

# Pattern 2: Fix ON DUPLICATE KEY UPDATE with updated_at
content = re.sub(
    r'ON DUPLICATE KEY UPDATE metric_value = %s, updated_at = NOW\(\)',
    'ON DUPLICATE KEY UPDATE metric_value = %s',
    content
)

# Write back
with open('/opt/dstreambolt/ingest/app.py', 'w') as f:
    f.write(content)

print("✅ Fixed app.py")
PYTHON_EOF

python3 /tmp/fix_metrics.py

# Verify the fix
echo "4️⃣  Verifying fix..."
if grep -q "updated_at" /opt/dstreambolt/ingest/app.py; then
    echo "⚠️  WARNING: Still found 'updated_at' in app.py"
    grep -n "updated_at" /opt/dstreambolt/ingest/app.py
else
    echo "✅ No more 'updated_at' references found"
fi

# Start service
echo "5️⃣  Starting service..."
sudo systemctl start dstreambolt-ingest

# Wait for startup
echo "6️⃣  Waiting for service to start..."
sleep 5

# Check status
echo "7️⃣  Checking service status..."
sudo systemctl status dstreambolt-ingest --no-pager | head -20

# Check for errors
echo ""
echo "8️⃣  Checking for MySQL errors in logs..."
if sudo journalctl -u dstreambolt-ingest --since "1 minute ago" | grep -q "Unknown column"; then
    echo "⚠️  Still seeing MySQL errors:"
    sudo journalctl -u dstreambolt-ingest --since "1 minute ago" | grep "Unknown column"
else
    echo "✅ No MySQL schema errors found!"
fi

# Test health endpoint
echo ""
echo "9️⃣  Testing health endpoint..."
if curl -s http://localhost:5000/health | grep -q "healthy"; then
    echo "✅ Service is healthy!"
    curl -s http://localhost:5000/health | python3 -m json.tool | head -20
else
    echo "⚠️  Health check failed"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    Fix Complete! ✅                           ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "The service should now run without MySQL schema errors."
echo ""
echo "To monitor logs:"
echo "  sudo journalctl -u dstreambolt-ingest -f"
echo ""
echo "To check metrics:"
echo "  curl http://localhost:5000/metrics"
echo ""

