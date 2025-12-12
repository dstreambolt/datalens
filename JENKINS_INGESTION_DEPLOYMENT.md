# Jenkins Ingestion Deployment Job - Updated for AWS Secrets Manager

## Date: December 12, 2025
## Status: ✅ Updated and Ready

---

## What Changed

The Jenkins ingestion deployment job has been updated to support AWS Secrets Manager integration:

### New Features ✅

1. **AWS Secrets Verification**
   - Checks if secrets exist before deployment
   - Validates IAM role on target servers
   - Verifies Secrets Manager access

2. **Enhanced Health Checks**
   - Verifies secrets are loaded
   - Checks background threads (including secrets refresh)
   - Tests both /health and /metrics endpoints
   - Monitors for errors in logs

3. **Secrets Rotation Testing**
   - Optional stage to test automatic rotation
   - Waits 5 minutes and verifies service still healthy
   - Can be enabled with `TEST_SECRETS_ROTATION` parameter

4. **Improved Deployment**
   - Includes `secrets_manager.py` in deployment
   - Verifies boto3 installation
   - Checks IAM role and Secrets Manager access
   - Better error messages

---

## Job Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `TARGET_IPS` | (required) | Comma-separated IPs: `13.201.43.125` |
| `GIT_BRANCH` | `main` | Git branch to deploy |
| `SSH_KEY_PATH` | `/home/ubuntu/.ssh/dstreambolt-access-key.pem` | SSH key path |
| `REMOTE_USER` | `ubuntu` | SSH username |
| `AWS_REGION` | `ap-south-1` | AWS region for secrets |
| `VERIFY_SECRETS` | `true` | Check secrets before deploy |
| `RESTART_SERVICE` | `true` | Restart service after deploy |
| `RUN_TESTS` | `true` | Run health checks |
| `TEST_SECRETS_ROTATION` | `false` | Test auto-rotation (5+ min) |

---

## Pipeline Stages

### 1. Validate Input ✅
- Parses and validates target IPs
- Logs deployment configuration

### 2. Checkout Code ✅
- Clones repository from GitHub
- Gets commit hash for versioning

### 3. Validate Ingestion Code ✅
- Checks `app.py` exists
- Checks `secrets_manager.py` exists
- Validates Python syntax
- Verifies `boto3` in requirements.txt

### 4. Verify AWS Secrets (New) ✅
- Checks if `dstreambolt/mysql` secret exists
- Checks if `dstreambolt/kafka` secret exists
- Warns if secrets not found (will use env vars)

### 5. Prepare Deployment Package ✅
- Creates tarball with all ingestion code
- Includes `app.py`, `secrets_manager.py`, `requirements.txt`
- Adds deployment info file

### 6. Deploy to Servers ✅
- Verifies IAM role on each server
- Tests Secrets Manager access
- Creates backup of current version
- Extracts and installs new code
- Installs dependencies (including boto3)
- Verifies secrets_manager module works

### 7. Restart Services ✅
- Restarts `dstreambolt-ingest` service
- Checks service status

### 8. Health Checks (Enhanced) ✅
- Checks service is running
- Verifies secrets loaded from logs:
  - "AWS Secrets Manager initialized"
  - "MySQL config loaded"
  - "Kafka config loaded"
  - "Background threads started"
- Tests `/health` endpoint
- Tests `/metrics` endpoint
- Checks for errors in logs

### 9. Test Secrets Rotation (Optional) ✅
- Waits 5 minutes for auto-refresh
- Monitors logs for refresh events
- Verifies service still healthy

### 10. Cleanup Old Backups ✅
- Keeps only last 5 backups

---

## Prerequisites

### Before First Deployment

1. **Create AWS Secrets** (if not exists)
   ```bash
   aws secretsmanager create-secret \
     --name dstreambolt/mysql \
     --secret-string '{"host":"10.0.1.61","port":3306,"username":"dstreambolt","password":"DStreamBolt2025!","database":"dstreambolt_metrics"}' \
     --region ap-south-1
   
   aws secretsmanager create-secret \
     --name dstreambolt/kafka \
     --secret-string '{"brokers":["10.0.10.101:9092"],"topic":"dstreambolt-logs","security_protocol":"PLAINTEXT"}' \
     --region ap-south-1
   ```

2. **Configure IAM Role**
   
   Attach policy to EC2 instance role:
   ```json
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
       }
     ]
   }
   ```

3. **Verify Jenkins Credentials**
   - SSH key available at `/home/ubuntu/.ssh/dstreambolt-access-key.pem`
   - AWS CLI configured on Jenkins server
   - Access to target servers

---

## How to Use

### Standard Deployment

1. Open Jenkins: `https://jenkins.dstreambolt.dashbird.com/`

2. Navigate to job: **"DStreamBolt-Deploy-Ingestion"**

3. Click **"Build with Parameters"**

4. Fill in parameters:
   - `TARGET_IPS`: `13.201.43.125` (your ingestion server IP)
   - `GIT_BRANCH`: `main`
   - Leave other defaults

5. Click **"Build"**

6. Monitor console output for:
   ```
   ✅ Code validation passed
   ✅ MySQL secret exists
   ✅ Kafka secret exists
   ✅ IAM Role attached: dstreambolt-ingest-role
   ✅ Secrets Manager access verified
   ✅ Deployment to 13.201.43.125 completed
   ✅ Service restarted
   ✅ Secrets Manager initialized
   ✅ MySQL config loaded
   ✅ Kafka config loaded
   ✅ Background threads started
   ✅ Health check passed
   ✅ All health checks passed
   ```

### Test Secrets Rotation

1. Run deployment with `TEST_SECRETS_ROTATION=true`

2. Job will:
   - Deploy code
   - Wait 5 minutes
   - Check logs for refresh events
   - Verify service still healthy

---

## Expected Output

### Successful Deployment

```
✅ ═══════════════════════════════════════════════════
✅ Deployment completed successfully!
✅ ═══════════════════════════════════════════════════
📦 Deployed to: 13.201.43.125
📌 Commit: abc1234
🌿 Branch: main
🔐 AWS Secrets Manager: Enabled
🔄 Auto-rotation: Every 5 minutes
═══════════════════════════════════════════════════

📋 Next Steps:
  1. Verify secrets in AWS Secrets Manager
  2. Monitor logs: sudo journalctl -u dstreambolt-ingest -f
  3. Test ingestion endpoint
  4. Monitor metrics dashboard

🔗 Useful Commands:
  Health: curl http://localhost:5000/health
  Metrics: curl http://localhost:5000/metrics
  Logs: sudo journalctl -u dstreambolt-ingest --since "10 minutes ago"
```

### Health Check Output

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Health Check: 13.201.43.125
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1️⃣  Checking service status...
✅ Service is running
2️⃣  Checking startup logs...
✅ Secrets Manager initialized
✅ MySQL config loaded
✅ Kafka config loaded
✅ Background threads started (worker, metrics, secrets refresh)
✅ No errors in recent logs
3️⃣  Testing /health endpoint...
✅ Health check passed
Response: {"status":"healthy","mysql":"connected","kafka":"connected"}
4️⃣  Testing /metrics endpoint...
✅ Metrics endpoint working
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ All health checks passed for 13.201.43.125
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Troubleshooting

### Error: "MySQL secret not found"

**Cause**: Secret doesn't exist in AWS Secrets Manager  
**Fix**: Create secret using AWS CLI:
```bash
aws secretsmanager create-secret \
  --name dstreambolt/mysql \
  --secret-string '{"host":"10.0.1.61","port":3306,"username":"dstreambolt","password":"PASSWORD","database":"dstreambolt_metrics"}' \
  --region ap-south-1
```

### Error: "No IAM role attached"

**Cause**: EC2 instance doesn't have IAM role  
**Fix**: Attach IAM role via AWS Console or CLI:
```bash
aws ec2 associate-iam-instance-profile \
  --instance-id i-xxxxx \
  --iam-instance-profile Name=dstreambolt-ingest-role
```

### Error: "Cannot access Secrets Manager"

**Cause**: IAM role lacks permissions  
**Fix**: Update IAM role policy:
```bash
aws iam attach-role-policy \
  --role-name dstreambolt-ingest-role \
  --policy-arn arn:aws:iam::ACCOUNT_ID:policy/DStreamBoltSecretsAccess
```

### Warning: "Secrets Manager not initialized"

**Cause**: Service is using environment variables fallback  
**Impact**: Service will work but without Secrets Manager benefits  
**Fix**: 
1. Verify secrets exist in AWS
2. Verify IAM role attached
3. Check logs: `sudo journalctl -u dstreambolt-ingest -n 50`

### Health Check Failed

**Cause**: Service not starting properly  
**Debug**:
```bash
# SSH to server
ssh -i ~/dstreambolt-access-key.pem ubuntu@13.201.43.125

# Check service status
sudo systemctl status dstreambolt-ingest

# Check logs
sudo journalctl -u dstreambolt-ingest -n 100

# Check for Python errors
sudo journalctl -u dstreambolt-ingest | grep -i "error\|exception"

# Verify secrets manager
cd /opt/dstreambolt/ingestion
source venv/bin/activate
python3 -c "from secrets_manager import SecretsManager; sm = SecretsManager(); print(sm.get_mysql_config())"
```

---

## Rollback

If deployment fails or service has issues:

1. **Via Jenkins** (recommended):
   - Revert Git commit
   - Re-run deployment job

2. **Manual Rollback**:
   ```bash
   # SSH to server
   ssh -i ~/dstreambolt-access-key.pem ubuntu@13.201.43.125
   
   # Stop service
   sudo systemctl stop dstreambolt-ingest
   
   # Restore backup
   cd /opt/dstreambolt/backups
   LATEST_BACKUP=$(ls -t ingest-backup-*.tar.gz | head -1)
   sudo tar -xzf $LATEST_BACKUP -C /opt/dstreambolt/ingestion
   
   # Restart service
   sudo systemctl restart dstreambolt-ingest
   
   # Verify
   curl http://localhost:5000/health
   ```

---

## Monitoring

### After Deployment

1. **Check Service Logs**:
   ```bash
   sudo journalctl -u dstreambolt-ingest -f
   ```
   
   Look for:
   - ✅ "AWS Secrets Manager initialized"
   - ✅ "MySQL config loaded"
   - ✅ "Kafka config loaded"
   - ✅ "Background threads started"

2. **Monitor Secrets Refresh**:
   ```bash
   sudo journalctl -u dstreambolt-ingest | grep -i "refresh"
   ```
   
   Should see every 5 minutes:
   - "🔄 Refreshing secrets from AWS Secrets Manager..."
   - "✅ Secrets refresh completed"

3. **Test Endpoints**:
   ```bash
   # Health
   curl http://localhost:5000/health
   
   # Metrics
   curl http://localhost:5000/metrics | python3 -m json.tool
   ```

4. **Test Ingestion**:
   ```bash
   # From local machine
   python3 examples/02-send-to-ingest.py \
     --alb-url https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/ingest \
     --no-verify \
     examples/logs/access.log
   ```

---

## Additional Notes

- **Deployment Time**: ~2-3 minutes per server
- **Downtime**: ~10-15 seconds during service restart
- **Backup Retention**: Last 5 backups kept
- **Secrets Refresh**: Every 5 minutes automatically
- **Health Check Timeout**: 10 seconds startup + tests

---

## Related Documentation

- `DEPLOYMENT_CHECKLIST.md` - Manual deployment steps
- `SECRETS_IMPLEMENTATION.md` - Secrets Manager setup guide
- `APP_OPTIMIZATION_SUMMARY.md` - Code changes summary

---

**Jenkins Job**: `DStreamBolt-Deploy-Ingestion`  
**Last Updated**: December 12, 2025  
**Status**: ✅ Ready for production use

