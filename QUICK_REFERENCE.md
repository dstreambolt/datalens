# DStreamBolt Quick Reference

## 🎯 System At-a-Glance

### Infrastructure Components

| Component | Instance Type | Public IP | Private IP | Role |
|-----------|---------------|-----------|------------|------|
| **Ingestion** | t3.small | 13.232.206.53 | 10.0.1.x | Accept and queue log bundles |
| **DevOps** | t3.small | 13.235.238.208 | 10.0.1.x | Jenkins, Grafana, MySQL, AKHQ |
| **Kafka** | t3.small | - | 10.0.10.248 | Message broker |
| **Spark Master** | t3.small | 52.66.171.95 | 10.0.1.x | Cluster manager, job scheduler |
| **Spark Executor** | t3.small | 65.0.74.255 | 10.0.1.x | Task execution, processing |

### Service Ports

| Service | Port | Protocol | Access |
|---------|------|----------|--------|
| Ingestion API | 5000 | HTTP | Internal (via ALB) |
| Kafka | 9092 | TCP | Private subnet only |
| Zookeeper | 2181 | TCP | Private subnet only |
| MySQL | 3306 | TCP | Private subnet only |
| Spark Master | 7077 | TCP | Cluster communication |
| Spark Master UI | 8080 | HTTP | Public (view-only) |
| Spark Worker UI | 8081 | HTTP | Public (view-only) |
| Jenkins | 8081 | HTTP | Public (ALB) |
| Grafana | 3000 | HTTP | Public (ALB) |
| AKHQ | 8080 | HTTP | Public (ALB) |

---

## 🔑 Access Credentials

### Default Passwords

```bash
# Jenkins
Username: admin
Password: (check /var/lib/jenkins/secrets/initialAdminPassword on first login)

# Grafana
Username: admin
Password: DStreamBolt2025!

# AKHQ (Kafka UI)
Username: admin
Password: DStreamBolt2025!

# MySQL
Username: root
Password: DStreamBolt2025!
Database: dstreambolt_metrics
```

### SSH Access

```bash
# DevOps Node
ssh -i ~/dstreambolt-access-key.pem ubuntu@13.235.238.208

# Ingestion Node
ssh -i ~/dstreambolt-access-key.pem ubuntu@13.232.206.53

# Spark Master
ssh -i ~/dstreambolt-access-key.pem ubuntu@52.66.171.95

# Spark Executor
ssh -i ~/dstreambolt-access-key.pem ubuntu@65.0.74.255

# Kafka (via bastion)
ssh -i ~/dstreambolt-access-key.pem -J ubuntu@13.235.238.208 ubuntu@10.0.10.248
```

---

## 📊 Data Flow Summary

```
1. Client sends gzipped log bundle
   │
   ├─► POST https://dstreambolt.click/ingest
   │
   ▼
2. Ingestion Service
   │
   ├─► Verifies mTLS certificate
   ├─► Returns 201 Accepted immediately
   ├─► Writes to disk queue
   │
   ▼
3. Background Worker
   │
   ├─► Decompresses bundle
   ├─► Parses JSON log lines
   ├─► Produces to Kafka topic
   │
   ▼
4. Kafka Topic: dstreambolt-logs
   │
   ├─► 3 partitions
   ├─► 7-day retention
   │
   ▼
5. Spark Streaming Consumer
   │
   ├─► 30-second windows
   ├─► Aggregates metrics
   ├─► Calculates statistics
   │
   ▼
6. MySQL Database
   │
   ├─► endpoint_summary table
   ├─► status_summary table
   ├─► ingest_metrics table
   │
   ▼
7. Grafana Dashboards
   │
   └─► Visualizations
```

---

## 🔍 Quick Health Checks

### One-Liner Health Check

```bash
# Check all services at once
for service in ingestion kafka spark mysql grafana jenkins; do
  echo "=== $service ==="
  case $service in
    ingestion)
      curl -s https://dstreambolt.click/health | jq '.kafka'
      ;;
    kafka)
      ssh -J ubuntu@13.235.238.208 ubuntu@10.0.10.248 \
        'systemctl is-active kafka' 2>/dev/null
      ;;
    spark)
      curl -s http://52.66.171.95:8080/json/ | jq -r '.status'
      ;;
    mysql)
      ssh ubuntu@13.235.238.208 \
        'mysql -u root -pDStreamBolt2025! -e "SELECT 1" 2>/dev/null && echo "UP" || echo "DOWN"'
      ;;
    grafana)
      curl -s -o /dev/null -w "%{http_code}" http://13.235.238.208:3000/grafana/
      ;;
    jenkins)
      curl -s -o /dev/null -w "%{http_code}" http://13.235.238.208:8081/
      ;;
  esac
done
```

### Individual Service Checks

```bash
# Ingestion Service
curl https://dstreambolt.click/health

# Kafka Topics
ssh -J ubuntu@13.235.238.208 ubuntu@10.0.10.248 \
  '/opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092'

# Spark Jobs
curl http://52.66.171.95:8080/json/ | jq '.activeapps'

# MySQL Tables
ssh ubuntu@13.235.238.208 \
  'mysql -u root -pDStreamBolt2025! -e "SHOW TABLES FROM dstreambolt_metrics;"'

# Grafana Datasource
curl -u admin:DStreamBolt2025! http://13.235.238.208:3000/api/datasources

# Jenkins Jobs
curl -s http://13.235.238.208:8081/api/json | jq '.jobs[].name'
```

---

## 🚀 Common Operations

### Restart Services

```bash
# Ingestion
ssh ubuntu@13.232.206.53 'sudo systemctl restart dstreambolt-ingest'

# Kafka
ssh -J ubuntu@13.235.238.208 ubuntu@10.0.10.248 \
  'sudo systemctl restart kafka'

# Spark Job
ssh ubuntu@52.66.171.95 '
  pkill -f spark_processor
  cd /opt/dstreambolt/computations && ./submit_job.sh
'

# Jenkins
ssh ubuntu@13.235.238.208 'sudo systemctl restart jenkins'

# Grafana
ssh ubuntu@13.235.238.208 'sudo systemctl restart grafana-server'

# MySQL
ssh ubuntu@13.235.238.208 'sudo systemctl restart mysql'
```

### View Logs

```bash
# Ingestion Logs
ssh ubuntu@13.232.206.53 \
  'sudo journalctl -u dstreambolt-ingest -n 100 --no-pager'

# Kafka Logs
ssh -J ubuntu@13.235.238.208 ubuntu@10.0.10.248 \
  'tail -100 /opt/kafka/logs/server.log'

# Spark Job Logs
ssh ubuntu@52.66.171.95 'tail -100 /opt/spark/logs/spark-job.log'

# Jenkins Logs
ssh ubuntu@13.235.238.208 'tail -100 /var/log/jenkins/jenkins.log'

# Grafana Logs
ssh ubuntu@13.235.238.208 'sudo journalctl -u grafana-server -n 100 --no-pager'

# MySQL Logs
ssh ubuntu@13.235.238.208 'sudo tail -100 /var/log/mysql/error.log'
```

### Check Metrics

```bash
# Ingestion Queue Depth
ssh ubuntu@13.232.206.53 'ls /opt/dstreambolt/queue/*.gz 2>/dev/null | wc -l'

# Kafka Consumer Lag
ssh -J ubuntu@13.235.238.208 ubuntu@10.0.10.248 \
  '/opt/kafka/bin/kafka-consumer-groups.sh --describe \
   --group spark-consumer --bootstrap-server localhost:9092'

# Spark Executor Memory
ssh ubuntu@65.0.74.255 'free -h'

# MySQL Database Size
ssh ubuntu@13.235.238.208 \
  'mysql -u root -pDStreamBolt2025! -e "
    SELECT table_schema AS Database,
           ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS Size_MB
    FROM information_schema.tables
    WHERE table_schema = \"dstreambolt_metrics\"
    GROUP BY table_schema;"'

# Disk Usage
for ip in 13.235.238.208 13.232.206.53 52.66.171.95 65.0.74.255; do
  echo "=== $ip ==="
  ssh -i ~/dstreambolt-access-key.pem ubuntu@$ip 'df -h / | tail -1'
done
```

---

## 🐛 Troubleshooting Quick Reference

### Problem: 503 Service Unavailable

```bash
# Check queue
ssh ubuntu@13.232.206.53 'ls /opt/dstreambolt/queue/ | wc -l'

# Solution: Clear queue or scale Spark
ssh ubuntu@13.232.206.53 'sudo systemctl restart dstreambolt-ingest'
```

### Problem: High Kafka Lag

```bash
# Check lag
ssh -J ubuntu@13.235.238.208 ubuntu@10.0.10.248 \
  '/opt/kafka/bin/kafka-consumer-groups.sh --describe \
   --group spark-consumer --bootstrap-server localhost:9092'

# Solution: Add Spark executors or increase batch size
```

### Problem: Spark Job Failed

```bash
# Check logs
ssh ubuntu@52.66.171.95 'tail -100 /opt/spark/logs/spark-job.log'

# Check executor status
curl http://52.66.171.95:8080/json/ | jq '.aliveworkers'

# Restart job
ssh ubuntu@52.66.171.95 '
  pkill -f spark_processor
  cd /opt/dstreambolt/computations
  ./submit_job.sh
'
```

### Problem: MySQL Connection Refused

```bash
# Check MySQL status
ssh ubuntu@13.235.238.208 'sudo systemctl status mysql'

# Check connections
ssh ubuntu@13.235.238.208 \
  'mysql -u root -pDStreamBolt2025! -e "SHOW PROCESSLIST;"'

# Restart MySQL
ssh ubuntu@13.235.238.208 'sudo systemctl restart mysql'
```

---

## 📈 Performance Benchmarks

### Current Capacity (t3.small instances)

| Metric | Value |
|--------|-------|
| **Ingestion Throughput** | ~10,000 requests/sec |
| **Kafka Throughput** | ~50 MB/sec |
| **Spark Processing Rate** | ~100,000 logs/sec |
| **MySQL Write Rate** | ~1,000 inserts/sec |
| **End-to-End Latency** | 30-60 seconds (streaming) |
| **Storage** | 7-day retention (~100 GB) |

### Scale Limits (Single Region)

| Component | Current | Max Recommended |
|-----------|---------|-----------------|
| Ingestion Instances | 1 | 10 |
| Kafka Brokers | 1 | 3 |
| Spark Executors | 1 | 10 |
| Concurrent Requests | 1,000 | 10,000 |
| Daily Log Volume | 1 GB | 100 GB |

---

## 💰 Cost Summary

| Resource | Monthly Cost (USD) |
|----------|-------------------|
| EC2 Instances (5x t3.small) | $75 |
| EBS Storage (40 GB) | $4 |
| Application Load Balancer | $16 |
| Data Transfer (10 GB) | $1 |
| Secrets Manager (5 secrets) | $2 |
| **Total** | **~$98/month** |

**Cost Optimization:**
- Use Reserved Instances: Save 30-40%
- Use Spot Instances for executors: Save 70%
- Archive old data to S3 Glacier: Save 90% on storage

---

## 🔗 Quick Links

### Dashboards

- **Load Balancer**: https://dstreambolt.click
- **Jenkins**: http://13.235.238.208:8081
- **Grafana**: http://13.235.238.208:3000/grafana
- **AKHQ (Kafka UI)**: http://13.235.238.208:8080
- **Spark Master UI**: http://52.66.171.95:8080
- **Spark Worker UI**: http://65.0.74.255:8081

### Documentation

- **Architecture**: [ARCHITECTURE.md](./ARCHITECTURE.md)
- **Operations**: [OPERATIONS_GUIDE.md](./OPERATIONS_GUIDE.md)
- **Setup**: [setup_scripts/README.md](./setup_scripts/README.md)

### Code Repository

- **GitHub**: https://github.com/dstreambolt/dstream_cloud
- **Issues**: https://github.com/dstreambolt/dstream_cloud/issues

---

## 📞 Support

**Email**: support@dstreambolt.click  
**On-Call**: on-call-engineer@dstreambolt.click  
**Slack**: dstreambolt.slack.com

---

**Last Updated:** December 13, 2025  
**Version:** 1.0.0

