# DStreamBolt Complete Observability Implementation Guide

## 🎯 Overview

This guide implements comprehensive observability across:
1. **Ingestion Layer** - Request tracking, bundle processing, Kafka writes
2. **Kafka Metrics** - Topic health, consumer lag, throughput  
3. **Spark Processing** - Records processed, skipped, failed
4. **DevOps Dashboard** - Complete visibility for production troubleshooting

## 📊 New MySQL Tables

### 1. Ingestion Layer Tables

```sql
-- 1.1 Ingestion Requests (every incoming HTTP request)
CREATE TABLE ingestion_requests (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    request_id VARCHAR(255) NOT NULL,
    timestamp TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP(3),
    source_ip VARCHAR(45),
    user_agent VARCHAR(500),
    content_type VARCHAR(100),
    bundle_size_bytes INT,
    http_status INT,
    processing_stage VARCHAR(50),
    INDEX(request_id),
    INDEX(timestamp),
    INDEX(http_status)
) COMMENT='Captures every incoming HTTP request';

-- 1.2 Bundle Processing (detailed processing metrics)
CREATE TABLE bundle_processing (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    request_id VARCHAR(255) NOT NULL,
    timestamp TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP(3),
    bundle_size_bytes INT NOT NULL,
    uncompressed_size_bytes INT,
    decompression_time_ms INT,
    total_lines INT,
    valid_lines INT,
    invalid_lines INT,
    kafka_write_time_ms INT,
    total_processing_time_ms INT,
    status VARCHAR(50) NOT NULL,
    INDEX(request_id),
    INDEX(timestamp),
    INDEX(status)
) COMMENT='Detailed bundle processing metrics';

-- 1.3 Kafka Production Metrics
CREATE TABLE kafka_production_metrics (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    request_id VARCHAR(255) NOT NULL,
    timestamp TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP(3),
    topic VARCHAR(255) NOT NULL,
    records_attempted INT NOT NULL,
    records_successful INT NOT NULL,
    records_failed INT NOT NULL,
    write_time_ms INT,
    avg_record_size_bytes INT,
    kafka_errors TEXT,
    INDEX(request_id),
    INDEX(timestamp),
    INDEX(topic)
) COMMENT='Kafka production success/failure tracking';

-- 1.4 Failed Bundles (comprehensive failure tracking)
CREATE TABLE failed_bundles (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    request_id VARCHAR(255) NOT NULL,
    timestamp TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP(3),
    failure_stage VARCHAR(50) NOT NULL,
    error_type VARCHAR(100),
    error_message TEXT,
    bundle_size_bytes INT,
    source_ip VARCHAR(45),
    retry_count INT DEFAULT 0,
    bundle_data_sample TEXT,
    stack_trace TEXT,
    resolved BOOLEAN DEFAULT FALSE,
    resolved_at TIMESTAMP NULL,
    INDEX(request_id),
    INDEX(timestamp),
    INDEX(failure_stage),
    INDEX(resolved)
) COMMENT='Failed bundles with full error context for troubleshooting';

-- 1.5 Ingestion Real-time Metrics
CREATE TABLE ingestion_realtime_metrics (
    id INT AUTO_INCREMENT PRIMARY KEY,
    metric_name VARCHAR(100) NOT NULL UNIQUE,
    metric_value BIGINT NOT NULL,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) COMMENT='Real-time ingestion counters for dashboard';
```

### 2. Kafka Health Tables

```sql
-- 2.1 Kafka Topic Metrics
CREATE TABLE kafka_topic_metrics (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    topic VARCHAR(255) NOT NULL,
    partition_count INT,
    replication_factor INT,
    message_count BIGINT,
    total_size_bytes BIGINT,
    messages_per_sec DECIMAL(10,2),
    bytes_in_per_sec BIGINT,
    bytes_out_per_sec BIGINT,
    INDEX(timestamp),
    INDEX(topic)
) COMMENT='Kafka topic health and throughput metrics';

-- 2.2 Kafka Consumer Lag
CREATE TABLE kafka_consumer_lag (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    consumer_group VARCHAR(255) NOT NULL,
    topic VARCHAR(255) NOT NULL,
    partition_id INT NOT NULL,
    current_offset BIGINT,
    log_end_offset BIGINT,
    lag BIGINT,
    INDEX(timestamp),
    INDEX(consumer_group),
    INDEX(topic)
) COMMENT='Consumer lag monitoring for each partition';

-- 2.3 Kafka Broker Metrics
CREATE TABLE kafka_broker_metrics (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    broker_id INT,
    broker_host VARCHAR(255),
    requests_per_sec DECIMAL(10,2),
    bytes_in_per_sec BIGINT,
    bytes_out_per_sec BIGINT,
    active_connections INT,
    INDEX(timestamp),
    INDEX(broker_id)
) COMMENT='Kafka broker health metrics';
```

### 3. Spark Processing Tables

```sql
-- 3.1 Spark Batch/Stream Processing Metrics
CREATE TABLE spark_processing_metrics (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    job_id VARCHAR(255) NOT NULL,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    processing_mode VARCHAR(20),
    batch_id BIGINT,
    records_read BIGINT NOT NULL,
    records_processed BIGINT NOT NULL,
    records_written BIGINT NOT NULL,
    records_skipped BIGINT NOT NULL,
    records_failed BIGINT NOT NULL,
    processing_time_ms BIGINT,
    kafka_read_time_ms BIGINT,
    transformation_time_ms BIGINT,
    mysql_write_time_ms BIGINT,
    INDEX(job_id),
    INDEX(timestamp),
    INDEX(processing_mode)
) COMMENT='Spark processing metrics per batch/micro-batch';

-- 3.2 Spark Failed Records
CREATE TABLE spark_failed_records (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    job_id VARCHAR(255) NOT NULL,
    batch_id BIGINT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    failure_stage VARCHAR(50),
    record_data TEXT,
    error_type VARCHAR(100),
    error_message TEXT,
    stack_trace TEXT,
    INDEX(job_id),
    INDEX(timestamp),
    INDEX(failure_stage)
) COMMENT='Failed Spark records for debugging';

-- 3.3 Spark Job Status
CREATE TABLE spark_job_status (
    id INT AUTO_INCREMENT PRIMARY KEY,
    job_id VARCHAR(255) NOT NULL UNIQUE,
    job_name VARCHAR(255),
    processing_mode VARCHAR(20),
    status VARCHAR(50),
    started_at TIMESTAMP,
    last_heartbeat TIMESTAMP,
    total_batches_processed BIGINT DEFAULT 0,
    total_records_processed BIGINT DEFAULT 0,
    total_errors BIGINT DEFAULT 0,
    INDEX(job_id),
    INDEX(status)
) COMMENT='Current Spark job status and health';
```

### 4. DevOps Dashboard Aggregations

```sql
-- 4.1 Pipeline Health Summary (1-minute aggregations)
CREATE TABLE pipeline_health_1min (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    minute_timestamp TIMESTAMP NOT NULL,
    layer VARCHAR(50) NOT NULL,
    requests_received BIGINT,
    requests_successful BIGINT,
    requests_failed BIGINT,
    avg_processing_time_ms INT,
    p95_processing_time_ms INT,
    p99_processing_time_ms INT,
    error_rate_percent DECIMAL(5,2),
    throughput_per_sec DECIMAL(10,2),
    INDEX(minute_timestamp),
    INDEX(layer),
    UNIQUE KEY(minute_timestamp, layer)
) COMMENT='1-minute aggregated metrics per pipeline layer';

-- 4.2 Error Summary
CREATE TABLE error_summary (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    layer VARCHAR(50),
    error_type VARCHAR(100),
    error_count INT,
    sample_error_message TEXT,
    INDEX(timestamp),
    INDEX(layer),
    INDEX(error_type)
) COMMENT='Error aggregations for troubleshooting';
```

## 🔧 Kafka Metrics Collection Script

Create `/opt/dstreambolt/scripts/collect_kafka_metrics.py`:

```python
#!/usr/bin/env python3
"""
Kafka metrics collector for DStreamBolt
Collects topic, consumer lag, and broker metrics
"""
import subprocess
import json
import pymysql
from datetime import datetime
import time

KAFKA_HOME = "/opt/kafka"
KAFKA_BROKER = "localhost:9092"
MYSQL_HOST = "10.0.1.61"
MYSQL_USER = "dstreambolt"
MYSQL_PASS = "DStreamBolt2025!"
MYSQL_DB = "dstreambolt_metrics"

def get_db_connection():
    return pymysql.connect(
        host=MYSQL_HOST,
        user=MYSQL_USER,
        password=MYSQL_PASS,
        database=MYSQL_DB,
        autocommit=True
    )

def collect_topic_metrics():
    """Collect metrics for all topics"""
    try:
        # List topics
        result = subprocess.run(
            [f"{KAFKA_HOME}/bin/kafka-topics.sh", "--bootstrap-server", KAFKA_BROKER, "--list"],
            capture_output=True, text=True
        )
        topics = result.stdout.strip().split('\n')
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        for topic in topics:
            if not topic:
                continue
                
            # Get topic details
            result = subprocess.run(
                [f"{KAFKA_HOME}/bin/kafka-topics.sh", "--bootstrap-server", KAFKA_BROKER, 
                 "--describe", "--topic", topic],
                capture_output=True, text=True
            )
            
            # Parse output (simplified - enhance as needed)
            lines = result.stdout.strip().split('\n')
            if len(lines) > 0:
                # Extract partition count and replication factor
                partition_count = len([l for l in lines if 'Partition' in l])
                
                cursor.execute("""
                    INSERT INTO kafka_topic_metrics 
                    (topic, partition_count, replication_factor)
                    VALUES (%s, %s, %s)
                """, (topic, partition_count, 1))
        
        conn.close()
        print(f"✅ Collected metrics for {len(topics)} topics")
    except Exception as e:
        print(f"❌ Failed to collect topic metrics: {e}")

def collect_consumer_lag():
    """Collect consumer lag metrics"""
    try:
        # Get consumer groups
        result = subprocess.run(
            [f"{KAFKA_HOME}/bin/kafka-consumer-groups.sh", "--bootstrap-server", KAFKA_BROKER, "--list"],
            capture_output=True, text=True
        )
        groups = result.stdout.strip().split('\n')
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        for group in groups:
            if not group:
                continue
            
            # Get group details
            result = subprocess.run(
                [f"{KAFKA_HOME}/bin/kafka-consumer-groups.sh", "--bootstrap-server", KAFKA_BROKER,
                 "--describe", "--group", group],
                capture_output=True, text=True
            )
            
            lines = result.stdout.strip().split('\n')[1:]  # Skip header
            for line in lines:
                parts = line.split()
                if len(parts) >= 6:
                    topic = parts[0]
                    partition = int(parts[1])
                    current_offset = int(parts[2]) if parts[2].isdigit() else 0
                    log_end_offset = int(parts[3]) if parts[3].isdigit() else 0
                    lag = int(parts[4]) if parts[4].isdigit() else 0
                    
                    cursor.execute("""
                        INSERT INTO kafka_consumer_lag
                        (consumer_group, topic, partition_id, current_offset, log_end_offset, lag)
                        VALUES (%s, %s, %s, %s, %s, %s)
                    """, (group, topic, partition, current_offset, log_end_offset, lag))
        
        conn.close()
        print(f"✅ Collected consumer lag for {len(groups)} groups")
    except Exception as e:
        print(f"❌ Failed to collect consumer lag: {e}")

if __name__ == "__main__":
    while True:
        print(f"🔍 Collecting Kafka metrics at {datetime.now()}")
        collect_topic_metrics()
        collect_consumer_lag()
        time.sleep(60)  # Collect every minute
```

## 📊 Enhanced Grafana Dashboard

The DevOps dashboard will include:

### Panel 1: Pipeline Health Overview
- Requests/sec across all layers (Ingestion → Kafka → Spark)
- Success/failure rates
- End-to-end latency

### Panel 2: Ingestion Layer Metrics
- Total requests received
- Bundle processing rate
- Kafka write success/failure
- Average processing time
- Failed bundles (with drill-down)

### Panel 3: Kafka Health
- Topic message rates
- Consumer lag by group
- Partition distribution
- Broker throughput

### Panel 4: Spark Processing
- Records processed/sec
- Records skipped/failed
- Batch processing time
- MySQL write performance

### Panel 5: Error Tracking
- Top errors by layer
- Failed bundles table
- Failed records table
- Error rate trends

### Panel 6: System Resources
- Memory usage by service
- CPU usage
- Disk I/O
- Network throughput

## 🚀 Implementation Steps

See `COMPLETE_OBSERVABILITY_SETUP.md` for detailed implementation steps.

## 📞 Troubleshooting with New Metrics

### Issue: Ingestion Service Slow

```sql
-- Check bundle processing times
SELECT 
    DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:00') as minute,
    COUNT(*) as bundles,
    AVG(total_processing_time_ms) as avg_time_ms,
    AVG(decompression_time_ms) as avg_decomp_ms,
    AVG(kafka_write_time_ms) as avg_kafka_ms
FROM bundle_processing
WHERE timestamp >= NOW() - INTERVAL 1 HOUR
GROUP BY minute
ORDER BY minute DESC;
```

### Issue: Kafka Consumer Lag Growing

```sql
-- Check current lag
SELECT 
    consumer_group,
    topic,
    SUM(lag) as total_lag,
    AVG(lag) as avg_lag_per_partition
FROM kafka_consumer_lag
WHERE timestamp >= NOW() - INTERVAL 5 MINUTE
GROUP BY consumer_group, topic
HAVING total_lag > 1000
ORDER BY total_lag DESC;
```

### Issue: Spark Job Failing

```sql
-- Check Spark failures
SELECT 
    job_id,
    batch_id,
    records_read,
    records_processed,
    records_failed,
    processing_time_ms
FROM spark_processing_metrics
WHERE records_failed > 0
ORDER BY timestamp DESC
LIMIT 20;

-- Get failure details
SELECT * FROM spark_failed_records
WHERE timestamp >= NOW() - INTERVAL 1 HOUR
ORDER BY timestamp DESC;
```

### Issue: Failed Bundles Need Investigation

```sql
-- Get failed bundles with context
SELECT 
    request_id,
    timestamp,
    failure_stage,
    error_type,
    error_message,
    bundle_size_bytes,
    source_ip,
    bundle_data_sample
FROM failed_bundles
WHERE timestamp >= NOW() - INTERVAL 1 HOUR
    AND resolved = FALSE
ORDER BY timestamp DESC;
```

## 📈 Next Steps

1. Run setup scripts to create all new tables
2. Deploy enhanced ingestion service
3. Start Kafka metrics collector
4. Update Spark code with metrics tracking
5. Import DevOps dashboard to Grafana
6. Set up alerting rules

---

**Complete observability implementation continues in additional files...**

