# Migration Guide: Environment Variables → AWS Secrets Manager

## Overview
This guide walks through migrating DStreamBolt from insecure environment variables to AWS Secrets Manager.

**Time Required**: 30-60 minutes  
**Risk Level**: Low (with rollback plan)  
**Downtime**: Optional (can be done with rolling deployment)

---

## Pre-Migration Checklist

- [ ] AWS CLI installed and configured
- [ ] AWS account with permissions to create secrets and IAM policies
- [ ] Current passwords documented securely
- [ ] Backup of current configuration
- [ ] Test environment available
- [ ] Rollback plan reviewed

---

## Step 1: Setup AWS Secrets Manager (10 minutes)

### 1.1 Run Setup Script

```bash
cd /Users/skalaise/apps/cloud/terraform/dstream_bolt
./setup_secrets_manager.sh
```

**What this does:**
- Creates secrets in AWS Secrets Manager
- Creates IAM policy for secret access
- Tags all resources properly

### 1.2 Verify Secrets Created

```bash
# List all DStreamBolt secrets
aws secretsmanager list-secrets \
  --region ap-south-1 \
  --filters Key=name,Values=dstreambolt/ \
  --query 'SecretList[*].[Name,Description]' \
  --output table

# Expected output:
# ---------------------------------------------------
# |                  ListSecrets                   |
# +------------------------+-----------------------+
# |  dstreambolt/mysql     | MySQL credentials    |
# |  dstreambolt/kafka     | Kafka credentials    |
# |  dstreambolt/app       | App secrets          |
# +------------------------+-----------------------+
```

---

## Step 2: Configure IAM Roles (10 minutes)

### 2.1 Get Policy ARN

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/DStreamBoltSecretsAccess"
```

### 2.2 Attach Policy to Roles

```bash
# Ingestion service
aws iam attach-role-policy \
  --role-name dstreambolt-ingest-role \
  --policy-arn $POLICY_ARN

# Spark compute
aws iam attach-role-policy \
  --role-name dstreambolt-compute-role \
  --policy-arn $POLICY_ARN

# DevOps instance
aws iam attach-role-policy \
  --role-name dstreambolt-devops-role \
  --policy-arn $POLICY_ARN
```

### 2.3 Verify Policy Attached

```bash
# Check ingestion role
aws iam list-attached-role-policies \
  --role-name dstreambolt-ingest-role \
  --query 'AttachedPolicies[?PolicyName==`DStreamBoltSecretsAccess`]'

# Should return the policy
```

---

## Step 3: Install Dependencies (5 minutes)

### 3.1 On Each EC2 Instance

```bash
# SSH to ingestion instance
ssh -i ~/dstreambolt-spark-key.pem ubuntu@<INGEST_IP>

# Install boto3 (AWS SDK)
pip3 install boto3

# Verify installation
python3 -c "import boto3; print('✅ boto3 installed')"
```

Repeat for:
- Spark compute instance
- DevOps instance

---

## Step 4: Deploy Secrets Manager Module (5 minutes)

### 4.1 Copy Module to Servers

```bash
# From your local machine
cd /Users/skalaise/apps/cloud/terraform/dstream_bolt/ingestion

# Copy to ingestion server
scp -i ~/dstreambolt-spark-key.pem \
    secrets_manager.py \
    ubuntu@<INGEST_IP>:/opt/dstreambolt/ingestion/

# SSH and set permissions
ssh -i ~/dstreambolt-spark-key.pem ubuntu@<INGEST_IP>
sudo chown ubuntu:ubuntu /opt/dstreambolt/ingestion/secrets_manager.py
sudo chmod 644 /opt/dstreambolt/ingestion/secrets_manager.py
```

### 4.2 Test Secrets Access

```bash
# On the server
cd /opt/dstreambolt/ingestion
python3 secrets_manager.py

# Expected output:
# ================================================================================
# DStreamBolt Secrets Manager - Test
# ================================================================================
#
# Testing connection...
# ✅ Secrets Manager connection OK
#
# --------------------------------------------------------------------------------
#
# 📊 MySQL Configuration:
#    Host: 10.0.1.61
#    Port: 3306
#    User: dstreambolt
#    Password: ********
#    Database: dstreambolt_metrics
# ...
```

---

## Step 5: Update app.py (10 minutes)

### 5.1 Backup Current app.py

```bash
cd /opt/dstreambolt/ingestion
sudo cp app.py app.py.backup.$(date +%Y%m%d_%H%M%S)
```

### 5.2 Update Configuration Section

Edit `/opt/dstreambolt/ingestion/app.py`:

**Find this section:**
```python
# CONFIGURATION
MYSQL_HOST = os.getenv('MYSQL_HOST', '10.0.1.61')
MYSQL_USER = os.getenv('MYSQL_USER', 'dstreambolt')
MYSQL_PASSWORD = os.getenv('MYSQL_PASSWORD', 'DStreamBolt2025!')
MYSQL_DB = os.getenv('MYSQL_DB', 'dstreambolt_metrics')

KAFKA_BROKER = os.getenv('KAFKA_BROKER', '10.0.10.101:9092')
KAFKA_TOPIC = os.getenv('KAFKA_TOPIC', 'dstreambolt-logs')
```

**Replace with:**
```python
# CONFIGURATION - Load from AWS Secrets Manager
from secrets_manager import get_secrets_manager

# Initialize secrets manager
secrets_mgr = get_secrets_manager()

try:
    # Load MySQL configuration
    mysql_config = secrets_mgr.get_mysql_config()
    MYSQL_HOST = mysql_config['host']
    MYSQL_USER = mysql_config['user']
    MYSQL_PASSWORD = mysql_config['password']
    MYSQL_DB = mysql_config['database']
    MYSQL_PORT = mysql_config.get('port', 3306)
    
    # Load Kafka configuration
    kafka_config = secrets_mgr.get_kafka_config()
    KAFKA_BROKER = kafka_config['brokers']
    KAFKA_TOPIC = kafka_config['topic']
    
    print("✅ Secrets loaded from AWS Secrets Manager")
    
except Exception as e:
    print(f"❌ Failed to load secrets: {e}")
    print("⚠️  Falling back to environment variables")
    
    # Fallback (will be removed in production)
    MYSQL_HOST = os.getenv('MYSQL_HOST', '10.0.1.61')
    MYSQL_USER = os.getenv('MYSQL_USER', 'dstreambolt')
    MYSQL_PASSWORD = os.getenv('MYSQL_PASSWORD', '')
    MYSQL_DB = os.getenv('MYSQL_DB', 'dstreambolt_metrics')
    
    KAFKA_BROKER = os.getenv('KAFKA_BROKER', '10.0.10.101:9092')
    KAFKA_TOPIC = os.getenv('KAFKA_TOPIC', 'dstreambolt-logs')
```

### 5.3 Test Syntax

```bash
python3 -m py_compile app.py
# No output = success
```

---

## Step 6: Test in Staging (10 minutes)

### 6.1 Start Service Manually

```bash
# Stop existing service
sudo systemctl stop dstreambolt-ingest

# Start manually to see output
cd /opt/dstreambolt/ingestion
python3 app.py

# Expected output:
# 🔐 AWS Secrets Manager initialized (region: ap-south-1)
# 🔐 Fetching secret: dstreambolt/mysql
# ✅ Secret loaded: dstreambolt/mysql
# 🔐 Fetching secret: dstreambolt/kafka
# ✅ Secret loaded: dstreambolt/kafka
# ✅ Secrets loaded from AWS Secrets Manager
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 🚀 DStreamBolt Ingestion Service (Production)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### 6.2 Test Ingestion Endpoint

```bash
# From another terminal
curl -X POST http://localhost:5000/health

# Should return 200 OK
```

### 6.3 Test MySQL Connection

```bash
# Check logs for MySQL connection
# Should see successful connection without errors
```

---

## Step 7: Deploy to Production (5-10 minutes)

### 7.1 Update Systemd Service

Edit `/etc/systemd/system/dstreambolt-ingest.service`:

**Remove environment variables:**
```ini
# OLD - Remove these lines:
Environment="MYSQL_PASSWORD=DStreamBolt2025!"
Environment="KAFKA_BROKER=10.0.10.101:9092"
```

Keep only non-secret config:
```ini
Environment="QUEUE_DIR=/opt/dstreambolt/queue"
Environment="MAX_QUEUE_SIZE=10000"
```

### 7.2 Reload and Restart

```bash
# Reload systemd
sudo systemctl daemon-reload

# Restart service
sudo systemctl restart dstreambolt-ingest

# Check status
sudo systemctl status dstreambolt-ingest

# Check logs
sudo journalctl -u dstreambolt-ingest -f
```

### 7.3 Verify Service Health

```bash
# Health check
curl http://localhost:5000/health

# Metrics
curl http://localhost:5000/metrics

# Test ingestion
curl -X POST http://localhost:5000/ingest \
  -H "Content-Type: application/gzip" \
  --data-binary @/tmp/test-bundle.gz
```

---

## Step 8: Clean Up Environment Variables

### 8.1 Remove from Shell Profiles

```bash
# Check for hardcoded passwords
grep -r "MYSQL_PASSWORD" /home/ubuntu/.bashrc
grep -r "MYSQL_PASSWORD" /etc/environment

# Remove any found
```

### 8.2 Remove from Systemd Units

```bash
# Check all systemd services
sudo grep -r "MYSQL_PASSWORD" /etc/systemd/system/

# Edit and remove
```

### 8.3 Verify No Passwords in Process List

```bash
# This should NOT show passwords
ps aux | grep dstreambolt-ingest

# Before: python3 app.py (MYSQL_PASSWORD visible)
# After: python3 app.py (no password visible)
```

---

## Step 9: Verify Security (5 minutes)

### 9.1 Test Secret Rotation

```bash
# Update MySQL password in Secrets Manager
aws secretsmanager put-secret-value \
  --secret-id dstreambolt/mysql \
  --secret-string '{
    "host": "10.0.1.61",
    "port": 3306,
    "username": "dstreambolt",
    "password": "NewPassword2025!",
    "database": "dstreambolt_metrics"
  }' \
  --region ap-south-1

# Wait 5 minutes (cache TTL)
sleep 300

# Restart service (will pick up new password)
sudo systemctl restart dstreambolt-ingest

# Verify connection with new password
sudo journalctl -u dstreambolt-ingest -n 50 | grep -i mysql
```

### 9.2 Verify CloudTrail Logging

```bash
# Check CloudTrail for secret access
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceType,AttributeValue=AWS::SecretsManager::Secret \
  --region ap-south-1 \
  --max-results 10 \
  --query 'Events[*].[EventTime,EventName,Resources]'
```

---

## Rollback Plan

If anything goes wrong:

### Quick Rollback (1 minute)

```bash
# 1. Restore old app.py
sudo cp app.py.backup.TIMESTAMP app.py

# 2. Re-add environment variables to systemd
sudo systemctl edit dstreambolt-ingest
# Add:
# [Service]
# Environment="MYSQL_PASSWORD=DStreamBolt2025!"

# 3. Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart dstreambolt-ingest
```

### Complete Rollback

```bash
# Remove IAM policy
aws iam detach-role-policy \
  --role-name dstreambolt-ingest-role \
  --policy-arn $POLICY_ARN

# Keep secrets in Secrets Manager (no cost to keep)
# Can delete later if needed
```

---

## Post-Migration Verification

### Checklist

- [ ] Service starts without errors
- [ ] MySQL connection successful
- [ ] Kafka connection successful
- [ ] Ingestion endpoint responding
- [ ] No passwords in process list (`ps aux`)
- [ ] No passwords in logs (`journalctl`)
- [ ] CloudTrail logging secret access
- [ ] Secret rotation tested
- [ ] All environment variables removed
- [ ] Backups taken
- [ ] Documentation updated

### Success Criteria

✅ **Security:**
- No plaintext passwords in environment variables
- No passwords in process lists or logs
- IAM policies correctly configured
- CloudTrail logging enabled

✅ **Functionality:**
- All services connecting successfully
- No degraded performance
- Secret rotation working
- Monitoring alerts configured

✅ **Compliance:**
- Meets security audit requirements
- Secrets encrypted at rest (KMS)
- Secrets encrypted in transit (TLS)
- Complete audit trail (CloudTrail)

---

## Monitoring

### Set Up CloudWatch Alarms

```bash
# Alert on failed secret access
aws cloudwatch put-metric-alarm \
  --alarm-name DStreamBolt-SecretsAccess-Failures \
  --alarm-description "Alert when secrets access fails" \
  --metric-name ErrorCount \
  --namespace AWS/SecretsManager \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold
```

### Dashboard Metrics

Monitor:
- Secrets Manager API call count
- Secrets Manager error rate
- Service restart frequency
- MySQL connection errors
- Kafka connection errors

---

## Support

If you encounter issues:

1. **Check IAM permissions**: `aws iam simulate-principal-policy`
2. **Test secret access**: `python3 secrets_manager.py`
3. **Check CloudTrail logs**: AWS Console → CloudTrail
4. **Review service logs**: `sudo journalctl -u dstreambolt-ingest -f`
5. **Verify KMS key permissions**: `aws kms describe-key`

---

**Migration completed successfully?** ✅  
**All passwords removed from environment variables?** ✅  
**Security audit requirements met?** ✅  
**Ready for production customer use?** ✅

