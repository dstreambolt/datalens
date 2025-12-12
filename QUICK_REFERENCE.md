# DStreamBolt Quick Reference

Essential commands and operations for DStreamBolt platform.

## 🚀 Deployment

```bash
# Initialize Terraform
cd terraform && terraform init

# Plan infrastructure
terraform plan -out=tfplan

# Apply changes
terraform apply tfplan

# Get outputs
terraform output
```

## 🔑 Access Services

```bash
# Get instance IPs
cd terraform
DEVOPS_IP=$(terraform output -raw devops_ip)
INGEST_IP=$(terraform output -raw ingest_ip)
SPARK_IP=$(terraform output -raw spark_master_ip)
KAFKA_IP=$(terraform output -raw kafka_ip)

# SSH to instances
ssh -i ~/dstreambolt-access-key.pem ubuntu@$DEVOPS_IP
ssh -i ~/dstreambolt-access-key.pem ubuntu@$INGEST_IP
ssh -i ~/dstreambolt-access-key.pem ubuntu@$SPARK_IP
```

## 📊 Service URLs

```bash
# Jenkins
http://$DEVOPS_IP/jenkins
# Login: admin / (see /var/lib/jenkins/secrets/initialAdminPassword)

# Grafana  
http://$DEVOPS_IP/grafana
# Login: admin / DStreamBolt2025!

# AKHQ (Kafka Manager)
http://$DEVOPS_IP/kafkamgr
# No authentication required

# Spark Master UI
http://$SPARK_IP:8080

# Spark Worker UI
http://$SPARK_IP:8081
```

## 🔍 Check Service Status

```bash
# On DevOps node
ssh -i ~/dstreambolt-access-key.pem ubuntu@$DEVOPS_IP
sudo systemctl status jenkins grafana-server nginx akhq mysql

# On Ingestion node
ssh -i ~/dstreambolt-access-key.pem ubuntu@$INGEST_IP
sudo systemctl status dstreambolt-ingest

# On Kafka node
ssh -i ~/dstreambolt-access-key.pem ubuntu@$KAFKA_IP
sudo systemctl status kafka zookeeper

# On Spark node
ssh -i ~/dstreambolt-access-key.pem ubuntu@$SPARK_IP
sudo systemctl status spark-master spark-worker
```

## 📝 View Logs

```bash
# Ingestion logs
sudo journalctl -u dstreambolt-ingest -f

# Kafka logs
sudo journalctl -u kafka -f

# Spark logs
tail -f /opt/spark/logs/spark-*.out

# Jenkins logs
sudo journalctl -u jenkins -f

# Grafana logs
sudo journalctl -u grafana-server -f
```

## 🔄 Restart Services

```bash
# Restart ingestion service
sudo systemctl restart dstreambolt-ingest

# Restart Kafka
sudo systemctl restart kafka

# Restart Spark (stop and start new job)
pkill -f SparkProcessor
cd /opt/dstreambolt/computations && ./submit_job.sh

# Restart Jenkins
sudo systemctl restart jenkins

# Restart Grafana
sudo systemctl restart grafana-server

# Restart AKHQ
sudo systemctl restart akhq
```

## 📤 Send Test Logs

```bash
cd examples

# Generate test logs
python3 01-generate-logs.py --lines 1000 --output logs/test.log

# Send to ingestion (with mTLS)
python3 02-send-to-ingest.py \
  --alb-url https://$(cd ../terraform && terraform output -raw alb_dns)/ingest \
  --cert ../certs/client/client-cert.pem \
  --key ../certs/client/client-key.pem \
  --ca-cert ../certs/ca/ca-cert.pem \
  logs/test.log
```

## 🗄️ MySQL Operations

```bash
# Connect to MySQL
mysql -h $DEVOPS_IP -u root -p
# Password is in AWS Secrets Manager: dstreambolt/mysql

# View metrics
USE dstreambolt_metrics;

# Ingestion metrics
SELECT * FROM ingestion_metrics ORDER BY timestamp DESC LIMIT 10;

# Endpoint summary
SELECT * FROM endpoint_summary ORDER BY window_start DESC LIMIT 10;

# Status summary
SELECT * FROM status_summary ORDER BY window_start DESC LIMIT 10;

# Kafka metrics
SELECT * FROM kafka_metrics ORDER BY timestamp DESC LIMIT 10;
```

## 🔐 AKHQ Credentials Setup

```bash
# Copy script to DevOps node
scp -i ~/dstreambolt-access-key.pem \
  utils/set_akhq_credentials.sh \
  ubuntu@$DEVOPS_IP:/tmp/

# SSH and run
ssh -i ~/dstreambolt-access-key.pem ubuntu@$DEVOPS_IP
sudo bash /tmp/set_akhq_credentials.sh
```

## 🚀 Deploy via Jenkins

### Deploy Ingestion Service

1. Go to Jenkins: `http://$DEVOPS_IP/jenkins`
2. Job: **DStreamBolt-Deploy-Ingestion**
3. Parameters:
   - Git Branch: `release/v1.0.0`
   - Target IPs: (ingestion node IP)
4. Build

### Deploy Spark Jobs

1. Go to Jenkins: `http://$DEVOPS_IP/jenkins`
2. Job: **DStreamBolt-Deploy-Spark-Scala**
3. Parameters:
   - Git Branch: `release/v1.0.1`
   - Spark Master IPs: (spark master IP)
   - Kafka Broker: `10.0.10.248:9092`
4. Build

## 🧪 Test Kafka

```bash
# List topics (on DevOps node via AKHQ)
http://$DEVOPS_IP/kafkamgr

# Or SSH to Kafka node
ssh -i ~/dstreambolt-access-key.pem ubuntu@$KAFKA_IP

# List topics
/opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092

# Consume messages
/opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic dstreambolt-logs \
  --from-beginning \
  --max-messages 10
```

## 🛑 Emergency Operations

### Stop All Processing

```bash
# Stop ingestion
ssh ubuntu@$INGEST_IP 'sudo systemctl stop dstreambolt-ingest'

# Stop Spark jobs
ssh ubuntu@$SPARK_IP 'pkill -f SparkProcessor'

# Kafka will continue buffering messages
```

### Start All Processing

```bash
# Start ingestion
ssh ubuntu@$INGEST_IP 'sudo systemctl start dstreambolt-ingest'

# Start Spark job
ssh ubuntu@$SPARK_IP 'cd /opt/dstreambolt/computations && ./submit_job.sh'
```

### Clear Kafka Topic

```bash
ssh ubuntu@$KAFKA_IP

# Delete and recreate topic
/opt/kafka/bin/kafka-topics.sh --delete \
  --topic dstreambolt-logs \
  --bootstrap-server localhost:9092

/opt/kafka/bin/kafka-topics.sh --create \
  --topic dstreambolt-logs \
  --bootstrap-server localhost:9092 \
  --partitions 3 \
  --replication-factor 1
```

## 💡 Troubleshooting

### Ingestion Not Receiving Logs

```bash
# Check service
sudo systemctl status dstreambolt-ingest

# Check logs
sudo journalctl -u dstreambolt-ingest -n 100 --no-pager

# Test health endpoint
curl http://localhost:5000/health

# Check Kafka connectivity
nc -zv $KAFKA_IP 9092
```

### Spark Not Processing

```bash
# Check Spark Master UI
open http://$SPARK_IP:8080

# Check logs
tail -100 /opt/spark/logs/spark-*.out

# Check if job is running
ps aux | grep SparkProcessor

# Check Kafka connectivity
nc -zv $KAFKA_IP 9092
```

### Kafka Issues

```bash
# Check service
sudo systemctl status kafka zookeeper

# Check logs
sudo journalctl -u kafka -n 100 --no-pager

# Check disk space
df -h

# Check if listening
netstat -tulpn | grep 9092
```

## 📋 Useful Commands

```bash
# Get all service URLs
cd terraform && terraform output

# Get AWS Secrets
aws secretsmanager get-secret-value \
  --secret-id dstreambolt/mysql \
  --region ap-south-1 \
  --query SecretString \
  --output text

# Check all running processes
ps aux | grep -E "java|python|gunicorn|spark"

# Check open ports
sudo netstat -tulpn | grep LISTEN

# Check disk usage
df -h
du -sh /opt/*

# Check memory
free -h

# Check system load
uptime
```

---

**For more detailed documentation, see:**
- [README.md](README.md) - Full platform documentation
- [SECRETS_MANAGEMENT.md](SECRETS_MANAGEMENT.md) - AWS Secrets Manager guide
- [ingestion/README.md](ingestion/README.md) - Ingestion service details
- [computations/README.md](computations/README.md) - Spark jobs documentation
- [jenkins/README.md](jenkins/README.md) - CI/CD pipelines

