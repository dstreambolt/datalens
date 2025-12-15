# DataLens Observability & Monitoring Guide

## 📊 Complete Visibility into Your Data Pipeline

This guide covers monitoring every component of DataLens to ensure:
- ✅ All log lines are processed
- ✅ No data loss
- ✅ Performance is optimal
- ✅ Issues are detected before they impact users

---

## Table of Contents

1. [Monitoring Architecture](#monitoring-architecture)
2. [Processing Metrics](#processing-metrics)
3. [Data Quality Metrics](#data-quality-metrics)
4. [Grafana Dashboards](#grafana-dashboards)
5. [Alerting Rules](#alerting-rules)
6. [Troubleshooting Guide](#troubleshooting-guide)

---

## 1. Monitoring Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   Data Processing Pipeline                   │
│                                                              │
│  S3 → Spark → Kafka → TimescaleDB                          │
│         │       │         │                                 │
│         └───────┴─────────┴───── Metrics Collection         │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
        ┌─────────────────────────────────────┐
        │   TimescaleDB (Metrics Storage)     │
        │                                      │
        │  Tables:                             │
        │  • processing_metrics                │
        │  • data_quality_metrics              │
        │  • job_status                        │
        │  • system_health                     │
        └─────────────────┬────────────────────┘
                          │
                          ▼
        ┌─────────────────────────────────────┐
        │        Grafana Dashboards            │
        │                                      │
        │  • Processing Overview               │
        │  • Data Quality                      │
        │  • System Health                     │
        │  • Alert Dashboard                   │
        └──────────────────────────────────────┘
```

---

## 2. Processing Metrics

### Metrics Tracked

Every Spark job records:

```python
{
    "job_id": "job_1702512000",
    "timestamp": "2024-12-14T12:00:00Z",
    "stage": "processing",
    
    # Line counts
    "lines_read": 10000000,           # From S3
    "lines_processed": 9995000,       # Valid records
    "lines_stored": 9995000,          # Written to TimescaleDB
    "lines_failed": 5000,             # Invalid/rejected
    
    # Performance
    "processing_duration_ms": 45000,  # 45 seconds
    "throughput_lines_per_sec": 222222,
    
    # Data quality
    "quality_score": 99.95,           # Percentage
    "error_rate": 0.05,
    
    # Resource usage
    "memory_used_mb": 4096,
    "cpu_usage_percent": 75,
    
    # Source
    "s3_path": "s3://bucket/logs/2024/12/14/",
    "partition_date": "2024-12-14",
    
    # Errors
    "error_message": null,
    "error_count": 0
}
```

### Schema: `processing_metrics` Table

```sql
CREATE TABLE processing_metrics (
    id SERIAL PRIMARY KEY,
    
    -- Job identification
    job_id VARCHAR(100) NOT NULL,
    timestamp TIMESTAMPTZ NOT NULL,
    stage VARCHAR(50),
    
    -- Line counts
    lines_read BIGINT DEFAULT 0,
    lines_processed BIGINT DEFAULT 0,
    lines_stored BIGINT DEFAULT 0,
    lines_failed BIGINT DEFAULT 0,
    
    -- Calculated metrics
    success_rate NUMERIC(5,2),         -- Percentage
    throughput_lines_per_sec BIGINT,
    
    -- Performance
    processing_duration_ms BIGINT,
    memory_used_mb INT,
    cpu_usage_percent NUMERIC(5,2),
    
    -- Source info
    s3_path TEXT,
    partition_date DATE,
    
    -- Errors
    error_message TEXT,
    error_count INT DEFAULT 0,
    
    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Convert to hypertable for time-series optimization
SELECT create_hypertable('processing_metrics', 'timestamp');

-- Indexes
CREATE INDEX idx_proc_job_id ON processing_metrics(job_id);
CREATE INDEX idx_proc_date ON processing_metrics(partition_date);
CREATE INDEX idx_proc_timestamp ON processing_metrics(timestamp DESC);
```

### Key Queries

**1. Current Processing Status**
```sql
SELECT
    job_id,
    timestamp,
    lines_read,
    lines_processed,
    lines_stored,
    lines_failed,
    success_rate,
    processing_duration_ms,
    CASE 
        WHEN error_count > 0 THEN '❌ Errors'
        WHEN success_rate < 95 THEN '⚠️ Warning'
        ELSE '✅ OK'
    END AS status
FROM processing_metrics
WHERE timestamp > NOW() - INTERVAL '1 hour'
ORDER BY timestamp DESC
LIMIT 10;
```

**2. Hourly Processing Summary**
```sql
SELECT
    time_bucket('1 hour', timestamp) AS hour,
    COUNT(*) AS job_count,
    SUM(lines_read) AS total_lines_read,
    SUM(lines_processed) AS total_lines_processed,
    SUM(lines_stored) AS total_lines_stored,
    SUM(lines_failed) AS total_lines_failed,
    AVG(success_rate) AS avg_success_rate,
    AVG(processing_duration_ms) AS avg_duration_ms,
    SUM(error_count) AS total_errors
FROM processing_metrics
WHERE timestamp > NOW() - INTERVAL '24 hours'
GROUP BY hour
ORDER BY hour DESC;
```

**3. Data Loss Detection**
```sql
-- Alert if lines_read != lines_processed + lines_failed
SELECT
    job_id,
    timestamp,
    lines_read,
    lines_processed,
    lines_failed,
    (lines_read - lines_processed - lines_failed) AS missing_lines,
    CASE
        WHEN (lines_read - lines_processed - lines_failed) > 0 THEN '🚨 DATA LOSS'
        ELSE '✅ OK'
    END AS status
FROM processing_metrics
WHERE timestamp > NOW() - INTERVAL '1 hour'
    AND (lines_read - lines_processed - lines_failed) != 0
ORDER BY timestamp DESC;
```

**4. Failed Lines Analysis**
```sql
SELECT
    DATE(partition_date) AS date,
    COUNT(*) AS jobs_with_failures,
    SUM(lines_failed) AS total_failed_lines,
    AVG(lines_failed) AS avg_failed_per_job,
    MAX(lines_failed) AS max_failed_single_job
FROM processing_metrics
WHERE lines_failed > 0
    AND timestamp > NOW() - INTERVAL '7 days'
GROUP BY DATE(partition_date)
ORDER BY date DESC;
```

**5. Performance Trends**
```sql
SELECT
    DATE(timestamp) AS date,
    COUNT(*) AS total_jobs,
    SUM(lines_processed) AS total_lines,
    AVG(throughput_lines_per_sec) AS avg_throughput,
    AVG(processing_duration_ms) AS avg_duration_ms,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY processing_duration_ms) AS p95_duration_ms
FROM processing_metrics
WHERE timestamp > NOW() - INTERVAL '30 days'
GROUP BY DATE(timestamp)
ORDER BY date DESC;
```

---

## 3. Data Quality Metrics

### Quality Checks

The processor performs these validations:

```python
# 1. Missing critical fields
dq_missing_ip = when(col("cli_ip").isNull(), 1).otherwise(0)

# 2. Invalid status codes
dq_invalid_status = when(
    (col("http_status_code") < 100) | 
    (col("http_status_code") > 599), 
    1
).otherwise(0)

# 3. Negative byte counts
dq_negative_bytes = when(col("bytes") < 0, 1).otherwise(0)

# 4. Future timestamps
dq_future_timestamp = when(
    col("req_time_sec") > unix_timestamp(), 
    1
).otherwise(0)

# 5. Invalid geolocation
dq_invalid_geo = when(
    col("country").isNull() & col("cli_ip").isNotNull(),
    1
).otherwise(0)

# Calculate quality score (0-100)
quality_score = lit(100) - (
    dq_missing_ip + 
    dq_invalid_status + 
    dq_negative_bytes + 
    dq_future_timestamp + 
    dq_invalid_geo
) * 20
```

### Schema: `data_quality_metrics` Table

```sql
CREATE TABLE data_quality_metrics (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL,
    
    -- Job reference
    job_id VARCHAR(100),
    partition_date DATE,
    
    -- Quality dimensions
    metric_name VARCHAR(100),     -- e.g., 'missing_ip', 'invalid_status'
    failed_count BIGINT,          -- Number of records failing check
    total_count BIGINT,           -- Total records checked
    failure_rate NUMERIC(5,2),    -- Percentage
    
    -- Sample failed records (for investigation)
    sample_failed_records JSONB,
    
    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW()
);

SELECT create_hypertable('data_quality_metrics', 'timestamp');

CREATE INDEX idx_dq_timestamp ON data_quality_metrics(timestamp DESC);
CREATE INDEX idx_dq_metric ON data_quality_metrics(metric_name, timestamp DESC);
```

### Quality Queries

**1. Overall Data Quality**
```sql
SELECT
    DATE(timestamp) AS date,
    AVG(
        CASE WHEN metric_name = 'quality_score' 
        THEN 100 - failure_rate 
        ELSE NULL END
    ) AS avg_quality_score,
    SUM(failed_count) AS total_failures
FROM data_quality_metrics
WHERE timestamp > NOW() - INTERVAL '7 days'
GROUP BY DATE(timestamp)
ORDER BY date DESC;
```

**2. Quality by Dimension**
```sql
SELECT
    metric_name,
    COUNT(*) AS occurrences,
    SUM(failed_count) AS total_failed,
    AVG(failure_rate) AS avg_failure_rate,
    MAX(failure_rate) AS max_failure_rate
FROM data_quality_metrics
WHERE timestamp > NOW() - INTERVAL '24 hours'
GROUP BY metric_name
ORDER BY total_failed DESC;
```

**3. Quality Trend**
```sql
SELECT
    time_bucket('1 hour', timestamp) AS hour,
    metric_name,
    AVG(failure_rate) AS avg_failure_rate
FROM data_quality_metrics
WHERE timestamp > NOW() - INTERVAL '24 hours'
    AND metric_name IN ('missing_ip', 'invalid_status', 'negative_bytes')
GROUP BY hour, metric_name
ORDER BY hour DESC, metric_name;
```

---

## 4. Grafana Dashboards

### Dashboard 1: Processing Overview

**Panels:**

1. **Total Lines Processed (Today)**
   ```sql
   SELECT SUM(lines_processed) 
   FROM processing_metrics 
   WHERE timestamp > CURRENT_DATE;
   ```
   Display: Single Stat (large number)

2. **Success Rate (24h)**
   ```sql
   SELECT AVG(success_rate) 
   FROM processing_metrics 
   WHERE timestamp > NOW() - INTERVAL '24 hours';
   ```
   Display: Gauge (0-100%)

3. **Lines Processed Over Time**
   ```sql
   SELECT
       time_bucket('5 minutes', timestamp) AS time,
       SUM(lines_processed) AS lines
   FROM processing_metrics
   WHERE $__timeFilter(timestamp)
   GROUP BY time
   ORDER BY time;
   ```
   Display: Time series graph

4. **Failed Lines**
   ```sql
   SELECT
       time_bucket('5 minutes', timestamp) AS time,
       SUM(lines_failed) AS failed
   FROM processing_metrics
   WHERE $__timeFilter(timestamp)
   GROUP BY time
   ORDER BY time;
   ```
   Display: Bar chart (red)

5. **Processing Duration**
   ```sql
   SELECT
       time_bucket('5 minutes', timestamp) AS time,
       AVG(processing_duration_ms) / 1000 AS avg_duration_sec
   FROM processing_metrics
   WHERE $__timeFilter(timestamp)
   GROUP BY time
   ORDER BY time;
   ```
   Display: Line graph

6. **Current Jobs Status**
   ```sql
   SELECT
       job_id,
       timestamp,
       lines_processed,
       success_rate,
       CASE
           WHEN error_count > 0 THEN 'Error'
           WHEN success_rate < 95 THEN 'Warning'
           ELSE 'OK'
       END AS status
   FROM processing_metrics
   WHERE timestamp > NOW() - INTERVAL '1 hour'
   ORDER BY timestamp DESC
   LIMIT 10;
   ```
   Display: Table

### Dashboard 2: Data Quality

**Panels:**

1. **Quality Score (Current)**
   ```sql
   SELECT AVG(quality_score) 
   FROM (
       SELECT 
           job_id,
           (100 - (SUM(failed_count) * 100.0 / SUM(total_count))) AS quality_score
       FROM data_quality_metrics
       WHERE timestamp > NOW() - INTERVAL '1 hour'
       GROUP BY job_id
   ) AS scores;
   ```
   Display: Gauge (0-100%)

2. **Quality Issues by Type**
   ```sql
   SELECT
       metric_name AS metric,
       SUM(failed_count) AS count
   FROM data_quality_metrics
   WHERE timestamp > NOW() - INTERVAL '24 hours'
   GROUP BY metric_name
   ORDER BY count DESC;
   ```
   Display: Pie chart

3. **Quality Trend**
   ```sql
   SELECT
       time_bucket('1 hour', timestamp) AS time,
       metric_name,
       AVG(failure_rate) AS failure_rate
   FROM data_quality_metrics
   WHERE $__timeFilter(timestamp)
   GROUP BY time, metric_name
   ORDER BY time;
   ```
   Display: Multi-line graph

### Dashboard 3: System Health

**Panels:**

1. **Spark Jobs (Active)**
   Query Kubernetes API for running Spark jobs

2. **Kafka Consumer Lag**
   ```sql
   SELECT
       consumer_group,
       topic,
       partition,
       lag
   FROM kafka_consumer_lag
   WHERE lag > 1000
   ORDER BY lag DESC;
   ```

3. **TimescaleDB Size**
   ```sql
   SELECT
       pg_size_pretty(pg_database_size('datalens_metrics')) AS size;
   ```

4. **S3 Storage Growth**
   Query AWS CloudWatch metrics

---

## 5. Alerting Rules

### Critical Alerts (PagerDuty)

**1. Data Loss Detected**
```sql
-- Trigger if any lines are unaccounted for
SELECT COUNT(*) 
FROM processing_metrics
WHERE timestamp > NOW() - INTERVAL '5 minutes'
    AND (lines_read - lines_processed - lines_failed) > 0;
```
Threshold: > 0
Action: Page on-call engineer

**2. Processing Failure**
```sql
-- Trigger if job fails
SELECT COUNT(*)
FROM processing_metrics
WHERE timestamp > NOW() - INTERVAL '5 minutes'
    AND error_count > 0;
```
Threshold: > 0
Action: Page on-call engineer

**3. Success Rate Drop**
```sql
-- Trigger if success rate drops below 90%
SELECT AVG(success_rate)
FROM processing_metrics
WHERE timestamp > NOW() - INTERVAL '15 minutes';
```
Threshold: < 90%
Action: Page on-call engineer

### Warning Alerts (Slack)

**1. Slow Processing**
```sql
-- Trigger if processing takes > 2x normal time
SELECT AVG(processing_duration_ms)
FROM processing_metrics
WHERE timestamp > NOW() - INTERVAL '15 minutes';
```
Threshold: > 120000 (2 minutes)
Action: Notify team Slack channel

**2. High Failure Rate**
```sql
-- Trigger if > 1% of lines fail
SELECT AVG(lines_failed * 100.0 / lines_read)
FROM processing_metrics
WHERE timestamp > NOW() - INTERVAL '30 minutes';
```
Threshold: > 1%
Action: Notify team Slack channel

**3. Quality Score Drop**
```sql
-- Trigger if quality score < 95%
SELECT AVG(quality_score)
FROM (
    SELECT 
        job_id,
        (100 - (SUM(failed_count) * 100.0 / SUM(total_count))) AS quality_score
    FROM data_quality_metrics
    WHERE timestamp > NOW() - INTERVAL '1 hour'
    GROUP BY job_id
) AS scores;
```
Threshold: < 95%
Action: Notify team Slack channel

### Info Alerts (Email)

**1. Daily Processing Report**
```sql
-- Send daily summary at 9 AM
SELECT
    DATE(timestamp) AS date,
    SUM(lines_read) AS total_read,
    SUM(lines_processed) AS total_processed,
    SUM(lines_stored) AS total_stored,
    SUM(lines_failed) AS total_failed,
    AVG(success_rate) AS avg_success_rate,
    COUNT(*) AS total_jobs
FROM processing_metrics
WHERE timestamp >= CURRENT_DATE - INTERVAL '1 day'
    AND timestamp < CURRENT_DATE
GROUP BY DATE(timestamp);
```
Schedule: Daily at 9 AM
Action: Email to team

---

## 6. Troubleshooting Guide

### Problem: Lines Processed < Lines Read

**Symptom:**
```sql
SELECT * FROM processing_metrics
WHERE lines_processed < lines_read - lines_failed
ORDER BY timestamp DESC LIMIT 1;
```

**Possible Causes:**
1. Data validation failures
2. Parsing errors
3. Schema mismatches

**Investigation:**
```sql
-- Check error messages
SELECT error_message 
FROM processing_metrics 
WHERE job_id = '<job_id>';

-- Check data quality metrics
SELECT * FROM data_quality_metrics
WHERE job_id = '<job_id>';

-- Review failed records
SELECT sample_failed_records
FROM data_quality_metrics
WHERE job_id = '<job_id>' 
    AND failed_count > 0;
```

**Resolution:**
- Review and fix data quality issues
- Update schema if format changed
- Reprocess failed batch

### Problem: Slow Processing

**Symptom:**
```sql
SELECT job_id, processing_duration_ms
FROM processing_metrics
WHERE processing_duration_ms > 120000  -- > 2 minutes
ORDER BY timestamp DESC LIMIT 5;
```

**Possible Causes:**
1. Large batch size
2. Insufficient resources
3. Database connection issues

**Investigation:**
```bash
# Check Spark job resources
kubectl top pods -n datalens -l spark-role=executor

# Check TimescaleDB connections
kubectl exec timescaledb-0 -n datalens -- \
    psql -U datalens -d datalens_metrics -c \
    "SELECT count(*) FROM pg_stat_activity;"
```

**Resolution:**
- Scale Spark executors
- Increase TimescaleDB connections
- Optimize batch size

### Problem: Failed Jobs

**Symptom:**
```sql
SELECT * FROM processing_metrics
WHERE error_count > 0
ORDER BY timestamp DESC LIMIT 5;
```

**Investigation:**
```bash
# Check Spark job logs
kubectl logs <spark-driver-pod> -n datalens

# Check Spark operator status
kubectl get sparkapplications -n datalens

# Check S3 connectivity
aws s3 ls s3://<bucket>/logs/
```

**Resolution:**
- Fix S3 permissions
- Restart failed jobs
- Review error logs

---

## Summary

This monitoring setup provides:

✅ **Complete Visibility:** Every line tracked from S3 to storage
✅ **Data Quality:** Automated validation and quality scores
✅ **Real-time Alerts:** Immediate notification of issues
✅ **Performance Tracking:** Optimize processing over time
✅ **Troubleshooting:** Quick root cause analysis

**Next Steps:**
1. Deploy Grafana dashboards
2. Configure alert channels
3. Set up daily reports
4. Create runbooks for common issues

**Related Docs:**
- [STORAGE_ARCHITECTURE.md](STORAGE_ARCHITECTURE.md)
- [OPERATIONS_GUIDE.md](OPERATIONS_GUIDE.md)
- [QUICK_START.md](QUICK_START.md)

