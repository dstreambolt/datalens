# Observability Quick Reference Card

## 🚀 Quick Deploy Commands

```bash
# Deploy everything in 3 steps:
cd /Users/skalaise/apps/cloud/terraform/dstream_bolt

# 1. Create tables
cd observability && ./setup_observability.sh

# 2. Deploy Kafka collector (via AWS SSM)
./deploy_kafka_collector.sh i-0bdf20dd0b5e1cc81 ap-south-1

# 3. Deploy optimized ingestion
cd ../ingestion
# Use your existing deployment method or:
scp app_optimized.py ubuntu@13.201.43.125:/opt/dstreambolt-ingest/app.py
ssh ubuntu@13.201.43.125 "sudo systemctl restart dstreambolt-ingest"
```

## 📊 Check Metrics

### Ingestion Metrics
```sql
-- Recent requests
SELECT * FROM ingestion_requests ORDER BY timestamp DESC LIMIT 10;

-- Processing performance
SELECT AVG(total_processing_time_ms), AVG(kafka_write_time_ms) 
FROM bundle_processing WHERE timestamp >= NOW() - INTERVAL 1 HOUR;

-- Failed bundles
SELECT * FROM failed_bundles WHERE resolved = FALSE;

-- Real-time counters
SELECT * FROM ingestion_realtime_metrics;
```

### Kafka Metrics
```sql
-- Topic health
SELECT * FROM kafka_topic_metrics ORDER BY timestamp DESC LIMIT 5;

-- Consumer lag
SELECT consumer_group, topic, SUM(lag) as total_lag 
FROM kafka_consumer_lag 
WHERE timestamp >= NOW() - INTERVAL 5 MINUTE
GROUP BY consumer_group, topic;

-- Broker health
SELECT * FROM kafka_broker_metrics ORDER BY timestamp DESC LIMIT 5;
```

## 🔧 Service Management

### Kafka Collector (runs on i-0bdf20dd0b5e1cc81)
```bash
# Connect via SSM
aws ssm start-session --target i-0bdf20dd0b5e1cc81 --region ap-south-1

# Then inside SSM session:
# Status
sudo systemctl status kafka-metrics-collector

# Logs
tail -f /var/log/dstreambolt/kafka-metrics.log

# Restart
sudo systemctl restart kafka-metrics-collector
```

### Ingestion Service (runs on 13.201.43.125)
```bash
# Status
ssh ubuntu@13.201.43.125 "sudo systemctl status dstreambolt-ingest"

# Test
curl http://13.201.43.125:5000/health
curl http://13.201.43.125:5000/metrics

# Logs
ssh ubuntu@13.201.43.125 "sudo journalctl -u dstreambolt-ingest -f"
```

## 🐛 Troubleshooting Queries

### Find Slow Bundles
```sql
SELECT request_id, total_processing_time_ms, decompression_time_ms, kafka_write_time_ms
FROM bundle_processing 
WHERE total_processing_time_ms > 5000 
ORDER BY timestamp DESC LIMIT 10;
```

### High Consumer Lag
```sql
SELECT consumer_group, topic, partition_id, lag
FROM kafka_consumer_lag 
WHERE lag > 1000 
ORDER BY lag DESC;
```

### Recent Failures
```sql
SELECT failure_stage, error_type, COUNT(*) as count
FROM failed_bundles 
WHERE timestamp >= NOW() - INTERVAL 1 HOUR
GROUP BY failure_stage, error_type
ORDER BY count DESC;
```

### Failed Bundle Details
```sql
SELECT request_id, failure_stage, error_message, bundle_data_sample
FROM failed_bundles 
WHERE resolved = FALSE 
ORDER BY timestamp DESC 
LIMIT 10;
```

## 📈 Key Metrics for Dashboard

### Ingestion Health
```sql
SELECT 
    DATE_FORMAT(timestamp, '%H:%i') as time,
    COUNT(*) as requests,
    AVG(bundle_size_bytes) as avg_size
FROM ingestion_requests 
WHERE timestamp >= NOW() - INTERVAL 1 HOUR
GROUP BY time;
```

### Success vs Failure Rate
```sql
SELECT 
    SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) * 100.0 / COUNT(*) as success_rate
FROM bundle_processing 
WHERE timestamp >= NOW() - INTERVAL 1 HOUR;
```

### Kafka Write Performance
```sql
SELECT 
    AVG(records_successful) as avg_successful,
    AVG(records_failed) as avg_failed,
    AVG(write_time_ms) as avg_write_time
FROM kafka_production_metrics 
WHERE timestamp >= NOW() - INTERVAL 1 HOUR;
```

## 🎯 Files & Locations

| Component | Location | Service Name |
|-----------|----------|--------------|
| Optimized Ingestion | ingestion/app_optimized.py | dstreambolt-ingest |
| Kafka Collector | observability/kafka_metrics_collector.py | kafka-metrics-collector |
| Collector Service | /etc/systemd/system/kafka-metrics-collector.service | - |
| Collector Logs | /var/log/dstreambolt/kafka-metrics.log | - |
| SQL Schema | observability/create_observability_tables.sql | - |

## ⚡ Quick Tests

```bash
# Test ingestion
curl -X POST http://13.201.43.125:5000/ingest \
  -H "Content-Type: application/gzip" \
  --data-binary @test.gz

# Check it worked
mysql -h 10.0.1.61 -u dstreambolt -p'DStreamBolt2025!' dstreambolt_metrics \
  -e "SELECT * FROM ingestion_requests ORDER BY timestamp DESC LIMIT 1;"

# Check Kafka lag
mysql -h 10.0.1.61 -u dstreambolt -p'DStreamBolt2025!' dstreambolt_metrics \
  -e "SELECT * FROM kafka_consumer_lag ORDER BY timestamp DESC LIMIT 5;"
```

---

**Full Documentation:** `observability/DEPLOYMENT_INSTRUCTIONS.md`

