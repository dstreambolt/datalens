#!/bin/bash
# Optimize Compute Instance Performance (for t3.small)
# This script optimizes the existing instance instead of upgrading

COMPUTE_IP="13.127.201.0"
SSH_KEY="$HOME/dstreambolt-access-key.pem"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 OPTIMIZING COMPUTE INSTANCE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Note: Free tier doesn't allow t3.medium upgrade"
echo "Applying optimizations instead..."
echo ""

# Check current status
echo "📊 Checking current resource usage..."
ssh -i "$SSH_KEY" ubuntu@${COMPUTE_IP} << 'ENDSSH'
echo "=== Current Status ==="
echo ""
echo "Memory Usage:"
free -h
echo ""
echo "CPU Load:"
uptime
echo ""
echo "Disk Usage:"
df -h /
echo ""
echo "Running Processes:"
ps aux | head -10
ENDSSH

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🛠️  APPLYING OPTIMIZATIONS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Apply optimizations
ssh -i "$SSH_KEY" ubuntu@${COMPUTE_IP} << 'ENDSSH'
set -e

echo "1. Enabling swap (2GB)..."
if [ ! -f /swapfile ]; then
    sudo fallocate -l 2G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    echo "✅ Swap enabled"
else
    echo "✅ Swap already exists"
fi

echo ""
echo "2. Adjusting swappiness..."
sudo sysctl vm.swappiness=10
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf

echo ""
echo "3. Cleaning up old logs..."
sudo journalctl --vacuum-time=2d
sudo find /opt/spark/logs -name "*.log.*" -mtime +1 -delete 2>/dev/null || true
sudo find /tmp -name "spark-*" -mtime +1 -delete 2>/dev/null || true

echo ""
echo "4. Optimizing Spark memory settings..."
SPARK_ENV="/opt/spark/conf/spark-env.sh"
if [ -f "$SPARK_ENV" ]; then
    sudo bash -c "cat > $SPARK_ENV << 'EOF'
# Optimized for t3.small (2GB RAM)
SPARK_WORKER_MEMORY=1024m
SPARK_DAEMON_MEMORY=256m
SPARK_EXECUTOR_MEMORY=512m
SPARK_DRIVER_MEMORY=512m
EOF"
    echo "✅ Spark environment configured"
else
    echo "⚠️  Spark not found, skipping"
fi

echo ""
echo "5. Restarting Spark services..."
sudo systemctl restart spark-master 2>/dev/null || true
sudo systemctl restart spark-worker 2>/dev/null || true

echo ""
echo "6. Checking if Spark job needs restart..."
if [ -f /opt/dstreambolt/computations/spark_job.pid ]; then
    PID=$(cat /opt/dstreambolt/computations/spark_job.pid)
    if ps -p $PID > /dev/null 2>&1; then
        echo "⚠️  Spark job is running (PID: $PID)"
        echo "   Consider restarting it with optimized memory settings"
    fi
fi

echo ""
echo "=== After Optimization ==="
echo ""
echo "Memory Usage:"
free -h
echo ""
echo "Swap Status:"
swapon --show
ENDSSH

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ OPTIMIZATION COMPLETE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Recommendations:"
echo ""
echo "1. Use these Spark settings in Jenkins:"
echo "   SPARK_DRIVER_MEMORY: 512m"
echo "   SPARK_EXECUTOR_MEMORY: 512m"
echo ""
echo "2. If still unresponsive, consider:"
echo "   - Using batch mode instead of streaming"
echo "   - Processing smaller data chunks"
echo "   - Upgrading AWS account from free tier"
echo ""
echo "3. To recreate instance with more optimizations:"
echo "   terraform taint module.compute.aws_instance.compute"
echo "   terraform apply"
echo ""

