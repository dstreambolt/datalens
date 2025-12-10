#!/bin/bash
# Fix MySQL Authentication for DStreamBolt
# Run this on the DevOps node (13.232.132.240)

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 Fixing MySQL Authentication"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 1. Create dstreambolt user with password authentication
echo "📝 Creating dstreambolt user with password authentication..."
sudo mysql << 'EOSQL'
-- Drop user if exists
DROP USER IF EXISTS 'dstreambolt'@'%';
DROP USER IF EXISTS 'dstreambolt'@'localhost';

-- Create database
CREATE DATABASE IF NOT EXISTS dstreambolt_metrics;

-- Create user with password authentication
CREATE USER 'dstreambolt'@'%' IDENTIFIED BY 'DStreamBolt2025!';
CREATE USER 'dstreambolt'@'localhost' IDENTIFIED BY 'DStreamBolt2025!';

-- Grant privileges
GRANT ALL PRIVILEGES ON dstreambolt_metrics.* TO 'dstreambolt'@'%';
GRANT ALL PRIVILEGES ON dstreambolt_metrics.* TO 'dstreambolt'@'localhost';

-- Also create tables if they don't exist
USE dstreambolt_metrics;

CREATE TABLE IF NOT EXISTS ingestion_metrics (
    id INT AUTO_INCREMENT PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    request_id VARCHAR(255),
    bundle_size_bytes INT,
    uncompressed_size_bytes INT,
    status VARCHAR(50),
    processing_time_ms INT,
    kafka_topic VARCHAR(255),
    error_message TEXT,
    INDEX(request_id),
    INDEX(timestamp),
    INDEX(status)
);

CREATE TABLE IF NOT EXISTS bundle_status (
    id INT AUTO_INCREMENT PRIMARY KEY,
    request_id VARCHAR(255) UNIQUE,
    status VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX(request_id),
    INDEX(status)
);

CREATE TABLE IF NOT EXISTS spark_results (
    id INT AUTO_INCREMENT PRIMARY KEY,
    timestamp VARCHAR(50),
    ip VARCHAR(50),
    method VARCHAR(10),
    endpoint VARCHAR(255),
    status INT,
    size INT,
    referer TEXT,
    user_agent TEXT,
    response_time DOUBLE,
    request_id VARCHAR(255),
    ingestion_timestamp VARCHAR(50),
    processing_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX(timestamp),
    INDEX(status),
    INDEX(endpoint),
    INDEX(request_id)
);

FLUSH PRIVILEGES;
EOSQL

echo "✅ User 'dstreambolt' created successfully"

# 2. Configure MySQL to listen on all interfaces
echo ""
echo "📝 Configuring MySQL to accept remote connections..."
sudo sed -i 's/bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf

# 3. Restart MySQL
echo ""
echo "🔄 Restarting MySQL..."
sudo systemctl restart mysql

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ MySQL Configuration Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Connection Details:"
echo "   Host: 13.232.132.240"
echo "   User: dstreambolt"
echo "   Password: DStreamBolt2025!"
echo "   Database: dstreambolt_metrics"
echo ""
echo "🔍 Test connection:"
echo "   mysql -u dstreambolt -p'DStreamBolt2025!' dstreambolt_metrics"
echo ""
echo "📊 For root access (sudo only):"
echo "   sudo mysql"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

