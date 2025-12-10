#!/bin/bash
# Fix Grafana Dashboard - Import New DevOps Dashboard
# This script uploads and imports the corrected dashboard to Grafana

set -e

GRAFANA_HOST="${1:-13.232.132.240}"
GRAFANA_PORT="${2:-3000}"
GRAFANA_USER="${3:-admin}"
GRAFANA_PASS="${4:-DStreamBolt2025!}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 Fixing Grafana Dashboard"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Grafana: http://$GRAFANA_HOST:$GRAFANA_PORT"
echo "User: $GRAFANA_USER"
echo ""

# Check if dashboard file exists
if [ ! -f "devops-dashboard.json" ]; then
    echo "❌ devops-dashboard.json not found!"
    echo "   Make sure you're in the grafana directory"
    exit 1
fi

echo "1️⃣  Testing Grafana connection..."
if ! curl -s -f -u "$GRAFANA_USER:$GRAFANA_PASS" \
    "http://$GRAFANA_HOST:$GRAFANA_PORT/api/health" > /dev/null; then
    echo "❌ Cannot connect to Grafana"
    echo "   Check if Grafana is running: ssh ubuntu@$GRAFANA_HOST 'sudo systemctl status grafana-server'"
    exit 1
fi
echo "✅ Grafana is reachable"
echo ""

echo "2️⃣  Checking MySQL data source..."
DATASOURCE_CHECK=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" \
    "http://$GRAFANA_HOST:$GRAFANA_PORT/api/datasources/name/DStreamBolt%20MySQL" \
    -w "%{http_code}" -o /tmp/datasource_response.txt)

if [ "$DATASOURCE_CHECK" = "404" ]; then
    echo "⚠️  MySQL data source not found. Creating..."

    curl -X POST -H "Content-Type: application/json" \
        -u "$GRAFANA_USER:$GRAFANA_PASS" \
        -d '{
          "name": "DStreamBolt MySQL",
          "type": "mysql",
          "access": "proxy",
          "url": "10.0.1.61:3306",
          "database": "dstreambolt_metrics",
          "user": "dstreambolt",
          "secureJsonData": {
            "password": "DStreamBolt2025!"
          },
          "isDefault": true
        }' \
        "http://$GRAFANA_HOST:$GRAFANA_PORT/api/datasources"

    echo ""
    echo "✅ MySQL data source created"
else
    echo "✅ MySQL data source exists"
fi
echo ""

echo "3️⃣  Importing DevOps dashboard..."

# Prepare dashboard JSON for import
cat devops-dashboard.json | jq '{
  dashboard: .dashboard,
  overwrite: true,
  inputs: [],
  folderId: 0
}' > /tmp/import_dashboard.json

# Import dashboard
RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -u "$GRAFANA_USER:$GRAFANA_PASS" \
    -d @/tmp/import_dashboard.json \
    "http://$GRAFANA_HOST:$GRAFANA_PORT/api/dashboards/db")

echo "$RESPONSE" | jq .

if echo "$RESPONSE" | grep -q '"status":"success"'; then
    echo "✅ Dashboard imported successfully!"

    # Get dashboard URL
    DASHBOARD_URL=$(echo "$RESPONSE" | jq -r '.url // empty')
    if [ ! -z "$DASHBOARD_URL" ]; then
        echo ""
        echo "📊 Dashboard URL: http://$GRAFANA_HOST:$GRAFANA_PORT$DASHBOARD_URL"
    fi
else
    echo "❌ Failed to import dashboard"
    echo "$RESPONSE"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Dashboard Fixed!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 Access Dashboard:"
echo "   http://$GRAFANA_HOST:$GRAFANA_PORT/dashboards"
echo ""
echo "🔍 Verify Data:"
echo "   mysql -h 10.0.1.61 -u dstreambolt -p'DStreamBolt2025!' dstreambolt_metrics"
echo "   SELECT * FROM ingestion_requests ORDER BY timestamp DESC LIMIT 5;"
echo ""
echo "📖 Full Guide: grafana/FIX_DASHBOARD.md"
echo ""

