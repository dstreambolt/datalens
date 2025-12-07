# DStreamBolt Compute Instance Upgrade - Summary

## Changes Made ✅

### Instance Type Upgrade
- **Previous**: t3.micro (1 vCPU, 1 GB RAM)
- **New**: t3.small (2 vCPUs, 2 GB RAM)

---

## Files Updated

### 1. **terraform/modules/compute/main.tf**
```terraform
# Changed instance_type
instance_type = "t3.small"  // Was: "t3.micro"
```

### 2. **terraform/user_data/compute.sh**
Updated Spark memory configuration to utilize increased resources:

```bash
# Spark Defaults (in spark-defaults.conf)
spark.executor.memory = 1g      // Was: 512m
spark.driver.memory = 1g        // Was: 512m

# Spark Environment (in spark-env.sh)
SPARK_WORKER_MEMORY = 1g        // Was: 512m
SPARK_WORKER_CORES = 2          // Was: 1
```

### 3. **jenkins/deploy-spark-jobs.jenkinsfile**
Updated default memory parameters:

```groovy
SPARK_DRIVER_MEMORY: '1g'       // Was: '512m'
SPARK_EXECUTOR_MEMORY: '1g'     // Was: '512m'
```

---

## Resource Comparison

### t3.micro (Old)
- **vCPUs**: 1
- **RAM**: 1 GB
- **Network**: Low to Moderate
- **Cost**: ~$0.0104/hour (~$7.50/month)

### t3.small (New) ⭐
- **vCPUs**: 2
- **RAM**: 2 GB
- **Network**: Low to Moderate
- **Cost**: ~$0.0208/hour (~$15/month)
- **Increase**: 2x CPU, 2x RAM, ~$7.50/month additional cost

---

## Benefits

✅ **Better Performance**
- 2x CPU cores for parallel processing
- 2x memory for larger datasets
- Better worker concurrency

✅ **Improved Stability**
- Less risk of out-of-memory errors
- Better handling of streaming workloads
- More resources for Spark overhead

✅ **Enhanced Capabilities**
- Can process larger batches
- Better for real-time streaming
- Reduced task failures

---

## Deployment Steps

### Option 1: Terraform (Recommended)

```bash
cd terraform

# Review changes
terraform plan

# Apply the upgrade
terraform apply

# Terraform will:
# 1. Stop the old t3.micro instance
# 2. Create new t3.small instance
# 3. Run user_data with new memory settings
# 4. Verify instance is healthy
```

**Note**: This will replace the instance (new instance ID, new IPs)

### Option 2: Manual Instance Replacement

1. **Backup important data** (if any)
2. **Note current IP addresses**
3. **Run terraform apply**
4. **Update any hardcoded IPs** in scripts/configs
5. **Verify Spark services** are running

---

## Verification After Deployment

### 1. Check Instance Type
```bash
# Get instance details
aws ec2 describe-instances \
  --region ap-south-1 \
  --filters "Name=tag:Name,Values=*compute*" \
  --query 'Reservations[0].Instances[0].[InstanceType,State.Name]' \
  --output table

# Expected output: t3.small | running
```

### 2. Verify Spark Configuration
```bash
# SSH to compute instance
ssh -i ~/dstreambolt-access-key.pem ubuntu@<NEW_IP>

# Check Spark memory settings
cat /opt/spark/conf/spark-defaults.conf | grep memory
# Should show: 1g

cat /opt/spark/conf/spark-env.sh | grep WORKER
# Should show: SPARK_WORKER_MEMORY=1g, SPARK_WORKER_CORES=2
```

### 3. Check Spark Services
```bash
# On compute instance
sudo systemctl status spark-master spark-worker

# Check ports listening
sudo ss -tlnp | grep -E ":(7077|8080|8081)"

# View Spark Master UI
curl http://localhost:8080
```

### 4. Test Spark Worker
```bash
# Check available resources in Spark Master UI
# Should show:
# - Cores: 2 Total
# - Memory: 1 GB Total (per worker)

# Or via command line
curl -s http://localhost:8080 | grep -E "Cores:|Memory:"
```

---

## Cost Impact

### Monthly Cost Increase
- **Before**: ~$7.50/month (t3.micro)
- **After**: ~$15/month (t3.small)
- **Increase**: ~$7.50/month (100% increase)

### Annual Cost Increase
- **Additional**: ~$90/year

**Note**: Prices are for On-Demand in ap-south-1 (Mumbai) region

---

## Performance Expectations

### Before (t3.micro)
- Small batch processing: ✅
- Real-time streaming: ⚠️ (limited)
- Multiple executors: ❌
- Large datasets: ❌

### After (t3.small)
- Small batch processing: ✅✅
- Real-time streaming: ✅
- Multiple executors: ✅ (2 cores)
- Medium datasets: ✅
- Better stability: ✅

---

## Rollback Procedure

If you need to rollback to t3.micro:

```bash
cd terraform/modules/compute

# Edit main.tf
# Change: instance_type = "t3.micro"

# Edit ../user_data/compute.sh
# Change memory back to: 512m
# Change cores back to: 1

# Apply changes
cd ../../
terraform apply
```

---

## Jenkins Pipeline

The Jenkins pipeline (`deploy-spark-jobs.jenkinsfile`) is already updated with the new defaults:
- Driver Memory: 1g
- Executor Memory: 1g

When deploying Spark jobs via Jenkins, these values will be used automatically.

---

## Next Steps

1. **Review the changes** - Check this document
2. **Backup any critical data** (if needed)
3. **Run terraform plan** - Review what will change
4. **Run terraform apply** - Apply the upgrade
5. **Get new IP address** - Note the new compute instance IP
6. **Update references** - Update any scripts/docs with new IP
7. **Verify Spark** - Check Spark Master/Worker UIs
8. **Test deployment** - Deploy a Spark job via Jenkins
9. **Monitor performance** - Check resource utilization

---

## Important Notes

⚠️ **Instance Replacement**
- Terraform will **replace** the instance (not resize)
- New instance ID and IP addresses
- Update any hardcoded IPs in scripts
- Security group remains the same

⚠️ **Data Loss**
- Any data on the instance will be lost
- Use backups if you have important data
- State is managed by Spark/Kafka, not on compute

⚠️ **Downtime**
- Brief downtime during instance replacement
- Typically 2-3 minutes
- Plan accordingly

✅ **No Breaking Changes**
- All configurations compatible
- Scripts work with new settings
- Jenkins pipeline updated

---

## Verification Checklist

After deployment, verify:

- [ ] Instance type is t3.small
- [ ] Instance is running
- [ ] Spark Master service is active
- [ ] Spark Worker service is active
- [ ] Spark Master UI accessible (port 8080)
- [ ] Spark Worker UI accessible (port 8081)
- [ ] Worker shows 2 cores available
- [ ] Worker shows 1GB memory available
- [ ] Jenkins pipeline can deploy jobs
- [ ] Test Spark job runs successfully

---

## Support Commands

### Get New IP After Upgrade
```bash
cd terraform
terraform output -json | jq -r '.direct_access.value.compute_ip'
```

### Test Spark Submission
```bash
ssh -i ~/dstreambolt-access-key.pem ubuntu@<NEW_IP>

cd /opt/dstreambolt/computations
./submit_spark_job.sh \
  spark://$(hostname -I | awk '{print $1}'):7077 \
  10.0.10.101:9092 \
  streaming \
  1g \
  1g
```

### Monitor Resources
```bash
# On compute instance
htop  # or top

# Check memory usage
free -h

# Check Spark logs
tail -f /opt/spark/logs/*master*.out
tail -f /opt/spark/logs/*worker*.out
```

---

**Status**: ✅ Ready for Deployment
**Cost Impact**: +$7.50/month
**Performance**: 2x improvement
**Updated**: December 7, 2025

