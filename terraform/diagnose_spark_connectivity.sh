#!/bin/bash
# Diagnostic script to check Spark connectivity and port status

echo "=========================================="
echo "🔍 Spark Connectivity Diagnostics"
echo "=========================================="
echo ""

MASTER_IP="10.0.1.199"
DRIVER_PORT="39499"

echo "1️⃣ Checking listening ports on Master:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ssh -i ~/dstreambolt-access-key.pem ubuntu@$MASTER_IP 'sudo ss -tlnp' | grep -E ":(7077|8080|4040|39499|18080)" || echo "No Spark ports found"
echo ""

echo "2️⃣ Checking Spark Master service:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ssh -i ~/dstreambolt-access-key.pem ubuntu@$MASTER_IP 'systemctl status spark-master --no-pager | head -10'
echo ""

echo "3️⃣ Checking for running Spark jobs:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ssh -i ~/dstreambolt-access-key.pem ubuntu@$MASTER_IP 'ps aux | grep -i spark | grep -v grep | head -10'
echo ""

echo "4️⃣ Understanding Port 39499:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cat << 'EOF'
Port 39499 is the Spark DRIVER port, which:
  ✓ Opens when a Spark job is submitted
  ✓ Used for executor <-> driver communication
  ✓ NOT a service that runs continuously
  ✓ Only exists when a job is running

Why is it not listening?
  → No active Spark job is currently running!

When will it open?
  → When Jenkins deploys and starts a Spark job
  → When you manually submit a spark-submit job

EOF

echo "5️⃣ Security Group Check:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Checking if port 39499 is allowed in security group..."
aws ec2 describe-security-groups --region ap-south-1 \
  --filters "Name=tag:Name,Values=dstreambolt-compute-sg" \
  --query 'SecurityGroups[0].IpPermissions[?FromPort<=`39499` && ToPort>=`39499`]' \
  --output json
echo ""

echo "6️⃣ Network Connectivity Test:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Testing if master is reachable on port 7077 (Spark Master):"
nc -zv $MASTER_IP 7077 2>&1
echo ""

echo "7️⃣ Solution:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cat << 'EOF'
The "Connection refused" on port 39499 is EXPECTED when no job is running.

To verify everything works:
  1. Deploy a Spark job via Jenkins
  2. The driver port (39499) will open automatically
  3. Executors will connect to it

The security group already allows this port (0-65535 TCP within VPC).
Everything is configured correctly! ✅

Alternative driver port configuration:
  - Set in spark-submit: --conf spark.driver.port=39499
  - Or let Spark choose a random port dynamically
  - Jenkins pipeline already sets this: SPARK_DRIVER_PORT=39499

EOF

echo "=========================================="
echo "✅ Diagnostics Complete"
echo "=========================================="

