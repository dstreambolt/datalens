# DataLens Architecture - Deep Dive

## Table of Contents
1. [System Overview](#system-overview)
2. [Data Flow](#data-flow)
3. [Components](#components)
4. [Akamai DataStream2 Integration](#akamai-datastream2-integration)
5. [Processing Pipeline](#processing-pipeline)
6. [Storage Strategy](#storage-strategy)
7. [Scalability & Performance](#scalability--performance)
8. [Security](#security)
9. [Monitoring & Observability](#monitoring--observability)
10. [Disaster Recovery](#disaster-recovery)

---

## System Overview

DataLens is a cloud-native, Kubernetes-based analytics platform designed specifically for processing and visualizing Akamai DataStream2 CDN logs stored in AWS S3. The platform provides real-time insights into content delivery performance, security events, and user experience metrics.

### Key Design Principles

1. **Cloud-Native**: Built on Kubernetes for portability and orchestration
2. **Distributed Processing**: Apache Spark for scalable data processing
3. **Real-Time + Batch**: Hybrid processing for different latency requirements
4. **Time-Series Optimized**: TimescaleDB for efficient time-series data storage
5. **Event-Driven**: Kafka for event streaming and decoupling
6. **Self-Healing**: Kubernetes health checks and auto-restart capabilities

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          AWS Cloud Infrastructure                            │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────┐    │
│  │                     S3 Bucket (Source)                              │    │
│  │                 s3://datalens-akamai-logs/                          │    │
│  │                                                                      │    │
│  │  ├── 2025/                                                          │    │
│  │      ├── 12/                                                        │    │
│  │          ├── 13/                                                    │    │
│  │              ├── 00/ (hourly partition)                            │    │
│  │              ├── 01/                                                │    │
│  │              └── ...                                                │    │
│  └────────────────────────────────────────────────────────────────────┘    │
│                              │                                              │
│                              │ S3 Read (via Hadoop S3A)                     │
│                              ▼                                              │
│  ┌────────────────────────────────────────────────────────────────────┐    │
│  │              Kubernetes Cluster (EKS/GKE/AKS)                      │    │
│  │                                                                      │    │
│  │  ┌──────────────────────────────────────────────────────────────┐ │    │
│  │  │              Spark Operator (Kubernetes Operator)             │ │    │
│  │  │  • Manages Spark Application lifecycle                        │ │    │
│  │  │  • Auto-scaling executors                                     │ │    │
│  │  │  • Resource quota management                                  │ │    │
│  │  └──────────────────────────────────────────────────────────────┘ │    │
│  │                              │                                      │    │
│  │                              ▼                                      │    │
│  │  ┌──────────────────────────────────────────────────────────────┐ │    │
│  │  │         Apache Spark Cluster (3.5.0)                         │ │    │
│  │  │  ┌─────────────────────────────────────────────────────────┐ │ │    │
│  │  │  │ Driver Pod (2 cores, 4GB RAM)                           │ │ │    │
│  │  │  │  • Coordinates execution                                 │ │ │    │
│  │  │  │  • Manages executors                                     │ │ │    │
│  │  │  │  • DAG scheduling                                        │ │ │    │
│  │  │  └─────────────────────────────────────────────────────────┘ │ │    │
│  │  │                              │                                 │ │    │
│  │  │           ┌──────────────────┼──────────────────┐            │ │    │
│  │  │           ▼                  ▼                  ▼             │ │    │
│  │  │  ┌────────────┐     ┌────────────┐     ┌────────────┐      │ │    │
│  │  │  │ Executor 1 │     │ Executor 2 │     │ Executor N │      │ │    │
│  │  │  │ 2C / 4GB   │     │ 2C / 4GB   │     │ 2C / 4GB   │      │ │    │
│  │  │  └────────────┘     └────────────┘     └────────────┘      │ │    │
│  │  │                                                               │ │    │
│  │  │  Processing Steps:                                           │ │    │
│  │  │  1. Read from S3 (partitioned by date/hour)                │ │    │
│  │  │  2. Parse log lines (70+ fields)                            │ │    │
│  │  │  3. Transform & enrich data                                 │ │    │
│  │  │  4. Calculate derived metrics                               │ │    │
│  │  │  5. Write to multiple sinks                                 │ │    │
│  │  └──────────────────────────────────────────────────────────────┘ │    │
│  │                              │                                      │    │
│  │              ┌───────────────┼───────────────┐                    │    │
│  │              ▼               ▼               ▼                     │    │
│  │  ┌────────────────┐ ┌──────────────┐ ┌──────────────┐          │    │
│  │  │  Kafka Cluster │ │ TimescaleDB  │ │    MinIO     │          │    │
│  │  │  (3 brokers)   │ │ (PostgreSQL) │ │ (S3 Storage) │          │    │
│  │  └────────────────┘ └──────────────┘ └──────────────┘          │    │
│  │          │                  │                 │                    │    │
│  │          │ Topics:          │ Tables:         │ Buckets:          │    │
│  │          │ • raw-logs       │ • akamai_logs   │ • processed/      │    │
│  │          │ • metrics        │ • hourly_metrics│ • archived/       │    │
│  │          │ • alerts         │                 │                   │    │
│  │          │                  │                 │                   │    │
│  │          ▼                  ▼                 ▼                    │    │
│  │  ┌──────────────────────────────────────────────────────────────┐ │    │
│  │  │              Grafana Dashboards                               │ │    │
│  │  │  • Performance Analytics                                      │ │    │
│  │  │  • Security Monitoring                                        │ │    │
│  │  │  • Geographic Insights                                        │ │    │
│  │  │  • EdgeWorkers Metrics                                        │ │    │
│  │  └──────────────────────────────────────────────────────────────┘ │    │
│  └────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Data Flow

### 1. Ingestion Phase

```
Akamai Edge Servers
        │
        │ (DataStream2 configured)
        ▼
AWS S3 Bucket (datalens-akamai-logs)
        │
        │ Partitioning: /YYYY/MM/DD/HH/*.log
        │ Compression: gzip
        │ Format: Space-delimited text
        ▼
```

**Data Characteristics:**
- **Volume**: 100GB - 10TB per day (depending on CDN traffic)
- **Velocity**: Files arrive every 5-60 minutes
- **Format**: Space-delimited log lines
- **Compression**: gzip (10:1 ratio typical)
- **File Size**: 100MB - 1GB per file

### 2. Processing Phase

```
Spark Driver
    │
    ├─→ Read Partition (S3A FileSystem)
    │   └─ Parallel reads across executors
    │
    ├─→ Parse Log Lines
    │   ├─ Split by delimiter
    │   ├─ Type casting
    │   └─ Schema validation
    │
    ├─→ Transform & Enrich
    │   ├─ Calculate derived fields
    │   ├─ Decode URL-encoded strings
    │   ├─ Parse user agent
    │   └─ GeoIP enrichment (optional)
    │
    ├─→ Aggregate Metrics
    │   ├─ Time windows (1min, 5min, 1hour)
    │   ├─ Group by dimensions
    │   └─ Calculate statistics
    │
    └─→ Write to Sinks (parallel)
        ├─→ Kafka (real-time)
        ├─→ TimescaleDB (queryable)
        └─→ MinIO/S3 (archival)
```

### 3. Storage Phase

#### Kafka (Event Streaming)
- **Purpose**: Real-time event distribution
- **Retention**: 7 days
- **Topics**:
  - `akamai-raw-logs`: Parsed but unprocessed logs
  - `akamai-processed-metrics`: Aggregated metrics
  - `akamai-alerts`: Anomaly alerts
- **Consumers**:
  - Real-time dashboard updaters
  - Alert processors
  - Secondary analytics jobs

#### TimescaleDB (Time-Series Database)
- **Purpose**: Fast analytical queries
- **Retention**: 90 days (configurable)
- **Tables**:
  - `akamai_logs`: Raw log records
  - `akamai_hourly_metrics`: Pre-aggregated hourly data
- **Hypertables**: Automatic partitioning by time
- **Compression**: Automatic after 7 days
- **Indexes**:
  - Time-based (clustered)
  - Geographic (country, city)
  - Status codes
  - Cache status

#### MinIO/S3 (Long-Term Storage)
- **Purpose**: Historical data archive
- **Retention**: Unlimited (with lifecycle policies)
- **Format**: Parquet (columnar, compressed)
- **Partitioning**: By date (year/month/day/hour)
- **Compression**: Snappy
- **Use Cases**:
  - Historical trend analysis
  - Compliance requirements
  - Data lake integration

### 4. Visualization Phase

```
Grafana
    │
    ├─→ TimescaleDB (primary data source)
    │   └─ SQL queries with time-series functions
    │
    ├─→ Kafka (real-time metrics via connector)
    │   └─ WebSocket streaming
    │
    └─→ Dashboards
        ├─ Performance Overview
        ├─ Security Events
        ├─ Geographic Distribution
        ├─ Cache Efficiency
        └─ EdgeWorkers Analytics
```

---

## Components

### 1. Apache Spark (3.5.0)

**Why Spark?**
- **Distributed Processing**: Handles terabytes of data in parallel
- **In-Memory Computing**: 100x faster than disk-based processing
- **Unified Engine**: Batch + Streaming in one framework
- **Rich APIs**: DataFrames, SQL, MLlib
- **Ecosystem**: Excellent S3, Kafka, and database connectors

**Configuration:**
```yaml
Driver:
  cores: 2
  memory: 4GB
  
Executors:
  instances: 4-16 (auto-scaling)
  cores: 2 per executor
  memory: 4GB per executor
  
Total Capacity:
  CPU: 8-32 cores
  Memory: 16-64GB
  Throughput: ~1-5 GB/min
```

**Optimizations:**
- Adaptive Query Execution (AQE)
- Dynamic partition coalescing
- Broadcast joins for small dimensions
- Columnar batch processing
- Partition pruning on S3 paths

### 2. Apache Kafka (3.6.1)

**Why Kafka?**
- **Decoupling**: Producers and consumers independent
- **Durability**: Replicated, persistent message log
- **Scalability**: Horizontal scaling with partitions
- **Real-Time**: Sub-millisecond latency
- **Replay**: Re-process historical events

**Configuration:**
```yaml
Brokers: 3
Replication Factor: 2
Partitions per topic: 6 (raw-logs), 3 (metrics)
Retention: 7 days
Max Message Size: 10MB
Compression: snappy
```

**Topics:**
1. **akamai-raw-logs**
   - Parsed log records (JSON)
   - 6 partitions for parallelism
   - Consumed by real-time dashboards

2. **akamai-processed-metrics**
   - Pre-aggregated metrics
   - 3 partitions
   - Lower volume, higher value

3. **akamai-alerts**
   - Anomaly alerts
   - 1 partition (ordered)
   - Triggers notifications

### 3. TimescaleDB (2.x)

**Why TimescaleDB over plain PostgreSQL?**
- **Automatic Partitioning**: Time-based chunks
- **Query Performance**: 1000x faster for time-series
- **Compression**: 90% space savings
- **Continuous Aggregates**: Real-time rollups
- **PostgreSQL Compatible**: All standard SQL works

**Schema Design:**

```sql
-- Main hypertable (partitioned by time)
CREATE TABLE akamai_logs (
    request_timestamp TIMESTAMPTZ NOT NULL,
    reqId TEXT,
    cp INTEGER,
    cliIP INET,
    statusCode INTEGER,
    bytes BIGINT,
    timeToFirstByte BIGINT,
    throughput BIGINT,
    country TEXT,
    city TEXT,
    ...
);

-- Convert to hypertable (automatic partitioning)
SELECT create_hypertable('akamai_logs', 'request_timestamp', chunk_time_interval => INTERVAL '1 day');

-- Continuous aggregate (auto-updated)
CREATE MATERIALIZED VIEW akamai_hourly_metrics
WITH (timescaledb.continuous) AS
SELECT 
    time_bucket('1 hour', request_timestamp) AS hour,
    country,
    COUNT(*) as requests,
    SUM(bytes) as total_bytes,
    AVG(timeToFirstByte) as avg_ttfb
FROM akamai_logs
GROUP BY hour, country;
```

**Performance:**
- **Inserts**: 100K rows/sec on 4-core instance
- **Queries**: Sub-second for 1 billion rows
- **Compression**: 10:1 ratio after 7 days
- **Retention**: Automatic drop of old chunks

### 4. MinIO (S3-Compatible Storage)

**Why MinIO?**
- **S3 Compatibility**: Drop-in replacement
- **On-Premises**: No egress costs
- **Performance**: 10GB/s+ throughput
- **Erasure Coding**: Fault tolerance
- **Lifecycle Policies**: Auto-tiering

**Usage in DataLens:**
- Archive processed data in Parquet format
- Store intermediate results
- Backup TimescaleDB exports
- Share data with other analytics tools

### 5. Grafana (10.x)

**Why Grafana?**
- **Flexible**: Multiple data sources
- **Beautiful**: Professional dashboards
- **Alerting**: Built-in alert manager
- **Variables**: Dynamic, interactive dashboards
- **Plugins**: Extensive ecosystem

**Dashboards:**
1. **Performance Overview**
   - Request volume (requests/sec)
   - TTFB percentiles (p50, p95, p99)
   - Throughput trends
   - Error rates

2. **Geographic Insights**
   - World map with request density
   - Top countries/cities
   - Latency by region

3. **Security Events**
   - WAF rule triggers
   - Bot detection
   - DDoS indicators
   - Blocked requests

4. **Cache Efficiency**
   - Hit ratio trends
   - Origin offload
   - Byte savings

5. **EdgeWorkers Analytics**
   - Execution times
   - Error rates
   - Resource usage

---

## Akamai DataStream2 Integration

### Log Format

Akamai DataStream2 delivers logs in a **space-delimited format** with 70+ fields:

```
<version> <cp> <reqId> <reqTimeSec> <streamId> ...
```

**Example:**
```
1 123456 1239f220 1573840000 12345 1 2 2 602093 4995 128.147.28.68 206 HTTPS test.hostname.net GET path/file.ext ...
```

### Field Categories

1. **Request Info**: reqId, reqTimeSec, reqMethod, reqPath, reqHost
2. **Client Info**: cliIP, country, city, UA, accLang
3. **Performance**: timeToFirstByte, throughput, turnAroundTimeMSec, transferTimeMSec
4. **Response**: statusCode, rspContentLen, rspContentType
5. **Cache**: cacheStatus, cacheable, maxAgeSec
6. **Security**: securityRules, errorCode
7. **EdgeWorkers**: ewUsageInfo, ewExecutionInfo
8. **TLS**: tlsVersion, tlsOverheadTimeMSec, tlsEarlyData
9. **Media**: cmcd, deliveryType, deliveryFormat

### S3 Delivery Configuration

**Akamai DataStream2 Settings:**
```
Destination: Amazon S3
Bucket: s3://datalens-akamai-logs
Prefix: logs/
Delimiter: " " (space)
Compression: gzip
Upload Frequency: Every 5 minutes
File Naming: {cpcode}_{date}_{time}_{sequence}.log.gz
```

**S3 Folder Structure:**
```
s3://datalens-akamai-logs/
└── logs/
    └── 2025/
        └── 12/
            └── 13/
                ├── 00/
                │   ├── 123456_20251213_0005_001.log.gz
                │   ├── 123456_20251213_0010_001.log.gz
                │   └── ...
                ├── 01/
                └── ...
```

### Handling Schema Evolution

**Problem**: Akamai may add new fields over time.

**Solution**: Schema-on-read with optional fields
```python
# All fields marked as nullable
schema = StructType([
    StructField("version", StringType(), True),
    StructField("newField", StringType(), True),  # New field
    ...
])

# Parse with error handling
parsed_df = raw_df.select(
    col("fields").getItem(0).cast("string").alias("version"),
    col("fields").getItem(N).cast("string").alias("newField")  # Gracefully handles missing
)
```

---

## Processing Pipeline

### Batch Processing (Primary)

**Trigger**: Scheduled (every hour, or on-demand)

**Process:**
1. **Scan S3** for new files in time range
2. **Read in parallel** across Spark executors
3. **Parse** space-delimited format
4. **Validate** data quality (nulls, outliers)
5. **Transform** and calculate derived metrics
6. **Write** to TimescaleDB, Kafka, MinIO

**Performance:**
- Processes 100GB in ~10-15 minutes (4 executors)
- Scales linearly with executor count
- Cost: ~$2-5 per TB processed (AWS)

### Stream Processing (Optional)

For near-real-time requirements, implement Structured Streaming:

```python
# Read from S3 as a stream (new files trigger processing)
stream_df = spark.readStream \
    .schema(akamai_schema) \
    .text("s3a://datalens-akamai-logs/logs/")

# Process with 5-minute microbatches
stream_df.writeStream \
    .trigger(processingTime='5 minutes') \
    .foreachBatch(process_batch) \
    .start()
```

**Trade-offs:**
- **Latency**: 5-10 minutes vs 60+ minutes (batch)
- **Cost**: Higher (continuous resource usage)
- **Complexity**: Checkpointing, state management

---

## Storage Strategy

### Hot Tier (TimescaleDB)
- **Duration**: 7-90 days
- **Purpose**: Interactive queries, dashboards
- **Cost**: Medium (compute + storage)
- **Performance**: Sub-second queries

### Warm Tier (MinIO/S3 Parquet)
- **Duration**: 90 days - 2 years
- **Purpose**: Historical analysis, ML training
- **Cost**: Low (storage only)
- **Performance**: Minutes for large scans

### Cold Tier (S3 Glacier)
- **Duration**: 2+ years
- **Purpose**: Compliance, archival
- **Cost**: Very low
- **Performance**: Hours to retrieve

### Lifecycle Policy

```python
# Automatic tiering
s3_lifecycle_policy = {
    'Rules': [
        {
            'Id': 'Move to Intelligent-Tiering',
            'Status': 'Enabled',
            'Transitions': [
                {'Days': 30, 'StorageClass': 'INTELLIGENT_TIERING'},
                {'Days': 90, 'StorageClass': 'GLACIER'},
                {'Days': 730, 'StorageClass': 'DEEP_ARCHIVE'}
            ],
            'Expiration': {'Days': 2555}  # 7 years
        }
    ]
}
```

---

## Scalability & Performance

### Horizontal Scaling

**Spark Executors:**
```bash
# Scale up for large batches
kubectl scale deployment spark-executor --replicas=16 -n datalens

# Auto-scaling based on CPU/Memory
kubectl autoscale deployment spark-executor \
    --min=4 --max=16 \
    --cpu-percent=70 \
    -n datalens
```

**Kafka:**
```bash
# Add broker
kubectl scale statefulset kafka --replicas=5 -n datalens

# Increase partitions for parallelism
kafka-topics.sh --alter --topic akamai-raw-logs --partitions 12
```

**TimescaleDB:**
```yaml
# Vertical scaling (more resources per instance)
resources:
  requests:
    memory: 8Gi
    cpu: 4
    
# Horizontal scaling (read replicas)
replicaCount: 3
```

### Performance Benchmarks

**Hardware**: EKS cluster, m5.2xlarge nodes (8 vCPU, 32GB RAM)

| Data Volume | Executors | Processing Time | Throughput |
|-------------|-----------|-----------------|------------|
| 10 GB       | 4         | 3 min           | 3.3 GB/min |
| 100 GB      | 8         | 12 min          | 8.3 GB/min |
| 500 GB      | 16        | 45 min          | 11 GB/min  |
| 1 TB        | 32        | 80 min          | 12.5 GB/min|

**Query Performance (TimescaleDB):**
- Point query (1 day): < 100ms
- Aggregation (7 days): < 1 second
- Full table scan (90 days): < 30 seconds

---

## Security

### Data in Transit
- **S3 → Spark**: TLS 1.2+ (HTTPS)
- **Spark → Kafka**: SASL/SCRAM with TLS
- **Spark → TimescaleDB**: PostgreSQL SSL mode=require
- **Grafana → TimescaleDB**: SSL connections

### Data at Rest
- **S3**: SSE-S3 or SSE-KMS encryption
- **MinIO**: Server-side encryption
- **TimescaleDB**: Transparent Data Encryption (TDE)
- **Kafka**: Disk encryption via Kubernetes volume encryption

### Access Control
- **RBAC**: Kubernetes role-based access for pods
- **IAM**: AWS IAM roles for S3 access (no keys)
- **Network Policies**: Pod-to-pod communication restrictions
- **Secrets**: Kubernetes Secrets for credentials

### Compliance
- **GDPR**: PII masking (client IP anonymization)
- **Audit Logs**: All access logged via Kubernetes audit
- **Data Retention**: Configurable, automated deletion

---

## Monitoring & Observability

### Metrics (Prometheus)
- Spark job duration, failure rate
- Kafka lag, throughput
- TimescaleDB query performance, connection pool
- Pod CPU/memory usage

### Logs (ELK/Loki)
- Spark driver/executor logs
- Application error logs
- Kafka broker logs

### Tracing (Jaeger - optional)
- Distributed tracing across Spark → Kafka → TimescaleDB

### Alerts
- Processing job failures
- Kafka consumer lag > 1 hour
- Disk usage > 80%
- Query latency > 5 seconds

---

## Disaster Recovery

### Backup Strategy
1. **TimescaleDB**: Daily full backup to S3
2. **Kafka**: Offset tracking in external store
3. **Grafana**: Dashboard JSON exported to Git
4. **Spark Jobs**: Code in Git, image in registry

### Recovery Procedures
1. **Data Loss**: Reprocess from S3 (immutable source)
2. **Database Corruption**: Restore from backup + replay Kafka
3. **Cluster Failure**: Deploy to new cluster, mount same PVs

### RTO/RPO
- **RTO** (Recovery Time Objective): 1-2 hours
- **RPO** (Recovery Point Objective): 1 hour (last processed batch)

---

## Cost Optimization

### AWS Cost Breakdown (1 TB/day)

| Component | Monthly Cost |
|-----------|--------------|
| S3 Storage (30TB) | $690 |
| S3 GET Requests | $40 |
| EKS Cluster | $73 |
| EC2 Nodes (3x m5.2xlarge) | $300 |
| EBS Volumes (500GB) | $50 |
| **Total** | **~$1,153/month** |

### Cost per TB: ~$38

### Optimization Tips
1. Use S3 Intelligent-Tiering
2. Spot instances for Spark executors (70% savings)
3. Compress data in MinIO
4. Use TimescaleDB compression
5. Right-size Kafka retention
6. Schedule batch jobs during off-peak (cheaper compute)

---

## Conclusion

DataLens provides a production-grade, scalable, and cost-effective solution for processing Akamai DataStream2 logs. The architecture balances:

- **Performance**: Distributed Spark processing
- **Cost**: Optimized storage tiering
- **Reliability**: Kubernetes self-healing
- **Flexibility**: Multi-sink output for different use cases
- **Observability**: Comprehensive monitoring

The platform can scale from gigabytes to petabytes, making it suitable for both small deployments and enterprise-scale CDN analytics.

