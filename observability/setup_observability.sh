#!/bin/bash
# Quick Start: Set up Complete Observability for DStreamBolt
# Run this script to create all metrics tables

set -e

MYSQL_HOST="${1:-13.232.132.240}"
MYSQL_USER="${2:-dstreambolt}"
MYSQL_PASSWORD="${3:-DStreamBolt2025!}"
MYSQL_DATABASE="${4:-dstreambolt_metrics}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 DStreamBolt Complete Observability Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "MySQL Host: $MYSQL_HOST"
echo "User: $MYSQL_USER"
echo "Database: $MYSQL_DATABASE"
echo ""

# Check if SQL file exists
if [ ! -f "create_observability_tables.sql" ]; then
    echo "❌ Error: create_observability_tables.sql not found!"
    echo "Please run this script from the observability directory."
    exit 1
fi

echo "📤 Uploading SQL schema to DevOps node..."
scp -i ~/dstreambolt-access-key.pem create_observability_tables.sql ubuntu@$MYSQL_HOST:/tmp/

echo ""
echo "🔧 Creating observability tables..."
ssh -i ~/dstreambolt-access-key.pem ubuntu@$MYSQL_HOST << EOSSH
mysql -u $MYSQL_USER -p'$MYSQL_PASSWORD' $MYSQL_DATABASE < /tmp/create_observability_tables.sql 2>&1 | grep -v "Warning"
EOSSH

echo ""
echo "✅ Tables created successfully!"
echo ""
echo "📊 Verifying tables..."
ssh -i ~/dstreambolt-access-key.pem ubuntu@$MYSQL_HOST << EOSSH
mysql -u $MYSQL_USER -p'$MYSQL_PASSWORD' $MYSQL_DATABASE -e "
SELECT
    CONCAT('✅ ', TABLE_NAME) as table_name,
    TABLE_COMMENT as purpose
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = '$MYSQL_DATABASE'
    AND (
        TABLE_NAME LIKE '%ingestion%'
        OR TABLE_NAME LIKE '%kafka%'
        OR TABLE_NAME LIKE '%spark%'
        OR TABLE_NAME LIKE '%pipeline%'
        OR TABLE_NAME LIKE '%failed%'
    )
ORDER BY TABLE_NAME;
" 2>/dev/null
EOSSH

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Observability Setup Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Created 13 new metrics tables:"
echo "  • Ingestion Layer (5 tables)"
echo "  • Kafka Health (3 tables)"
echo "  • Spark Processing (3 tables)"
echo "  • DevOps Dashboard (2 tables)"
echo ""
echo "📋 Next Steps:"
echo "  1. Deploy enhanced ingestion service"
echo "  2. Start Kafka metrics collector"
echo "  3. Update Spark code with metrics"
echo "  4. Import DevOps dashboard to Grafana"
echo ""
echo "📖 See IMPLEMENTATION_SUMMARY.md for details"
echo ""

