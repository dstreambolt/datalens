#!/bin/bash

###############################################################################
# MySQL Setup Script
# Installs and configures MySQL with DStreamBolt schema
###############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/mysql-setup.log"

# Default configuration
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-DStreamBolt2025!}"
DATABASE_NAME="${DATABASE_NAME:-dstreambolt_metrics}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN:${NC} $1" | tee -a "$LOG_FILE"
}

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              MySQL Setup Script                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

if [ "$EUID" -ne 0 ]; then
    error "Please run as root or with sudo"
    exit 1
fi

# Check if MySQL is already installed
if systemctl is-active --quiet mysql 2>/dev/null; then
    log "✅ MySQL is already running"
    read -p "Do you want to reconfigure? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        SKIP_INSTALL=true
    else
        SKIP_INSTALL=false
    fi
else
    SKIP_INSTALL=false
fi

if [ "$SKIP_INSTALL" != "true" ]; then
    log "📦 Installing MySQL..."

    # Set debconf selections for unattended install
    debconf-set-selections <<< "mysql-server mysql-server/root_password password $MYSQL_ROOT_PASSWORD"
    debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $MYSQL_ROOT_PASSWORD"

    apt-get update -qq
    apt-get install -y mysql-server mysql-client
fi

log "🔧 Configuring MySQL..."

# Configure MySQL to accept connections from all interfaces
cat > /etc/mysql/mysql.conf.d/dstreambolt.cnf << EOFMYSQL
[mysqld]
bind-address = 0.0.0.0
max_connections = 500
max_allowed_packet = 64M

# InnoDB settings
innodb_buffer_pool_size = 256M
innodb_log_file_size = 64M
innodb_flush_log_at_trx_commit = 2

# Query cache
query_cache_type = 1
query_cache_size = 32M

# Logging
general_log = 0
slow_query_log = 1
slow_query_log_file = /var/log/mysql/mysql-slow.log
long_query_time = 2
EOFMYSQL

log "🚀 Starting MySQL..."
systemctl enable mysql
systemctl restart mysql

# Wait for MySQL to start
log "⏳ Waiting for MySQL to initialize..."
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        break
    fi
    sleep 2
done

if ! systemctl is-active --quiet mysql; then
    error "MySQL failed to start"
    journalctl -u mysql -n 50 --no-pager
    exit 1
fi

log "✅ MySQL is running"

# Set root password if not already set
log "🔐 Configuring root access..."
mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}';" 2>/dev/null || \
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1;" > /dev/null 2>&1 || \
warn "Root password may already be set"

# Create database and tables
log "📊 Creating database and tables..."

mysql -u root -p"${MYSQL_ROOT_PASSWORD}" << EOFSQL
-- Create database
CREATE DATABASE IF NOT EXISTS ${DATABASE_NAME};
USE ${DATABASE_NAME};

-- Ingestion metrics table
CREATE TABLE IF NOT EXISTS ingestion_metrics (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    instance_id VARCHAR(50),
    requests_received BIGINT DEFAULT 0,
    requests_processed BIGINT DEFAULT 0,
    requests_failed BIGINT DEFAULT 0,
    bytes_received BIGINT DEFAULT 0,
    kafka_messages_sent BIGINT DEFAULT 0,
    kafka_send_failures BIGINT DEFAULT 0,
    queue_size INT DEFAULT 0,
    processing_time_ms FLOAT DEFAULT 0,
    INDEX idx_timestamp (timestamp),
    INDEX idx_instance (instance_id)
) ENGINE=InnoDB;

-- Bundle processing table
CREATE TABLE IF NOT EXISTS bundle_processing (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    bundle_id VARCHAR(100) UNIQUE,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    instance_id VARCHAR(50),
    size_bytes BIGINT,
    status ENUM('received', 'processing', 'completed', 'failed') DEFAULT 'received',
    lines_count INT,
    kafka_topic VARCHAR(100),
    processing_time_ms FLOAT,
    error_message TEXT,
    INDEX idx_timestamp (timestamp),
    INDEX idx_status (status),
    INDEX idx_instance (instance_id)
) ENGINE=InnoDB;

-- Endpoint summary table (Spark writes here)
CREATE TABLE IF NOT EXISTS endpoint_summary (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    window_start TIMESTAMP,
    window_end TIMESTAMP,
    endpoint VARCHAR(255),
    method VARCHAR(10),
    request_count BIGINT,
    avg_response_time FLOAT,
    p95_response_time FLOAT,
    p99_response_time FLOAT,
    error_count BIGINT,
    processing_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_window (window_start),
    INDEX idx_endpoint (endpoint)
) ENGINE=InnoDB;

-- Status summary table (Spark writes here)
CREATE TABLE IF NOT EXISTS status_summary (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    window_start TIMESTAMP,
    window_end TIMESTAMP,
    status INT,
    request_count BIGINT,
    avg_response_size FLOAT,
    avg_response_time FLOAT,
    max_response_time FLOAT,
    min_response_time FLOAT,
    processing_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_window (window_start),
    INDEX idx_status (status)
) ENGINE=InnoDB;

-- Kafka metrics table
CREATE TABLE IF NOT EXISTS kafka_metrics (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    broker_id INT,
    topic VARCHAR(255),
    partition_id INT,
    leader INT,
    replicas TEXT,
    isr TEXT,
    size_bytes BIGINT,
    offset_earliest BIGINT,
    offset_latest BIGINT,
    messages_count BIGINT,
    INDEX idx_timestamp (timestamp),
    INDEX idx_topic (topic)
) ENGINE=InnoDB;

-- Kafka consumer lag table
CREATE TABLE IF NOT EXISTS kafka_consumer_lag (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    consumer_group VARCHAR(255),
    topic VARCHAR(255),
    partition_id INT,
    current_offset BIGINT,
    log_end_offset BIGINT,
    lag BIGINT,
    INDEX idx_timestamp (timestamp),
    INDEX idx_consumer_group (consumer_group),
    INDEX idx_topic (topic)
) ENGINE=InnoDB;

-- Spark job metrics table
CREATE TABLE IF NOT EXISTS spark_job_metrics (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    job_id VARCHAR(100),
    application_id VARCHAR(100),
    status ENUM('RUNNING', 'SUCCEEDED', 'FAILED') DEFAULT 'RUNNING',
    records_processed BIGINT DEFAULT 0,
    records_failed BIGINT DEFAULT 0,
    processing_time_ms BIGINT,
    batch_id BIGINT,
    INDEX idx_timestamp (timestamp),
    INDEX idx_job (job_id),
    INDEX idx_status (status)
) ENGINE=InnoDB;

-- Create remote access user
CREATE USER IF NOT EXISTS 'dstreambolt'@'%' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
GRANT ALL PRIVILEGES ON ${DATABASE_NAME}.* TO 'dstreambolt'@'%';

CREATE USER IF NOT EXISTS 'dstreambolt'@'10.0.%' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
GRANT ALL PRIVILEGES ON ${DATABASE_NAME}.* TO 'dstreambolt'@'10.0.%';

FLUSH PRIVILEGES;

-- Show tables
SHOW TABLES;
EOFSQL

if [ $? -eq 0 ]; then
    log "✅ Database and tables created successfully"
else
    error "Failed to create database and tables"
    exit 1
fi

# Store password securely
echo "$MYSQL_ROOT_PASSWORD" > /root/.mysql_password
chmod 600 /root/.mysql_password

log "📊 MySQL Status:"
systemctl status mysql --no-pager -l | head -20 | tee -a "$LOG_FILE"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ MySQL Setup Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🔗 Connection Info:"
echo "   Host: localhost (or $(hostname -I | awk '{print $1}'))"
echo "   Port: 3306"
echo "   Database: $DATABASE_NAME"
echo ""
echo "🔑 Credentials:"
echo "   Root User: root"
echo "   Root Password: $MYSQL_ROOT_PASSWORD"
echo "   App User: dstreambolt"
echo "   App Password: $MYSQL_ROOT_PASSWORD"
echo ""
echo "📊 Tables Created:"
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "USE ${DATABASE_NAME}; SHOW TABLES;" 2>/dev/null
echo ""
echo "💡 Connect locally:"
echo "   mysql -u root -p'$MYSQL_ROOT_PASSWORD'"
echo ""
echo "💡 Connect remotely:"
echo "   mysql -h <host-ip> -u dstreambolt -p'$MYSQL_ROOT_PASSWORD' $DATABASE_NAME"
echo ""
echo "📝 Log file: $LOG_FILE"
echo "🔐 Password stored: /root/.mysql_password"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

