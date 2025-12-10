# Complete Deployment Guide - Optimized Ingestion & Kafka Metrics

## 📋 Overview

This guide covers:
1. **Optimized Ingestion Service** - app_optimized.py (no table creation)
2. **Kafka Metrics Collector** - Runs on Kafka node, collects metrics every minute

## 🚀 Part 1: Deploy Optimized Ingestion Service

### Prerequisites
- Tables must be created first: `cd observability && ./setup_observability.sh`

### Option A: Replace Existing app.py

```bash
# Backup current app.py
cd /Users/skalaise/apps/cloud/terraform/dstream_bolt/ingestion
cp app.py app.py.backup

# Replace with optimized version
cp app_optimized.py app.py

# Commit changes
git add app.py
git commit -m "Optimize ingestion service - remove table creation"
git push
```

### Option B: Deploy Side-by-Side

```bash
# Deploy optimized version alongside current
scp -i ~/dstreambolt-access-key.pem app_optimized.py ubuntu@13.201.43.125:/opt/dstreambolt-ingest/

# SSH to ingestion node
ssh -i ~/dstreambolt-access-key.pem ubuntu@13.201.43.125

# Stop current service
sudo systemctl stop dstreambolt-ingest

# Replace app.py
cd /opt/dstreambolt-ingest
cp app_optimized.py app.py

# Restart service
sudo systemctl start dstreambolt-ingest
sudo systemctl status dstreambolt-ingest

# Check logs
sudo journalctl -u dstreambolt-ingest -f
```

### Verify Ingestion Service

```bash
# Test health endpoint
curl http://13.201.43.125:5000/health

# Test metrics endpoint
curl http://13.201.43.125:5000/metrics

# Send test bundle
curl -X POST http://13.201.43.125:5000/ingest \
  -H "Content-Type: application/gzip" \
  --data-binary @test_bundle.gz
```

### Check Metrics in MySQL

```bash
ssh ubuntu@13.232.132.240
mysql -u dstreambolt -p'DStreamBolt2025!' dstreambolt_metrics

-- Check ingestion metrics
SELECT * FROM ingestion_requests ORDER BY timestamp DESC LIMIT 5;
SELECT * FROM bundle_processing ORDER BY timestamp DESC LIMIT 5;
SELECT * FROM kafka_production_metrics ORDER BY timestamp DESC LIMIT 5;

-- Check failed bundles
SELECT * FROM failed_bundles WHERE resolved = FALSE;

-- Check real-time metrics
SELECT * FROM ingestion_realtime_metrics;
```

## 🔍 Part 2: Deploy Kafka Metrics Collector

### Where to Run?
**Run on the Kafka Node: 10.0.10.101**

Why? The collector needs direct access to Kafka command-line tools and localhost:9092

### Quick Deployment

```bash
cd /Users/skalaise/apps/cloud/terraform/dstream_bolt/observability

# Make script executable
chmod +x deploy_kafka_collector.sh

# Deploy to Kafka node
./deploy_kafka_collector.sh

# The script will:
# 1. Create /opt/dstreambolt/observability on Kafka node
# 2. Copy kafka_metrics_collector.py
# 3. Install Python dependencies
# 4. Set up systemd service
# 5. Start the collector
```

### Manual Deployment Steps

If you prefer manual deployment:

```bash
# 1. SSH to Kafka node
ssh -i ~/dstreambolt-access-key.pem ubuntu@10.0.10.101

# 2. Create directories
sudo mkdir -p /opt/dstreambolt/observability
sudo mkdir -p /var/log/dstreambolt
sudo chown -R ubuntu:ubuntu /opt/dstreambolt
sudo chown -R ubuntu:ubuntu /var/log/dstreambolt

# 3. Copy collector script (from your local machine)
scp -i ~/dstreambolt-access-key.pem \
  observability/kafka_metrics_collector.py \
  ubuntu@10.0.10.101:/opt/dstreambolt/observability/

# 4. Install Python MySQL library
ssh ubuntu@10.0.10.101
pip3 install pymysql
# OR
sudo apt-get install -y python3-pymysql

# 5. Test collector manually
cd /opt/dstreambolt/observability
python3 kafka_metrics_collector.py
# Press Ctrl+C after seeing metrics collection

# 6. Install systemd service (from your local machine)
scp -i ~/dstreambolt-access-key.pem \
  observability/kafka-metrics-collector.service \
  ubuntu@10.0.10.101:/tmp/

ssh ubuntu@10.0.10.101
sudo mv /tmp/kafka-metrics-collector.service /etc/systemd/system/
sudo chmod 644 /etc/systemd/system/kafka-metrics-collector.service
sudo systemctl daemon-reload

# 7. Start and enable service
sudo systemctl enable kafka-metrics-collector.service
sudo systemctl start kafka-metrics-collector.service
sudo systemctl status kafka-metrics-collector.service
```

### Verify Kafka Collector

```bash
# Check service status
ssh ubuntu@10.0.10.101
sudo systemctl status kafka-metrics-collector

# View logs
tail -f /var/log/dstreambolt/kafka-metrics.log

# OR use journalctl
sudo journalctl -u kafka-metrics-collector -f

# Check data in MySQL
mysql -h 10.0.1.61 -u dstreambolt -p'DStreamBolt2025!' dstreambolt_metrics

SELECT * FROM kafka_topic_metrics ORDER BY timestamp DESC LIMIT 5;
SELECT * FROM kafka_consumer_lag ORDER BY timestamp DESC LIMIT 5;
SELECT * FROM kafka_broker_metrics ORDER BY timestamp DESC LIMIT 5;
```

## 🔧 Configuration

### Environment Variables (Optional)

Edit `/etc/systemd/system/kafka-metrics-collector.service` to customize:

```ini
Environment="KAFKA_HOME=/opt/kafka"
Environment="KAFKA_BROKER=localhost:9092"
Environment="MYSQL_HOST=10.0.1.61"
Environment="MYSQL_USER=dstreambolt"
Environment="MYSQL_PASS=DStreamBolt2025!"
Environment="MYSQL_DB=dstreambolt_metrics"
Environment="COLLECTION_INTERVAL=60"  # seconds
```

After changes:
```bash
sudo systemctl daemon-reload
sudo systemctl restart kafka-metrics-collector
```

## 🐛 Troubleshooting

### Kafka Collector Not Starting

**Check Kafka is Running:**
```bash
ssh ubuntu@10.0.10.101
sudo systemctl status kafka
/opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
```

**Check MySQL Connection:**
```bash
mysql -h 10.0.1.61 -u dstreambolt -p'DStreamBolt2025!' -e "SELECT 1"
```

**Check Logs:**
```bash
sudo journalctl -u kafka-metrics-collector -n 50
tail -100 /var/log/dstreambolt/kafka-metrics.log
```

**Test Script Manually:**
```bash
cd /opt/dstreambolt/observability
python3 kafka_metrics_collector.py
```

### Ingestion Service Issues

**Check Service Status:**
```bash
ssh ubuntu@13.201.43.125
sudo systemctl status dstreambolt-ingest
```

**Check Logs:**
```bash
sudo journalctl -u dstreambolt-ingest -f
```

**Test Kafka Connection:**
```bash
nc -zv 10.0.10.101 9092
```

**Test MySQL Connection:**
```bash
mysql -h 10.0.1.61 -u dstreambolt -p'DStreamBolt2025!' dstreambolt_metrics
```

### No Data in MySQL Tables

**For Ingestion Metrics:**
1. Check ingestion service is receiving requests
2. Check MySQL credentials are correct
3. Check tables exist: `SHOW TABLES LIKE '%ingestion%';`

**For Kafka Metrics:**
1. Check collector service is running
2. Check logs for errors
3. Check Kafka commands work manually

## 📊 Monitoring

### Dashboard Queries

Add these to Grafana for real-time monitoring:

**Ingestion Rate:**
```sql
SELECT 
    DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:00') as minute,
    COUNT(*) as requests
FROM ingestion_requests
WHERE timestamp >= NOW() - INTERVAL 1 HOUR
GROUP BY minute
ORDER BY minute;
```

**Kafka Consumer Lag:**
```sql
SELECT 
    consumer_group,
    topic,
    SUM(lag) as total_lag
FROM kafka_consumer_lag
WHERE timestamp >= NOW() - INTERVAL 5 MINUTE
GROUP BY consumer_group, topic
HAVING total_lag > 0
ORDER BY total_lag DESC;
```

**Failed Bundles:**
```sql
SELECT 
    COUNT(*) as failed_count,
    failure_stage,
    error_type
FROM failed_bundles
WHERE timestamp >= NOW() - INTERVAL 1 HOUR
    AND resolved = FALSE
GROUP BY failure_stage, error_type
ORDER BY failed_count DESC;
```

## ✅ Verification Checklist

### Ingestion Service
- [ ] Service running: `sudo systemctl status dstreambolt-ingest`
- [ ] Health endpoint returns 200: `curl http://13.201.43.125:5000/health`
- [ ] Metrics populated in `ingestion_requests` table
- [ ] Kafka writes successful
- [ ] No errors in logs

### Kafka Collector
- [ ] Service running: `sudo systemctl status kafka-metrics-collector`
- [ ] Logs show successful collection
- [ ] Data in `kafka_topic_metrics` table
- [ ] Data in `kafka_consumer_lag` table
- [ ] Collection happens every minute

### End-to-End
- [ ] Send test bundle to ingestion
- [ ] Verify data in Kafka topic
- [ ] Verify metrics in all tables
- [ ] Check Grafana dashboard shows data

## 📈 Performance Tips

1. **Ingestion Service:**
   - Runs on single thread (Flask dev server)
   - For production, use gunicorn: `gunicorn -w 4 -b 0.0.0.0:5000 app:app`

2. **Kafka Collector:**
   - Default: 60 second intervals
   - Adjust `COLLECTION_INTERVAL` if needed
   - Lower = more data, higher MySQL load

3. **MySQL:**
   - Index performance is optimized
   - Consider archiving old data after 7-30 days

## 🔗 Next Steps

1. Deploy optimized ingestion service
2. Deploy Kafka metrics collector
3. Verify data collection
4. Import DevOps dashboard to Grafana
5. Set up alerting rules

---

**Questions?** Check logs first, then review error messages in MySQL `failed_bundles` table.

