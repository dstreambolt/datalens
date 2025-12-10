# Observability Tables - Quick Reference

## ✅ Correct Table Names

### Ingestion Layer Tables
```
ingestion_requests          - Every HTTP request received
bundle_processing           - Detailed bundle processing metrics  
kafka_production_metrics    - Kafka write operations
failed_bundles              - Failed bundles with error context
ingestion_realtime_metrics  - Real-time counter values
```

### Kafka Health Tables
```
kafka_topic_metrics         - Topic configuration and health
kafka_consumer_lag          - Consumer lag by partition
kafka_broker_metrics        - Broker performance
```

### Spark Processing Tables
```
spark_processing_metrics    - Batch/streaming job metrics
spark_failed_records        - Failed record tracking
spark_job_status            - Job health monitoring
```

### Aggregated Views
```
pipeline_health_1min        - 1-minute aggregated metrics
error_summary               - Error patterns and counts
```

## 🔍 Example Queries

### Ingestion Metrics
```sql
-- Requests in last hour
SELECT COUNT(*) FROM ingestion_requests 
WHERE timestamp >= NOW() - INTERVAL 1 HOUR;

-- Success rate
SELECT 
  SUM(CASE WHEN http_status = 201 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) as success_rate
FROM ingestion_requests 
WHERE timestamp >= NOW() - INTERVAL 1 HOUR;

-- Processing performance
SELECT 
  AVG(total_processing_time_ms) as avg_time,
  MAX(total_processing_time_ms) as max_time
FROM bundle_processing 
WHERE timestamp >= NOW() - INTERVAL 1 HOUR;
```

### Kafka Metrics
```sql
-- Consumer lag
SELECT 
  consumer_group, 
  topic, 
  SUM(lag) as total_lag
FROM kafka_consumer_lag 
WHERE timestamp >= NOW() - INTERVAL 5 MINUTE
GROUP BY consumer_group, topic;

-- Records written vs failed
SELECT 
  SUM(records_successful) as successful,
  SUM(records_failed) as failed
FROM kafka_production_metrics 
WHERE timestamp >= NOW() - INTERVAL 1 HOUR;
```

### Failed Operations
```sql
-- Recent failures
SELECT * FROM failed_bundles 
WHERE resolved = FALSE 
ORDER BY timestamp DESC 
LIMIT 10;

-- Failures by stage
SELECT 
  failure_stage, 
  COUNT(*) as count 
FROM failed_bundles 
WHERE timestamp >= NOW() - INTERVAL 1 HOUR
GROUP BY failure_stage;
```

### Real-Time Metrics
```sql
-- Current counters
SELECT * FROM ingestion_realtime_metrics;
```

## ❌ Deprecated Table Names (DO NOT USE)

These tables DO NOT exist:
```
❌ log_metrics
❌ status_summary  
❌ spark_results
❌ kafka_metrics
```

## 🎯 Dashboard Panel Queries

### Panel: Requests Per Minute
```sql
SELECT 
  DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:00') as time,
  COUNT(*) as value 
FROM ingestion_requests 
WHERE timestamp >= NOW() - INTERVAL 1 HOUR 
GROUP BY time 
ORDER BY time;
```

### Panel: Success vs Failed (Pie Chart)
```sql
SELECT 
  CASE WHEN http_status = 201 THEN 'Success' ELSE 'Failed' END as metric,
  COUNT(*) as value 
FROM ingestion_requests 
WHERE timestamp >= NOW() - INTERVAL 1 HOUR 
GROUP BY metric;
```

### Panel: Processing Time
```sql
SELECT 
  DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:00') as time,
  AVG(total_processing_time_ms) as avg_time,
  MAX(total_processing_time_ms) as max_time 
FROM bundle_processing 
WHERE timestamp >= NOW() - INTERVAL 1 HOUR 
GROUP BY time 
ORDER BY time;
```

### Panel: Consumer Lag by Topic
```sql
SELECT 
  DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:00') as time,
  topic,
  SUM(lag) as value 
FROM kafka_consumer_lag 
WHERE timestamp >= NOW() - INTERVAL 1 HOUR 
GROUP BY time, topic 
ORDER BY time;
```

### Panel: Failed Bundles Table
```sql
SELECT 
  timestamp,
  request_id,
  failure_stage,
  error_type,
  LEFT(error_message, 100) as error 
FROM failed_bundles 
WHERE timestamp >= NOW() - INTERVAL 1 HOUR 
ORDER BY timestamp DESC 
LIMIT 10;
```

## 📝 Notes

- All timestamps are in UTC
- Use `NOW() - INTERVAL X HOUR/MINUTE` for time ranges
- Real-time metrics table has cumulative counters
- Failed records have `resolved` flag for tracking fixes
- Use `DATE_FORMAT()` for time series grouping in Grafana

---

**Created:** December 10, 2025  
**Schema Version:** v1.0  
**See:** `observability/create_observability_tables.sql` for full schema

