# Apache Spark Streaming in DStreamBolt - Technical Deep Dive

## Table of Contents
1. [Why Spark Streaming?](#why-spark-streaming)
2. [Spark Architecture in DStreamBolt](#spark-architecture-in-dstreambolt)
3. [How Processing Works](#how-processing-works)
4. [Failure Handling & Recovery](#failure-handling--recovery)
5. [Auto-Start & Service Management](#auto-start--service-management)
6. [Troubleshooting Guide](#troubleshooting-guide)
7. [Zero-Downtime Upgrades](#zero-downtime-upgrades)
8. [MySQL Write Semantics](#mysql-write-semantics)
9. [Performance Optimization](#performance-optimization)
10. [Monitoring & Alerting](#monitoring--alerting)

---

## Why Spark Streaming?

### The Real-Time Processing Problem

**Requirement**: Process 10,000 log lines/second, compute aggregations, write to MySQL

**Problems with Batch** (Cron job every 5 minutes):
1. ❌ **Latency**: 5-minute delay (not "real-time")
2. ❌ **Memory**: Load 3 million rows into memory (OOM risk)
3. ❌ **Scalability**: Single machine bottleneck
4. ❌ **No incremental**: Reprocess everything (wasteful)
5. ❌ **No windowing**: Can't compute "last 5 minutes" metrics
6. ❌ **Complex state**: Managing state across runs is painful

**Spark Streaming Benefits**:
1. ✅ **Real-Time**: Sub-second latency (30s micro-batches)
2. ✅ **Scalable**: Distributed processing (1 to 100 executors)
3. ✅ **Incremental**: Only process new data
4. ✅ **Stateful**: Maintain running aggregations (windows, joins)
5. ✅ **Fault-Tolerant**: Automatic recovery from failures
6. ✅ **Exactly-Once**: Kafka offsets + idempotent writes = no duplicates

### Spark vs Other Stream Processors

| Feature | Spark Streaming | Flink | Storm | Kafka Streams |
|---------|----------------|-------|-------|---------------|
| Processing Model | Micro-batch | True streaming | True streaming | Micro-batch |
| Latency | ~100ms - 1s | ~10ms | ~10ms | ~50ms |
| Throughput | Very High | High | Medium | High |
| SQL Support | ✅ Full | ⚠️ Partial | ❌ No | ⚠️ Partial |
| Scala/Java/Python | ✅ All | ✅ All | ⚠️ Java only | ⚠️ Java/Scala |
| Complexity | Medium | High | Medium | Low |
| Maturity | Very Mature | Mature | Mature | Mature |

**Why Spark for DStreamBolt**:
- **Unified**: Same code for batch and streaming
- **SQL**: Complex aggregations with DataFrame API
- **Ecosystem**: Connectors for Kafka, MySQL, S3, etc.
- **Operations**: Mature monitoring, UI, logs
- **Scala**: Type safety + functional programming

---

## Spark Architecture in DStreamBolt

### Cluster Topology

```
┌──────────────────────────────────────────────────────────────┐
│                    Spark Cluster                             │
│                                                              │
│  ┌────────────────────┐        ┌────────────────────┐      │
│  │  Spark Master      │        │  Spark Executor 1  │      │
│  │  (Scheduler)       │◄──────►│  (Worker)          │      │
│  │  Port: 8080 (UI)   │        │  Port: 8081 (UI)   │      │
│  │  Port: 7077 (RPC)  │        │  4 cores, 2GB RAM  │      │
│  └────────────────────┘        └────────────────────┘      │
│           │                                                  │
│           │                    ┌────────────────────┐      │
│           └───────────────────►│  Spark Executor 2  │      │
│                                │  (Worker)          │      │
│                                │  4 cores, 2GB RAM  │      │
│                                └────────────────────┘      │
└──────────────────────────────────────────────────────────────┘
```

**In DStreamBolt** (Single-node setup):
- **Master + Executor on same machine** (t3.small)
- **1 executor, 1 core, 512MB** (cost-optimized)
- **Client deploy mode** (driver runs on master)

**Production Recommendation**:
- **Separate master** (t3.small)
- **3+ executor nodes** (c5.2xlarge: 8 cores, 16GB)
- **Cluster deploy mode** (driver on YARN/K8s)

### SparkProcessor Application

**Main Components**:
1. **SparkSession**: Entry point, manages cluster connection
2. **Kafka Source**: Reads from `dstreambolt-logs` topic
3. **Transformation Pipeline**: Parse, filter, aggregate
4. **MySQL Sink**: Write results to tables
5. **Checkpointing**: Track Kafka offsets for recovery

---

## How Processing Works

### Data Flow (End-to-End)

```
Kafka Topic                Spark Processing              MySQL
─────────────            ──────────────────            ─────────
Partition 0:             ┌─────────────────┐          ┌──────────┐
[log1, log2, ...]  ─────►│ Read (micro-   │          │ endpoint_│
                          │ batch = 30s)   │          │ summary  │
Partition 1:              └────────┬────────┘          └──────────┘
[log3, log4, ...]  ──────────────►│                   
                                   │                   ┌──────────┐
Partition 2:              ┌────────▼────────┐          │ status_  │
[log5, log6, ...]  ─────►│ Parse Logs      │────────► │ summary  │
                          │ (regex/JSON)    │          └──────────┘
                          └────────┬────────┘          
                                   │                   ┌──────────┐
                          ┌────────▼────────┐          │ user_    │
                          │ Aggregate       │────────► │ summary  │
                          │ (windows, groups│          └──────────┘
                          └────────┬────────┘          
                                   │                   
                          ┌────────▼────────┐          
                          │ Write to MySQL  │          
                          │ (JDBC batch)    │          
                          └─────────────────┘          
```

### Step 1: Kafka Source Configuration

```scala
val df = spark
  .readStream
  .format("kafka")
  .option("kafka.bootstrap.servers", "10.0.10.101:9092")
  .option("subscribe", "dstreambolt-logs")
  .option("startingOffsets", "latest")  // Start from newest on first run
  .option("failOnDataLoss", "false")    // Tolerate partition reassignment
  .option("maxOffsetsPerTrigger", 10000) // Rate limiting
  .load()
```

**Key Options**:
- `startingOffsets`: `latest` (prod) or `earliest` (reprocess)
- `maxOffsetsPerTrigger`: Prevent executor overload
- `failOnDataLoss`: `false` = tolerate partition changes

### Step 2: Deserialization

```scala
// Kafka message = binary, need to parse
val logs = df
  .selectExpr("CAST(value AS STRING) as json_line")
  .select(from_json($"json_line", logSchema).as("data"))
  .select("data.*")
```

**Schema Definition**:
```scala
val logSchema = StructType(Seq(
  StructField("timestamp", StringType, nullable = false),
  StructField("ip", StringType, nullable = false),
  StructField("method", StringType, nullable = false),
  StructField("endpoint", StringType, nullable = false),
  StructField("status", IntegerType, nullable = false),
  StructField("response_time", DoubleType, nullable = false),
  StructField("user_agent", StringType, nullable = true)
))
```

### Step 3: Windowed Aggregations

```scala
// 30-second tumbling windows
val aggregated = logs
  .withWatermark("event_timestamp", "2 minutes")  // Handle late data
  .groupBy(
    window($"event_timestamp", "30 seconds"),
    $"endpoint",
    $"method"
  )
  .agg(
    count("*").as("request_count"),
    avg("response_time").as("avg_response_time"),
    approx_count_distinct("ip").as("unique_ips"),  // HyperLogLog
    sum(when($"status" >= 400, 1).otherwise(0)).as("error_count")
  )
```

**Watermarking** (handles late arrivals):
- **Problem**: Events arrive out-of-order (network delays)
- **Solution**: Wait up to 2 minutes for late events
- **Trade-off**: Higher latency but more accurate results

### Step 4: MySQL Sink

```scala
aggregated.writeStream
  .foreachBatch { (batchDF: DataFrame, batchId: Long) =>
    batchDF.write
      .mode("append")
      .format("jdbc")
      .option("url", "jdbc:mysql://10.0.1.68:3306/dstreambolt_metrics")
      .option("dbtable", "endpoint_summary")
      .option("user", "dstreambolt")
      .option("password", getSecret("mysql_password"))
      .option("batchsize", 1000)  // Insert 1000 rows per batch
      .save()
  }
  .trigger(Trigger.ProcessingTime("30 seconds"))
  .option("checkpointLocation", "/opt/spark/checkpoints/endpoint_summary")
  .start()
```

**Key Concepts**:
- `foreachBatch`: Custom logic per micro-batch
- `batchsize`: Reduce round-trips (performance)
- `checkpointLocation`: Stores Kafka offsets (recovery)

---

## Failure Handling & Recovery

### Failure Scenarios

#### 1. Executor Crash

**What Happens**:
1. Task running on executor fails
2. Master detects lost executor (heartbeat timeout)
3. Reschedules failed tasks on healthy executors
4. Re-reads data from Kafka (same offsets)

**Recovery Time**: ~10-30 seconds (configurable)

**No Data Loss**: Kafka retains data, Spark re-reads

#### 2. Master Crash

**What Happens**:
1. Entire application stops
2. Need manual restart (systemd will auto-restart)
3. On restart, reads checkpoint location
4. Resumes from last committed Kafka offsets

**Recovery Time**: ~30-60 seconds (JVM startup)

**No Data Loss**: Checkpoints store offsets

#### 3. Kafka Unavailable

**What Happens**:
1. Kafka read fails (broker down)
2. Spark retries with exponential backoff
3. If all retries fail, micro-batch fails
4. Application continues retrying (doesn't crash)

**Recovery**: Automatic when Kafka recovers

**Configuration**:
```scala
.option("kafka.request.timeout.ms", "30000")      // 30s timeout
.option("kafka.session.timeout.ms", "10000")      // 10s session
.option("kafka.max.poll.interval.ms", "300000")   // 5min processing
```

#### 4. MySQL Write Failure

**What Happens**:
1. JDBC write throws exception
2. Current micro-batch fails
3. Kafka offsets NOT committed (checkpoint not updated)
4. On retry, re-reads same Kafka offsets
5. Writes data again (idempotency needed!)

**Ensuring Idempotency**:

**Option 1: Upsert (MySQL 8.0+)**
```sql
INSERT INTO endpoint_summary (window_start, endpoint, method, request_count)
VALUES (?, ?, ?, ?)
ON DUPLICATE KEY UPDATE
  request_count = VALUES(request_count),
  avg_response_time = VALUES(avg_response_time);
```

**Option 2: Deduplication Key**
```scala
// Add batch ID as unique constraint
batchDF.withColumn("batch_id", lit(batchId))
  .write.mode("append")...
  
// Table schema:
CREATE TABLE endpoint_summary (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  batch_id BIGINT NOT NULL,
  window_start TIMESTAMP,
  ...
  UNIQUE KEY unique_batch_window (batch_id, window_start, endpoint, method)
);
```

### Checkpointing Deep Dive

**Checkpoint Directory Structure**:
```
/opt/spark/checkpoints/endpoint_summary/
├── commits/
│   ├── 0        # Batch 0 completed
│   ├── 1        # Batch 1 completed
│   └── 2        # Batch 2 completed
├── metadata
├── offsets/
│   ├── 0        # Kafka offsets for batch 0
│   ├── 1        # Kafka offsets for batch 1
│   └── 2        # Kafka offsets for batch 2
└── sources/
    └── 0/
        └── 0    # Source info (Kafka topic/partitions)
```

**Recovery Process**:
1. Read `commits/` → Last successful batch = 2
2. Read `offsets/3` → Next Kafka offsets to consume
3. Resume processing from batch 3

**Important**: Checkpoint is **mandatory** for production!

---

## Auto-Start & Service Management

### Systemd Service Unit

```ini
[Unit]
Description=DStreamBolt Spark Streaming Job
After=network.target

[Service]
Type=forking
User=ubuntu
WorkingDirectory=/opt/dstreambolt/computations
ExecStart=/opt/spark/bin/spark-submit \
  --master spark://10.0.1.199:7077 \
  --deploy-mode client \
  --driver-memory 512m \
  --executor-memory 512m \
  --conf spark.sql.shuffle.partitions=3 \
  --packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0 \
  --class com.dstreambolt.processor.SparkProcessor \
  /opt/dstreambolt/computations/target/scala-2.12/dstreambolt-processor_2.12-1.0.jar

Restart=always
RestartSec=30s

[Install]
WantedBy=multi-user.target
```

**Key Settings**:
- `Type=forking`: Spark submit spawns background process
- `Restart=always`: Auto-restart on crash
- `RestartSec=30s`: Wait 30s before retry (prevent rapid restart loop)

### Health Monitoring Script

```bash
#!/bin/bash
# /opt/dstreambolt/scripts/check_spark_health.sh

MASTER_UI="http://10.0.1.199:8080"
APP_NAME="DStreamBolt-SparkProcessor"

# Check if master is up
curl -sf "$MASTER_UI" > /dev/null || {
  echo "ERROR: Spark master unreachable"
  exit 1
}

# Check if application is running
curl -sf "$MASTER_UI/json/" | jq -e ".activeapps[] | select(.name==\"$APP_NAME\")" > /dev/null || {
  echo "ERROR: Application not running"
  systemctl restart dstreambolt-spark
  exit 1
}

echo "OK: Spark job healthy"
```

**Cron Job** (runs every 5 minutes):
```cron
*/5 * * * * /opt/dstreambolt/scripts/check_spark_health.sh >> /var/log/spark_health.log 2>&1
```

---

## Troubleshooting Guide

### Common Issues

#### Issue 1: "Connection refused to Kafka"

**Symptoms**:
```
ERROR org.apache.kafka.clients.NetworkClient: Connection to node -1 failed
```

**Diagnosis**:
```bash
# Check Kafka is running
ssh kafka-node systemctl status kafka

# Test connectivity from Spark node
telnet 10.0.10.101 9092
```

**Fix**:
- Ensure Kafka security group allows port 9092 from Spark SG
- Verify `advertised.listeners` in Kafka config
- Check AWS Secrets Manager has correct broker address

#### Issue 2: "OutOfMemoryError: Java heap space"

**Symptoms**:
```
java.lang.OutOfMemoryError: Java heap space
at org.apache.spark.sql.execution.aggregate
```

**Diagnosis**:
- Too much data in single micro-batch
- Executor memory too small (512MB)

**Fix**:
```scala
// Option 1: Reduce batch size
.option("maxOffsetsPerTrigger", 5000)  // Was 10000

// Option 2: Increase executor memory
--executor-memory 1g  // Was 512m

// Option 3: Repartition before aggregation
df.repartition(6)  // More partitions = less memory per partition
```

#### Issue 3: "Checkpoint mismatch"

**Symptoms**:
```
java.lang.IllegalStateException: Cannot start query with id xxx as another query 
with same id is already started
```

**Diagnosis**:
- Checkpoint from different Spark version
- Schema changed (added/removed columns)

**Fix**:
```bash
# Option 1: Delete checkpoint (LOSES KAFKA OFFSET STATE!)
rm -rf /opt/spark/checkpoints/endpoint_summary

# Option 2: Use new checkpoint location
.option("checkpointLocation", "/opt/spark/checkpoints/endpoint_summary_v2")
```

#### Issue 4: "Slow Processing (backlog growing)"

**Symptoms**:
```
Grafana dashboard shows "Kafka Consumer Lag" increasing
Spark UI shows "Scheduling Delay" > 30s
```

**Diagnosis**:
```bash
# Check Spark UI → Streaming tab
# If "Scheduling Delay" > "Batch Interval", you're falling behind

# Check CPU/memory on executors
ssh spark-executor
top
```

**Fix**:
```scala
// Option 1: Increase parallelism
.option("maxOffsetsPerTrigger", 20000)  // Process more per batch
--executor-cores 2  // Was 1

// Option 2: Scale out (add more executors)
# Deploy additional executor nodes

// Option 3: Optimize aggregation
.groupBy(window(...), $"endpoint")  // Remove $"method" if not needed
```

---

## Zero-Downtime Upgrades

### Challenge

**Problem**: Need to deploy new Spark code without:
1. Losing Kafka offsets (data loss)
2. Duplicate processing (write twice to MySQL)
3. Downtime (alerts fire)

### Strategy 1: Blue-Green Deployment

```
┌─────────────────────────────────────────────────┐
│ Step 1: Current (Blue) running                  │
│   Spark Job A → Kafka (offset 1000) → MySQL    │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│ Step 2: Deploy new (Green) with NEW checkpoint │
│   Spark Job A → Kafka (offset 1000)            │
│   Spark Job B → Kafka (offset 1000) → MySQL    │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│ Step 3: Verify Green, stop Blue                │
│   Spark Job B → Kafka (offset 1050) → MySQL    │
└─────────────────────────────────────────────────┘
```

**Implementation**:
```bash
# 1. Deploy new JAR
scp dstreambolt-processor_2.12-1.0.jar spark-master:/opt/dstreambolt/computations/new/

# 2. Start Green with new checkpoint
spark-submit \
  --checkpoint-location /opt/spark/checkpoints/endpoint_summary_v2 \
  --master spark://master:7077 \
  new/dstreambolt-processor_2.12-1.0.jar

# 3. Monitor Green for 5 minutes (check logs, Grafana)

# 4. Stop Blue (graceful shutdown)
kill -SIGTERM <blue-process-pid>

# 5. Rename checkpoint (now Green is primary)
mv /opt/spark/checkpoints/endpoint_summary /opt/spark/checkpoints/endpoint_summary_old
mv /opt/spark/checkpoints/endpoint_summary_v2 /opt/spark/checkpoints/endpoint_summary
```

**Pros**: Zero data loss, can rollback
**Cons**: Double processing for 5min (need idempotent writes)

### Strategy 2: Graceful Restart

```bash
# 1. Deploy new JAR (overwrites old)
scp dstreambolt-processor_2.12-1.0.jar spark-master:/opt/dstreambolt/computations/

# 2. Graceful stop (waits for current micro-batch to complete)
kill -SIGTERM <process-pid>
# Wait for "Streaming query stopped" in logs (~30s)

# 3. Start new version
systemctl start dstreambolt-spark
```

**Pros**: Simple, single code path
**Cons**: 30-60s downtime (micro-batch + JVM startup)

---

## MySQL Write Semantics

### Ensuring Exactly-Once Delivery

**The Problem**: Spark can process same data twice (on retry)

**Example Failure Scenario**:
```
Batch 10: Read offsets 1000-1099 from Kafka
          ↓
       Process 100 logs
          ↓
       Write to MySQL ✅
          ↓
       Commit offsets... ❌ CRASH!
          
On Restart:
Batch 10 (again): Read offsets 1000-1099 from Kafka  # SAME DATA!
                  ↓
               Process 100 logs
                  ↓
               Write to MySQL  # DUPLICATE!
```

### Solution 1: Idempotent Writes (Recommended)

```sql
CREATE TABLE endpoint_summary (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  window_start TIMESTAMP NOT NULL,
  endpoint VARCHAR(255) NOT NULL,
  method VARCHAR(10) NOT NULL,
  request_count BIGINT,
  avg_response_time DOUBLE,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  
  UNIQUE KEY unique_window_endpoint (window_start, endpoint, method)
);

-- Upsert query (MySQL 8.0+)
INSERT INTO endpoint_summary (window_start, endpoint, method, request_count, avg_response_time)
VALUES (?, ?, ?, ?, ?)
ON DUPLICATE KEY UPDATE
  request_count = VALUES(request_count),
  avg_response_time = VALUES(avg_response_time),
  updated_at = CURRENT_TIMESTAMP;
```

**Scala Code**:
```scala
def writeToMySQL(df: DataFrame, table: String): Unit = {
  df.write
    .mode("append")
    .format("jdbc")
    .option("url", jdbcUrl)
    .option("dbtable", table)
    .option("batchsize", 1000)
    // CRITICAL: Use custom INSERT ... ON DUPLICATE KEY UPDATE
    .option("createTableOptions", "ENGINE=InnoDB")
    .option("rewriteBatchedStatements", "true")  // Performance
    .save()
}
```

**Note**: Spark JDBC doesn't natively support `ON DUPLICATE KEY UPDATE`. Options:
1. Use `foreachBatch` with custom JDBC logic
2. Pre-create table with unique constraints
3. Use MariaDB connector (supports upsert)

### Solution 2: Deduplication with Batch ID

```sql
CREATE TABLE endpoint_summary (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  batch_id BIGINT NOT NULL,         -- Spark batch ID
  window_start TIMESTAMP NOT NULL,
  endpoint VARCHAR(255) NOT NULL,
  method VARCHAR(10) NOT NULL,
  request_count BIGINT,
  
  UNIQUE KEY unique_batch (batch_id, window_start, endpoint, method)
);
```

```scala
df.withColumn("batch_id", lit(batchId))
  .write.mode("append")...
```

**On retry**: Duplicate key error → Ignore (data already written)

---

## Performance Optimization

### Tuning Checklist

#### 1. Kafka Consumer

```scala
// Increase fetch size (reduce round-trips)
.option("kafka.fetch.min.bytes", "1048576")         // 1MB
.option("kafka.fetch.max.wait.ms", "500")           // Wait 500ms for 1MB
.option("maxOffsetsPerTrigger", "10000")            // Process 10k msgs/batch

// Parallelize consumption
.option("minPartitions", "6")  // If topic has 3 partitions, read each twice
```

#### 2. Executor Resources

```bash
# Increase parallelism
--executor-cores 4           # More cores = more tasks
--executor-memory 4g         # More memory = larger shuffle buffers

# Tune shuffle
--conf spark.sql.shuffle.partitions=12  # Default 200 (too high for small data)
```

#### 3. MySQL Writes

```scala
// Batch inserts
.option("batchsize", 5000)                    // Insert 5000 rows at once
.option("rewriteBatchedStatements", "true")   // Rewrite as single INSERT

// Connection pooling
.option("numPartitions", "3")     // 3 parallel JDBC connections
.option("connectionTimeout", "30000")
```

#### 4. Caching

```scala
// If reusing DataFrame multiple times
val parsed = logs.select(...).cache()

parsed.write...
parsed.groupBy(...).write...

parsed.unpersist()  // Free memory when done
```

### Benchmarking

**Test Setup**:
- 10,000 log lines/second
- 30-second micro-batches = 300k records/batch
- 3 aggregations (endpoint, status, user)

**Baseline** (1 core, 512MB):
- Batch time: 45 seconds ❌ (falling behind!)
- CPU: 100% (bottleneck)

**Optimized** (2 cores, 1GB):
- Batch time: 12 seconds ✅
- CPU: 60% (headroom)

**Calculation**:
```
Throughput = Records per batch / Batch processing time
          = 300,000 / 12s
          = 25,000 records/second ✅
```

---

## Monitoring & Alerting

### Key Metrics

#### 1. Processing Rate

**Grafana Query**:
```sql
SELECT 
  window_start,
  SUM(request_count) / 30 AS logs_per_second
FROM endpoint_summary
WHERE window_start >= NOW() - INTERVAL 10 MINUTE
GROUP BY window_start
ORDER BY window_start;
```

**Alert**: If `logs_per_second < 1000` for 5min → "Processing slow"

#### 2. Consumer Lag

**Definition**: How far behind Spark is from Kafka

**Calculation**:
```
Lag = Latest Kafka offset - Spark committed offset
```

**AKHQ Dashboard** shows this automatically

**Alert**: If `lag > 100,000` → "Spark falling behind"

#### 3. Batch Duration

**Spark UI** → Streaming tab → "Avg Batch Duration"

**Alert**: If `batch_duration > 30s` → "Approaching capacity"

#### 4. Error Rate

**Grafana Query**:
```sql
SELECT 
  window_start,
  SUM(error_count) * 100.0 / SUM(request_count) AS error_rate_pct
FROM endpoint_summary
WHERE window_start >= NOW() - INTERVAL 1 HOUR
GROUP BY window_start;
```

**Alert**: If `error_rate_pct > 5%` → "High error rate"

### Structured Streaming UI

**Access**: `http://spark-master:4040/StreamingQuery/`

**Key Metrics**:
- **Input Rate**: Messages/sec from Kafka
- **Process Rate**: Messages/sec processed
- **Batch Duration**: Time to process one batch
- **Scheduling Delay**: Time waiting for resources

**Healthy Job**:
- `Input Rate ≈ Process Rate` (keeping up)
- `Batch Duration < Trigger Interval` (not falling behind)
- `Scheduling Delay ≈ 0` (no resource contention)

### Logs to Monitor

```bash
# Application logs
tail -f /opt/spark/logs/spark-job.log

# Executor logs (stderr = warnings/errors)
tail -f /opt/spark/work/app-<id>/*/stderr

# Common patterns to grep for:
grep -i "error\|exception\|failed" /opt/spark/logs/*.log
```

---

## Challenges in DStreamBolt Pipeline

### Challenge 1: Small Data, High Frequency

**Problem**: Processing 10k logs/sec with small payloads (1KB each)
- Kafka: 10k messages/sec = lots of small network calls
- Spark: Overhead of micro-batch scheduling

**Solution**:
1. **Batch ingestion**: Clients send 1000 logs per POST (reduce Kafka writes)
2. **Increase trigger interval**: 30s batches (reduce Spark overhead)
3. **Tune fetch size**: Read more messages per poll

### Challenge 2: Late Data

**Problem**: Logs arrive out-of-order (client buffering, network delays)

**Example**:
```
Time 10:00:00 → Process window [09:59:30 - 10:00:00]
Time 10:00:05 → Late log arrives with timestamp 09:59:45
```

**Solution**: Watermarking
```scala
.withWatermark("event_timestamp", "2 minutes")
```

Spark waits 2 minutes before finalizing window.

**Trade-off**: 2min extra latency, but accurate results

### Challenge 3: Schema Evolution

**Problem**: Clients update log format (new field added)

**Breaking Change**:
```json
// Old: {"timestamp": "...", "ip": "..."}
// New: {"timestamp": "...", "ip": "...", "user_id": 123}
```

**Solution**:
1. **Schema registry**: Store schema versions in Kafka headers
2. **Schema inference**: Use `schema_of_json` (slower but flexible)
3. **Backward compatibility**: Make new fields optional

```scala
val logSchema = StructType(Seq(
  // ...existing fields...
  StructField("user_id", IntegerType, nullable = true)  // New field optional
))
```

### Challenge 4: Hot Partitions

**Problem**: Endpoint `/api/v1/popular` gets 80% of traffic
- Kafka partition key = endpoint
- Result: Partition 0 overloaded, partitions 1-2 idle

**Solution**:
1. **Better partition key**: Hash of `endpoint + random(0-9)`
2. **Repartition in Spark**: `df.repartition($"endpoint")`

---

## Summary: Why Spark Works for DStreamBolt

| Requirement | Spark Solution |
|-------------|---------------|
| Real-time (< 1 min latency) | ✅ 30-second micro-batches |
| Handle 10k logs/sec | ✅ Distributed processing |
| Complex aggregations | ✅ DataFrame API / SQL |
| Fault tolerance | ✅ Checkpointing + Kafka replay |
| Exactly-once semantics | ✅ Idempotent MySQL writes |
| Scalability | ✅ Add executors horizontally |
| Operational visibility | ✅ Spark UI + Grafana |

**Next Steps**:
- Read [KAFKA_DEEPDIVE.md](./KAFKA_DEEPDIVE.md) for Kafka best practices
- Read [INGESTION_DEEPDIVE.md](./INGESTION_DEEPDIVE.md) for ingestion layer
- Check [OPERATIONS_GUIDE.md](../OPERATIONS_GUIDE.md) for deployment procedures
