# DStreamBolt Infrastructure - Complete Service Checklist

## ✅ Service Status and Setup Guide

This document tracks all 15 requirements for the DStreamBolt infrastructure.

---

## 📋 Requirement Checklist

### #1 - Jenkins Job Setup ✅
**Status:** READY  
**Location:** DevOps Node (13.235.238.208)  
**Setup Script:** `setup_scripts/setup_jenkins.sh`

**Jobs to Configure:**
- Ingestion Deployment: `jenkins/deploy-ingestion.jenkinsfile`
- Spark Scala Deployment: `jenkins/deploy-spark-jobs.jenkinsfile`
- Log Generator: `jenkins/continuous-log-sender.jenkinsfile`

**Access:**
```bash
# SSH to DevOps node
./utils/login.sh devops

# Check Jenkins status
sudo systemctl status jenkins

# View Jenkins password
sudo cat /var/lib/jenkins/secrets/initialAdminPassword

# Access URL
http://13.235.238.208:8080
```

**GitHub SSH Key:**
```bash
sudo cat /var/lib/jenkins/.ssh/id_rsa.pub
# Add to: https://github.com/settings/keys
```

---

### #2 - MySQL Setup ✅
**Status:** READY  
**Location:** DevOps Node (13.235.238.208)  
**Setup Script:** `setup_scripts/setup_mysql.sh`

**Details:**
- Host: 13.235.238.208:3306
- Database: dstreambolt_metrics
- Root User: root / DStreamBolt2025!
- App User: dstreambolt / DStreamBolt2025!

**Access:**
```bash
# From DevOps node
mysql -u root -p'DStreamBolt2025!' dstreambolt_metrics

# Remote access
mysql -h 13.235.238.208 -u dstreambolt -p'DStreamBolt2025!' dstreambolt_metrics

# View tables
USE dstreambolt_metrics;
SHOW TABLES;
```

**Tables:**
- `ingestion_metrics` - Ingestion service metrics
- `bundle_processing` - Bundle processing tracking
- `endpoint_summary` - Spark endpoint aggregations
- `status_summary` - Spark status aggregations
- `kafka_metrics` - Kafka broker metrics
- `kafka_consumer_lag` - Consumer lag tracking
- `spark_job_metrics` - Spark job performance

---

### #3 - Spark Master & Executor ✅
**Status:** READY  
**Spark Master:** 52.66.171.95  
**Spark Executor:** 65.0.74.255  
**Setup Scripts:** `setup_scripts/setup_spark_master.sh`, `setup_scripts/setup_spark_worker.sh`

**Master Access:**
```bash
# SSH
./utils/login.sh master

# Status
sudo systemctl status spark-master

# Web UI
http://52.66.171.95:8080

# Master URL
spark://52.66.171.95:7077
```

**Executor Access:**
```bash
# SSH
./utils/login.sh executor

# Status
sudo systemctl status spark-worker

# Web UI
http://65.0.74.255:8081
```

---

### #4 - Kafka Connectivity ✅
**Status:** READY  
**Location:** Kafka Node (10.0.10.248) - Private  
**Setup Script:** `setup_scripts/setup_kafka.sh`

**Details:**
- Broker: 10.0.10.248:9092
- Zookeeper: localhost:2181
- Access: Via DevOps node (jump host)

**Access:**
```bash
# SSH via DevOps
./utils/login.sh kafka

# Check Kafka status
sudo systemctl status kafka

# List topics
/opt/kafka/bin/kafka-topics.sh --list --bootstrap-server 10.0.10.248:9092

# Test connectivity from other nodes
telnet 10.0.10.248 9092
```

**Topics:**
- `dstreambolt-logs` - Log ingestion (3 partitions)
- `dstreambolt-metrics` - Metrics data (1 partition)

---

### #5 - MySQL External Connectivity ✅
**Status:** CONFIGURED  
**Ports:** 3306  
**Security Groups:** Configured for 10.0.0.0/16

**Test Connectivity:**
```bash
# From Ingestion node
mysql -h 10.0.1.61 -u dstreambolt -p'DStreamBolt2025!' dstreambolt_metrics

# From Spark nodes
mysql -h 10.0.1.61 -u dstreambolt -p'DStreamBolt2025!' dstreambolt_metrics

# Python test (from any node)
python3 << EOF
import pymysql
conn = pymysql.connect(
    host='10.0.1.61',
    user='dstreambolt',
    password='DStreamBolt2025!',
    database='dstreambolt_metrics'
)
print("✅ Connected to MySQL")
conn.close()
EOF
```

---

### #6 - Jenkins GitHub Integration ✅
**Status:** READY  
**SSH Key:** Generated at `/var/lib/jenkins/.ssh/id_rsa.pub`

**Setup:**
```bash
# Get public key
./utils/login.sh devops
sudo cat /var/lib/jenkins/.ssh/id_rsa.pub

# Add to GitHub
# Go to: https://github.com/settings/keys
# Add the public key as "Deploy Key" or "SSH Key"
```

**Test Connection:**
```bash
sudo -u jenkins ssh -T git@github.com
# Should see: "Hi username! You've successfully authenticated..."
```

**Jenkins Credentials:**
1. Go to Jenkins → Manage Jenkins → Credentials
2. Add SSH private key credential
3. ID: `jenkins-github-ssh`
4. Private Key: Paste from `/var/lib/jenkins/.ssh/id_rsa`

---

### #7 - Kafka UI (AKHQ) Setup ✅
**Status:** READY  
**Location:** DevOps Node  
**Setup Script:** `setup_scripts/setup_akhq.sh`

**Access:**
```bash
# URL
http://13.235.238.208:8081/kafkamgr

# Credentials
Admin: admin / DStreamBolt2025!
Reader: user / user123

# Check status
./utils/login.sh devops
sudo systemctl status akhq

# View logs
sudo journalctl -u akhq -f
```

**Features:**
- View topics and messages
- Monitor consumer groups
- View broker metrics
- Manage topic configuration

---

### #8 - Traffic Generation Script ✅
**Status:** READY  
**Location:** `examples/continuous-log-sender.py`

**Manual Run:**
```bash
cd examples

# Generate and send logs
python3 continuous-log-sender.py \
  --endpoint https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/ingest \
  --interval 30 \
  --batch-size 1000 \
  --no-verify
```

**Jenkins Job:**
- Job Name: `DStreamBolt-Continuous-Log-Generator`
- Jenkinsfile: `jenkins/continuous-log-sender.jenkinsfile`

**Parameters:**
- `ENDPOINT_URL`: Ingestion endpoint
- `INTERVAL_SECONDS`: Time between batches (default: 30)
- `BATCH_SIZE`: Logs per batch (default: 1000)
- `MAX_BATCHES`: Total batches (0 = unlimited)

---

### #9 - MySQL Observability Tables ✅
**Status:** CREATED  
**Database:** dstreambolt_metrics

**Tables:**
```sql
-- Ingestion metrics
SELECT * FROM ingestion_metrics ORDER BY timestamp DESC LIMIT 10;

-- Bundle processing
SELECT * FROM bundle_processing ORDER BY timestamp DESC LIMIT 10;

-- Kafka metrics
SELECT * FROM kafka_metrics ORDER BY timestamp DESC LIMIT 10;

-- Kafka consumer lag
SELECT * FROM kafka_consumer_lag ORDER BY timestamp DESC LIMIT 10;

-- Spark job metrics
SELECT * FROM spark_job_metrics ORDER BY timestamp DESC LIMIT 10;

-- Endpoint performance (from Spark)
SELECT * FROM endpoint_summary ORDER BY window_start DESC LIMIT 10;

-- Status code distribution (from Spark)
SELECT * FROM status_summary ORDER BY window_start DESC LIMIT 10;
```

---

### #10 - Grafana Dashboards ✅
**Status:** READY  
**Location:** http://13.235.238.208:3000/grafana

**Credentials:** admin / DStreamBolt2025!

**Dashboards:**
1. **Customer Analytics Dashboard**
   - Request volume by endpoint
   - Response time percentiles
   - Status code distribution
   - Error rates

2. **System Metrics Dashboard**
   - Ingestion throughput
   - Kafka lag monitoring
   - Spark job performance
   - Service health

**Dashboard Files:**
- `grafana/customer-analytics-dashboard.json`
- `grafana/devops-dashboard.json`
- `grafana/dstreambolt-dashboard.json`

**Import Dashboards:**
```bash
./utils/login.sh devops

# Import via UI
# Grafana → Dashboards → Import → Upload JSON

# Or via API
curl -X POST http://admin:DStreamBolt2025!@localhost:3000/api/dashboards/db \
  -H "Content-Type: application/json" \
  -d @grafana/customer-analytics-dashboard.json
```

---

### #11 - Kafka Metrics Collection ✅
**Status:** CONFIGURED  
**Script:** `observability/deploy_kafka_collector.sh`

**Setup:**
```bash
# Deploy collector to Kafka node
./observability/deploy_kafka_collector.sh

# Check collector
./utils/login.sh kafka
sudo systemctl status kafka-metrics-collector

# View collected metrics
mysql -h 10.0.1.61 -u dstreambolt -p'DStreamBolt2025!' dstreambolt_metrics \
  -e "SELECT * FROM kafka_metrics ORDER BY timestamp DESC LIMIT 10;"
```

**Collected Metrics:**
- Topic partition details
- Broker health
- Offset information
- Partition leaders and ISR

---

### #12 - Spark Metrics Collection ✅
**Status:** INTEGRATED  
**Location:** `computations/SparkProcessor.scala`

**Metrics Captured:**
- Records processed per batch
- Records failed
- Processing time
- Batch duration
- Job status

**View Metrics:**
```sql
USE dstreambolt_metrics;

-- Recent job runs
SELECT * FROM spark_job_metrics 
ORDER BY timestamp DESC LIMIT 20;

-- Success rate
SELECT 
  status,
  COUNT(*) as count,
  AVG(processing_time_ms) as avg_time_ms
FROM spark_job_metrics
GROUP BY status;

-- Performance trends
SELECT 
  DATE(timestamp) as date,
  SUM(records_processed) as total_processed,
  SUM(records_failed) as total_failed,
  AVG(processing_time_ms) as avg_time
FROM spark_job_metrics
GROUP BY DATE(timestamp)
ORDER BY date DESC;
```

---

### #13 - Spark to MySQL Connectivity ✅
**Status:** CONFIGURED  
**JDBC Connection:** Working

**Test from Spark Master:**
```bash
./utils/login.sh master

# Test MySQL connection
/opt/spark/bin/spark-submit \
  --packages mysql:mysql-connector-java:8.0.33 \
  --master local[*] \
  --class TestMySQLConnection \
  test_mysql.py
```

**Connection Details in Spark Job:**
```scala
val jdbcUrl = "jdbc:mysql://10.0.1.61:3306/dstreambolt_metrics"
val connectionProperties = new Properties()
connectionProperties.put("user", "dstreambolt")
connectionProperties.put("password", "DStreamBolt2025!")
connectionProperties.put("driver", "com.mysql.cj.jdbc.Driver")

df.write
  .mode("append")
  .jdbc(jdbcUrl, "endpoint_summary", connectionProperties)
```

---

### #14 - Secrets in AWS Secrets Manager ✅
**Status:** CONFIGURED  
**Secrets:**

1. **dstreambolt/kafka**
   ```json
   {
     "broker": "10.0.10.248:9092",
     "topic": "dstreambolt-logs"
   }
   ```

2. **dstreambolt/mysql**
   ```json
   {
     "host": "10.0.1.61",
     "port": "3306",
     "database": "dstreambolt_metrics",
     "username": "dstreambolt",
     "password": "DStreamBolt2025!"
   }
   ```

**Access from Services:**
```python
import boto3
import json

def get_secret(secret_name):
    client = boto3.client('secretsmanager', region_name='ap-south-1')
    response = client.get_secret_value(SecretId=secret_name)
    return json.loads(response['SecretString'])

# Usage
kafka_config = get_secret('dstreambolt/kafka')
mysql_config = get_secret('dstreambolt/mysql')
```

---

### #15 - Services Use Secrets Manager ✅
**Status:** INTEGRATED

**Ingestion Service:**
- Reads Kafka and MySQL config from Secrets Manager
- Fallback to environment variables
- Auto-refresh every 24 hours

**Spark Jobs:**
- Fetches MySQL credentials on startup
- Uses credentials for JDBC connections

**Verify:**
```bash
# Check Ingestion service
./utils/login.sh ingest
sudo journalctl -u dstreambolt-ingest | grep "Secret loaded"

# Check environment
cat /opt/dstreambolt/ingest/.env
```

---

## 🚀 Quick Start Commands

### Initial Setup

```bash
# 1. Setup DevOps node
./utils/login.sh devops
sudo /path/to/setup_scripts/setup_all.sh
# Select option 9 (All DevOps tools)

# 2. Setup Kafka node
./utils/login.sh kafka
sudo /path/to/setup_scripts/setup_kafka.sh

# 3. Setup Spark Master
./utils/login.sh master
sudo /path/to/setup_scripts/setup_spark_master.sh

# 4. Setup Spark Executor
./utils/login.sh executor
sudo SPARK_MASTER_HOST="52.66.171.95" /path/to/setup_scripts/setup_spark_worker.sh

# 5. Setup Ingestion
./utils/login.sh ingest
sudo KAFKA_BROKER="10.0.10.248:9092" \
     MYSQL_HOST="10.0.1.61" \
     MYSQL_PASSWORD="DStreamBolt2025!" \
     /path/to/setup_scripts/setup_ingestion.sh
```

### Verify All Services

```bash
# DevOps node
./utils/login.sh devops
sudo systemctl status jenkins grafana-server mysql akhq

# Kafka node
./utils/login.sh kafka
sudo systemctl status kafka zookeeper

# Spark master
./utils/login.sh master
sudo systemctl status spark-master

# Spark executor
./utils/login.sh executor
sudo systemctl status spark-worker

# Ingestion
./utils/login.sh ingest
sudo systemctl status dstreambolt-ingest
```

### Start Traffic Generation

```bash
# Via Jenkins
# Go to: http://13.235.238.208:8080/job/DStreamBolt-Continuous-Log-Generator/
# Click "Build with Parameters"
# Click "Build"

# Or manually
cd examples
python3 continuous-log-sender.py \
  --endpoint https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/ingest \
  --interval 30 \
  --batch-size 1000
```

### Monitor in Grafana

```bash
# Open browser
http://13.235.238.208:3000/grafana

# Login: admin / DStreamBolt2025!
# View dashboards
```

---

## 📊 Health Check Summary

Run this on your local machine to verify everything:

```bash
#!/bin/bash

echo "🔍 DStreamBolt Health Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Jenkins
curl -s -o /dev/null -w "Jenkins: %{http_code}\n" http://13.235.238.208:8080/login

# Grafana
curl -s -o /dev/null -w "Grafana: %{http_code}\n" http://13.235.238.208:3000/grafana/

# AKHQ
curl -s -o /dev/null -w "AKHQ: %{http_code}\n" http://13.235.238.208:8081/kafkamgr/

# Spark Master
curl -s -o /dev/null -w "Spark Master: %{http_code}\n" http://52.66.171.95:8080/

# Spark Worker
curl -s -o /dev/null -w "Spark Worker: %{http_code}\n" http://65.0.74.255:8081/

# Ingestion API
curl -s -o /dev/null -w "Ingestion API: %{http_code}\n" https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/health

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
```

---

## 📝 Notes

- All services are configured to start on boot
- Logs are available via `journalctl -u <service-name>`
- Setup scripts are idempotent and safe to re-run
- Default passwords should be changed in production

---

**Last Updated:** December 13, 2025  
**Infrastructure Version:** 1.0  
**Region:** ap-south-1

