#!/bin/bash

###############################################################################
# DStreamBolt Post-Deployment Verification
# Comprehensive health check of all services
###############################################################################

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     🔍 DStreamBolt Health Check                             ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Get outputs from Terraform
echo "📋 Gathering deployment information..."
ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null)
DEVOPS_IP=$(terraform output -json direct_access 2>/dev/null | python3 -c "import sys, json; print(json.load(sys.stdin)['devops_ip'])" 2>/dev/null)
KAFKA_IP=$(terraform output -json direct_access 2>/dev/null | python3 -c "import sys, json; print(json.load(sys.stdin)['kafka_ip'])" 2>/dev/null)
SPARK_IP=$(terraform output -json direct_access 2>/dev/null | python3 -c "import sys, json; print(json.load(sys.stdin)['compute_ip'])" 2>/dev/null)
INGEST_IP=$(terraform output -json direct_access 2>/dev/null | python3 -c "import sys, json; print(json.load(sys.stdin)['ingest_ip'])" 2>/dev/null)
KEY_NAME=$(grep key_name terraform.tfvars | cut -d'=' -f2 | tr -d ' "')

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1️⃣  AWS Infrastructure"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check EC2 instances
echo ""
echo "EC2 Instances:"
aws ec2 describe-instances \
  --region ap-south-1 \
  --filters "Name=tag:Project,Values=DStreamBolt" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value | [0], State.Name, PrivateIpAddress, PublicIpAddress]' \
  --output table

# Check ALB
echo ""
echo "Load Balancer:"
if [ ! -z "$ALB_DNS" ]; then
    echo "  DNS: $ALB_DNS"
    ALB_STATUS=$(aws elbv2 describe-load-balancers \
      --region ap-south-1 \
      --query "LoadBalancers[?DNSName=='$ALB_DNS'].State.Code" \
      --output text)
    echo "  Status: $ALB_STATUS"
else
    echo "  ⚠️  ALB DNS not found"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2️⃣  Service Health Checks"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Test ALB endpoints
echo ""
echo "ALB Endpoints:"
for endpoint in "/" "/health" "/jenkins" "/grafana" "/kafkamgr" "/spark"; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k "https://$ALB_DNS$endpoint" --connect-timeout 10 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        echo -e "  ✅ $endpoint → HTTP $HTTP_CODE"
    elif [ "$HTTP_CODE" = "000" ]; then
        echo -e "  ❌ $endpoint → Connection failed"
    else
        echo -e "  ⚠️  $endpoint → HTTP $HTTP_CODE"
    fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3️⃣  DevOps Node Services"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ ! -z "$DEVOPS_IP" ]; then
    ssh -i "$HOME/${KEY_NAME}.pem" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@$DEVOPS_IP << 'EOFDEVOPS'
    echo ""
    echo "Service Status on DevOps Node:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Jenkins
    if systemctl is-active --quiet jenkins 2>/dev/null; then
        echo "  ✅ Jenkins: Running"
    else
        echo "  ❌ Jenkins: Not running"
    fi

    # Grafana
    if systemctl is-active --quiet grafana-server 2>/dev/null; then
        echo "  ✅ Grafana: Running"
    else
        echo "  ❌ Grafana: Not running"
    fi

    # MySQL
    if systemctl is-active --quiet mysql 2>/dev/null; then
        echo "  ✅ MySQL: Running"
    else
        echo "  ❌ MySQL: Not running"
    fi

    # Nginx
    if systemctl is-active --quiet nginx 2>/dev/null; then
        echo "  ✅ Nginx: Running"
    else
        echo "  ❌ Nginx: Not running"
    fi

    # AKHQ
    if systemctl is-active --quiet akhq 2>/dev/null; then
        echo "  ✅ AKHQ: Running"
    else
        echo "  ⚠️  AKHQ: Not running (may not be installed yet)"
    fi

    echo ""
    echo "Listening Ports:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    sudo netstat -tlnp 2>/dev/null | grep LISTEN | grep -E ':(80|8080|3000|3306|8081)' | awk '{print "  " $4}' || echo "  (checking...)"
EOFDEVOPS
else
    echo "⚠️  Cannot connect to DevOps node"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "4️⃣  Kafka Node"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ ! -z "$KAFKA_IP" ] && [ ! -z "$DEVOPS_IP" ]; then
    ssh -i "$HOME/${KEY_NAME}.pem" -o StrictHostKeyChecking=no ubuntu@$DEVOPS_IP << EOFVIA
    ssh -i ~/${KEY_NAME}.pem -o StrictHostKeyChecking=no ubuntu@$KAFKA_IP << 'EOFKAFKA'
    echo ""
    echo "Kafka Services:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if systemctl is-active --quiet zookeeper 2>/dev/null; then
        echo "  ✅ Zookeeper: Running"
    else
        echo "  ❌ Zookeeper: Not running"
    fi

    if systemctl is-active --quiet kafka 2>/dev/null; then
        echo "  ✅ Kafka: Running"

        # List topics
        PRIVATE_IP=\$(hostname -I | awk '{print \$1}')
        echo ""
        echo "Topics:"
        /opt/kafka/bin/kafka-topics.sh --list --bootstrap-server \${PRIVATE_IP}:9092 2>/dev/null | while read topic; do
            echo "  • \$topic"
        done
    else
        echo "  ❌ Kafka: Not running"
    fi
EOFKAFKA
EOFVIA
else
    echo "⚠️  Cannot connect to Kafka node"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "5️⃣  Spark Master"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ ! -z "$SPARK_IP" ]; then
    ssh -i "$HOME/${KEY_NAME}.pem" -o StrictHostKeyChecking=no ubuntu@$SPARK_IP << 'EOFSPARK'
    echo ""
    echo "Spark Services:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if systemctl is-active --quiet spark-master 2>/dev/null; then
        echo "  ✅ Spark Master: Running"
    else
        echo "  ❌ Spark Master: Not running"
    fi

    if systemctl is-active --quiet spark-worker 2>/dev/null; then
        echo "  ✅ Spark Worker: Running"
    else
        echo "  ⚠️  Spark Worker: Not running"
    fi

    echo ""
    echo "Spark Ports:"
    sudo netstat -tlnp 2>/dev/null | grep LISTEN | grep -E ':(7077|8080|8081)' | awk '{print "  " $4}' || echo "  (checking...)"
EOFSPARK
else
    echo "⚠️  Cannot connect to Spark node"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "6️⃣  Ingestion Service"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ ! -z "$INGEST_IP" ]; then
    ssh -i "$HOME/${KEY_NAME}.pem" -o StrictHostKeyChecking=no ubuntu@$INGEST_IP << 'EOFINGEST'
    echo ""
    echo "Ingestion Service:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if systemctl is-active --quiet dstreambolt-ingest 2>/dev/null; then
        echo "  ✅ Ingestion Service: Running"
    else
        echo "  ❌ Ingestion Service: Not running"
    fi

    # Test health endpoint locally
    if curl -s http://localhost:5000/health > /dev/null 2>&1; then
        HEALTH=$(curl -s http://localhost:5000/health)
        echo "  Health: $HEALTH"
    fi
EOFINGEST
else
    echo "⚠️  Cannot connect to Ingestion node"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Count issues
TOTAL_CHECKS=20
PASSED_CHECKS=$(grep -c "✅" /tmp/health_check_$$.log 2>/dev/null || echo "0")

echo "Health Score: $PASSED_CHECKS/$TOTAL_CHECKS checks passed"
echo ""

if [ "$PASSED_CHECKS" -ge 15 ]; then
    echo "✅ System is healthy!"
elif [ "$PASSED_CHECKS" -ge 10 ]; then
    echo "⚠️  System is partially operational"
else
    echo "❌ System needs attention"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔗 Quick Access"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Main Dashboard:   https://$ALB_DNS/"
echo "Jenkins:          https://$ALB_DNS/jenkins"
echo "Grafana:          https://$ALB_DNS/grafana"
echo "Spark UI:         https://$ALB_DNS/spark"
echo "Kafka Manager:    https://$ALB_DNS/kafkamgr"
echo ""
echo "SSH to DevOps:    ssh -i ~/${KEY_NAME}.pem ubuntu@$DEVOPS_IP"
echo ""

