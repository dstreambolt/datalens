# Spark Worker Not Responding - Troubleshooting Guide

## Problem

**Spark Worker UI not accessible**: `http://10.0.1.128:8081/`

## Root Cause Analysis

### Issue #1: Private IP Access
The IP `10.0.1.128` is a **private IP address** that cannot be accessed directly from your local machine.

**Your Infrastructure:**
- **Compute (Spark)**: `43.205.94.74` (public IP)
- **DevOps**: `13.232.38.64` (public IP)  
- **Kafka**: `10.0.10.101` (private IP)
- **Unknown**: `10.0.1.128` (private IP - likely old/incorrect)

### Issue #2: Possible Causes

1. **Spark Worker service not running**
2. **Port 8081 not listening**
3. **Security group not allowing port 8081**
4. **Firewall blocking port 8081**
5. **Wrong IP address being used**

---

## Quick Fix Steps

### Step 1: Identify the Correct Spark Instance

```bash
# From your local machine
cd terraform
terraform output -json | jq -r '.direct_access.value'
```

**Expected Output:**
```json
{
  "compute_ip": "43.205.94.74",    ← This is your Spark master
  "devops_ip": "13.232.38.64",
  "ingest_ip": "13.201.43.125",
  "kafka_ip": "10.0.10.101"
}
```

**Correct URL to access Spark Worker:**
- Spark Master UI: `http://43.205.94.74:8080`
- Spark Worker UI: `http://43.205.94.74:8081`
- Spark History: `http://43.205.94.74:18080`

### Step 2: SSH to Spark Instance and Diagnose

```bash
# SSH to the Spark instance
ssh -i ~/dstreambolt-access-key.pem ubuntu@43.205.94.74

# Run the diagnostic script
curl -s https://raw.githubusercontent.com/dstreambolt/dstream_cloud/main/utils/diagnose_spark_worker.sh | bash
```

**Or upload the script:**
```bash
# From your local machine
scp -i ~/dstreambolt-access-key.pem \
    utils/diagnose_spark_worker.sh \
    ubuntu@43.205.94.74:/tmp/

# SSH and run
ssh -i ~/dstreambolt-access-key.pem ubuntu@43.205.94.74
chmod +x /tmp/diagnose_spark_worker.sh
sudo /tmp/diagnose_spark_worker.sh
```

### Step 3: Check Service Status

```bash
# Check if Spark services are running
sudo systemctl status spark-master
sudo systemctl status spark-worker

# Check listening ports
sudo netstat -tlnp | grep -E ":(7077|8080|8081)"
```

### Step 4: Restart Services if Needed

```bash
# Restart both services
sudo systemctl restart spark-master
sudo systemctl restart spark-worker

# Wait a few seconds
sleep 5

# Check status again
sudo systemctl status spark-master spark-worker
```

### Step 5: Check Logs for Errors

```bash
# Check systemd logs
sudo journalctl -u spark-worker -n 50 --no-pager

# Check Spark logs
tail -100 /opt/spark/logs/*worker*.out
tail -100 /opt/spark/logs/*master*.out
```

### Step 6: Verify Port is Listening

```bash
# Check if port 8081 is listening
sudo netstat -tlnp | grep 8081

# Or use ss
sudo ss -tlnp | grep 8081

# Expected output:
# tcp6  0  0 :::8081  :::*  LISTEN  <pid>/java
```

---

## Common Issues and Solutions

### Issue 1: Service Not Running

**Check:**
```bash
sudo systemctl status spark-worker
```

**Fix:**
```bash
# If failed, check why
sudo journalctl -u spark-worker -n 50

# Restart service
sudo systemctl restart spark-worker

# Enable to start on boot
sudo systemctl enable spark-worker
```

### Issue 2: Port Not Listening

**Check:**
```bash
sudo netstat -tlnp | grep 8081
```

**Fix:**
```bash
# Check Spark configuration
cat /opt/spark/conf/spark-env.sh | grep WEBUI

# Should show:
# export SPARK_WORKER_WEBUI_PORT=8081

# If missing, add it:
echo 'export SPARK_WORKER_WEBUI_PORT=8081' | sudo tee -a /opt/spark/conf/spark-env.sh

# Restart worker
sudo systemctl restart spark-worker
```

### Issue 3: AWS Security Group Blocking

**Fix from AWS Console:**
1. Go to EC2 → Security Groups
2. Find the security group for Spark instance (compute)
3. Add inbound rules:
   - Port 7077 (Spark Master)
   - Port 8080 (Master UI)
   - Port 8081 (Worker UI)
   - Port 18080 (History Server)
   - Source: Your IP or 0.0.0.0/0

**Fix via AWS CLI:**
```bash
# Get security group ID
SG_ID=$(aws ec2 describe-instances \
    --region ap-south-1 \
    --filters "Name=tag:Name,Values=*compute*" \
    --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
    --output text)

# Add port 8081
aws ec2 authorize-security-group-ingress \
    --region ap-south-1 \
    --group-id $SG_ID \
    --protocol tcp \
    --port 8081 \
    --cidr 0.0.0.0/0

# Add port 8080
aws ec2 authorize-security-group-ingress \
    --region ap-south-1 \
    --group-id $SG_ID \
    --protocol tcp \
    --port 8080 \
    --cidr 0.0.0.0/0
```

### Issue 4: UFW Firewall Blocking

**Check:**
```bash
sudo ufw status
```

**Fix:**
```bash
# Allow Spark ports
sudo ufw allow 7077/tcp
sudo ufw allow 8080/tcp
sudo ufw allow 8081/tcp
sudo ufw allow 18080/tcp

# Reload UFW
sudo ufw reload

# Verify
sudo ufw status numbered
```

### Issue 5: Spark Installation Missing

**Check:**
```bash
ls -la /opt/spark/sbin/
```

**Fix:**
```bash
# If missing, reinstall Spark
cd /opt
sudo wget https://archive.apache.org/dist/spark/spark-3.5.0/spark-3.5.0-bin-hadoop3.tgz
sudo tar -xzf spark-3.5.0-bin-hadoop3.tgz
sudo ln -sf spark-3.5.0-bin-hadoop3 spark
sudo chown -R ubuntu:ubuntu /opt/spark*

# Configure and restart
sudo systemctl restart spark-master spark-worker
```

---

## Verification Steps

### 1. Check from Server

```bash
# SSH to Spark instance
ssh -i ~/dstreambolt-access-key.pem ubuntu@43.205.94.74

# Test locally
curl http://localhost:8080  # Should return HTML
curl http://localhost:8081  # Should return HTML

# Check processes
ps aux | grep spark
```

### 2. Check from Your Local Machine

```bash
# Test Master UI
curl -I http://43.205.94.74:8080

# Test Worker UI
curl -I http://43.205.94.74:8081

# Expected: HTTP/1.1 200 OK
```

### 3. Access in Browser

Open in your browser:
- Master UI: `http://43.205.94.74:8080`
- Worker UI: `http://43.205.94.74:8081`

---

## Complete Restart Procedure

If nothing works, try a complete restart:

```bash
# SSH to Spark instance
ssh -i ~/dstreambolt-access-key.pem ubuntu@43.205.94.74

# Stop all Spark services
sudo systemctl stop spark-master spark-worker spark-history

# Kill any remaining processes
sudo pkill -f "org.apache.spark"

# Wait a moment
sleep 3

# Start services
sudo systemctl start spark-master
sleep 5
sudo systemctl start spark-worker

# Check status
sudo systemctl status spark-master spark-worker

# Check ports
sudo netstat -tlnp | grep -E ":(7077|8080|8081)"
```

---

## Understanding the Architecture

### Network Layout

```
Internet → ALB (HTTPS) → [VPC]
                          ↓
                    ┌─────────────┐
                    │  Public     │
                    │  Subnet     │
                    └─────────────┘
                          ↓
        ┌─────────────────┼─────────────────┐
        ↓                 ↓                 ↓
   Ingestion        Compute (Spark)     DevOps
   13.201.43.125    43.205.94.74      13.232.38.64
   (Public)         (Public)          (Public)
                          ↓
                    ┌─────────────┐
                    │  Private    │
                    │  Subnet     │
                    └─────────────┘
                          ↓
                        Kafka
                    10.0.10.101
                    (Private only)
```

### Spark Ports

- **7077**: Spark Master (cluster communication)
- **8080**: Spark Master UI (web interface)
- **8081**: Spark Worker UI (web interface)
- **18080**: Spark History Server (web interface)

---

## Automated Fix Script

Save this as `fix_spark_worker.sh`:

```bash
#!/bin/bash
# Quick fix for Spark Worker

echo "🔧 Fixing Spark Worker..."

# Stop services
sudo systemctl stop spark-master spark-worker

# Kill any hanging processes
sudo pkill -9 -f "org.apache.spark" || true

# Wait
sleep 3

# Start Master
sudo systemctl start spark-master
sleep 5

# Start Worker
sudo systemctl start spark-worker
sleep 3

# Check status
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Status Check:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

sudo systemctl is-active spark-master && echo "✅ Master: Running" || echo "❌ Master: Failed"
sudo systemctl is-active spark-worker && echo "✅ Worker: Running" || echo "❌ Worker: Failed"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Listening Ports:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sudo netstat -tlnp | grep -E ":(7077|8080|8081)"

# Get public IP
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Access URLs:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Master UI:  http://$PUBLIC_IP:8080"
echo "Worker UI:  http://$PUBLIC_IP:8081"
echo "History:    http://$PUBLIC_IP:18080"
echo ""
```

**Usage:**
```bash
# Copy to server
scp -i ~/dstreambolt-access-key.pem fix_spark_worker.sh ubuntu@43.205.94.74:/tmp/

# Run it
ssh -i ~/dstreambolt-access-key.pem ubuntu@43.205.94.74 "chmod +x /tmp/fix_spark_worker.sh && sudo /tmp/fix_spark_worker.sh"
```

---

## Summary

**Most Likely Issues:**
1. ❌ Using wrong IP address (`10.0.1.128` instead of `43.205.94.74`)
2. ❌ Spark Worker service not running
3. ❌ Security group not allowing port 8081
4. ❌ Firewall blocking the port

**Quick Solution:**
1. Use correct IP: `http://43.205.94.74:8081`
2. SSH to server and restart: `sudo systemctl restart spark-worker`
3. Open security group port 8081
4. Check with diagnostic script

**Need Help?**
Run the diagnostic script on the Spark instance:
```bash
ssh -i ~/dstreambolt-access-key.pem ubuntu@43.205.94.74
curl -s https://raw.githubusercontent.com/dstreambolt/dstream_cloud/main/utils/diagnose_spark_worker.sh | bash
```

