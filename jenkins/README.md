# Jenkins Deployment Jobs

This directory contains Jenkins pipeline scripts for deploying DStreamBolt components.

## 📋 Available Jobs

### 1. Deploy Ingestion Service
**File**: `deploy-ingestion.jenkinsfile`

Deploys the ingestion service to one or more ingestion servers.

### 2. Deploy Spark Jobs
**File**: `deploy-spark-jobs.jenkinsfile`

Deploys Spark computation jobs, gracefully kills existing jobs, and starts new ones.

---

## 🚀 Setup Instructions

### Prerequisites

1. **Jenkins Server** with:
   - Git plugin
   - Pipeline plugin
   - SSH access to target servers
   - SSH private key (`dstreambolt-access-key.pem`)

2. **Target Servers** must have:
   - SSH access enabled
   - Sudo privileges for the deployment user
   - Required services installed (via Terraform)

### Step 1: Add SSH Credentials to Jenkins

1. Go to **Jenkins → Manage Jenkins → Manage Credentials**
2. Click **Add Credentials**
3. Choose **SSH Username with private key**
4. Fill in:
   - **ID**: `dstreambolt-ssh-key`
   - **Username**: `ubuntu`
   - **Private Key**: Paste contents of `~/dstreambolt-access-key.pem`
5. Click **OK**

### Step 2: Create Jenkins Jobs

#### Job 1: Deploy Ingestion Service

1. Go to **Jenkins → New Item**
2. Enter name: `DStreamBolt-Deploy-Ingestion`
3. Select **Pipeline**
4. Click **OK**
5. In **Pipeline** section:
   - **Definition**: Pipeline script from SCM
   - **SCM**: Git
   - **Repository URL**: `https://github.com/dstreambolt/dstream_cloud.git`
   - **Branch**: `*/main`
   - **Script Path**: `jenkins/deploy-ingestion.jenkinsfile`
6. Click **Save**

#### Job 2: Deploy Spark Jobs

1. Go to **Jenkins → New Item**
2. Enter name: `DStreamBolt-Deploy-Spark`
3. Select **Pipeline**
4. Click **OK**
5. In **Pipeline** section:
   - **Definition**: Pipeline script from SCM
   - **SCM**: Git
   - **Repository URL**: `https://github.com/dstreambolt/dstream_cloud.git`
   - **Branch**: `*/main`
   - **Script Path**: `jenkins/deploy-spark-jobs.jenkinsfile`
6. Click **Save**

### Step 3: Configure SSH Key Path

Update the default SSH key path in both Jenkinsfiles:

```groovy
string(
    name: 'SSH_KEY_PATH',
    defaultValue: '/home/ubuntu/.ssh/dstreambolt-access-key.pem',  // Update this path
    description: 'Path to SSH private key on Jenkins server'
)
```

Or store the key on Jenkins server at the specified path:

```bash
# On Jenkins server
sudo mkdir -p /home/ubuntu/.ssh
sudo cp ~/dstreambolt-access-key.pem /home/ubuntu/.ssh/
sudo chmod 600 /home/ubuntu/.ssh/dstreambolt-access-key.pem
sudo chown jenkins:jenkins /home/ubuntu/.ssh/dstreambolt-access-key.pem
```

---

## 📖 Usage Guide

### Deploy Ingestion Service

#### Single Server Deployment

1. Go to **DStreamBolt-Deploy-Ingestion** job
2. Click **Build with Parameters**
3. Fill in parameters:
   ```
   TARGET_IPS: 13.201.43.125
   GIT_BRANCH: main
   RESTART_SERVICE: ✓ (checked)
   RUN_TESTS: ✓ (checked)
   ```
4. Click **Build**

#### Multiple Servers Deployment

```
TARGET_IPS: 13.201.43.125,52.66.123.45,15.206.146.37
GIT_BRANCH: main
RESTART_SERVICE: ✓ (checked)
RUN_TESTS: ✓ (checked)
```

**Features:**
- ✅ Deploys in parallel to all servers
- ✅ Creates automatic backups
- ✅ Validates Python code before deployment
- ✅ Restarts service automatically
- ✅ Runs health checks
- ✅ Keeps last 5 backups

#### Deploy from Feature Branch

```
TARGET_IPS: 13.201.43.125
GIT_BRANCH: feature/new-endpoint
RESTART_SERVICE: ✓ (checked)
RUN_TESTS: ✓ (checked)
```

### Deploy Spark Jobs

#### Single Spark Master

1. Go to **DStreamBolt-Deploy-Spark** job
2. Click **Build with Parameters**
3. Fill in parameters:
   ```
   SPARK_MASTER_IPS: 43.205.94.74
   KAFKA_BROKER: 10.0.10.101:9092
   PROCESSING_MODE: streaming
   GRACEFUL_SHUTDOWN: ✓ (checked)
   AUTO_START: ✓ (checked)
   ```
4. Click **Build**

#### Multiple Spark Masters

```
SPARK_MASTER_IPS: 43.205.94.74,52.66.123.45
KAFKA_BROKER: 10.0.10.101:9092
PROCESSING_MODE: streaming
GRACEFUL_SHUTDOWN: ✓ (checked)
AUTO_START: ✓ (checked)
```

**Features:**
- ✅ Gracefully stops existing Spark jobs (waits up to 60s)
- ✅ Force kills if not stopped gracefully
- ✅ Deploys new code in parallel
- ✅ Automatically starts new jobs
- ✅ Creates backups before deployment
- ✅ Verifies deployment success

#### Batch Processing Mode

```
SPARK_MASTER_IPS: 43.205.94.74
KAFKA_BROKER: 10.0.10.101:9092
PROCESSING_MODE: batch
GRACEFUL_SHUTDOWN: ✓ (checked)
AUTO_START: ✓ (checked)
```

#### Custom Memory Settings

```
SPARK_MASTER_IPS: 43.205.94.74
KAFKA_BROKER: 10.0.10.101:9092
PROCESSING_MODE: streaming
SPARK_DRIVER_MEMORY: 1g
SPARK_EXECUTOR_MEMORY: 1g
```

---

## 🔧 Job Parameters Reference

### Ingestion Deployment Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `TARGET_IPS` | String | (required) | Comma-separated list of ingestion server IPs |
| `GIT_BRANCH` | String | `main` | Git branch to deploy from |
| `SSH_KEY_PATH` | String | `/home/ubuntu/.ssh/...` | Path to SSH private key |
| `REMOTE_USER` | String | `ubuntu` | SSH user for remote servers |
| `RESTART_SERVICE` | Boolean | `true` | Restart the service after deployment |
| `RUN_TESTS` | Boolean | `true` | Run health checks after deployment |

### Spark Deployment Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `SPARK_MASTER_IPS` | String | (required) | Comma-separated list of Spark master IPs |
| `JOB_NAME_FILTER` | String | `DStreamBolt` | Filter for killing existing jobs |
| `GIT_BRANCH` | String | `main` | Git branch to deploy from |
| `SSH_KEY_PATH` | String | `/home/ubuntu/.ssh/...` | Path to SSH private key |
| `REMOTE_USER` | String | `ubuntu` | SSH user for remote servers |
| `KAFKA_BROKER` | String | `10.0.10.101:9092` | Kafka broker address |
| `PROCESSING_MODE` | Choice | `streaming` | Spark processing mode (streaming/batch) |
| `SPARK_DRIVER_MEMORY` | String | `512m` | Spark driver memory |
| `SPARK_EXECUTOR_MEMORY` | String | `512m` | Spark executor memory |
| `GRACEFUL_SHUTDOWN` | Boolean | `true` | Wait for existing jobs before killing |
| `AUTO_START` | Boolean | `true` | Auto-start the new Spark job |

---

## 📊 Job Stages Explained

### Ingestion Deployment Stages

1. **Validate Input** - Checks required parameters
2. **Checkout Code** - Clones from Git repository
3. **Validate Ingestion Code** - Python syntax check
4. **Prepare Deployment Package** - Creates tarball
5. **Deploy to Servers** - Parallel deployment to all IPs
6. **Restart Services** - Restarts the ingestion service
7. **Health Checks** - Validates deployment with HTTP checks
8. **Cleanup Old Backups** - Keeps only last 5 backups

### Spark Deployment Stages

1. **Validate Input** - Checks required parameters
2. **Checkout Code** - Clones from Git repository
3. **Validate Spark Code** - Python syntax check
4. **Prepare Deployment Package** - Creates tarball with submit script
5. **Kill Existing Jobs** - Gracefully stops running Spark jobs
6. **Deploy to Spark Masters** - Parallel deployment
7. **Start Spark Jobs** - Submits new Spark jobs
8. **Verify Deployment** - Checks files and running processes
9. **Cleanup Old Backups** - Keeps only last 5 backups

---

## 🔍 Monitoring Deployments

### View Build Console

1. Go to the job (e.g., `DStreamBolt-Deploy-Ingestion`)
2. Click on the build number (e.g., `#42`)
3. Click **Console Output**

### Check Service Status on Server

#### Ingestion Service

```bash
# SSH to ingestion server
ssh -i ~/dstreambolt-access-key.pem ubuntu@13.201.43.125

# Check service status
sudo systemctl status ingest-api

# View logs
sudo journalctl -u ingest-api -f

# Test health endpoint
curl http://localhost:5000/health
```

#### Spark Jobs

```bash
# SSH to Spark master
ssh -i ~/dstreambolt-access-key.pem ubuntu@43.205.94.74

# Check running jobs
ps aux | grep spark_processor.py

# View Spark logs
tail -f /opt/spark/logs/spark-job-*.log

# Check Spark Master UI
curl http://localhost:8080

# View PID file
cat /opt/dstreambolt/computations/spark_job.pid
```

### Access Spark UI

Via direct IP:
```
http://43.205.94.74:8080
```

Via ALB (if configured):
```
https://dstreambolt-alb-xyz.amazonaws.com/spark
```

---

## 🚨 Troubleshooting

### Deployment Failed - SSH Connection Issues

**Symptom**: `Connection timeout` or `Permission denied`

**Solution**:
```bash
# 1. Verify SSH key exists on Jenkins server
ls -la /home/ubuntu/.ssh/dstreambolt-access-key.pem

# 2. Check key permissions
chmod 600 /home/ubuntu/.ssh/dstreambolt-access-key.pem

# 3. Test SSH manually from Jenkins server
ssh -i /home/ubuntu/.ssh/dstreambolt-access-key.pem ubuntu@<target-ip>

# 4. Check security groups allow SSH (port 22) from Jenkins server
```

### Ingestion Service Not Starting

**Symptom**: Service restarts but health check fails

**Solution**:
```bash
# SSH to server
ssh -i ~/dstreambolt-access-key.pem ubuntu@<ingestion-ip>

# Check service status
sudo systemctl status ingest-api

# View detailed logs
sudo journalctl -u ingest-api -n 100 --no-pager

# Check if port 5000 is listening
sudo netstat -tlnp | grep 5000

# Manual test
cd /opt/dstreambolt/agent
source venv/bin/activate
python app.py
```

### Spark Job Not Running

**Symptom**: Deployment succeeds but job not running

**Solution**:
```bash
# SSH to Spark master
ssh -i ~/dstreambolt-access-key.pem ubuntu@<spark-ip>

# Check if job is running
ps aux | grep spark_processor.py

# View recent logs
tail -100 /opt/spark/logs/spark-job-*.log

# Check Spark master status
/opt/spark/sbin/spark-daemon.sh status org.apache.spark.deploy.master.Master

# Manual job submission
cd /opt/dstreambolt/computations
./submit_spark_job.sh spark://<private-ip>:7077 10.0.10.101:9092 streaming 512m 512m
```

### Existing Jobs Not Killed

**Symptom**: New jobs fail because old jobs still running

**Solution**:
```bash
# SSH to Spark master
ssh -i ~/dstreambolt-access-key.pem ubuntu@<spark-ip>

# Find all Spark processes
ps aux | grep spark

# Force kill all
pkill -9 -f spark_processor.py

# Or kill specific PID
kill -9 <PID>

# Verify
ps aux | grep spark_processor.py
```

### Rollback to Previous Version

#### Rollback Ingestion

```bash
# SSH to server
ssh -i ~/dstreambolt-access-key.pem ubuntu@<ingestion-ip>

# List backups
ls -lt /opt/dstreambolt/backups/

# Restore from backup
cd /opt/dstreambolt/agent
sudo tar -xzf /opt/dstreambolt/backups/ingest-backup-20251207-120000.tar.gz

# Restart service
sudo systemctl restart ingest-api
```

#### Rollback Spark

```bash
# SSH to Spark master
ssh -i ~/dstreambolt-access-key.pem ubuntu@<spark-ip>

# Stop current job
pkill -f spark_processor.py

# List backups
ls -lt /opt/dstreambolt/backups/

# Restore from backup
cd /opt/dstreambolt/computations
sudo tar -xzf /opt/dstreambolt/backups/spark-backup-20251207-120000.tar.gz

# Restart job
./submit_spark_job.sh spark://<private-ip>:7077 10.0.10.101:9092 streaming 512m 512m
```

---

## 📈 Best Practices

### 1. Test in Staging First

Always deploy to a staging environment before production:

```
# Deploy to staging
TARGET_IPS: 10.0.1.100  # Staging IP
GIT_BRANCH: develop

# After testing, deploy to production
TARGET_IPS: 13.201.43.125,52.66.123.45
GIT_BRANCH: main
```

### 2. Use Feature Branches

```
GIT_BRANCH: feature/new-kafka-handler
TARGET_IPS: 10.0.1.100  # Single test server
```

### 3. Deploy Off-Peak Hours

Schedule deployments during low traffic periods.

### 4. Monitor After Deployment

```bash
# Watch logs for 5 minutes after deployment
ssh ubuntu@<ip> "sudo journalctl -u ingest-api -f"
```

### 5. Gradual Rollout

Deploy to one server first, then gradually to others:

```
# Phase 1: Deploy to one server
TARGET_IPS: 13.201.43.125

# Phase 2: Deploy to remaining servers
TARGET_IPS: 52.66.123.45,15.206.146.37
```

### 6. Keep Documentation Updated

Update deployment notes in the build description.

---

## 🔐 Security Considerations

1. **SSH Keys**: Never commit SSH keys to Git
2. **Credentials**: Use Jenkins credentials store
3. **Backups**: Backups contain sensitive code
4. **Logs**: Logs may contain sensitive data
5. **Network**: Ensure Jenkins can reach servers via security groups

---

## 📞 Support

For issues with Jenkins jobs:

1. Check **Console Output** in Jenkins
2. SSH to target server and check logs
3. Review deployment backups
4. Check network connectivity
5. Verify service configuration

---

## 📄 Files

- `deploy-ingestion.jenkinsfile` - Ingestion service deployment pipeline
- `deploy-spark-jobs.jenkinsfile` - Spark jobs deployment pipeline
- `README.md` - This documentation

---

**Last Updated**: December 7, 2025  
**Jenkins Version**: 2.x+  
**Repository**: https://github.com/dstreambolt/dstream_cloud

