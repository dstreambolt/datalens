#!/bin/bash

# Quick Deployment Script for Compute Instance Upgrade
# Upgrades dstreambolt-compute from t3.micro to t3.small

set -e

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║     DStreamBolt Compute Instance Upgrade Deployment           ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check we're in the right directory
if [ ! -d "terraform" ]; then
    echo -e "${RED}❌ Error: terraform directory not found${NC}"
    echo "Please run this script from the dstream_bolt directory"
    exit 1
fi

echo "📋 Pre-Upgrade Checklist"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Get current compute IP
echo "Getting current compute instance info..."
cd terraform

CURRENT_IP=$(terraform output -json 2>/dev/null | jq -r '.direct_access.value.compute_ip' 2>/dev/null || echo "Unknown")

if [ "$CURRENT_IP" != "Unknown" ] && [ -n "$CURRENT_IP" ]; then
    echo -e "${GREEN}✓${NC} Current Compute IP: $CURRENT_IP"
else
    echo -e "${YELLOW}⚠${NC}  Could not determine current IP"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Upgrade Details"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Instance Type:"
echo "  Before: t3.micro (1 vCPU, 1 GB RAM)"
echo "  After:  t3.small (2 vCPUs, 2 GB RAM)"
echo ""
echo "Spark Configuration:"
echo "  Driver Memory:   512m → 1g"
echo "  Executor Memory: 512m → 1g"
echo "  Worker Memory:   512m → 1g"
echo "  Worker Cores:    1 → 2"
echo ""
echo "Cost Impact:"
echo "  Additional: ~\$7.50/month"
echo ""
echo "⚠️  Important Notes:"
echo "  - Instance will be REPLACED (new instance ID)"
echo "  - New IP address will be assigned"
echo "  - Brief downtime (2-3 minutes)"
echo "  - Update any hardcoded IPs after deployment"
echo ""

read -p "Continue with upgrade? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Upgrade cancelled."
    exit 0
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 1: Terraform Plan"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

terraform plan -out=upgrade.tfplan

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Review the plan above. Continue with apply?"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
read -p "Apply changes? (yes/no): " APPLY_CONFIRM

if [ "$APPLY_CONFIRM" != "yes" ]; then
    echo "Apply cancelled. Plan saved to upgrade.tfplan"
    exit 0
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 2: Applying Upgrade"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

terraform apply upgrade.tfplan

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 3: Getting New Instance Info"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

sleep 5

NEW_IP=$(terraform output -json | jq -r '.direct_access.value.compute_ip')

echo -e "${GREEN}✓${NC} New Compute IP: $NEW_IP"

# Wait for instance to be ready
echo ""
echo "Waiting for instance to be fully ready (30 seconds)..."
for i in {1..30}; do
    echo -n "."
    sleep 1
done
echo ""

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 4: Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check instance type via AWS CLI
echo "Verifying instance type..."
INSTANCE_TYPE=$(aws ec2 describe-instances \
    --region ap-south-1 \
    --filters "Name=tag:Name,Values=*compute*" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].InstanceType' \
    --output text 2>/dev/null || echo "Unknown")

if [ "$INSTANCE_TYPE" = "t3.small" ]; then
    echo -e "${GREEN}✓${NC} Instance type confirmed: t3.small"
else
    echo -e "${YELLOW}⚠${NC}  Instance type: $INSTANCE_TYPE (expected t3.small)"
fi

# Check SSH connectivity
echo ""
echo "Testing SSH connectivity..."
if ssh -i ~/dstreambolt-access-key.pem -o ConnectTimeout=10 -o StrictHostKeyChecking=no ubuntu@$NEW_IP "echo 'SSH OK'" &>/dev/null; then
    echo -e "${GREEN}✓${NC} SSH connection successful"

    echo ""
    echo "Checking Spark services..."
    ssh -i ~/dstreambolt-access-key.pem -o StrictHostKeyChecking=no ubuntu@$NEW_IP << 'REMOTE_CHECK'
        echo "Spark Master:"
        systemctl is-active spark-master && echo "  ✅ Running" || echo "  ⚠️  Not running"

        echo "Spark Worker:"
        systemctl is-active spark-worker && echo "  ✅ Running" || echo "  ⚠️  Not running"

        echo ""
        echo "Spark Configuration:"
        grep -E "executor.memory|driver.memory" /opt/spark/conf/spark-defaults.conf | sed 's/^/  /'
        grep -E "WORKER_MEMORY|WORKER_CORES" /opt/spark/conf/spark-env.sh | sed 's/^/  /'
REMOTE_CHECK
else
    echo -e "${YELLOW}⚠${NC}  SSH not ready yet (may still be initializing)"
fi

# Test Spark UIs
echo ""
echo "Testing Spark UIs..."
MASTER_UI=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 http://$NEW_IP:8080 2>/dev/null || echo "000")
WORKER_UI=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 http://$NEW_IP:8081 2>/dev/null || echo "000")

if [ "$MASTER_UI" = "200" ]; then
    echo -e "${GREEN}✓${NC} Spark Master UI accessible (http://$NEW_IP:8080)"
else
    echo -e "${YELLOW}⚠${NC}  Spark Master UI not accessible (HTTP $MASTER_UI)"
fi

if [ "$WORKER_UI" = "200" ]; then
    echo -e "${GREEN}✓${NC} Spark Worker UI accessible (http://$NEW_IP:8081)"
else
    echo -e "${YELLOW}⚠${NC}  Spark Worker UI not accessible (HTTP $WORKER_UI)"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Upgrade Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Summary:"
echo "  Old IP: $CURRENT_IP"
echo "  New IP: $NEW_IP"
echo "  Instance: t3.small"
echo ""
echo "Access URLs:"
echo "  Spark Master:  http://$NEW_IP:8080"
echo "  Spark Worker:  http://$NEW_IP:8081"
echo "  History:       http://$NEW_IP:18080"
echo ""
echo "Next Steps:"
echo "  1. Update any scripts/configs with new IP: $NEW_IP"
echo "  2. Test Spark job deployment via Jenkins"
echo "  3. Monitor resource utilization"
echo "  4. Clean up: rm upgrade.tfplan"
echo ""
echo "Documentation: COMPUTE_INSTANCE_UPGRADE.md"
echo ""

