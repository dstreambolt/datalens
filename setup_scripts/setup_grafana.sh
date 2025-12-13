#!/bin/bash

###############################################################################
# Grafana Setup Script
# Installs and configures Grafana with MySQL datasource
###############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/grafana-setup.log"

# Default configuration
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-DStreamBolt2025!}"
MYSQL_HOST="${MYSQL_HOST:-localhost}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_DATABASE="${MYSQL_DATABASE:-dstreambolt_metrics}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"

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
echo "║              Grafana Setup Script                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

if [ "$EUID" -ne 0 ]; then
    error "Please run as root or with sudo"
    exit 1
fi

# Check if already installed
if systemctl is-active --quiet grafana-server 2>/dev/null; then
    log "✅ Grafana is already running"
    read -p "Do you want to reconfigure? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Exiting..."
        exit 0
    fi
    SKIP_INSTALL=true
else
    SKIP_INSTALL=false
fi

if [ "$SKIP_INSTALL" != "true" ]; then
    log "📦 Installing Grafana..."

    # Add Grafana repository
    apt-get install -y software-properties-common wget
    wget -q -O - https://packages.grafana.com/gpg.key | apt-key add -
    echo "deb https://packages.grafana.com/oss/deb stable main" | tee /etc/apt/sources.list.d/grafana.list

    apt-get update -qq
    apt-get install -y grafana
fi

log "🔧 Configuring Grafana..."

# Configure Grafana
cat > /etc/grafana/grafana.ini << EOFGRAFANA
[server]
protocol = http
http_addr = 0.0.0.0
http_port = 3000
domain = localhost
root_url = %(protocol)s://%(domain)s:%(http_port)s/grafana/
serve_from_sub_path = true

[security]
admin_user = admin
admin_password = ${GRAFANA_ADMIN_PASSWORD}
allow_embedding = true

[auth.anonymous]
enabled = false

[users]
allow_sign_up = false
allow_org_create = false

[database]
type = sqlite3

[session]
provider = file

[analytics]
reporting_enabled = false
check_for_updates = false

[log]
mode = console file
level = info

[log.console]
level = info

[log.file]
level = info
log_rotate = true
max_lines = 1000000
max_size_shift = 28
daily_rotate = true
max_days = 7
EOFGRAFANA

log "🚀 Starting Grafana..."
systemctl daemon-reload
systemctl enable grafana-server
systemctl restart grafana-server

# Wait for Grafana to start
log "⏳ Waiting for Grafana to initialize..."
for i in {1..30}; do
    if curl -s http://localhost:3000/api/health > /dev/null 2>&1; then
        break
    fi
    sleep 2
done

if ! systemctl is-active --quiet grafana-server; then
    error "Grafana failed to start"
    journalctl -u grafana-server -n 50 --no-pager
    exit 1
fi

log "✅ Grafana is running"

# Configure MySQL datasource
if [ ! -z "$MYSQL_PASSWORD" ]; then
    log "🔧 Configuring MySQL datasource..."

    sleep 5  # Wait for Grafana API to be ready

    # Create datasource via API
    curl -X POST http://admin:${GRAFANA_ADMIN_PASSWORD}@localhost:3000/api/datasources \
        -H "Content-Type: application/json" \
        -d '{
            "name": "DStreamBolt-MySQL",
            "type": "mysql",
            "url": "'${MYSQL_HOST}:${MYSQL_PORT}'",
            "access": "proxy",
            "database": "'${MYSQL_DATABASE}'",
            "user": "'${MYSQL_USER}'",
            "secureJsonData": {
                "password": "'${MYSQL_PASSWORD}'"
            },
            "jsonData": {
                "maxOpenConns": 100,
                "maxIdleConns": 100,
                "connMaxLifetime": 14400
            },
            "isDefault": true
        }' 2>/dev/null || warn "Datasource may already exist"

    log "✅ MySQL datasource configured"
fi

# Import dashboards if available
DASHBOARD_DIR="${SCRIPT_DIR}/../grafana"
if [ -d "$DASHBOARD_DIR" ]; then
    log "📊 Importing dashboards..."
    for dashboard in "$DASHBOARD_DIR"/*.json; do
        if [ -f "$dashboard" ]; then
            DASHBOARD_NAME=$(basename "$dashboard")
            log "Importing: $DASHBOARD_NAME"

            # Wrap dashboard JSON in proper format
            DASHBOARD_JSON=$(cat "$dashboard" | jq '{dashboard: ., overwrite: true, folderId: 0}' 2>/dev/null || cat "$dashboard")

            curl -X POST http://admin:${GRAFANA_ADMIN_PASSWORD}@localhost:3000/api/dashboards/db \
                -H "Content-Type: application/json" \
                -d "$DASHBOARD_JSON" 2>/dev/null || warn "Failed to import $DASHBOARD_NAME"
        fi
    done
    log "✅ Dashboards imported"
fi

log "📊 Grafana Status:"
systemctl status grafana-server --no-pager -l | head -20 | tee -a "$LOG_FILE"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Grafana Setup Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🔗 Access Grafana:"
echo "   Local:  http://localhost:3000/grafana"
echo "   Public: http://$(curl -s ifconfig.me):3000/grafana"
echo ""
echo "🔑 Credentials:"
echo "   Username: admin"
echo "   Password: $GRAFANA_ADMIN_PASSWORD"
echo ""
echo "📊 Datasources:"
echo "   MySQL: ${MYSQL_HOST}:${MYSQL_PORT}/${MYSQL_DATABASE}"
echo ""
echo "📝 Log file: $LOG_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

