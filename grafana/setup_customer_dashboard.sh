#!/bin/bash
# Setup Customer Analytics Dashboard
set -e

DEVOPS_HOST="13.232.132.240"
SSH_KEY="${SSH_KEY:-$HOME/dstreambolt-access-key.pem}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Setting Up Customer Analytics Dashboard"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Step 1: Copy SQL file to DevOps instance
echo "1️⃣  Copying SQL file to DevOps instance..."
scp -i "$SSH_KEY" ../sql/customer_analytics_tables.sql ubuntu@$DEVOPS_HOST:/tmp/ 2>/dev/null
echo "✅ SQL file copied"
echo ""

# Step 2: Create customer analytics tables
echo "2️⃣  Creating customer analytics tables in MySQL..."
ssh -i "$SSH_KEY" ubuntu@$DEVOPS_HOST << 'EOSSH'
mysql -h 10.0.1.61 -u dstreambolt -p'DStreamBolt2025!' dstreambolt_metrics < /tmp/customer_analytics_tables.sql
echo "✅ Tables created"
EOSSH
echo ""

# Step 3: Verify tables
echo "3️⃣  Verifying tables..."
ssh -i "$SSH_KEY" ubuntu@$DEVOPS_HOST << 'EOSSH'
mysql -h 10.0.1.61 -u dstreambolt -p'DStreamBolt2025!' dstreambolt_metrics -e "
SHOW TABLES LIKE '%summary%';
SHOW TABLES LIKE '%customer%';
"
EOSSH
echo "✅ Tables verified"
echo ""

# Step 4: Import dashboard to Grafana
echo "4️⃣  Importing Customer Analytics dashboard to Grafana..."

GRAFANA_HOST="13.232.132.240"
GRAFANA_PORT="3000"
GRAFANA_USER="admin"
GRAFANA_PASS="DStreamBolt2025!"

# Check Grafana connectivity
if ! curl -s -f -u "$GRAFANA_USER:$GRAFANA_PASS" \
    "http://$GRAFANA_HOST:$GRAFANA_PORT/api/health" > /dev/null; then
    echo "❌ Cannot connect to Grafana at http://$GRAFANA_HOST:$GRAFANA_PORT"
    echo "   Please check if Grafana is running"
    exit 1
fi

# Import dashboard
curl -X POST -H "Content-Type: application/json" \
    -u "$GRAFANA_USER:$GRAFANA_PASS" \
    -d @customer-analytics-dashboard.json \
    "http://$GRAFANA_HOST:$GRAFANA_PORT/api/dashboards/db" -s | grep -q "success" && echo "✅ Dashboard imported" || echo "⚠️  Dashboard import may have failed"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Setup Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 Customer Analytics Dashboard:"
echo "   http://$GRAFANA_HOST:$GRAFANA_PORT/d/customer-analytics"
echo ""
echo "🔍 Verify Tables:"
echo "   mysql -h 10.0.1.61 -u dstreambolt -p'DStreamBolt2025!' dstreambolt_metrics"
echo "   SELECT COUNT(*) FROM status_summary;"
echo "   SELECT COUNT(*) FROM endpoint_summary;"
echo ""
echo "📈 The dashboard shows:"
echo "   • Total requests and error rates"
echo "   • Response time percentiles (avg, p95, p99)"
echo "   • Status code distribution"
echo "   • Top slowest endpoints"
echo "   • Most requested endpoints"
echo "   • Error analysis by endpoint"
echo "   • Traffic trends over time"
echo ""
echo "⚠️  Note: Dashboard will show data after Spark job processes logs"
echo "   Run Spark job to populate data:"
echo "   jenkins.dstreambolt.dashbird.com → DStreamBolt-Deploy-Spark-Scala"
echo ""

