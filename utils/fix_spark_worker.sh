#!/bin/bash

# Quick Fix for Spark Worker Not Responding
# Run this from your local machine

set -e

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║     Spark Worker Fix - Automated Troubleshooting              ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# Configuration
SSH_KEY="${SSH_KEY_PATH:-$HOME/dstreambolt-access-key.pem}"
TERRAFORM_DIR="${TERRAFORM_DIR:-./terraform}"

# Check if SSH key exists
if [ ! -f "$SSH_KEY" ]; then
    echo "❌ SSH key not found: $SSH_KEY"
    echo "Please set SSH_KEY_PATH environment variable or ensure key is at ~/dstreambolt-access-key.pem"
    exit 1
fi

echo "✅ SSH key found: $SSH_KEY"
echo ""

# Get Spark instance IP from Terraform
echo "📋 Getting Spark instance IP from Terraform..."
if [ -f "$TERRAFORM_DIR/terraform.tfstate" ]; then
    SPARK_IP=$(cd "$TERRAFORM_DIR" && terraform output -json 2>/dev/null | jq -r '.direct_access.value.compute_ip' 2>/dev/null)

    if [ -z "$SPARK_IP" ] || [ "$SPARK_IP" = "null" ]; then
        echo "❌ Could not get Spark IP from Terraform output"
        echo "Please provide IP manually:"
        read -p "Enter Spark instance public IP: " SPARK_IP
    else
        echo "✅ Found Spark instance: $SPARK_IP"
    fi
else
    echo "⚠️  Terraform state not found"
    read -p "Enter Spark instance public IP: " SPARK_IP
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 1: Testing SSH Connection"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no ubuntu@$SPARK_IP "echo 'SSH OK'" &>/dev/null; then
    echo "✅ SSH connection successful"
else
    echo "❌ SSH connection failed"
    echo "Please check:"
    echo "  1. Security group allows SSH (port 22) from your IP"
    echo "  2. SSH key has correct permissions (chmod 600)"
    echo "  3. Instance is running"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 2: Checking Current Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "Checking Spark services..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@$SPARK_IP << 'REMOTE_CHECK'
    echo "Spark Master:"
    systemctl is-active spark-master && echo "  ✅ Running" || echo "  ❌ Not running"

    echo "Spark Worker:"
    systemctl is-active spark-worker && echo "  ✅ Running" || echo "  ❌ Not running"

    echo ""
    echo "Listening ports:"
    netstat -tlnp 2>/dev/null | grep -E ":(7077|8080|8081)" || echo "  ⚠️  No Spark ports found"
REMOTE_CHECK

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 3: Fixing Spark Worker"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "Restarting Spark services..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@$SPARK_IP << 'REMOTE_FIX'
    # Stop services
    echo "Stopping services..."
    sudo systemctl stop spark-master spark-worker 2>/dev/null || true

    # Kill hanging processes
    sudo pkill -9 -f "org.apache.spark" 2>/dev/null || true

    # Wait
    sleep 3

    # Start Master
    echo "Starting Spark Master..."
    sudo systemctl start spark-master
    sleep 5

    # Start Worker
    echo "Starting Spark Worker..."
    sudo systemctl start spark-worker
    sleep 3

    echo "✅ Services restarted"
REMOTE_FIX

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 4: Verifying Services"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

sleep 5

MASTER_STATUS=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@$SPARK_IP "systemctl is-active spark-master" 2>/dev/null)
WORKER_STATUS=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@$SPARK_IP "systemctl is-active spark-worker" 2>/dev/null)

if [ "$MASTER_STATUS" = "active" ]; then
    echo "✅ Spark Master: Running"
else
    echo "❌ Spark Master: $MASTER_STATUS"
fi

if [ "$WORKER_STATUS" = "active" ]; then
    echo "✅ Spark Worker: Running"
else
    echo "❌ Spark Worker: $WORKER_STATUS"
fi

echo ""
echo "Checking ports..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@$SPARK_IP "netstat -tlnp 2>/dev/null | grep -E ':(7077|8080|8081)'"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 5: Testing Connectivity"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "Testing Master UI (port 8080)..."
MASTER_HTTP=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 http://$SPARK_IP:8080 2>/dev/null || echo "000")
if [ "$MASTER_HTTP" = "200" ]; then
    echo "✅ Master UI accessible"
else
    echo "❌ Master UI not accessible (HTTP $MASTER_HTTP)"
    echo "   Check AWS Security Group allows port 8080"
fi

echo "Testing Worker UI (port 8081)..."
WORKER_HTTP=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 http://$SPARK_IP:8081 2>/dev/null || echo "000")
if [ "$WORKER_HTTP" = "200" ]; then
    echo "✅ Worker UI accessible"
else
    echo "❌ Worker UI not accessible (HTTP $WORKER_HTTP)"
    echo "   Check AWS Security Group allows port 8081"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Spark Instance: $SPARK_IP"
echo ""
echo "Access URLs:"
echo "  Master UI:  http://$SPARK_IP:8080"
echo "  Worker UI:  http://$SPARK_IP:8081"
echo "  History:    http://$SPARK_IP:18080"
echo ""

if [ "$MASTER_HTTP" = "200" ] && [ "$WORKER_HTTP" = "200" ]; then
    echo "✅ All services are working correctly!"
    echo ""
    echo "Open in browser:"
    echo "  http://$SPARK_IP:8080  (Master UI)"
    echo "  http://$SPARK_IP:8081  (Worker UI)"
else
    echo "⚠️  Some services are not accessible"
    echo ""
    echo "Possible issues:"
    echo "  1. AWS Security Group not allowing ports 8080, 8081"
    echo "  2. Services failed to start (check logs)"
    echo "  3. Network connectivity issues"
    echo ""
    echo "Next steps:"
    echo "  1. Check AWS Security Group:"
    echo "     - Go to EC2 → Security Groups"
    echo "     - Find security group for this instance"
    echo "     - Add inbound rules for ports 7077, 8080, 8081, 18080"
    echo ""
    echo "  2. Check service logs:"
    echo "     ssh -i $SSH_KEY ubuntu@$SPARK_IP"
    echo "     sudo journalctl -u spark-worker -n 50"
    echo ""
    echo "  3. Run diagnostic script:"
    echo "     ssh -i $SSH_KEY ubuntu@$SPARK_IP"
    echo "     curl -s https://raw.githubusercontent.com/dstreambolt/dstream_cloud/main/utils/diagnose_spark_worker.sh | bash"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

