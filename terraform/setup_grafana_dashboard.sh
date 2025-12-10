#!/bin/bash
# Automated Grafana Dashboard Setup for DStreamBolt
# This script configures the MySQL datasource and imports the dashboard

set -e

GRAFANA_URL="${1:-http://13.232.132.240:3000}"
GRAFANA_USER="${2:-admin}"
GRAFANA_PASSWORD="${3:-DStreamBolt2025!}"
MYSQL_HOST="${4:-localhost}"
MYSQL_PORT="${5:-3306}"
MYSQL_DB="${6:-dstreambolt_metrics}"
MYSQL_USER="${7:-dstreambolt}"
MYSQL_PASS="${8:-DStreamBolt2025!}"

echo "=========================================="
echo "📊 Setting Up Grafana Dashboard"
echo "=========================================="
echo ""
echo "Grafana URL: $GRAFANA_URL"
echo "MySQL Host: $MYSQL_HOST:$MYSQL_PORT"
echo "Database: $MYSQL_DB"
echo ""

# Check if dashboard JSON exists
if [ ! -f "../grafana/dstreambolt-dashboard.json" ]; then
    echo "❌ Error: dstreambolt-dashboard.json not found!"
    echo "Please run this script from the terraform directory."
    exit 1
fi

echo "1️⃣ Testing Grafana connectivity..."
if curl -s -f -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/health" > /dev/null; then
    echo "✅ Grafana is reachable"
else
    echo "❌ Cannot connect to Grafana at $GRAFANA_URL"
    echo "Please check:"
    echo "  - Grafana is running: sudo systemctl status grafana-server"
    echo "  - URL is correct: $GRAFANA_URL"
    echo "  - Credentials are correct"
    exit 1
fi

echo ""
echo "2️⃣ Checking if datasource already exists..."
DATASOURCE_ID=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
    "$GRAFANA_URL/api/datasources/name/DStreamBolt-MySQL" \
    | jq -r '.id // empty' 2>/dev/null)

if [ ! -z "$DATASOURCE_ID" ]; then
    echo "ℹ️  Datasource already exists (ID: $DATASOURCE_ID)"
    echo "   Updating existing datasource..."

    curl -s -X PUT -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
        -H "Content-Type: application/json" \
        "$GRAFANA_URL/api/datasources/$DATASOURCE_ID" \
        -d "{
          \"id\": $DATASOURCE_ID,
          \"name\": \"DStreamBolt-MySQL\",
          \"type\": \"mysql\",
          \"url\": \"$MYSQL_HOST:$MYSQL_PORT\",
          \"database\": \"$MYSQL_DB\",
          \"user\": \"$MYSQL_USER\",
          \"secureJsonData\": {
            \"password\": \"$MYSQL_PASS\"
          },
          \"access\": \"proxy\",
          \"isDefault\": true
        }" > /dev/null
    echo "✅ Datasource updated"
else
    echo "Creating new datasource..."

    RESPONSE=$(curl -s -X POST -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
        -H "Content-Type: application/json" \
        "$GRAFANA_URL/api/datasources" \
        -d "{
          \"name\": \"DStreamBolt-MySQL\",
          \"type\": \"mysql\",
          \"url\": \"$MYSQL_HOST:$MYSQL_PORT\",
          \"database\": \"$MYSQL_DB\",
          \"user\": \"$MYSQL_USER\",
          \"secureJsonData\": {
            \"password\": \"$MYSQL_PASS\"
          },
          \"access\": \"proxy\",
          \"isDefault\": true
        }")

    if echo "$RESPONSE" | grep -q '"message":"Datasource added"'; then
        echo "✅ Datasource created successfully"
    else
        echo "❌ Failed to create datasource"
        echo "Response: $RESPONSE"
        exit 1
    fi
fi

echo ""
echo "3️⃣ Testing datasource connection..."
sleep 2
TEST_RESULT=$(curl -s -X POST -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
    "$GRAFANA_URL/api/datasources/name/DStreamBolt-MySQL/health")

if echo "$TEST_RESULT" | grep -q '"status":"OK"'; then
    echo "✅ Datasource connection test passed"
else
    echo "⚠️  Datasource connection test failed"
    echo "Response: $TEST_RESULT"
    echo "Dashboard import will continue, but may not show data..."
fi

echo ""
echo "4️⃣ Importing dashboard..."

# Update datasource UID in dashboard JSON
DASHBOARD_JSON=$(cat ../grafana/dstreambolt-dashboard.json | jq '.dashboard.panels[].datasource = {"type": "mysql", "uid": "dstreambolt-mysql"}')

IMPORT_RESPONSE=$(curl -s -X POST -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
    -H "Content-Type: application/json" \
    "$GRAFANA_URL/api/dashboards/db" \
    -d "$DASHBOARD_JSON")

if echo "$IMPORT_RESPONSE" | grep -q '"status":"success"'; then
    DASHBOARD_URL=$(echo "$IMPORT_RESPONSE" | jq -r '.url')
    echo "✅ Dashboard imported successfully!"
    echo ""
    echo "=========================================="
    echo "✅ Setup Complete!"
    echo "=========================================="
    echo ""
    echo "📊 Dashboard URL:"
    echo "   $GRAFANA_URL$DASHBOARD_URL"
    echo ""
    echo "🔗 Or access via:"
    echo "   Grafana → Dashboards → Browse → DStreamBolt Real-Time Analytics"
    echo ""
    echo "📝 Credentials:"
    echo "   Username: $GRAFANA_USER"
    echo "   Password: $GRAFANA_PASSWORD"
    echo ""
    echo "🚀 Next Steps:"
    echo "   1. Start streaming Spark job with --mode streaming"
    echo "   2. Open dashboard URL above"
    echo "   3. Watch real-time data flowing!"
    echo ""
else
    echo "⚠️  Dashboard import may have failed"
    echo "Response: $IMPORT_RESPONSE"
    echo ""
    echo "You can import manually:"
    echo "   1. Open $GRAFANA_URL"
    echo "   2. Go to Dashboards → Import"
    echo "   3. Upload grafana/dstreambolt-dashboard.json"
fi

