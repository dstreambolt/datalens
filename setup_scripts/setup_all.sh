#!/bin/bash

###############################################################################
# DStreamBolt Master Setup Script
# Orchestrates setup of all components
###############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="/var/log/dstreambolt-setup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$LOG_DIR"
MASTER_LOG="${LOG_DIR}/master_setup_${TIMESTAMP}.log"

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$MASTER_LOG"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$MASTER_LOG"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN:${NC} $1" | tee -a "$MASTER_LOG"
}

section() {
    echo "" | tee -a "$MASTER_LOG"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$MASTER_LOG"
    echo -e "${BLUE}$1${NC}" | tee -a "$MASTER_LOG"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$MASTER_LOG"
}

echo "╔═══════════════════════════════════════════════════════════════════╗"
echo "║         DStreamBolt Master Setup Script                          ║"
echo "║  Comprehensive setup for all infrastructure components           ║"
echo "╚═══════════════════════════════════════════════════════════════════╝"
echo ""

if [ "$EUID" -ne 0 ]; then
    error "Please run as root or with sudo"
    exit 1
fi

# Detect current node type
HOSTNAME=$(hostname)
PRIVATE_IP=$(hostname -I | awk '{print $1}')

log "Detected Hostname: $HOSTNAME"
log "Private IP: $PRIVATE_IP"
log "Master log: $MASTER_LOG"
echo ""

# Interactive mode selection
echo "Select components to install:"
echo ""
echo "  1. MySQL Database"
echo "  2. Jenkins CI/CD"
echo "  3. Grafana Monitoring"
echo "  4. Kafka Broker"
echo "  5. Spark Master"
echo "  6. Spark Worker"
echo "  7. Ingestion Service"
echo "  8. AKHQ (Kafka UI)"
echo "  9. All DevOps tools (Jenkins + Grafana + MySQL + AKHQ)"
echo " 10. Complete Infrastructure (All components)"
echo "  0. Custom selection"
echo ""

read -p "Enter choice [1-10]: " CHOICE

case $CHOICE in
    1) COMPONENTS=("mysql") ;;
    2) COMPONENTS=("jenkins") ;;
    3) COMPONENTS=("grafana") ;;
    4) COMPONENTS=("kafka") ;;
    5) COMPONENTS=("spark-master") ;;
    6) COMPONENTS=("spark-worker") ;;
    7) COMPONENTS=("ingestion") ;;
    8) COMPONENTS=("akhq") ;;
    9) COMPONENTS=("mysql" "jenkins" "grafana" "akhq") ;;
    10) COMPONENTS=("mysql" "jenkins" "grafana" "kafka" "spark-master" "ingestion" "akhq") ;;
    0)
        echo "Enter components (space-separated): mysql jenkins grafana kafka spark-master spark-worker ingestion akhq"
        read -p "Components: " USER_COMPONENTS
        IFS=' ' read -r -a COMPONENTS <<< "$USER_COMPONENTS"
        ;;
    *)
        error "Invalid choice"
        exit 1
        ;;
esac

log "Selected components: ${COMPONENTS[*]}"
echo ""

# Collect required configuration
if [[ " ${COMPONENTS[@]} " =~ " mysql " ]] || [[ " ${COMPONENTS[@]} " =~ " grafana " ]]; then
    read -sp "Enter MySQL root password [DStreamBolt2025!]: " MYSQL_PASSWORD
    echo
    MYSQL_PASSWORD="${MYSQL_PASSWORD:-DStreamBolt2025!}"
    export MYSQL_ROOT_PASSWORD="$MYSQL_PASSWORD"
    export MYSQL_PASSWORD="$MYSQL_PASSWORD"
    export MYSQL_HOST="${MYSQL_HOST:-localhost}"
fi

if [[ " ${COMPONENTS[@]} " =~ " kafka " ]] || [[ " ${COMPONENTS[@]} " =~ " ingestion " ]] || [[ " ${COMPONENTS[@]} " =~ " akhq " ]]; then
    read -p "Enter Kafka broker IP:port [${PRIVATE_IP}:9092]: " KAFKA_INPUT
    KAFKA_BROKER="${KAFKA_INPUT:-${PRIVATE_IP}:9092}"
    export KAFKA_BROKER="$KAFKA_BROKER"
fi

if [[ " ${COMPONENTS[@]} " =~ " spark-worker " ]]; then
    read -p "Enter Spark Master IP: " SPARK_MASTER_HOST
    export SPARK_MASTER_HOST="$SPARK_MASTER_HOST"
fi

if [[ " ${COMPONENTS[@]} " =~ " ingestion " ]]; then
    if [ -z "$MYSQL_HOST" ] || [ "$MYSQL_HOST" = "localhost" ]; then
        read -p "Enter MySQL Host IP: " MYSQL_HOST
        export MYSQL_HOST="$MYSQL_HOST"
    fi
fi

echo ""
log "Starting installation..."
echo ""

# Installation counter
TOTAL=${#COMPONENTS[@]}
CURRENT=0
FAILED=()
SUCCEEDED=()

for component in "${COMPONENTS[@]}"; do
    ((CURRENT++))
    section "[$CURRENT/$TOTAL] Installing: $component"

    SCRIPT="${SCRIPT_DIR}/setup_${component/-/_}.sh"

    if [ ! -f "$SCRIPT" ]; then
        error "Setup script not found: $SCRIPT"
        FAILED+=("$component")
        continue
    fi

    chmod +x "$SCRIPT"

    log "Executing: $SCRIPT"
    if bash "$SCRIPT" 2>&1 | tee -a "$MASTER_LOG"; then
        log "✅ $component installed successfully"
        SUCCEEDED+=("$component")
    else
        error "❌ $component installation failed"
        FAILED+=("$component")
    fi

    sleep 2
done

# Summary
section "Installation Summary"

echo "" | tee -a "$MASTER_LOG"
log "Succeeded (${#SUCCEEDED[@]}/$TOTAL):"
for comp in "${SUCCEEDED[@]}"; do
    echo "  ✅ $comp" | tee -a "$MASTER_LOG"
done

if [ ${#FAILED[@]} -gt 0 ]; then
    echo "" | tee -a "$MASTER_LOG"
    error "Failed (${#FAILED[@]}/$TOTAL):"
    for comp in "${FAILED[@]}"; do
        echo "  ❌ $comp" | tee -a "$MASTER_LOG"
    done
fi

echo "" | tee -a "$MASTER_LOG"
section "Service Status Check"

# Check service status
SERVICES=()
[[ " ${COMPONENTS[@]} " =~ " mysql " ]] && SERVICES+=("mysql")
[[ " ${COMPONENTS[@]} " =~ " jenkins " ]] && SERVICES+=("jenkins")
[[ " ${COMPONENTS[@]} " =~ " grafana " ]] && SERVICES+=("grafana-server")
[[ " ${COMPONENTS[@]} " =~ " kafka " ]] && SERVICES+=("kafka" "zookeeper")
[[ " ${COMPONENTS[@]} " =~ " spark-master " ]] && SERVICES+=("spark-master")
[[ " ${COMPONENTS[@]} " =~ " spark-worker " ]] && SERVICES+=("spark-worker")
[[ " ${COMPONENTS[@]} " =~ " ingestion " ]] && SERVICES+=("dstreambolt-ingest")
[[ " ${COMPONENTS[@]} " =~ " akhq " ]] && SERVICES+=("akhq")

for service in "${SERVICES[@]}"; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        echo "  ✅ $service" | tee -a "$MASTER_LOG"
    else
        echo "  ❌ $service (not running)" | tee -a "$MASTER_LOG"
    fi
done

echo "" | tee -a "$MASTER_LOG"
section "Access Information"

echo "" | tee -a "$MASTER_LOG"
PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || echo "N/A")

if [[ " ${COMPONENTS[@]} " =~ " jenkins " ]]; then
    echo "🔧 Jenkins:" | tee -a "$MASTER_LOG"
    echo "   URL: http://${PUBLIC_IP}:8080" | tee -a "$MASTER_LOG"
    if [ -f /tmp/jenkins_initial_password.txt ]; then
        echo "   Password: $(cat /tmp/jenkins_initial_password.txt)" | tee -a "$MASTER_LOG"
    fi
    echo "" | tee -a "$MASTER_LOG"
fi

if [[ " ${COMPONENTS[@]} " =~ " grafana " ]]; then
    echo "📊 Grafana:" | tee -a "$MASTER_LOG"
    echo "   URL: http://${PUBLIC_IP}:3000/grafana" | tee -a "$MASTER_LOG"
    echo "   User: admin / ${GRAFANA_ADMIN_PASSWORD:-DStreamBolt2025!}" | tee -a "$MASTER_LOG"
    echo "" | tee -a "$MASTER_LOG"
fi

if [[ " ${COMPONENTS[@]} " =~ " akhq " ]]; then
    echo "🎛️  AKHQ (Kafka UI):" | tee -a "$MASTER_LOG"
    echo "   URL: http://${PUBLIC_IP}:8081/kafkamgr" | tee -a "$MASTER_LOG"
    echo "   User: admin / DStreamBolt2025!" | tee -a "$MASTER_LOG"
    echo "" | tee -a "$MASTER_LOG"
fi

if [[ " ${COMPONENTS[@]} " =~ " spark-master " ]]; then
    echo "⚡ Spark Master:" | tee -a "$MASTER_LOG"
    echo "   URL: spark://${PRIVATE_IP}:7077" | tee -a "$MASTER_LOG"
    echo "   UI: http://${PUBLIC_IP}:8080" | tee -a "$MASTER_LOG"
    echo "" | tee -a "$MASTER_LOG"
fi

if [[ " ${COMPONENTS[@]} " =~ " kafka " ]]; then
    echo "📨 Kafka:" | tee -a "$MASTER_LOG"
    echo "   Broker: ${PRIVATE_IP}:9092" | tee -a "$MASTER_LOG"
    echo "" | tee -a "$MASTER_LOG"
fi

if [[ " ${COMPONENTS[@]} " =~ " ingestion " ]]; then
    echo "📥 Ingestion API:" | tee -a "$MASTER_LOG"
    echo "   URL: http://${PUBLIC_IP}:5000" | tee -a "$MASTER_LOG"
    echo "   Health: http://${PUBLIC_IP}:5000/health" | tee -a "$MASTER_LOG"
    echo "" | tee -a "$MASTER_LOG"
fi

if [[ " ${COMPONENTS[@]} " =~ " mysql " ]]; then
    echo "🗄️  MySQL:" | tee -a "$MASTER_LOG"
    echo "   Host: ${PRIVATE_IP}:3306" | tee -a "$MASTER_LOG"
    echo "   Database: dstreambolt_metrics" | tee -a "$MASTER_LOG"
    echo "   User: root / dstreambolt" | tee -a "$MASTER_LOG"
    echo "" | tee -a "$MASTER_LOG"
fi

echo "" | tee -a "$MASTER_LOG"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$MASTER_LOG"
if [ ${#FAILED[@]} -eq 0 ]; then
    log "✅ Setup completed successfully!"
else
    warn "⚠️  Setup completed with ${#FAILED[@]} failure(s)"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$MASTER_LOG"
echo "" | tee -a "$MASTER_LOG"
log "Master log file: $MASTER_LOG"
log "Individual logs: $LOG_DIR/"
echo "" | tee -a "$MASTER_LOG"

