# Building Scala Spark Jobs - Solutions for t3.small

The Jenkins DevOps node (t3.small with 2GB RAM) has limited memory for building Scala projects. Here are your options:

## 🎯 Solution 1: Build Locally, Deploy via Jenkins (RECOMMENDED)

**Best for:** t3.small instances, faster builds, better developer experience

### Steps:

1. **Build JAR on your Mac:**
   ```bash
   cd computations
   ./build_and_commit.sh
   ```
   
   This will:
   - Build the Scala JAR using SBT
   - Commit it to Git
   - Prompt you to push

2. **Push to Git:**
   ```bash
   git push
   ```

3. **Deploy via Jenkins:**
   - Use the new pipeline: `deploy-prebuilt-scala-spark`
   - URL: http://13.232.132.240:8081/job/deploy-prebuilt-scala-spark/
   - This pipeline just deploys the pre-built JAR

### Advantages:
- ✅ Fast deployment (no build time)
- ✅ No memory issues
- ✅ Works on t3.small
- ✅ JAR is versioned in Git

### Disadvantages:
- ❌ Requires local SBT installation
- ❌ JAR file in Git (larger repo size)

---

## 🎯 Solution 2: Optimize Jenkins Build

**Best for:** If you want to build on Jenkins

### Memory Optimization Applied:

The `build-deploy-scala-spark.jenkinsfile` has been optimized:

```groovy
SBT_OPTS = '-Xmx768m -Xss2m -XX:+UseG1GC -XX:MaxGCPauseMillis=200'
```

### Additional Steps:

1. **Increase Jenkins heap:**
   ```bash
   ssh -i ~/dstreambolt-access-key.pem ubuntu@13.232.132.240
   sudo nano /etc/default/jenkins
   ```
   
   Add:
   ```
   JAVA_ARGS="-Djava.awt.headless=true -Xmx512m"
   ```
   
   Restart:
   ```bash
   sudo systemctl restart jenkins
   ```

2. **Enable swap on DevOps node:**
   ```bash
   ssh -i ~/dstreambolt-access-key.pem ubuntu@13.232.132.240
   sudo dd if=/dev/zero of=/swapfile bs=1M count=2048
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
   ```

3. **Run the optimized build:**
   - URL: http://13.232.132.240:8081/job/build-deploy-scala-spark/

### Advantages:
- ✅ Builds on Jenkins (true CI/CD)
- ✅ No JAR in Git
- ✅ Automated

### Disadvantages:
- ❌ Slower (5-10 minutes to build)
- ❌ May still have GC warnings
- ❌ Requires swap memory

---

## 🎯 Solution 3: Upgrade Jenkins Node

**Best for:** Long-term solution

### Upgrade to t3.medium:

- Current: t3.small (2GB RAM, 2 vCPU) - $0.0208/hour
- Upgrade: t3.medium (4GB RAM, 2 vCPU) - $0.0416/hour
- Cost: +$15/month

### Steps:

1. **Stop Jenkins:**
   ```bash
   ssh -i ~/dstreambolt-access-key.pem ubuntu@13.232.132.240
   sudo systemctl stop jenkins
   ```

2. **Change instance type in AWS Console:**
   - EC2 → Instances → Select DevOps instance
   - Actions → Instance Settings → Change Instance Type
   - Select: t3.medium
   - Start instance

3. **Verify:**
   ```bash
   ssh -i ~/dstreambolt-access-key.pem ubuntu@13.232.132.240
   free -h
   ```

### Advantages:
- ✅ No memory issues
- ✅ Faster builds
- ✅ Room for other workloads

### Disadvantages:
- ❌ Costs $15/month more

---

## 📋 Quick Comparison

| Solution | Build Time | Cost | Memory Issues | Complexity |
|----------|-----------|------|---------------|------------|
| **Local Build** | 2-3 min | $0 | ❌ None | ⭐⭐ Easy |
| **Optimized Jenkins** | 5-10 min | $0 | ⚠️ Some GC | ⭐⭐⭐ Medium |
| **Upgrade Node** | 3-5 min | +$15/mo | ❌ None | ⭐ Very Easy |

---

## 🚀 Recommended Workflow

**For Development (Recommended):**
```bash
# Build locally
cd computations
./build_and_commit.sh

# Deploy via Jenkins
# Use: deploy-prebuilt-scala-spark pipeline
```

**For Production:**
- Consider upgrading to t3.medium
- Use full CI/CD with `build-deploy-scala-spark` pipeline

---

## 📦 Pipeline Files

1. **deploy-prebuilt-scala-spark.jenkinsfile**
   - Deploys pre-built JAR from Git
   - No build step
   - Fast and reliable

2. **build-deploy-scala-spark.jenkinsfile**
   - Builds from source on Jenkins
   - Optimized for low memory
   - Full CI/CD

---

## 🛠️ Manual Build on Jenkins (Troubleshooting)

If pipelines fail, build manually:

```bash
# SSH to Jenkins node
ssh -i ~/dstreambolt-access-key.pem ubuntu@13.232.132.240

# Navigate to workspace
cd /var/lib/jenkins/workspace/DStreamBolt-Deploy-Spark-Scala/computations

# Build with limited memory
export SBT_OPTS="-Xmx768m -Xss2m -XX:+UseG1GC"
sbt clean assembly

# Check result
ls -lh target/scala-2.12/dstreambolt-processor-*.jar
```

---

## 📝 Notes

- **GC warnings are normal** on t3.small with SBT
- **Swap helps** but makes builds slower
- **Local builds** are fastest and most reliable for small teams
- **CI/CD builds** are better for larger teams with dedicated infra

---

## 🔗 Jenkins Jobs

- **Pre-built Deploy:** http://13.232.132.240:8081/job/deploy-prebuilt-scala-spark/
- **Full Build+Deploy:** http://13.232.132.240:8081/job/build-deploy-scala-spark/

