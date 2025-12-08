# Jenkins Pipeline: Build & Deploy Scala Spark Job

Automated Jenkins pipeline to build Scala Spark processor from source and deploy to Spark cluster.

## 🎯 What This Pipeline Does

1. **Checks out code** from Git repository
2. **Installs SBT** (if not already installed)
3. **Builds Scala JAR** using SBT assembly
4. **Stops existing Spark jobs** on target nodes
5. **Deploys JAR** to Spark cluster nodes
6. **Starts new Spark job** (optional)
7. **Verifies deployment** and job status

## 📁 Files

- `build-deploy-scala-spark.jenkinsfile` - Pipeline definition
- `job-scala-spark.xml` - Jenkins job configuration
- `setup_scala_spark_job.sh` - Automated job setup script

## 🚀 Quick Setup

### Prerequisites

1. **Jenkins** running with:
   - Git plugin
   - SSH credentials configured
   - Workspace with sufficient disk space (~500MB for build)

2. **SSH Access** to Spark nodes configured in Jenkins:
   - Credential ID: `dstreambolt-accesskey`
   - Private key file

3. **Git SSH** access configured:
   - Credential ID: `jenkins-github-ssh`
   - GitHub SSH key

### Installation

```bash
cd jenkins

# Set your Jenkins credentials
export JENKINS_URL="http://13.232.132.240:8081"
export JENKINS_USER="admin"
export JENKINS_TOKEN="your-jenkins-api-token"

# Run setup script
./setup_scala_spark_job.sh
```

### Manual Setup

If you prefer to create the job manually:

1. Go to Jenkins: `http://13.232.132.240:8081`
2. Click "New Item"
3. Name: `build-deploy-scala-spark`
4. Type: "Pipeline"
5. Under "Pipeline" section:
   - Definition: "Pipeline script from SCM"
   - SCM: "Git"
   - Repository URL: `git@github.com:dstreambolt/dstream_cloud.git`
   - Credentials: Select your GitHub SSH key
   - Branch: `*/main`
   - Script Path: `jenkins/build-deploy-scala-spark.jenkinsfile`
6. Save

## 📋 Pipeline Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `SPARK_MASTER_IPS` | `13.127.201.0` | Comma-separated Spark node IPs |
| `GIT_BRANCH` | `main` | Git branch to build |
| `REMOTE_USER` | `ubuntu` | SSH username for Spark nodes |
| `KAFKA_BROKER` | `10.0.10.101:9092` | Kafka broker address |
| `PROCESSING_MODE` | `batch` | Processing mode (batch/streaming) |
| `SPARK_DRIVER_MEMORY` | `512m` | Spark driver memory |
| `SPARK_EXECUTOR_MEMORY` | `512m` | Spark executor memory |
| `SPARK_DRIVER_PORT` | `39499` | Spark driver port |
| `AUTO_START` | `true` | Start job after deployment |
| `CLEAN_BUILD` | `false` | Clean build from scratch |

## 🔧 Pipeline Stages

### 1. Validate
- Validates input parameters
- Parses target IP list

### 2. Checkout
- Clones Git repository
- Checks out specified branch
- Records commit SHA

### 3. Check SBT
- Verifies SBT is installed
- Installs SBT if missing (on Jenkins node)

### 4. Build Scala JAR
- Runs `sbt assembly`
- Creates fat JAR with dependencies
- Verifies JAR was created successfully

### 5. Create Deployment Package
- Creates deployment info file
- Creates submission script
- Packages JAR, scripts, and metadata into tar.gz

### 6. Stop Existing Jobs
- SSHs to each target node
- Finds running Scala Spark processes
- Gracefully stops them (SIGTERM + SIGKILL)

### 7. Deploy to Spark Nodes
- Transfers package to each node
- Extracts files to `/opt/dstreambolt/computations`
- Runs in parallel for multiple nodes

### 8. Start Spark Jobs
- Only runs if `AUTO_START` is true
- Gets private IP of each node
- Submits Spark job with configured parameters
- Captures PID and logs

### 9. Verify Deployment
- Checks if job is running
- Shows deployment files
- Displays recent logs

## 📊 Usage Examples

### Example 1: Deploy to Single Node

```
Parameters:
  SPARK_MASTER_IPS: 13.127.201.0
  GIT_BRANCH: main
  PROCESSING_MODE: batch
  AUTO_START: true
```

### Example 2: Deploy to Multiple Nodes

```
Parameters:
  SPARK_MASTER_IPS: 13.127.201.0,10.0.1.128
  GIT_BRANCH: release/v1.0.0
  PROCESSING_MODE: streaming
  AUTO_START: true
```

### Example 3: Build Only (No Deployment)

```
Parameters:
  SPARK_MASTER_IPS: 13.127.201.0
  AUTO_START: false
```

This will build the JAR and deploy it, but won't start the job.

### Example 4: Clean Build

```
Parameters:
  CLEAN_BUILD: true
```

This will run `sbt clean` before building.

## 🔍 Monitoring

### Jenkins Console Output

The pipeline provides detailed output for each stage:
- Build progress
- Deployment status
- Job verification

### Spark UI

After deployment, access Spark UIs:
- **Spark Master UI**: `http://<spark-ip>:8080`
- **Application UI**: `http://<spark-ip>:4040`

### Logs

Job logs are saved on Spark nodes:
```bash
/opt/spark/logs/scala-spark-job.log
```

View logs:
```bash
ssh ubuntu@<spark-ip>
tail -f /opt/spark/logs/scala-spark-job.log
```

## 🐛 Troubleshooting

### Build Failures

**Problem**: SBT compilation errors

**Solution**:
```bash
# On Jenkins node
cd /var/lib/jenkins/workspace/build-deploy-scala-spark/computations
sbt clean compile
```

### Deployment Failures

**Problem**: SSH connection refused

**Solution**:
- Check SSH credentials in Jenkins
- Verify Spark node IP is correct
- Ensure node is accessible from Jenkins

**Problem**: JAR not found on Spark node

**Solution**:
```bash
ssh ubuntu@<spark-ip>
ls -la /opt/dstreambolt/computations/
```

### Job Start Failures

**Problem**: Spark job exits immediately

**Solution**:
```bash
# Check logs
ssh ubuntu@<spark-ip>
tail -100 /opt/spark/logs/scala-spark-job.log

# Check if Spark master is running
sudo systemctl status spark-master
```

**Problem**: Out of memory

**Solution**: Increase memory parameters:
```
SPARK_DRIVER_MEMORY: 1g
SPARK_EXECUTOR_MEMORY: 1g
```

## 📦 Build Artifacts

The pipeline archives:
- `scala-spark-job-<commit>.tar.gz` - Deployment package

Download from Jenkins job page after build completes.

## 🔐 Security

### Required Credentials

1. **SSH Key for Spark Nodes**
   - Jenkins credential ID: `dstreambolt-accesskey`
   - Type: SSH Username with private key
   - Private key: Content of `~/.ssh/dstreambolt-access-key.pem`

2. **GitHub SSH Key**
   - Jenkins credential ID: `jenkins-github-ssh`
   - Type: SSH Username with private key
   - Private key: Your GitHub deploy key

### Adding Credentials

1. Go to: Jenkins → Manage Jenkins → Manage Credentials
2. Click "(global)" under "Stores scoped to Jenkins"
3. Click "Add Credentials"
4. Fill in details as above

## 🔄 CI/CD Integration

### Automatic Builds

To trigger builds automatically on Git push:

1. Edit job configuration
2. Under "Build Triggers":
   - Enable "GitHub hook trigger for GITScm polling"
3. Configure GitHub webhook:
   - URL: `http://13.232.132.240:8081/github-webhook/`
   - Events: "Push" events

### Scheduled Builds

To build on a schedule:

1. Edit job configuration
2. Under "Build Triggers":
   - Enable "Build periodically"
   - Schedule: e.g., `H 2 * * *` (daily at 2 AM)

## 📝 Notes

- **Build Time**: ~2-5 minutes (depending on SBT cache)
- **Deployment Time**: ~30 seconds per node
- **Total Time**: ~3-6 minutes for full pipeline
- **Disk Space**: ~500MB required on Jenkins node
- **JAR Size**: ~50MB

## 🚀 Next Steps

1. Run the setup script to create the job
2. Configure SSH credentials
3. Test with a single node first
4. Scale to multiple nodes
5. Set up monitoring and alerts

## 🔗 Related

- Main deployment pipeline: `deploy-spark-jobs.jenkinsfile`
- Scala source: `computations/src/main/scala/`
- Build config: `computations/build.sbt`

