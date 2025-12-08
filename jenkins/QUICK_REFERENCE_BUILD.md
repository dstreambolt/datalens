# Quick Reference: Building Scala Spark on t3.small

## 🚀 RECOMMENDED: Local Build + Jenkins Deploy

```bash
# 1. Build locally (on your Mac)
cd computations
./build_and_commit.sh

# 2. Push to Git
git push

# 3. Deploy via Jenkins
# http://13.232.132.240:8081/job/deploy-prebuilt-scala-spark/
```

**Time:** 30 seconds (deploy only)  
**Memory:** No issues  
**Cost:** $0

---

## 🔧 ALTERNATIVE: Jenkins Build (with GC warnings)

```bash
# Use existing optimized pipeline
# http://13.232.132.240:8081/job/build-deploy-scala-spark/
```

**Time:** 5-10 minutes  
**Memory:** GC warnings are normal  
**Cost:** $0

---

## 💰 LONG-TERM: Upgrade to t3.medium

```bash
# AWS Console:
# EC2 → Instances → Select DevOps → Actions → Change Instance Type → t3.medium
```

**Time:** 3-5 minutes  
**Memory:** No issues  
**Cost:** +$15/month

---

## 📝 Manual Build on Jenkins (Troubleshooting)

```bash
ssh -i ~/dstreambolt-access-key.pem ubuntu@13.232.132.240
cd /var/lib/jenkins/workspace/DStreamBolt-Deploy-Spark-Scala/computations
export SBT_OPTS="-Xmx768m -Xss2m -XX:+UseG1GC"
sbt clean assembly
```

---

## 🆘 If Build Fails

1. **Check memory:**
   ```bash
   ssh -i ~/dstreambolt-access-key.pem ubuntu@13.232.132.240
   free -h
   ```

2. **Add swap (if needed):**
   ```bash
   sudo dd if=/dev/zero of=/swapfile bs=1M count=2048
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   ```

3. **Use local build (easiest):**
   ```bash
   cd computations && ./build_and_commit.sh
   ```

---

## 📚 Full Documentation

See: `jenkins/BUILD_SOLUTIONS.md`

