# DStreamBolt Examples

This directory contains example scripts and configurations for working with the DStreamBolt platform.

## 📋 Overview

The examples demonstrate the complete data pipeline:

1. **01-generate-logs.py** - Generate realistic access logs
2. **02-send-to-ingest.py** - Send gzipped log bundles to the ingestion service
3. **03-kafka-consumer.py** - Consume messages from Kafka topics
4. **04-spark-processor.py** - Process logs using Spark
5. **grafana-dashboard.json** - Pre-configured Grafana dashboard

## 🚀 Quick Start

### Prerequisites

```bash
# Install required Python packages
pip install -r requirements.txt
```

Required packages:
- `requests` - HTTP client for ingestion API
- `kafka-python` - Kafka consumer client
- `pyspark` - Spark processing framework
- `pymysql` - MySQL database connector
- `boto3` - AWS SDK (optional, for S3 integration)

### 1. Generate Sample Logs

Create realistic access logs in Apache Combined Log Format:

```bash
# Generate 1000 log entries
python3 01-generate-logs.py --count 1000 --output logs/access.log

# Generate continuous logs (streaming mode)
python3 01-generate-logs.py --stream --interval 0.1

# Generate logs with custom error rate
python3 01-generate-logs.py --count 5000 --error-rate 15 --output logs/high-error.log
```

**Options:**
- `--count N` - Number of log entries to generate (default: 1000)
- `--output FILE` - Output file path (default: logs/access.log)
- `--stream` - Continuous generation mode
- `--interval SECONDS` - Delay between log entries in stream mode (default: 0.1)
- `--error-rate PERCENT` - Percentage of error responses (default: 10)

### 2. Send Logs to Ingestion Service

Send logs to the DStreamBolt ingestion API with optional mTLS authentication:

#### Basic Usage (No mTLS)

```bash
# Batch mode - send all logs at once
python3 02-send-to-ingest.py logs/access.log \
  --alb-url https://dstreambolt-alb-xxxxx.elb.amazonaws.com

# Streaming mode - send in batches
python3 02-send-to-ingest.py logs/access.log \
  --alb-url https://dstreambolt-alb-xxxxx.elb.amazonaws.com \
  --mode stream \
  --batch-size 50 \
  --delay 2.0
```

#### With mTLS Client Authentication

For production environments with mTLS enabled:

```bash
# First, generate certificates (one-time setup)
cd /Users/skalaise/apps/cloud/terraform/dstream_bolt
./generate_mtls_certs.sh

# Send logs with mTLS
python3 02-send-to-ingest.py logs/access.log \
  --alb-url https://ingest.dstreambolt.dashbird.com \
  --client-cert certs/client/client-cert.pem \
  --client-key certs/client/client-key.pem \
  --ca-cert certs/ca/ca-cert.pem

# Streaming with mTLS
python3 02-send-to-ingest.py logs/access.log \
  --alb-url https://ingest.dstreambolt.dashbird.com \
  --mode stream \
  --batch-size 100 \
  --delay 1.0 \
  --client-cert certs/client/client-cert.pem \
  --client-key certs/client/client-key.pem \
  --ca-cert certs/ca/ca-cert.pem
```

**Options:**
- `--alb-url URL` - Ingestion service URL (required)
- `--mode {batch,stream}` - Sending mode (default: batch)
- `--batch-size N` - Lines per batch in stream mode (default: 100)
- `--delay SECONDS` - Delay between batches in stream mode (default: 1.0)
- `--client-cert FILE` - Client certificate for mTLS
- `--client-key FILE` - Client private key for mTLS
- `--ca-cert FILE` - CA certificate for server verification
- `--no-verify` - Disable SSL verification (insecure, for testing only)

**mTLS Setup:**

1. Generate certificates:
   ```bash
   ./generate_mtls_certs.sh
   ```

2. Deploy server certificates to ingestion instances:
   ```bash
   # Copy CA and server certificates
   scp -r certs/ca ubuntu@<ingestion-ip>:/etc/dstreambolt/certs/
   scp -r certs/server ubuntu@<ingestion-ip>:/etc/dstreambolt/certs/
   ```

3. Enable mTLS on the ingestion service:
   ```bash
   # SSH to ingestion server
   ssh ubuntu@<ingestion-ip>
   
   # Update service environment
   sudo tee -a /etc/systemd/system/dstreambolt-ingest.service.d/override.conf << EOF
   [Service]
   Environment="MTLS_ENABLED=true"
   Environment="MTLS_CA_CERT_PATH=/etc/dstreambolt/certs/ca/ca-cert.pem"
   EOF
   
   # Reload and restart
   sudo systemctl daemon-reload
   sudo systemctl restart dstreambolt-ingest
   ```

4. Distribute client certificates to authorized clients:
   ```bash
   # Each client needs:
   # - certs/client/client-cert.pem
   # - certs/client/client-key.pem
   # - certs/ca/ca-cert.pem (for server verification)
   ```

**Security Notes:**
- Keep private keys secure (`.pem` files with `-key` in the name)
- Never commit certificates to version control
- Rotate certificates regularly (use `--days` parameter in generation script)
- Use separate client certificates for each client/application
- Monitor certificate expiration dates

**Output Format:**
```
192.168.1.100 - john_doe [05/Dec/2025:10:30:45 +0000] "GET /api/v1/users HTTP/1.1" 200 1234 "https://example.com" "Mozilla/5.0..."
```

### 2. Send Logs to Ingestion Service

Send gzipped log bundles to the DStreamBolt ingestion API:

```bash
# Basic usage (without mTLS)
python3 02-send-to-ingest.py \
  --alb-url https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com \
  --file logs/access.log

# With mTLS authentication (production)
python3 02-send-to-ingest.py \
  --alb-url https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com \
  --file logs/access.log \
  --cert certs/client-cert.pem \
  --key certs/client-key.pem

# Batch send multiple files
python3 02-send-to-ingest.py \
  --alb-url https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com \
  --batch logs/*.log

# Streaming mode (watch directory)
python3 02-send-to-ingest.py \
  --alb-url https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com \
  --watch logs/ \
  --interval 5
```

**Options:**
- `--alb-url URL` - DStreamBolt ALB URL (required)
- `--file FILE` - Single log file to send
- `--batch PATTERN` - Send multiple files matching pattern
- `--watch DIR` - Watch directory for new files
- `--cert FILE` - Client certificate for mTLS
- `--key FILE` - Client key for mTLS
- `--verify/--no-verify` - SSL verification (default: true)
- `--interval SECONDS` - Polling interval for watch mode

**Expected Response:**
```json
{
  "status": "accepted",
  "bundle_id": "bundle-20251205-103045-abc123",
  "timestamp": 1733395845,
  "message": "Bundle accepted for processing"
}
```

### 3. Consume from Kafka

Read processed logs from Kafka topics:

```bash
# Consume from default topic
python3 03-kafka-consumer.py \
  --broker 10.0.10.101:9092 \
  --topic dstreambolt-logs

# Consume from beginning with custom group
python3 03-kafka-consumer.py \
  --broker 10.0.10.101:9092 \
  --topic dstreambolt-logs \
  --group my-consumer-group \
  --from-beginning

# Save consumed messages to file
python3 03-kafka-consumer.py \
  --broker 10.0.10.101:9092 \
  --topic dstreambolt-logs \
  --output consumed-logs.json

# Filter by status code
python3 03-kafka-consumer.py \
  --broker 10.0.10.101:9092 \
  --topic dstreambolt-logs \
  --filter-status 500,503
```

**Options:**
- `--broker HOST:PORT` - Kafka broker address (required)
- `--topic TOPIC` - Kafka topic name (default: dstreambolt-logs)
- `--group ID` - Consumer group ID (default: dstreambolt-consumer)
- `--from-beginning` - Read from earliest offset
- `--output FILE` - Save messages to file
- `--filter-status CODES` - Filter by HTTP status codes (comma-separated)
- `--max-messages N` - Stop after N messages

**Message Format:**
```json
{
  "timestamp": "2025-12-05T10:30:45Z",
  "ip": "192.168.1.100",
  "method": "GET",
  "endpoint": "/api/v1/users",
  "status_code": 200,
  "response_size": 1234,
  "user_agent": "Mozilla/5.0...",
  "bundle_id": "bundle-20251205-103045-abc123"
}
```

### 4. Process with Spark

Run Spark jobs to analyze and aggregate logs:

```bash
# Basic processing
python3 04-spark-processor.py \
  --spark-master spark://10.0.11.80:7077 \
  --kafka-broker 10.0.10.101:9092

# Process with custom aggregation window
python3 04-spark-processor.py \
  --spark-master spark://10.0.11.80:7077 \
  --kafka-broker 10.0.10.101:9092 \
  --window-duration 60 \
  --output-mode complete

# Process and save to MySQL
python3 04-spark-processor.py \
  --spark-master spark://10.0.11.80:7077 \
  --kafka-broker 10.0.10.101:9092 \
  --mysql-host 10.0.1.70 \
  --mysql-user root \
  --mysql-password <password> \
  --mysql-database dstreambolt

# Real-time streaming with checkpointing
python3 04-spark-processor.py \
  --spark-master spark://10.0.11.80:7077 \
  --kafka-broker 10.0.10.101:9092 \
  --checkpoint-dir /tmp/spark-checkpoints \
  --streaming
```

**Options:**
- `--spark-master URL` - Spark master URL (required)
- `--kafka-broker HOST:PORT` - Kafka broker address (required)
- `--topic TOPIC` - Kafka topic to process (default: dstreambolt-logs)
- `--window-duration SECONDS` - Aggregation window size (default: 30)
- `--output-mode MODE` - Spark output mode: complete|append|update
- `--mysql-host HOST` - MySQL host for results
- `--mysql-user USER` - MySQL username
- `--mysql-password PASS` - MySQL password
- `--mysql-database DB` - MySQL database name
- `--checkpoint-dir DIR` - Checkpoint directory for fault tolerance
- `--streaming` - Run in streaming mode

**Processing Operations:**
- Count requests by endpoint
- Calculate average response times
- Detect error rate spikes
- Identify top IP addresses
- Analyze user agent distribution

### 5. Import Grafana Dashboard

Import the pre-configured dashboard to visualize metrics:

1. **Access Grafana:**
   ```
   https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/grafana
   ```
   Login: `admin` / (password from terraform output)

2. **Import Dashboard:**
   - Navigate to: Dashboards → Import
   - Click "Upload JSON file"
   - Select: `grafana-dashboard.json`
   - Click "Import"

3. **Dashboard Features:**
   - **Real-time Metrics**: Request rate, error rate, response times
   - **Kafka Monitoring**: Consumer lag, throughput, partition metrics
   - **Spark Jobs**: Running jobs, completed tasks, resource utilization
   - **System Health**: CPU, memory, disk usage per instance
   - **Ingestion Stats**: Bundle size, processing time, failures

## 📊 Complete Example Workflow

### End-to-End Pipeline

```bash
# Terminal 1: Start Spark processor (streaming mode)
python3 04-spark-processor.py \
  --spark-master spark://10.0.11.80:7077 \
  --kafka-broker 10.0.10.101:9092 \
  --streaming \
  --mysql-host 10.0.1.70 \
  --mysql-user root \
  --mysql-password YourPassword

# Terminal 2: Start Kafka consumer (monitoring)
python3 03-kafka-consumer.py \
  --broker 10.0.10.101:9092 \
  --topic dstreambolt-logs \
  --from-beginning

# Terminal 3: Generate and send logs continuously
python3 01-generate-logs.py --stream --interval 0.5 | while read line; do
  echo "$line" >> logs/stream.log
  python3 02-send-to-ingest.py \
    --alb-url https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com \
    --file logs/stream.log \
    --cert certs/client-cert.pem \
    --key certs/client-key.pem
done
```

### Batch Processing Example

```bash
# 1. Generate large dataset (10K entries)
python3 01-generate-logs.py --count 10000 --output logs/batch-10k.log

# 2. Send to ingestion
python3 02-send-to-ingest.py \
  --alb-url https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com \
  --file logs/batch-10k.log \
  --cert certs/client-cert.pem \
  --key certs/client-key.pem

# 3. Process with Spark (batch mode)
python3 04-spark-processor.py \
  --spark-master spark://10.0.11.80:7077 \
  --kafka-broker 10.0.10.101:9092 \
  --mysql-host 10.0.1.70 \
  --mysql-user root \
  --mysql-password YourPassword

# 4. View results in Grafana dashboard
# Open: https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/grafana
```

## 🔐 mTLS Configuration

### Generate Client Certificates

If you need to generate client certificates for mTLS:

```bash
# 1. Create private key
openssl genrsa -out certs/client-key.pem 2048

# 2. Create certificate signing request
openssl req -new -key certs/client-key.pem -out certs/client.csr \
  -subj "/CN=dstreambolt-client/O=DStreamBolt/C=US"

# 3. Sign with CA (using Terraform-generated CA)
openssl x509 -req -in certs/client.csr \
  -CA certs/ca-cert.pem \
  -CAkey certs/ca-key.pem \
  -CAcreateserial \
  -out certs/client-cert.pem \
  -days 365

# 4. Verify certificate
openssl verify -CAfile certs/ca-cert.pem certs/client-cert.pem
```

### Using Terraform-Generated Certificates

The infrastructure automatically generates certificates. Retrieve them:

```bash
# Get credentials and certificate paths from Terraform output
terraform output -json credentials

# Certificates are stored in AWS Secrets Manager
# Client cert: aws_secretsmanager_secret.client_key
# Server cert: aws_secretsmanager_secret.server_key
# CA cert: aws_secretsmanager_secret.ca
```

## 📈 Monitoring and Debugging

### Check Service Health

```bash
# Ingestion API health
curl -k https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/health

# Jenkins status
curl -k https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/jenkins/

# Grafana status
curl -k https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/grafana/api/health

# Spark Master UI
curl -k https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/spark/

# AKHQ Kafka Manager
curl -k https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/kafkamgr/
```

### View Logs

```bash
# SSH to instances (replace IPs from terraform output)
ssh -i ~/dstreambolt-access-key.pem ubuntu@<instance-ip>

# Ingestion service logs
sudo journalctl -u ingest-api -f

# Kafka logs
sudo journalctl -u kafka -f

# Spark logs
tail -f /opt/spark/logs/spark-*.out

# Jenkins logs
sudo journalctl -u jenkins -f

# Grafana logs
sudo journalctl -u grafana-server -f

# MySQL logs
sudo tail -f /var/log/mysql/error.log
```

### Query MySQL Metrics

```bash
# Connect to MySQL on devops instance
mysql -h 10.0.1.70 -u root -p dstreambolt

# View ingestion metrics
SELECT * FROM ingestion_metrics ORDER BY timestamp DESC LIMIT 10;

# View bundle statistics
SELECT status, COUNT(*) as count, AVG(size_bytes) as avg_size
FROM bundle_stats
GROUP BY status;

# View error logs
SELECT * FROM error_logs WHERE timestamp > NOW() - INTERVAL 1 HOUR;
```

## 🔧 Troubleshooting

### Connection Issues

```bash
# Test ALB connectivity
curl -v https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/health

# Test Kafka connectivity (from bastion/devops instance)
telnet 10.0.10.101 9092

# Test Spark connectivity
telnet 10.0.11.80 7077
```

### Certificate Errors

```bash
# Verify certificate chain
openssl s_client -connect dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com:443 \
  -CAfile certs/ca-cert.pem

# Test with self-signed cert (disable verification)
python3 02-send-to-ingest.py \
  --alb-url https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com \
  --file logs/test.log \
  --no-verify
```

### Kafka Consumer Lag

```bash
# Check consumer group lag (from AKHQ)
# Open: https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/kafkamgr/

# Or use Kafka CLI tools on kafka instance
/opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --group dstreambolt-consumer \
  --describe
```

## 📚 Additional Resources

- **Main README**: `../README.md` - Infrastructure setup and deployment
- **Terraform Docs**: `../modules/*/README.md` - Module documentation
- **AWS Documentation**: [ELB](https://aws.amazon.com/elasticloadbalancing/), [EC2](https://aws.amazon.com/ec2/)
- **Kafka Docs**: [Apache Kafka](https://kafka.apache.org/documentation/)
- **Spark Docs**: [Apache Spark](https://spark.apache.org/docs/latest/)
- **Grafana Docs**: [Grafana](https://grafana.com/docs/)

## 🆘 Getting Help

If you encounter issues:

1. Check service health endpoints
2. Review logs on respective instances
3. Verify security group rules
4. Ensure certificates are valid
5. Check Terraform output for correct endpoints

For infrastructure issues, run:
```bash
terraform refresh
terraform output -json
```

## 📝 Notes

- **Costs**: All resources use t3.micro (free tier eligible) or t3.small instances
- **Security**: mTLS is optional but recommended for production
- **Scaling**: This setup is for development/testing. For production, consider auto-scaling groups
- **Data Retention**: Configure log rotation and Kafka retention policies as needed

---

**DStreamBolt** - Real-Time Data Streaming Platform

