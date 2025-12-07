#!/bin/bash

# Spark Worker Diagnostics and Fix Script
# Run this on the Spark compute instance

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║          Spark Worker Diagnostics & Fix                       ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. CHECKING SPARK SERVICES STATUS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check Spark Master
echo -e "\n${YELLOW}Spark Master:${NC}"
systemctl status spark-master --no-pager | grep -E "(Active:|Main PID:|since)"

# Check Spark Worker
echo -e "\n${YELLOW}Spark Worker:${NC}"
systemctl status spark-worker --no-pager | grep -E "(Active:|Main PID:|since)"

# Check Spark History Server
echo -e "\n${YELLOW}Spark History Server:${NC}"
systemctl status spark-history --no-pager | grep -E "(Active:|Main PID:|since)" || echo "Not installed/running"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2. CHECKING LISTENING PORTS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo -e "\n${YELLOW}Checking if Spark ports are listening:${NC}"
netstat -tlnp 2>/dev/null | grep -E ":(7077|8080|8081|18080)" || echo "No Spark ports found listening"

MASTER_PORT=$(netstat -tlnp 2>/dev/null | grep ":8080" | wc -l)
WORKER_PORT=$(netstat -tlnp 2>/dev/null | grep ":8081" | wc -l)

if [ "$MASTER_PORT" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} Spark Master UI (8080) is listening"
else
    echo -e "${RED}✗${NC} Spark Master UI (8080) is NOT listening"
fi

if [ "$WORKER_PORT" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} Spark Worker UI (8081) is listening"
else
    echo -e "${RED}✗${NC} Spark Worker UI (8081) is NOT listening"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3. CHECKING SPARK INSTALLATION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -d "/opt/spark" ]; then
    echo -e "${GREEN}✓${NC} Spark installation directory exists: /opt/spark"
    echo "Spark version: $(ls -la /opt/spark | grep spark- | head -1)"
else
    echo -e "${RED}✗${NC} Spark installation NOT found at /opt/spark"
fi

if [ -f "/opt/spark/conf/spark-env.sh" ]; then
    echo -e "${GREEN}✓${NC} Spark configuration exists"
    echo -e "\n${YELLOW}Current configuration:${NC}"
    grep -E "SPARK_MASTER|SPARK_WORKER" /opt/spark/conf/spark-env.sh
else
    echo -e "${RED}✗${NC} Spark configuration NOT found"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "4. CHECKING RECENT LOGS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo -e "\n${YELLOW}Spark Master Logs (last 10 lines):${NC}"
if [ -d "/opt/spark/logs" ]; then
    MASTER_LOG=$(ls -t /opt/spark/logs/*master*.out 2>/dev/null | head -1)
    if [ -n "$MASTER_LOG" ]; then
        tail -10 "$MASTER_LOG"
    else
        echo "No master log found"
    fi
else
    echo "Logs directory not found"
fi

echo -e "\n${YELLOW}Spark Worker Logs (last 10 lines):${NC}"
if [ -d "/opt/spark/logs" ]; then
    WORKER_LOG=$(ls -t /opt/spark/logs/*worker*.out 2>/dev/null | head -1)
    if [ -n "$WORKER_LOG" ]; then
        tail -10 "$WORKER_LOG"
    else
        echo "No worker log found"
    fi
else
    echo "Logs directory not found"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "5. CHECKING NETWORK CONFIGURATION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo -e "\n${YELLOW}Private IP:${NC}"
PRIVATE_IP=$(hostname -I | awk '{print $1}')
echo "  $PRIVATE_IP"

echo -e "\n${YELLOW}Public IP:${NC}"
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "Not available")
echo "  $PUBLIC_IP"

echo -e "\n${YELLOW}Security Groups/Firewall:${NC}"
# Check UFW status
if command -v ufw &> /dev/null; then
    ufw status | grep -E "(Status:|8080|8081)"
else
    echo "UFW not installed"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "6. DIAGNOSTICS SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ISSUES=0

# Check Master
if ! systemctl is-active --quiet spark-master; then
    echo -e "${RED}✗${NC} Spark Master is not running"
    ((ISSUES++))
fi

# Check Worker
if ! systemctl is-active --quiet spark-worker; then
    echo -e "${RED}✗${NC} Spark Worker is not running"
    ((ISSUES++))
fi

# Check port 8081
if [ "$WORKER_PORT" -eq 0 ]; then
    echo -e "${RED}✗${NC} Port 8081 is not listening"
    ((ISSUES++))
fi

if [ $ISSUES -eq 0 ]; then
    echo -e "${GREEN}✓${NC} All services appear to be running correctly"
    echo ""
    echo "Access URLs:"
    echo "  Spark Master:  http://$PUBLIC_IP:8080"
    echo "  Spark Worker:  http://$PUBLIC_IP:8081"
    echo "  Private IP Worker: http://$PRIVATE_IP:8081"
else
    echo -e "${YELLOW}⚠${NC}  Found $ISSUES issue(s)"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "RECOMMENDED FIXES"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "1. Restart Spark services:"
    echo "   sudo systemctl restart spark-master"
    echo "   sudo systemctl restart spark-worker"
    echo ""
    echo "2. Check detailed logs:"
    echo "   sudo journalctl -u spark-master -n 50"
    echo "   sudo journalctl -u spark-worker -n 50"
    echo ""
    echo "3. If services fail to start, check installation:"
    echo "   ls -la /opt/spark/sbin/"
    echo ""
    echo "4. Verify Java is installed:"
    echo "   java -version"
    echo ""
    echo "5. Check AWS Security Group allows ports 8080, 8081, 7077"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "QUICK FIX COMMANDS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "# Restart all Spark services"
echo "sudo systemctl restart spark-master spark-worker"
echo ""
echo "# Check status"
echo "sudo systemctl status spark-master spark-worker"
echo ""
echo "# View logs"
echo "tail -100 /opt/spark/logs/*worker*.out"
echo ""
echo "# Open firewall ports (if UFW is active)"
echo "sudo ufw allow 8080/tcp"
echo "sudo ufw allow 8081/tcp"
echo "sudo ufw allow 7077/tcp"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Done!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

