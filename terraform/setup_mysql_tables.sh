#!/bin/bash
# Create MySQL tables for DStreamBolt analytics
# Run this script to set up all required tables

set -e

MYSQL_HOST="${1:-13.232.132.240}"
MYSQL_USER="${2:-dstreambolt}"
MYSQL_PASSWORD="${3:-DStreamBolt2025!}"
MYSQL_DATABASE="${4:-dstreambolt_metrics}"

echo "=========================================="
echo "🗄️  Creating MySQL Tables for DStreamBolt"
echo "=========================================="
echo ""
echo "Host: $MYSQL_HOST"
echo "User: $MYSQL_USER"
echo "Database: $MYSQL_DATABASE"
echo ""

# Check if SQL file exists
if [ ! -f "create_mysql_tables.sql" ]; then
    echo "❌ Error: create_mysql_tables.sql not found!"
    echo "Please run this script from the terraform directory."
    exit 1
fi

echo "📤 Uploading SQL file to DevOps node..."
scp -i ~/dstreambolt-access-key.pem create_mysql_tables.sql ubuntu@$MYSQL_HOST:/tmp/

echo ""
echo "🔧 Executing SQL script..."
ssh -i ~/dstreambolt-access-key.pem ubuntu@$MYSQL_HOST << EOSSH
mysql -u $MYSQL_USER -p'$MYSQL_PASSWORD' $MYSQL_DATABASE < /tmp/create_mysql_tables.sql
EOSSH

echo ""
echo "✅ Tables created successfully!"
echo ""
echo "📊 Verifying tables..."
ssh -i ~/dstreambolt-access-key.pem ubuntu@$MYSQL_HOST << EOSSH
mysql -u $MYSQL_USER -p'$MYSQL_PASSWORD' $MYSQL_DATABASE -e "SHOW TABLES;" 2>/dev/null
EOSSH

echo ""
echo "=========================================="
echo "✅ Database Setup Complete!"
echo "=========================================="
echo ""
echo "Created tables:"
echo "  • status_summary       - Status code aggregations"
echo "  • endpoint_summary     - Endpoint performance metrics"
echo "  • error_analysis       - Detailed error tracking"
echo "  • hourly_summary       - Long-term analytics"
echo "  • realtime_metrics     - Current dashboard metrics"
echo "  • spark_results        - Raw batch processing results"
echo ""

