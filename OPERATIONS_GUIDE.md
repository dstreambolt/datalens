# DStreamBolt Operations Guide

## 🎯 Quick Start

### Access URLs

| Service | URL | Credentials |
|---------|-----|-------------|
| **Load Balancer** | https://dstreambolt.click | - |
| **Jenkins** | http://13.235.238.208:8081 | admin / (check `/var/lib/jenkins/secrets/initialAdminPassword`) |
| **Grafana** | http://13.235.238.208:3000 | admin / DStreamBolt2025! |
| **AKHQ (Kafka UI)** | http://13.235.238.208:8080 | admin / DStreamBolt2025! |
| **Spark Master UI** | http://52.66.171.95:8080 | No auth |
| **Spark Executor UI** | http://65.0.74.255:8081 | No auth |

### Instance Access (SSH)

```bash
# DevOps Node (Jenkins, Grafana, MySQL, AKHQ)
ssh -i ~/dstreambolt-access-key.pem ubuntu@13.235.238.208

# Ingestion Node
ssh -i ~/dstreambolt-access-key.pem ubuntu@13.232.206.53

# Kafka Broker (Private - via DevOps bastion)
ssh -i ~/dstreambolt-access-key.pem -J ubuntu@13.235.238.208 ubuntu@10.0.10.248

# Spark Master
ssh -i ~/dstreambolt-access-key.pem ubuntu@52.66.171.95

# Spark Executor
ssh -i ~/dstreambolt-access-key.pem ubuntu@65.0.74.255
```

---

## 🔧 Service Management

### Check All Services Status

```bash
# Login to each node and run:

# DevOps Node
sudo systemctl status jenkins grafana-server mysql akhq

# Ingestion Node
sudo systemctl status dstreambolt-ingest

# Kafka Node
sudo systemctl status zookeeper kafka

# Spark Nodes
sudo systemctl status spark-master spark-worker
```

### Restart Services

```bash
# Ingestion Service
ssh ubuntu@13.232.206.53 'sudo systemctl restart dstreambolt-ingest'

# Kafka
ssh -J ubuntu@13.235.238.208 ubuntu@10.0.10.248 'sudo systemctl restart kafka'

# Spark Job (graceful restart)
ssh ubuntu@52.66.171.95 '
  PID=$(cat /opt/dstreambolt/computations/spark_job.pid 2>/dev/null)
  if [ ! -z "$PID" ]; then
    kill -TERM $PID
    sleep 5
    kill -9 $PID 2>/dev/null || true
  fi
  cd /opt/dstreambolt/computations
  nohup ./submit_job.sh > /opt/spark/logs/spark-job.log 2>&1 &
  echo $! > spark_job.pid
'
```

---

## 📊 Monitoring Commands

### Ingestion Metrics

```bash
# Check ingestion queue
ssh ubuntu@13.232.206.53 '
  echo "Queue depth: $(ls /opt/dstreambolt/queue/*.gz 2>/dev/null | wc -l)"
  echo "Corrupted bundles: $(ls /opt/dstreambolt/corrupted/*.gz 2>/dev/null | wc -l)"
'

# View ingestion logs (last 100 lines)
ssh ubuntu@13.232.206.53 'sudo journalctl -u dstreambolt-ingest -n 100 --no-pager'

# Test health endpoint
curl https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/health
```

### Kafka Metrics

```bash
# List topics
ssh -J ubuntu@13.235.238.208 ubuntu@10.0.10.248 \
  '/opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092'

# Check topic details
ssh -J ubuntu@13.235.238.208 ubuntu@10.0.10.248 \
  '/opt/kafka/bin/kafka-topics.sh --describe --topic dstreambolt-logs --bootstrap-server localhost:9092'

# Consumer group lag
ssh -J ubuntu@13.235.238.208 ubuntu@10.0.10.248 \
  '/opt/kafka/bin/kafka-consumer-groups.sh --describe --group spark-consumer --bootstrap-server localhost:9092'

# Kafka log size
ssh -J ubuntu@13.235.238.208 ubuntu@10.0.10.248 \
  'du -sh /var/lib/kafka-logs/'
```

### Spark Metrics

```bash
# Check running jobs
curl -s http://52.66.171.95:8080/json/ | jq '.activeapps'

# View Spark logs
ssh ubuntu@52.66.171.95 'tail -f /opt/spark/logs/spark-job.log'

# Check executor status
ssh ubuntu@65.0.74.255 'ps aux | grep spark'
```

### MySQL Metrics

```bash
# Connect to MySQL
ssh ubuntu@13.235.238.208
sudo mysql -u root -p

# Check database size
SELECT 
  table_schema AS 'Database',
  ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)'
FROM information_schema.tables
WHERE table_schema = 'dstreambolt_metrics'
GROUP BY table_schema;

# Recent records count
SELECT 
  'endpoint_summary' AS table_name, COUNT(*) AS count 
FROM endpoint_summary 
WHERE window_start >= NOW() - INTERVAL 1 HOUR
UNION ALL
SELECT 
  'status_summary', COUNT(*) 
FROM status_summary 
WHERE window_start >= NOW() - INTERVAL 1 HOUR;
```

---

## 🚀 Deployment Procedures

### Deploy Ingestion Code Changes

```bash
# Option 1: Via Jenkins (Recommended)
# Go to: http://13.235.238.208:8081/job/DStreamBolt-Deploy-Ingestion/
# Build with Parameters:
#   - TARGET_IPS: 13.232.206.53
#   - GIT_BRANCH: main

# Option 2: Manual Deployment
cd /Users/skalaise/apps/cloud/terraform/dstream_bolt
git pull origin main

scp -i ~/dstreambolt-access-key.pem ingestion/app.py \
  ubuntu@13.232.206.53:/opt/dstreambolt/ingestion/

ssh -i ~/dstreambolt-access-key.pem ubuntu@13.232.206.53 \
  'sudo systemctl restart dstreambolt-ingest && sudo systemctl status dstreambolt-ingest'
```

### Deploy Spark Job Changes

```bash
# Via Jenkins: http://13.235.238.208:8081/job/DStreamBolt-Deploy-Spark-Scala/
# Build with Parameters:
#   - SPARK_MASTER_IPS: 52.66.171.95
#   - GIT_BRANCH: main
#   - AUTO_START: true

# Manual steps:
cd computations
sbt clean package

scp -i ~/dstreambolt-access-key.pem \
  target/scala-2.12/dstreambolt-processor_2.12-1.0.jar \
  ubuntu@52.66.171.95:/opt/dstreambolt/computations/

ssh -i ~/dstreambolt-access-key.pem ubuntu@52.66.171.95 '
  # Kill old job
  PID=$(cat /opt/dstreambolt/computations/spark_job.pid 2>/dev/null)
  [ ! -z "$PID" ] && kill -TERM $PID && sleep 3

  # Start new job
  cd /opt/dstreambolt/computations
  ./submit_job.sh
'
```

---

## 🔐 Security Operations

### Certificate Rotation (mTLS)

```bash
# Generate new certificates (every 90 days)
cd utils
./generate_certificates.sh

# Upload to Secrets Manager
aws secretsmanager update-secret \
  --secret-id dstreambolt/ca-cert \
  --secret-string file://certs/ca/ca-cert.pem

aws secretsmanager update-secret \
  --secret-id dstreambolt/server-key \
  --secret-string file://certs/server/server-key.pem

# Restart ingestion service to pick up new certs
ssh ubuntu@13.232.206.53 'sudo systemctl restart dstreambolt-ingest'

# Test with new client certificate
python3 examples/02-send-to-ingest.py \
  --client-cert certs/client/client-cert.pem \
  --client-key certs/client/client-key.pem \
  --ca-cert certs/ca/ca-cert.pem
```

### Update MySQL Passwords

```bash
# Update in Secrets Manager
aws secretsmanager update-secret \
  --secret-id dstreambolt/mysql \
  --secret-string '{"username":"root","password":"NewPassword123!"}'

# Update services that use MySQL
ssh ubuntu@13.232.206.53 'sudo systemctl restart dstreambolt-ingest'
ssh ubuntu@52.66.171.95 'sudo systemctl restart spark-job'

# Test connection
ssh ubuntu@13.235.238.208 'mysql -u root -pNewPassword123! -e "SHOW DATABASES;"'
```

### Rotate Kafka Credentials (if using SASL)

```bash
# Update in Secrets Manager
aws secretsmanager update-secret \
  --secret-id dstreambolt/kafka \
  --secret-string '{"bootstrap_servers":"10.0.10.248:9092","topic":"dstreambolt-logs"}'

# Restart dependent services
ssh ubuntu@13.232.206.53 'sudo systemctl restart dstreambolt-ingest'
ssh ubuntu@52.66.171.95 'sudo systemctl restart spark-job'
```

---

## 📈 Scaling Procedures

### Scale Up Ingestion (Add Instance)

```bash
# 1. Launch new EC2 instance via Terraform
cd terraform
terraform apply -target=module.ingest.aws_instance.ingest[1]

# 2. Get new instance IP
NEW_IP=$(terraform output -json | jq -r '.ingest_ips.value[1]')

# 3. Run setup script on new instance
scp -i ~/dstreambolt-access-key.pem setup_scripts/setup_ingestion.sh ubuntu@$NEW_IP:/tmp/
ssh -i ~/dstreambolt-access-key.pem ubuntu@$NEW_IP 'bash /tmp/setup_ingestion.sh'

# 4. Add to ALB target group
aws elbv2 register-targets \
  --target-group-arn $(aws elbv2 describe-target-groups --names dstreambolt-ingest-tg --query 'TargetGroups[0].TargetGroupArn' --output text) \
  --targets Id=$NEW_IP

# 5. Verify health
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups --names dstreambolt-ingest-tg --query 'TargetGroups[0].TargetGroupArn' --output text)
```

### Scale Up Spark (Add Executor)

```bash
# 1. Launch new executor instance
cd terraform
terraform apply -target=module.compute.aws_instance.spark_executor[1]

# 2. Get new instance IP
NEW_EXECUTOR_IP=$(terraform output -json | jq -r '.spark_executor_ips.value[1]')

# 3. Setup Spark worker
scp -i ~/dstreambolt-access-key.pem setup_scripts/setup_spark_worker.sh ubuntu@$NEW_EXECUTOR_IP:/tmp/
ssh -i ~/dstreambolt-access-key.pem ubuntu@$NEW_EXECUTOR_IP \
  "SPARK_MASTER_IP=52.66.171.95 bash /tmp/setup_spark_worker.sh"

# 4. Verify executor registered
curl -s http://52.66.171.95:8080/json/ | jq '.aliveworkers'
```

### Scale Up Kafka (Add Broker)

```bash
# 1. Launch new Kafka instance
cd terraform
terraform apply -target=module.kafka.aws_instance.kafka[1]

# 2. Get new broker IP
NEW_BROKER_IP=$(terraform output -json | jq -r '.kafka_ips.value[1]')

# 3. Setup Kafka broker
scp -i ~/dstreambolt-access-key.pem setup_scripts/setup_kafka.sh ubuntu@$NEW_BROKER_IP:/tmp/
ssh -i ~/dstreambolt-access-key.pem ubuntu@$NEW_BROKER_IP \
  "BROKER_ID=2 bash /tmp/setup_kafka.sh"

# 4. Update topic replication
ssh -J ubuntu@13.235.238.208 ubuntu@10.0.10.248 \
  '/opt/kafka/bin/kafka-topics.sh --alter --topic dstreambolt-logs \
   --partitions 6 --bootstrap-server localhost:9092'
```

---

## 🐛 Troubleshooting Playbook

### Issue: Ingestion Service Returns 503

**Symptoms:**
```bash
$ curl https://dstreambolt.click/ingest
{"error": "Service Unavailable", "queue_full": true}
```

**Investigation Steps:**

1. Check queue depth:
```bash
ssh ubuntu@13.232.206.53 'ls /opt/dstreambolt/queue/*.gz 2>/dev/null | wc -l'
```

2. Check Kafka connectivity:
```bash
ssh ubuntu@13.232.206.53 'nc -zv 10.0.10.248 9092'
```

3. View ingestion logs:
```bash
ssh ubuntu@13.232.206.53 'sudo journalctl -u dstreambolt-ingest -n 200 --no-pager | grep -i error'
```

**Solutions:**

- **Queue full**: Increase worker threads or scale Spark processing
- **Kafka unreachable**: Check security groups, restart Kafka
- **Worker crashed**: `sudo systemctl restart dstreambolt-ingest`

---

### Issue: High Kafka Consumer Lag

**Symptoms:**
- Grafana shows increasing lag
- Spark processing falling behind

**Investigation:**

```bash
# Check consumer group lag
ssh -J ubuntu@13.235.238.208 ubuntu@10.0.10.248 \
  '/opt/kafka/bin/kafka-consumer-groups.sh --describe --group spark-consumer --bootstrap-server localhost:9092'

# Expected output:
# TOPIC           PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG
# dstreambolt-logs    0      1000000         1000500         500   ← Low lag (good)
# dstreambolt-logs    1      1000000         1050000         50000 ← High lag (bad)
```

**Solutions:**

1. **Add more Spark executors** (see scaling guide above)

2. **Increase executor resources**:
```bash
ssh ubuntu@52.66.171.95
nano /opt/dstreambolt/computations/submit_job.sh
# Change: --executor-memory 1g → --executor-memory 2g
# Restart job
```

3. **Optimize Spark job** (reduce shuffles, increase batch size)

---

### Issue: MySQL Connection Pool Exhausted

**Symptoms:**
```
pymysql.err.OperationalError: (1040, 'Too many connections')
```

**Investigation:**

```bash
ssh ubuntu@13.235.238.208
sudo mysql -u root -p

# Check current connections
SHOW PROCESSLIST;

# Check max connections
SHOW VARIABLES LIKE 'max_connections';
```

**Solution:**

```sql
-- Increase max connections
SET GLOBAL max_connections = 200;

-- Make permanent
sudo nano /etc/mysql/mysql.conf.d/mysqld.cnf
# Add: max_connections = 200

sudo systemctl restart mysql
```

---

### Issue: Spark Job Fails with OOM

**Symptoms:**
```
ERROR Executor: Exception in task 0.0 in stage 0.0 (TID 0)
java.lang.OutOfMemoryError: Java heap space
```

**Investigation:**

```bash
# Check executor memory usage
ssh ubuntu@65.0.74.255 'free -h'

# View Spark UI for memory metrics
open http://52.66.171.95:8080
```

**Solutions:**

1. **Increase executor memory**:
```bash
ssh ubuntu@52.66.171.95
nano /opt/dstreambolt/computations/submit_job.sh
# Change: --executor-memory 1g → --executor-memory 2g
# Change: --driver-memory 512m → --driver-memory 1g
```

2. **Reduce batch size**:
```python
# In spark_processor.py
.option("maxOffsetsPerTrigger", "500")  # Reduce from 1000
```

3. **Enable dynamic allocation**:
```bash
--conf spark.dynamicAllocation.enabled=true \
--conf spark.dynamicAllocation.minExecutors=1 \
--conf spark.dynamicAllocation.maxExecutors=5
```

---

## 🔄 Backup & Recovery

### Backup MySQL Database

```bash
# Automated daily backup (via cron)
ssh ubuntu@13.235.238.208

# Add to crontab
crontab -e
# Add line:
0 2 * * * /usr/bin/mysqldump -u root -pDStreamBolt2025! dstreambolt_metrics | gzip > /backups/mysql_$(date +\%Y\%m\%d).sql.gz

# Manual backup
mysqldump -u root -pDStreamBolt2025! dstreambolt_metrics | gzip > mysql_backup_$(date +%Y%m%d).sql.gz

# Upload to S3
aws s3 cp mysql_backup_*.sql.gz s3://dstreambolt-backups/mysql/
```

### Restore MySQL Database

```bash
# Download from S3
aws s3 cp s3://dstreambolt-backups/mysql/mysql_backup_20251210.sql.gz .

# Restore
gunzip < mysql_backup_20251210.sql.gz | mysql -u root -pDStreamBolt2025! dstreambolt_metrics

# Verify
mysql -u root -pDStreamBolt2025! -e "SELECT COUNT(*) FROM dstreambolt_metrics.endpoint_summary;"
```

### Backup Kafka Topics

```bash
# Mirror topic to S3 (using Kafka Connect or custom script)
ssh -J ubuntu@13.235.238.208 ubuntu@10.0.10.248

# Consume and save to file
/opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic dstreambolt-logs \
  --from-beginning \
  --max-messages 1000000 > kafka_backup.json

# Upload to S3
aws s3 cp kafka_backup.json s3://dstreambolt-backups/kafka/backup_$(date +%Y%m%d).json
```

### Disaster Recovery Plan

**Scenario: Complete Infrastructure Loss**

1. **Redeploy Infrastructure** (15 minutes):
```bash
cd terraform
terraform destroy -auto-approve
terraform apply -auto-approve
```

2. **Run Setup Scripts** (30 minutes):
```bash
cd setup_scripts
./setup_all.sh
```

3. **Restore MySQL Data** (10 minutes):
```bash
aws s3 cp s3://dstreambolt-backups/mysql/latest.sql.gz .
gunzip < latest.sql.gz | mysql -u root -p dstreambolt_metrics
```

4. **Restore Kafka Data** (optional, 20 minutes):
```bash
# If historical replay needed
aws s3 cp s3://dstreambolt-backups/kafka/latest.json .
# Use kafka-console-producer to replay
```

5. **Import Grafana Dashboards** (5 minutes):
```bash
cd grafana
./import_dashboard.sh customer-analytics-dashboard.json
./import_dashboard.sh devops-dashboard.json
```

**Total Recovery Time Objective (RTO): ~90 minutes**

---

## 📋 Maintenance Schedule

### Daily Tasks

- [ ] Check service health status
- [ ] Review Grafana dashboards for anomalies
- [ ] Check ingestion queue depth
- [ ] Monitor Kafka consumer lag
- [ ] Review error logs

### Weekly Tasks

- [ ] Review resource utilization (CPU/Memory/Disk)
- [ ] Check MySQL database size
- [ ] Clean up old logs (>7 days)
- [ ] Review security group rules
- [ ] Update documentation

### Monthly Tasks

- [ ] Update OS packages (`apt update && apt upgrade`)
- [ ] Review and optimize Spark jobs
- [ ] Capacity planning review
- [ ] Security audit (check for CVEs)
- [ ] Cost optimization review

### Quarterly Tasks

- [ ] Certificate rotation (if not automated)
- [ ] Disaster recovery drill
- [ ] Load testing
- [ ] Performance tuning
- [ ] Architecture review

---

## 🎓 Training Resources

### For New Operators

1. **Week 1: Understanding the Architecture**
   - Read ARCHITECTURE.md
   - Login to all services
   - Run health checks
   - View Grafana dashboards

2. **Week 2: Basic Operations**
   - Restart services
   - Check logs
   - Deploy code changes
   - Run backups

3. **Week 3: Troubleshooting**
   - Simulate common failures
   - Practice recovery procedures
   - Use monitoring tools

4. **Week 4: Advanced Topics**
   - Scaling procedures
   - Performance tuning
   - Security best practices

### Useful Commands Cheat Sheet

```bash
# Quick service status
alias dsb-status='
  echo "=== Ingestion ===" && ssh ubuntu@13.232.206.53 "systemctl status dstreambolt-ingest --no-pager | head -5"
  echo "=== Kafka ===" && ssh -J ubuntu@13.235.238.208 ubuntu@10.0.10.248 "systemctl status kafka --no-pager | head -5"
  echo "=== Spark ===" && ssh ubuntu@52.66.171.95 "ps aux | grep spark_processor | grep -v grep"
'

# Quick log tail
alias dsb-logs='
  echo "=== Ingestion Logs ===" && ssh ubuntu@13.232.206.53 "journalctl -u dstreambolt-ingest -n 20 --no-pager"
  echo "=== Spark Logs ===" && ssh ubuntu@52.66.171.95 "tail -20 /opt/spark/logs/spark-job.log"
'

# Quick metrics
alias dsb-metrics='
  echo "=== Queue Depth ===" && ssh ubuntu@13.232.206.53 "ls /opt/dstreambolt/queue/*.gz 2>/dev/null | wc -l"
  echo "=== Kafka Lag ===" && ssh -J ubuntu@13.235.238.208 ubuntu@10.0.10.248 "/opt/kafka/bin/kafka-consumer-groups.sh --describe --group spark-consumer --bootstrap-server localhost:9092 | tail -3"
'
```

---

## 📞 Escalation Contacts

| Issue Type | Contact | Response Time |
|------------|---------|---------------|
| **Critical Outage** | on-call-engineer@dstreambolt.click | 15 minutes |
| **Performance Degradation** | devops-team@dstreambolt.click | 1 hour |
| **Security Incident** | security@dstreambolt.click | Immediate |
| **Data Loss** | data-team@dstreambolt.click | 30 minutes |

### Incident Response Process

1. **Detect**: Monitoring alerts or user reports
2. **Assess**: Determine severity (P1/P2/P3)
3. **Communicate**: Notify stakeholders
4. **Mitigate**: Apply quick fixes
5. **Resolve**: Permanent solution
6. **Post-Mortem**: Document and prevent recurrence

---

**Last Updated:** December 13, 2025  
**Maintained By:** DStreamBolt DevOps Team

