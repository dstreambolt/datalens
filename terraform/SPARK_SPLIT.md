# Spark Cluster Split - Master and Executor Separation

## 🎯 Overview

The DStreamBolt compute infrastructure has been split into two separate instances:
- **Spark Master** (t3.small) - Manages cluster, runs driver programs
- **Spark Executor** (t3.small) - Executes Spark tasks

This separation provides better resource isolation, scalability, and fault tolerance.

## 📋 Changes Made

### 1. Terraform Module Changes

**File:** `terraform/modules/compute/main.tf`

**Before:**
- Single `aws_instance.compute` resource
- Combined Master + Worker on same node

**After:**
- `aws_instance.spark_master` - Dedicated master node
- `aws_instance.spark_executor` - Dedicated executor/worker node
- Both use `t3.small` instance type
- Executor depends on Master (ensures proper startup order)

### 2. New User Data Scripts

**Created:** `terraform/user_data/spark_master.sh`
- Installs Java 11
- Installs Spark 3.5.0
- Configures Spark Master service
- Starts History Server
- Opens ports: 7077 (master), 8080 (UI), 18080 (history)

**Created:** `terraform/user_data/spark_executor.sh`
- Installs Java 11
- Installs Spark 3.5.0
- Waits for master to be ready
- Connects to master using private IP
- Opens port: 8081 (worker UI)

### 3. Output Changes

**File:** `terraform/main.tf`

**New outputs:**
- `module.compute.master_public_ip` - Spark master public IP
- `module.compute.master_private_ip` - Spark master private IP
- `module.compute.executor_public_ip` - Executor public IP
- `module.compute.executor_private_ip` - Executor private IP

**Backward compatibility:**
- `module.compute.public_ip` - Points to master (deprecated)
- `module.compute.private_ip` - Points to master (deprecated)

### 4. Summary Output Updated

The deployment summary now shows separate SSH commands for:
- Spark Master
- Spark Executor

## 🏗️ Architecture

### Before:
```
┌─────────────────────────────┐
│   dstreambolt-compute       │
│   (t3.small)                │
│                             │
│   ┌───────────────────┐     │
│   │  Spark Master     │     │
│   │  Port 7077, 8080  │     │
│   └───────────────────┘     │
│                             │
│   ┌───────────────────┐     │
│   │  Spark Worker     │     │
│   │  Port 8081        │     │
│   └───────────────────┘     │
└─────────────────────────────┘
```

### After:
```
┌──────────────────────────┐      ┌──────────────────────────┐
│  dstreambolt-spark-master│      │ dstreambolt-spark-executor│
│  (t3.small)              │      │  (t3.small)               │
│                          │      │                           │
│  ┌────────────────────┐  │      │  ┌─────────────────────┐ │
│  │  Spark Master      │  │      │  │  Spark Worker       │ │
│  │  Port 7077, 8080   │  │◄─────┤  │  Port 8081          │ │
│  │  History: 18080    │  │      │  │  Connects to master │ │
│  └────────────────────┘  │      │  └─────────────────────┘ │
└──────────────────────────┘      └──────────────────────────┘
         Master                           Executor
```

## 🚀 Deployment Steps

### 1. Destroy Old Compute Instance

```bash
cd terraform
terraform destroy -target=module.compute.aws_instance.compute
```

### 2. Apply New Configuration

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

### 3. Verify Deployment

```bash
# Get the new IPs
terraform output direct_access

# SSH to master
ssh -i ~/dstreambolt-access-key.pem ubuntu@<master-ip>

# Check master status
systemctl status spark-master
systemctl status spark-history

# View Master UI
# http://<master-public-ip>:8080

# SSH to executor
ssh -i ~/dstreambolt-access-key.pem ubuntu@<executor-ip>

# Check worker status
systemctl status spark-worker

# View Worker UI
# http://<executor-public-ip>:8081
```

## 🔍 Verification

### Check Master UI
Access: `http://<master-public-ip>:8080`

You should see:
- ✅ Master status: ALIVE
- ✅ Workers: 1 registered
- ✅ Cores: 2 available
- ✅ Memory: 1500 MB available

### Check Worker UI
Access: `http://<executor-public-ip>:8081`

You should see:
- ✅ Master URL: spark://<master-private-ip>:7077
- ✅ Worker ID assigned
- ✅ Status: ALIVE

### Test Spark Job Submission

```bash
# SSH to master
ssh -i ~/dstreambolt-access-key.pem ubuntu@<master-ip>

# Get master private IP
MASTER_IP=$(hostname -I | awk '{print $1}')

# Test spark-submit
/opt/spark/bin/spark-submit \
  --master spark://$MASTER_IP:7077 \
  --class org.apache.spark.examples.SparkPi \
  /opt/spark/examples/jars/spark-examples_2.12-3.5.0.jar \
  100
```

You should see the job run successfully and appear in both UIs.

## 📊 Resource Allocation

| Component | Instance Type | vCPU | Memory | Purpose |
|-----------|---------------|------|--------|---------|
| **Master** | t3.small | 2 | 2 GB | Cluster management, driver |
| **Executor** | t3.small | 2 | 2 GB | Task execution |

**Total Resources:**
- vCPU: 4 cores
- Memory: 4 GB
- Cost: ~$30/month (2 x t3.small)

## 🔧 Jenkins Pipeline Update

The Jenkins pipeline (`deploy-prebuilt-scala-spark.jenkinsfile`) **does not require changes**.

**Why?** 
- Pipeline uses `SPARK_MASTER_IPS` parameter
- Default value will be updated to new master private IP
- Jobs are submitted to master, which delegates to executor

**To update default IP:**
1. Get new master private IP from Terraform output
2. Update Jenkins job parameter default value
3. Or pass the new IP when running the job

## 🎯 Benefits

### 1. Resource Isolation
- Master handles cluster management and driver
- Executor handles task execution
- No resource contention

### 2. Scalability
- Easy to add more executors
- Scale executors independently of master
- Future: Auto-scaling group for executors

### 3. Fault Tolerance
- Master failure doesn't kill executors
- Executor failure doesn't affect master
- Better debugging (separate logs)

### 4. Performance
- More memory per component (2GB each vs shared 2GB)
- Dedicated CPU for master operations
- Better network isolation

## 🔄 Rollback Plan

If issues occur, rollback to single-node:

```bash
cd terraform

# 1. Destroy new instances
terraform destroy -target=module.compute

# 2. Checkout previous version of compute module
git checkout HEAD~1 -- modules/compute/main.tf user_data/compute.sh

# 3. Remove new files
rm user_data/spark_master.sh user_data/spark_executor.sh

# 4. Apply old configuration
terraform apply
```

## 📝 Configuration Details

### Master Configuration
- **Service:** spark-master
- **Port:** 7077 (master), 8080 (UI), 18080 (history)
- **User Data:** `user_data/spark_master.sh`
- **Role Tag:** spark-master

### Executor Configuration
- **Service:** spark-worker
- **Port:** 8081 (worker UI)
- **User Data:** `user_data/spark_executor.sh`
- **Role Tag:** spark-executor
- **Connects to:** Master private IP (passed via Terraform)
- **Resources:** 2 cores, 1500 MB memory

### Network Communication
- Executor → Master: Port 7077 (Spark protocol)
- User → Master UI: Port 8080 (HTTP)
- User → Executor UI: Port 8081 (HTTP)
- User → History Server: Port 18080 (HTTP)

## 🆘 Troubleshooting

### Issue: Executor not connecting to master

**Check master is running:**
```bash
ssh ubuntu@<master-ip>
systemctl status spark-master
```

**Check master port is open:**
```bash
telnet <master-private-ip> 7077
```

**Check executor logs:**
```bash
ssh ubuntu@<executor-ip>
journalctl -u spark-worker -f
```

### Issue: Worker not visible in Master UI

**Verify worker is running:**
```bash
ssh ubuntu@<executor-ip>
systemctl status spark-worker
```

**Check Master IP in worker config:**
```bash
ssh ubuntu@<executor-ip>
cat /etc/systemd/system/spark-worker.service
# Should show: ExecStart=/opt/spark/sbin/start-worker.sh spark://<master-ip>:7077
```

**Restart worker:**
```bash
ssh ubuntu@<executor-ip>
sudo systemctl restart spark-worker
```

### Issue: Jobs not executing

**Check resources in Master UI:**
- Go to: http://<master-ip>:8080
- Verify: Workers > 0, Cores > 0, Memory > 0

**Check executor logs:**
```bash
ssh ubuntu@<executor-ip>
tail -100 /opt/spark/logs/spark-root-org.apache.spark.deploy.worker.Worker-*.out
```

## ✅ Success Criteria

After deployment, verify:

- [ ] Master service running: `systemctl status spark-master`
- [ ] Executor service running: `systemctl status spark-worker`
- [ ] Master UI accessible: http://<master-ip>:8080
- [ ] Worker visible in Master UI: Shows 1 worker
- [ ] Worker UI accessible: http://<executor-ip>:8081
- [ ] History Server accessible: http://<master-ip>:18080
- [ ] Test job runs successfully
- [ ] Jenkins pipeline works with new master IP

## 📚 Related Files

- `terraform/modules/compute/main.tf` - Instance definitions
- `terraform/user_data/spark_master.sh` - Master setup script
- `terraform/user_data/spark_executor.sh` - Executor setup script
- `terraform/main.tf` - Module invocation and outputs
- `jenkins/deploy-prebuilt-scala-spark.jenkinsfile` - Deployment pipeline

---

**Status:** ✅ Complete  
**Date:** December 10, 2025  
**Impact:** Improved resource isolation and scalability

