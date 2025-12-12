# DStreamBolt Secrets Manager - Quick Deployment Checklist

## ✅ Completed (Development)

- [x] Updated `ingestion/app.py` to use AWS Secrets Manager
- [x] Added automatic secret rotation (5-minute refresh)
- [x] Enhanced Kafka producer with SASL support
- [x] Removed API key authentication (mTLS-only)
- [x] Added comprehensive logging
- [x] Created validation script (`validate_secrets.py`)
- [x] Local testing passed
- [x] Documentation created

---

## ⏳ Required (Production Deployment)

### Step 1: AWS Secrets Manager Setup

```bash
# 1. Create MySQL secret
aws secretsmanager create-secret \
  --name dstreambolt/mysql \
  --description "DStreamBolt MySQL credentials" \
  --secret-string '{
    "host": "10.0.1.61",
    "port": 3306,
    "username": "dstreambolt",
    "password": "DStreamBolt2025!",
    "database": "dstreambolt_metrics"
  }' \
  --region ap-south-1

# 2. Create Kafka secret
aws secretsmanager create-secret \
  --name dstreambolt/kafka \
  --description "DStreamBolt Kafka credentials" \
  --secret-string '{
    "brokers": ["10.0.10.101:9092"],
    "topic": "dstreambolt-logs",
    "security_protocol": "PLAINTEXT"
  }' \
  --region ap-south-1

# 3. Verify secrets created
aws secretsmanager list-secrets --region ap-south-1 | grep dstreambolt
```

- [ ] MySQL secret created
- [ ] Kafka secret created
- [ ] Secrets verified

---

### Step 2: IAM Policy Configuration

```bash
# 1. Create IAM policy file
cat > /tmp/secrets-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:ap-south-1:*:secret:dstreambolt/*"
    },
    {
      "Effect": "Allow",
      "Action": ["kms:Decrypt"],
      "Resource": "*"
    }
  ]
}
EOF

# 2. Create policy
aws iam create-policy \
  --policy-name DStreamBoltSecretsAccess \
  --policy-document file:///tmp/secrets-policy.json

# 3. Attach to EC2 instance role
INSTANCE_ID="i-xxxxx"  # Replace with actual ID
ROLE_NAME=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' \
  --output text | cut -d'/' -f2)

aws iam attach-role-policy \
  --role-name $ROLE_NAME \
  --policy-arn $(aws iam list-policies --query 'Policies[?PolicyName==`DStreamBoltSecretsAccess`].Arn' --output text)
```

- [ ] IAM policy created
- [ ] Policy attached to instance role
- [ ] Permissions verified

---

### Step 3: Deploy Updated Code

```bash
# On your local machine
cd /Users/skalaise/apps/cloud/terraform/dstream_bolt

# 1. Package updated code
tar -czf dstreambolt-ingest-update.tar.gz \
  ingestion/app.py \
  ingestion/secrets_manager.py \
  ingestion/requirements.txt

# 2. Copy to server
INGEST_IP="13.201.43.125"  # Replace with actual IP
scp -i ~/dstreambolt-access-key.pem \
  dstreambolt-ingest-update.tar.gz \
  ubuntu@$INGEST_IP:/tmp/

# 3. SSH to server and deploy
ssh -i ~/dstreambolt-access-key.pem ubuntu@$INGEST_IP

# On the server:
cd /opt/dstreambolt/ingestion

# Backup current version
sudo cp app.py app.py.backup.$(date +%Y%m%d)
sudo cp secrets_manager.py secrets_manager.py.backup.$(date +%Y%m%d)

# Extract new version
cd /tmp
tar -xzf dstreambolt-ingest-update.tar.gz
sudo cp ingestion/* /opt/dstreambolt/ingestion/

# Verify files
ls -la /opt/dstreambolt/ingestion/app.py
ls -la /opt/dstreambolt/ingestion/secrets_manager.py

# Test import
cd /opt/dstreambolt/ingestion
source venv/bin/activate
python3 -c "from secrets_manager import SecretsManager; print('OK')"
```

- [ ] Code packaged
- [ ] Copied to server
- [ ] Backup created
- [ ] New code deployed
- [ ] Import test passed

---

### Step 4: Restart Service

```bash
# On the server
sudo systemctl restart dstreambolt-ingest

# Check logs for successful startup
sudo journalctl -u dstreambolt-ingest -f

# Look for these lines:
# ✅ AWS Secrets Manager initialized
# ✅ MySQL config loaded: dstreambolt@10.0.1.61:3306/dstreambolt_metrics
# ✅ Kafka config loaded: 10.0.10.101:9092
# ✅ Background threads started (worker, metrics, secrets refresh)
```

- [ ] Service restarted
- [ ] Logs show secrets loaded successfully
- [ ] No error messages

---

### Step 5: Verify Service Health

```bash
# 1. Check service status
curl -k https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/health

# Expected response:
# {
#   "status": "healthy",
#   "mysql": "connected",
#   "kafka": "connected",
#   "timestamp": "..."
# }

# 2. Check metrics endpoint
curl -k https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/metrics

# 3. Test ingestion
python3 examples/02-send-to-ingest.py \
  --alb-url https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/ingest \
  --no-verify \
  examples/logs/access.log
```

- [ ] Health check passes
- [ ] Metrics endpoint working
- [ ] Ingestion working
- [ ] Logs processing

---

### Step 6: Test Secret Rotation

```bash
# 1. Update MySQL password
aws secretsmanager update-secret \
  --secret-id dstreambolt/mysql \
  --secret-string '{
    "host": "10.0.1.61",
    "port": 3306,
    "username": "dstreambolt",
    "password": "NewPassword2025!",
    "database": "dstreambolt_metrics"
  }' \
  --region ap-south-1

# 2. Wait 5 minutes for automatic refresh
sleep 300

# 3. Check logs
sudo journalctl -u dstreambolt-ingest | grep "refresh"

# Look for:
# 🔄 Refreshing secrets from AWS Secrets Manager...
# ✅ MySQL config updated

# 4. Verify service still working
curl -k https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/health
```

- [ ] Secret updated in AWS
- [ ] Automatic refresh detected in logs
- [ ] Service still healthy
- [ ] No manual restart required

---

### Step 7: Enable CloudWatch Monitoring

```bash
# Create CloudWatch alarm for secret access failures
aws cloudwatch put-metric-alarm \
  --alarm-name DStreamBolt-SecretsAccessFailed \
  --metric-name SecretAccessAttempts \
  --namespace DStreamBolt \
  --statistic Sum \
  --period 300 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1 \
  --alarm-actions arn:aws:sns:ap-south-1:ACCOUNT_ID:alerts
```

- [ ] CloudWatch alarms configured
- [ ] SNS topic for alerts created
- [ ] Test alert sent

---

### Step 8: Update Documentation

- [ ] Update runbook with new deployment process
- [ ] Document secret rotation procedure
- [ ] Train ops team on new process
- [ ] Update incident response plan

---

## Rollback Procedure (If Needed)

```bash
# On the server
cd /opt/dstreambolt/ingestion

# 1. Restore backup
sudo cp app.py.backup.YYYYMMDD app.py
sudo cp secrets_manager.py.backup.YYYYMMDD secrets_manager.py

# 2. Ensure environment variables set
sudo systemctl edit dstreambolt-ingest
# Add:
# Environment="MYSQL_PASSWORD=DStreamBolt2025!"

# 3. Restart
sudo systemctl restart dstreambolt-ingest

# 4. Verify
curl -k https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/health
```

---

## Success Criteria

✅ All secrets loaded from AWS Secrets Manager  
✅ Service running without errors  
✅ Health check passes  
✅ Ingestion working  
✅ Automatic rotation verified  
✅ CloudWatch monitoring enabled  
✅ Documentation updated  

---

## Cost

**Monthly:** $1.25 (~$15/year)  
**ROI:** Security compliance + automatic rotation + audit trail = **Priceless**

---

## Support

**Validation Script:**
```bash
python3 validate_secrets.py
```

**Check Logs:**
```bash
sudo journalctl -u dstreambolt-ingest -f
```

**Verify Secrets:**
```bash
aws secretsmanager list-secrets --region ap-south-1 | grep dstreambolt
```

---

**Status**: Ready for production deployment  
**Last Updated**: December 12, 2025  
**Version**: 1.0

