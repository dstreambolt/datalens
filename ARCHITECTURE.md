# DStreamBolt Architecture Documentation

## 🏗️ System Overview

DStreamBolt is a production-grade, real-time data streaming platform built on AWS that provides:
- **Secure data ingestion** with mTLS authentication
- **Distributed stream processing** using Apache Spark
- **Real-time monitoring** with Grafana dashboards
- **Automated CI/CD** pipelines with Jenkins
- **Cost-optimized** infrastructure (<$50/month)

---

## 📊 High-Level Architecture

```
                                    ┌─────────────────────────────────────┐
                                    │      AWS Application Load           │
                                    │      Balancer (ALB)                 │
                                    │   https://dstreambolt.click         │
                                    └──────────────┬──────────────────────┘
                                                   │
                ┌──────────────────────────────────┼──────────────────────────────────┐
                │                                  │                                  │
                ▼                                  ▼                                  ▼
    ┌───────────────────────┐        ┌───────────────────────┐        ┌───────────────────────┐
    │  Ingestion Service    │        │   DevOps Tools        │        │   Monitoring          │
    │  (Public Subnet)      │        │   (Public Subnet)     │        │   (Private Access)    │
    │                       │        │                       │        │                       │
    │  • mTLS Endpoint      │        │  • Jenkins CI/CD      │        │  • Grafana            │
    │  • Rate Limiting      │        │  • AKHQ Kafka UI      │        │  • Metrics Collector  │
    │  • Queue Management   │        │  • MySQL Database     │        │                       │
    │  • Async Processing   │        │  • Secret Manager     │        │                       │
    └──────────┬────────────┘        └───────────────────────┘        └───────────────────────┘
               │                                  │
               │ Produce Logs                    │ Read/Write
               ▼                                  ▼
    ┌─────────────────────────────────────────────────────────┐
    │            Apache Kafka Cluster                         │
    │            (Private Subnet)                             │
    │                                                          │
    │  • Topic: dstreambolt-logs                              │
    │  • Partitions: 3                                        │
    │  • Replication: 1                                       │
    │  • Retention: 7 days                                    │
    └──────────────────────┬──────────────────────────────────┘
                           │
                           │ Consume Logs
                           ▼
    ┌─────────────────────────────────────────────────────────┐
    │         Apache Spark Cluster                            │
    │         (Private Subnet)                                │
    │                                                          │
    │  ┌──────────────────┐      ┌──────────────────┐        │
    │  │  Spark Master    │◄─────┤ Spark Executor   │        │
    │  │  (t3.small)      │      │ (t3.small)       │        │
    │  │                  │      │                  │        │
    │  │  • Job Scheduler │      │ • Task Execution │        │
    │  │  • Cluster Mgmt  │      │ • Data Transform │        │
    │  └──────────────────┘      └──────────────────┘        │
    │                                                          │
    │  Processing Modes:                                      │
    │  • Streaming: 30-second windows                         │
    │  • Batch: Historical analysis                           │
    └──────────────────────┬──────────────────────────────────┘
                           │
                           │ Write Metrics
                           ▼
    ┌─────────────────────────────────────────────────────────┐
    │              MySQL Database                             │
    │              (DevOps Node)                              │
    │                                                          │
    │  Tables:                                                │
    │  • endpoint_summary    - API endpoint metrics           │
    │  • status_summary      - HTTP status aggregations       │
    │  • error_analysis      - Error tracking                 │
    │  • ingest_metrics      - Ingestion service metrics      │
    │  • kafka_metrics       - Broker performance             │
    │  • spark_metrics       - Processing statistics          │
    └─────────────────────────────────────────────────────────┘
```

---

## 🔐 Why mTLS? Security Architecture

### The Problem: Securing External APIs

When exposing data ingestion endpoints to external clients (agents, partners, IoT devices), you need to ensure:

1. **Authentication**: Verify the identity of the client
2. **Authorization**: Ensure the client has permission to send data
3. **Encryption**: Protect data in transit
4. **Non-repudiation**: Prove who sent what and when

### Traditional Approaches vs. mTLS

| Approach | Pros | Cons | Use Case |
|----------|------|------|----------|
| **API Tokens** | Simple, easy to rotate | Stolen tokens can be replayed | Low-security scenarios |
| **OAuth 2.0** | Standard, widely adopted | Complex setup, token management | User-facing APIs |
| **IP Whitelisting** | Simple firewall rules | Doesn't verify client identity | Static infrastructure |
| **mTLS** ✅ | Strongest cryptographic auth | Cert management overhead | Production data ingestion |

### mTLS Implementation

```
┌─────────────────────────────────────────────────────────────────┐
│                    mTLS Handshake Process                       │
└─────────────────────────────────────────────────────────────────┘

Client                                              Server
  │                                                    │
  │  1. ClientHello (TLS version, ciphers)            │
  ├──────────────────────────────────────────────────>│
  │                                                    │
  │  2. ServerHello + Server Certificate               │
  │     + CertificateRequest                           │
  │<──────────────────────────────────────────────────┤
  │                                                    │
  │  3. Client Certificate + ClientKeyExchange         │
  │     + CertificateVerify                            │
  ├──────────────────────────────────────────────────>│
  │                                                    │
  │  4. Verify Client Certificate against CA          │
  │     ✓ Valid signature                              │
  │     ✓ Not expired                                  │
  │     ✓ Not revoked (CRL check)                      │
  │                                                    │
  │  5. Finished (Encrypted connection established)    │
  │<═══════════════════════════════════════════════════│
  │                                                    │
  │  6. Application Data (gzipped bundles)             │
  │════════════════════════════════════════════════════>│
```

### Certificate Management

```
┌─────────────────────────────────────────────────────────────┐
│           Certificate Authority (CA) Structure              │
└─────────────────────────────────────────────────────────────┘

                    ┌─────────────────┐
                    │   Root CA       │
                    │  (Self-signed)  │
                    │  10-year expiry │
                    └────────┬────────┘
                             │
                ┌────────────┴────────────┐
                │                         │
       ┌────────▼────────┐       ┌───────▼────────┐
       │  Server Cert    │       │  Client Cert   │
       │  (90-day expiry)│       │  (90-day expiry)│
       │                 │       │                 │
       │  • CN: *.dsb... │       │  • CN: client-1│
       │  • SAN: domains │       │  • Unique ID    │
       └─────────────────┘       └────────────────┘
```

**Benefits:**
- **Mutual Authentication**: Both parties prove their identity
- **Certificate-based**: Can't be stolen like API tokens
- **Automatic Rotation**: Short-lived certs force regular renewal
- **Granular Control**: Each client has unique certificate
- **Audit Trail**: Certificate serial numbers in logs

**Storage:**
- **AWS Secrets Manager**: Stores all certificates and private keys
- **Encrypted at rest**: AES-256 encryption
- **Rotation**: Automated 90-day certificate renewal
- **Access Control**: IAM policies restrict who can read secrets

---

## 🌊 Data Flow Detailed

### 1. Log Ingestion Flow

```
┌──────────────────────────────────────────────────────────────┐
│                    Ingestion Service Pipeline                 │
└──────────────────────────────────────────────────────────────┘

External Client
     │
     │ POST /ingest
     │ Content-Type: application/gzip
     │ Content-Encoding: gzip
     │ Body: <compressed log bundle>
     │
     ▼
┌─────────────────────────────────┐
│  1. Request Reception           │
│  • Verify mTLS certificate      │──> If invalid: 403 Forbidden
│  • Rate limit check (100/min)   │──> If exceeded: 429 Too Many
│  • Size validation (<50MB)      │──> If too large: 413 Payload
└──────────────┬──────────────────┘
               │
               ▼
┌─────────────────────────────────┐
│  2. Queue Management            │
│  • Check queue size (<10k)      │──> If full: 503 Service Unavailable
│  • Generate unique bundle ID    │
│  • Write to disk:               │
│    /opt/dstreambolt/queue/      │
│    bundle_<timestamp>_<uuid>.gz │
└──────────────┬──────────────────┘
               │
               │ Return immediately: 201 Accepted
               │ {"status": "accepted", "bundle_id": "..."}
               │
               ▼
┌─────────────────────────────────┐
│  3. Async Worker Thread         │
│  (Background Processing)        │
│                                 │
│  • Scan queue directory         │
│  • Pick oldest bundle           │
│  • Decompress gzip              │
│  • Validate JSON                │──> If corrupt: Move to /corrupted/
│  • Parse log lines              │
│  • Add metadata:                │
│    - ingestion_timestamp        │
│    - bundle_id                  │
│    - source_ip                  │
└──────────────┬──────────────────┘
               │
               ▼
┌─────────────────────────────────┐
│  4. Kafka Producer              │
│  • Batch logs (1000 records)    │
│  • Compress with Snappy         │
│  • Partition by timestamp       │
│  • Send to topic:               │
│    dstreambolt-logs             │
│  • Wait for broker ACK          │
│  • Retry on failure (3 times)   │──> If all fail: DLQ
└──────────────┬──────────────────┘
               │
               ▼
┌─────────────────────────────────┐
│  5. Metrics Collection          │
│  • Update counters:             │
│    - bundles_received           │
│    - bundles_processed          │
│    - logs_produced              │
│    - errors_encountered         │
│  • Flush to MySQL (10s)         │
└─────────────────────────────────┘
```

### 2. Stream Processing Flow

```
┌──────────────────────────────────────────────────────────────┐
│              Spark Streaming Processing Pipeline              │
└──────────────────────────────────────────────────────────────┘

Kafka Topic: dstreambolt-logs
     │
     │ Continuous stream
     │
     ▼
┌─────────────────────────────────┐
│  1. Kafka Consumer              │
│  • Subscribe to all partitions  │
│  • Read from latest offset      │
│  • Fetch batch: 1000 records    │
│  • Deserialize JSON             │
└──────────────┬──────────────────┘
               │
               ▼
┌─────────────────────────────────┐
│  2. Schema Validation           │
│  • Parse timestamp              │
│  • Extract fields:              │
│    - ip, method, endpoint       │
│    - status, response_time      │
│    - user_agent, referer        │
│  • Filter malformed records     │──> Log to error table
└──────────────┬──────────────────┘
               │
               ▼
┌─────────────────────────────────┐
│  3. Windowing (30 seconds)      │
│  • Tumbling windows             │
│  • Watermark: 2 minutes         │
│  • Group by window + keys       │
└──────────────┬──────────────────┘
               │
               ├──────────────────────────────┐
               │                              │
               ▼                              ▼
┌──────────────────────────┐   ┌──────────────────────────┐
│  4a. Endpoint Analysis   │   │  4b. Status Analysis     │
│  • Group by:             │   │  • Group by:             │
│    - endpoint, method    │   │    - status code         │
│  • Aggregate:            │   │  • Aggregate:            │
│    - request_count       │   │    - request_count       │
│    - avg_response_time   │   │    - avg_response_time   │
│    - p95, p99            │   │    - max/min             │
│    - error_count         │   │  • Calculate:            │
│    - unique_ips          │   │    - error_rate          │
└─────────────┬────────────┘   └─────────────┬────────────┘
              │                               │
              ▼                               ▼
┌─────────────────────────────────────────────────────────┐
│  5. Write to MySQL                                      │
│  • Table: endpoint_summary                              │
│  • Table: status_summary                                │
│  • Mode: Append                                         │
│  • Transaction: ACID guarantees                         │
└─────────────────────────────────────────────────────────┘
```

### 3. Monitoring & Observability Flow

```
┌──────────────────────────────────────────────────────────┐
│             Metrics Collection & Visualization            │
└──────────────────────────────────────────────────────────┘

┌─────────────┐   ┌─────────────┐   ┌─────────────┐
│  Ingestion  │   │    Kafka    │   │    Spark    │
│   Service   │   │   Broker    │   │   Cluster   │
└──────┬──────┘   └──────┬──────┘   └──────┬──────┘
       │                 │                 │
       │ Write metrics   │                 │
       ├─────────────────┼─────────────────┤
       │                 │                 │
       ▼                 ▼                 ▼
┌───────────────────────────────────────────────────┐
│              MySQL (Metrics Database)             │
│                                                   │
│  • ingest_metrics    - API performance           │
│  • kafka_metrics     - Broker stats              │
│  • spark_metrics     - Processing metrics        │
│  • endpoint_summary  - Customer analytics        │
│  • status_summary    - HTTP status breakdown     │
└───────────────────────┬───────────────────────────┘
                        │
                        │ SQL Queries
                        │
                        ▼
┌───────────────────────────────────────────────────┐
│                  Grafana Dashboards               │
│                                                   │
│  📊 Customer Analytics Dashboard:                │
│     • Requests per endpoint                      │
│     • Response time percentiles (P50/P95/P99)    │
│     • Error rate by endpoint                     │
│     • Geographic distribution                    │
│     • User agent analysis                        │
│                                                   │
│  🔧 DevOps Dashboard:                            │
│     • Ingestion throughput (req/sec)             │
│     • Queue depth                                │
│     • Kafka lag (consumer offset)                │
│     • Spark processing rate                      │
│     • Error breakdown                            │
│     • System resources (CPU/Memory/Disk)         │
└───────────────────────────────────────────────────┘
```

---

## 🎯 Component Deep Dive

### Ingestion Service

**Technology:** Flask + Gunicorn (4 workers)

**Why Flask?**
- **Lightweight**: Minimal overhead for high-throughput ingestion
- **Async capable**: Background worker threads for non-blocking I/O
- **Production-ready**: With Gunicorn, handles thousands of concurrent requests
- **Easy maintenance**: Simple Python codebase

**Key Features:**

1. **Two-Phase Ingestion**
   - Phase 1: Accept and queue (milliseconds)
   - Phase 2: Process and produce (background)
   - Prevents blocking on Kafka slowness

2. **Rate Limiting**
   - Per-IP limits: 100 requests/minute
   - Prevents abuse and DDoS
   - Uses in-memory sliding window

3. **Queue Management**
   - Disk-based queue (survives crashes)
   - Max queue size: 10,000 bundles
   - FIFO processing
   - Automatic cleanup of processed bundles

4. **Error Handling**
   - Corrupt bundles → `/corrupted/` directory
   - Kafka failures → Retry with exponential backoff
   - Permanent failures → Dead Letter Queue (DLQ)

**Metrics Tracked:**
```python
{
    "bundles_received": 45234,
    "bundles_processed": 45230,
    "bundles_failed": 4,
    "logs_produced": 4523000,
    "avg_processing_time_ms": 125.5,
    "queue_depth": 23,
    "kafka_errors": 2
}
```

---

### Apache Kafka

**Version:** 3.6.1  
**Why Kafka?**

- **Durability**: Logs written to disk, survives broker crashes
- **Scalability**: Horizontal scaling with partitions
- **High throughput**: Millions of messages per second
- **Decoupling**: Producers and consumers operate independently
- **Replay**: Consumers can reprocess historical data

**Configuration:**

```properties
# Broker Settings
broker.id=1
listeners=PLAINTEXT://10.0.10.248:9092
advertised.listeners=PLAINTEXT://10.0.10.248:9092

# Topic Configuration
num.partitions=3                    # Parallel processing
replication.factor=1                # Single broker setup
log.retention.hours=168             # 7-day retention
log.segment.bytes=1073741824        # 1GB segments

# Performance Tuning
compression.type=snappy             # Fast compression
batch.size=16384                    # 16KB batches
linger.ms=10                        # Batch delay
```

**Topic Architecture:**

```
Topic: dstreambolt-logs
├── Partition 0 (Leader: Broker 1)
│   ├── Segment 00000000000000000000.log
│   ├── Segment 00000000000001000000.log
│   └── Index files
├── Partition 1 (Leader: Broker 1)
│   └── ...
└── Partition 2 (Leader: Broker 1)
    └── ...

Messages distributed by timestamp hash
→ Ensures time-ordered processing per partition
```

---

### Apache Spark

**Version:** 3.5.0  
**Cluster Mode:** Standalone  
**Why Spark?**

- **Unified engine**: Batch + streaming in one framework
- **Fault tolerance**: RDD lineage allows recomputation on failure
- **In-memory processing**: 100x faster than MapReduce
- **Scala/Python support**: Flexible development
- **Rich ecosystem**: SQL, ML, Graph processing

**Deployment Architecture:**

```
┌────────────────────────────────────────────────────────┐
│               Spark Master (t3.small)                  │
│  IP: 52.66.171.95                                      │
│  Ports: 7077 (cluster), 8080 (UI), 6066 (REST)        │
│                                                         │
│  Responsibilities:                                     │
│  • Resource management                                 │
│  • Job scheduling                                      │
│  • Executor monitoring                                 │
│  • WebUI serving                                       │
└────────────────┬───────────────────────────────────────┘
                 │
                 │ Heartbeat (every 10s)
                 │
┌────────────────▼───────────────────────────────────────┐
│              Spark Executor (t3.small)                 │
│  IP: 65.0.74.255                                       │
│  Cores: 2, Memory: 1GB                                 │
│                                                         │
│  Responsibilities:                                     │
│  • Task execution                                      │
│  • Data shuffling                                      │
│  • Cache management                                    │
│  • Metrics reporting                                   │
└────────────────────────────────────────────────────────┘
```

**Job Configuration:**

```bash
spark-submit \
  --master spark://52.66.171.95:7077 \
  --deploy-mode client \
  --driver-memory 512m \
  --executor-memory 1g \
  --executor-cores 2 \
  --conf spark.sql.streaming.checkpointLocation=/tmp/checkpoint \
  --conf spark.streaming.kafka.maxRatePerPartition=1000 \
  --packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0 \
  spark_processor.py \
  --kafka-broker 10.0.10.248:9092 \
  --mode streaming
```

**Processing Logic:**

```python
# Streaming aggregation (30-second windows)
windowed_df = (
    df
    .withWatermark("event_timestamp", "2 minutes")
    .groupBy(
        window("event_timestamp", "30 seconds"),
        "endpoint",
        "method"
    )
    .agg(
        count("*").alias("request_count"),
        avg("response_time").alias("avg_response_time"),
        percentile_approx("response_time", 0.95).alias("p95"),
        percentile_approx("response_time", 0.99).alias("p99"),
        approx_count_distinct("ip").alias("unique_ips"),
        sum(when(col("status") >= 400, 1).otherwise(0)).alias("error_count")
    )
)

# Write to MySQL
windowed_df.writeStream \
    .format("jdbc") \
    .option("url", "jdbc:mysql://13.235.238.208:3306/dstreambolt_metrics") \
    .option("dbtable", "endpoint_summary") \
    .option("user", "root") \
    .option("password", secret_password) \
    .trigger(processingTime="30 seconds") \
    .start()
```

---

### MySQL Database

**Version:** 8.0  
**Why MySQL?**

- **ACID transactions**: Data integrity guarantees
- **Mature ecosystem**: Decades of production use
- **Grafana integration**: Native data source
- **SQL analytics**: Rich query capabilities
- **Cost-effective**: No licensing fees

**Schema Design:**

```sql
-- Endpoint aggregations (30-second windows)
CREATE TABLE endpoint_summary (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    window_start TIMESTAMP NOT NULL,
    window_end TIMESTAMP NOT NULL,
    endpoint VARCHAR(255) NOT NULL,
    method VARCHAR(10) NOT NULL,
    request_count BIGINT NOT NULL,
    avg_response_time DOUBLE,
    p95_response_time DOUBLE,
    p99_response_time DOUBLE,
    unique_ips BIGINT,
    error_count BIGINT,
    processing_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_window (window_start, endpoint),
    INDEX idx_endpoint (endpoint, window_start)
);

-- HTTP status aggregations
CREATE TABLE status_summary (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    window_start TIMESTAMP NOT NULL,
    window_end TIMESTAMP NOT NULL,
    status INT NOT NULL,
    request_count BIGINT NOT NULL,
    avg_response_size BIGINT,
    avg_response_time DOUBLE,
    max_response_time DOUBLE,
    min_response_time DOUBLE,
    processing_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_status (status, window_start),
    INDEX idx_window (window_start)
);

-- Ingestion service metrics
CREATE TABLE ingest_metrics (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    instance_id VARCHAR(50),
    bundles_received BIGINT,
    bundles_processed BIGINT,
    bundles_failed BIGINT,
    logs_produced BIGINT,
    avg_processing_time_ms DOUBLE,
    queue_depth INT,
    kafka_errors INT,
    INDEX idx_timestamp (timestamp),
    INDEX idx_instance (instance_id, timestamp)
);

-- Kafka broker metrics
CREATE TABLE kafka_metrics (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    broker_id INT,
    topic VARCHAR(255),
    partition INT,
    offset_lag BIGINT,
    messages_per_sec DOUBLE,
    bytes_in_per_sec DOUBLE,
    bytes_out_per_sec DOUBLE,
    INDEX idx_topic (topic, timestamp),
    INDEX idx_lag (offset_lag, timestamp)
);
```

**Optimization:**
- Indexes on frequently queried columns
- Partition by time (future optimization)
- Archival strategy: Move data >90 days to cold storage (S3)

---

### Jenkins CI/CD

**Why Jenkins?**

- **Pipeline as Code**: Jenkinsfile in version control
- **Extensible**: 1800+ plugins
- **Distributed builds**: Master-agent architecture
- **Industry standard**: Widely adopted, good documentation

**Pipelines Implemented:**

1. **Ingestion Deployment Pipeline**
   ```groovy
   pipeline {
       agent any
       parameters {
           string(name: 'TARGET_IPS', defaultValue: '13.232.206.53')
           string(name: 'GIT_BRANCH', defaultValue: 'main')
       }
       stages {
           stage('Checkout') {
               steps {
                   git branch: params.GIT_BRANCH,
                       credentialsId: 'jenkins-github-ssh',
                       url: 'git@github.com:dstreambolt/dstream_cloud.git'
               }
           }
           stage('Deploy') {
               steps {
                   script {
                       def ips = params.TARGET_IPS.split(',')
                       ips.each { ip ->
                           sh """
                               scp -i ~/.ssh/dstreambolt-access-key.pem \
                                   ingestion/* ubuntu@${ip}:/opt/dstreambolt/ingestion/
                               ssh -i ~/.ssh/dstreambolt-access-key.pem \
                                   ubuntu@${ip} 'sudo systemctl restart dstreambolt-ingest'
                           """
                       }
                   }
               }
           }
       }
   }
   ```

2. **Spark Jobs Deployment Pipeline**
   - Builds Scala JAR with SBT
   - Kills existing Spark jobs gracefully
   - Deploys to Spark master/executors
   - Starts new job with updated code

3. **Continuous Log Generator**
   - Generates realistic access logs
   - Sends to ingestion endpoint
   - Runs continuously for testing

---

### Grafana Monitoring

**Why Grafana?**

- **Beautiful visualizations**: Professional dashboards
- **Alerting**: Integrated alert manager
- **Multi-source**: Query MySQL, Prometheus, etc.
- **Templating**: Dynamic dashboards with variables
- **Open source**: Free, community-driven

**Dashboards:**

1. **Customer Analytics Dashboard**
   - Request volume by endpoint
   - Response time heatmaps
   - Error rate trends
   - Geographic distribution
   - Peak traffic hours

2. **DevOps Operational Dashboard**
   - System health overview
   - Ingestion throughput
   - Kafka lag monitoring
   - Spark job status
   - Resource utilization (CPU/Memory/Disk)
   - Alert status

**Sample Query (Endpoint Response Time):**
```sql
SELECT
  window_start as time,
  endpoint,
  AVG(avg_response_time) as avg_time,
  AVG(p95_response_time) as p95_time,
  AVG(p99_response_time) as p99_time
FROM endpoint_summary
WHERE window_start >= NOW() - INTERVAL 1 HOUR
GROUP BY window_start, endpoint
ORDER BY window_start
```

---

## 🔒 Security Architecture

### Network Security

```
┌────────────────────────────────────────────────────────┐
│                    VPC: 10.0.0.0/16                    │
│                                                         │
│  ┌─────────────────────────────────────────────────┐  │
│  │  Public Subnet A: 10.0.1.0/24                   │  │
│  │  AZ: ap-south-1a                                │  │
│  │                                                  │  │
│  │  ┌──────────────┐  ┌──────────────┐            │  │
│  │  │  Ingestion   │  │   DevOps     │            │  │
│  │  │  Instance    │  │   Instance   │            │  │
│  │  └──────────────┘  └──────────────┘            │  │
│  └─────────────────────────────────────────────────┘  │
│                           │                            │
│                           │ NAT Gateway                │
│                           ▼                            │
│  ┌─────────────────────────────────────────────────┐  │
│  │  Private Subnet A: 10.0.10.0/24                 │  │
│  │  AZ: ap-south-1a                                │  │
│  │                                                  │  │
│  │  ┌──────────────┐  ┌──────────────┐            │  │
│  │  │    Kafka     │  │    Spark     │            │  │
│  │  │   Broker     │  │   Cluster    │            │  │
│  │  └──────────────┘  └──────────────┘            │  │
│  └─────────────────────────────────────────────────┘  │
│                                                         │
│  Internet Gateway (IGW)                                │
│         ▲                                              │
└─────────┼──────────────────────────────────────────────┘
          │
          ▼
    Application Load Balancer
     (Internet-facing)
```

**Security Groups:**

| Service | Inbound Rules | Purpose |
|---------|---------------|---------|
| **ALB** | 443 (HTTPS) from 0.0.0.0/0 | Public ingestion endpoint |
| **Ingestion** | 5000 from ALB SG | Flask app |
| **DevOps** | 22 (SSH) from MyIP<br>3306 (MySQL) from Ingestion/Spark SG<br>8080 (Jenkins) from ALB<br>3000 (Grafana) from ALB<br>8080 (AKHQ) from ALB | Admin tools |
| **Kafka** | 9092 from Ingestion/Spark/DevOps SG<br>2181 from DevOps SG | Kafka + Zookeeper |
| **Spark** | 7077 from Spark Executor SG<br>8080 from ALB | Cluster communication |

**IAM Roles:**

```json
{
  "DStreamBolt-EC2-Role": {
    "Policies": [
      "SecretsManagerReadAccess",  // Read certificates and DB passwords
      "CloudWatchPutMetrics",       // Send custom metrics
      "S3ReadOnlyAccess"            // Download deployment artifacts
    ]
  }
}
```

---

## 💰 Cost Optimization

### Monthly Cost Breakdown (AWS ap-south-1)

| Resource | Type | Quantity | Unit Cost | Monthly Cost |
|----------|------|----------|-----------|--------------|
| **EC2 Instances** | | | | |
| Ingestion | t3.small | 1 | $15/month | $15 |
| DevOps | t3.small | 1 | $15/month | $15 |
| Kafka | t3.small | 1 | $15/month | $15 |
| Spark Master | t3.small | 1 | $15/month | $15 |
| Spark Executor | t3.small | 1 | $15/month | $15 |
| **Storage** | | | | |
| EBS (gp3) | 8GB each | 5 | $0.80/month | $4 |
| **Networking** | | | | |
| ALB | 1 | $16/month | $16 |
| Data Transfer | 10GB/month | $0.09/GB | $0.90 |
| **Secrets Manager** | | | | |
| Secrets | 5 | $0.40/secret | $2 |
| **Total** | | | | **~$97.90/month** |

**Optimization Strategies:**

1. **Use Reserved Instances**: Save 30-40% with 1-year commitment
2. **Auto-scaling (future)**: Scale executors based on Kafka lag
3. **Spot Instances**: Use for Spark executors (70% cost reduction)
4. **S3 Lifecycle**: Archive old logs to Glacier (90% cheaper)
5. **CloudWatch Logs**: Use log insights instead of storing raw logs

**Cost vs. Performance Trade-offs:**

| Scenario | Configuration | Cost | Performance |
|----------|---------------|------|-------------|
| **Current (Dev)** | All t3.small | $98/month | 10K req/sec |
| **Production Low** | t3.medium (critical) | $150/month | 50K req/sec |
| **Production High** | t3.large + auto-scale | $300/month | 200K req/sec |
| **Enterprise** | c5.xlarge + multi-AZ | $800/month | 1M req/sec |

---

## 🚀 Deployment Guide

### Prerequisites

1. **AWS Account** with admin access
2. **Terraform** v1.5+ installed
3. **AWS CLI** v2 configured
4. **SSH Key Pair** created
5. **Domain** registered (optional for mTLS)

### Step 1: Clone Repository

```bash
git clone https://github.com/dstreambolt/dstream_cloud.git
cd dstream_cloud
```

### Step 2: Configure Terraform

```bash
cd terraform

# Edit terraform.tfvars
cat > terraform.tfvars <<EOF
project_name    = "dstreambolt"
aws_region      = "ap-south-1"
key_name        = "dstreambolt-access-key"
mysql_root_password = "YourStrongPassword123!"
vpc_cidr        = "10.0.0.0/16"
EOF
```

### Step 3: Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Preview changes
terraform plan -out=tfplan

# Apply changes
terraform apply tfplan

# Save outputs
terraform output > outputs.txt
```

**Deployment time:** 10-15 minutes

### Step 4: Setup Services

```bash
cd ../setup_scripts

# Run master setup script (installs everything)
./setup_all.sh

# Or setup individually:
./setup_jenkins.sh
./setup_grafana.sh
./setup_mysql.sh
./setup_kafka.sh
./setup_spark_master.sh
./setup_spark_worker.sh
./setup_ingestion.sh
./setup_akhq.sh
```

### Step 5: Configure Secrets (Optional mTLS)

```bash
# Generate certificates
cd ../utils
./generate_certificates.sh

# Upload to Secrets Manager
./upload_secrets.sh
```

### Step 6: Import Grafana Dashboards

```bash
cd ../grafana

# Customer analytics dashboard
./import_dashboard.sh customer-analytics-dashboard.json

# DevOps dashboard
./import_dashboard.sh devops-dashboard.json
```

### Step 7: Setup Jenkins Jobs

```bash
cd ../jenkins
./setup_jenkins_jobs.sh
```

### Step 8: Test the Pipeline

```bash
cd ../examples

# Generate sample logs
python3 01-generate-logs.py --count 10000

# Send to ingestion endpoint
python3 02-send-to-ingest.py \
  --alb-url https://dstreambolt-alb-xxx.ap-south-1.elb.amazonaws.com/ingest \
  --file logs/access.log

# Check Kafka topic
python3 03-kafka-consumer.py --kafka-broker 10.0.10.248:9092

# View results in Grafana
open http://13.235.238.208:3000/grafana
```

---

## 📈 Scaling Guide

### Vertical Scaling (Increase Instance Size)

**When to scale:**
- CPU utilization > 70% sustained
- Memory usage > 80%
- Disk I/O wait > 10%

**How to scale:**

```bash
cd terraform

# Edit instance types in modules/*/main.tf
# Example: t3.small → t3.medium

terraform plan -out=scale-plan
terraform apply scale-plan
```

### Horizontal Scaling (Add More Instances)

**Kafka Cluster:**

```hcl
# modules/kafka/main.tf
resource "aws_instance" "kafka" {
  count = 3  # Increase from 1 to 3

  # Add replication
  user_data = templatefile("user_data/kafka.sh", {
    broker_id = count.index + 1
    replication_factor = 3
  })
}
```

**Spark Executors:**

```hcl
# modules/compute/main.tf
resource "aws_instance" "spark_executor" {
  count = 3  # Add more executors

  user_data = templatefile("user_data/spark_executor.sh", {
    spark_master = "spark://master-ip:7077"
    executor_memory = "2g"
    executor_cores = 4
  })
}
```

### Auto-Scaling (Future Enhancement)

```hcl
resource "aws_autoscaling_group" "spark_executors" {
  min_size = 1
  max_size = 10
  desired_capacity = 2

  # Scale up when Kafka lag > 10000
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "KafkaConsumerLag"
    }
    target_value = 10000
  }
}
```

---

## 🔍 Troubleshooting

### Common Issues

#### 1. Ingestion Service Returns 503

**Symptoms:**
```bash
curl https://alb.../ingest
{"error": "Service Unavailable", "queue_full": true}
```

**Diagnosis:**
```bash
ssh ubuntu@ingest-ip
ls -l /opt/dstreambolt/queue/ | wc -l  # Check queue depth
journalctl -u dstreambolt-ingest -n 100  # Check logs
```

**Solutions:**
- Increase worker threads in `app.py`
- Scale up Kafka brokers
- Check Kafka connectivity

#### 2. Kafka Consumer Lag

**Symptoms:** Grafana shows increasing lag in `kafka_metrics` table

**Diagnosis:**
```bash
ssh ubuntu@kafka-ip
/opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe --group spark-streaming-consumer
```

**Solutions:**
- Add more Spark executors
- Increase `spark.streaming.kafka.maxRatePerPartition`
- Optimize Spark job (reduce shuffles)

#### 3. Spark Job Failures

**Symptoms:** Spark UI shows failed tasks

**Diagnosis:**
```bash
ssh ubuntu@spark-master-ip
tail -f /opt/spark/logs/spark-*.out
```

**Common causes:**
- Out of memory → Increase executor memory
- Kafka connection timeout → Check security groups
- MySQL connection pool exhausted → Increase pool size

#### 4. Certificate Verification Failed

**Symptoms:**
```bash
urllib3.exceptions.SSLError: [SSL: CERTIFICATE_VERIFY_FAILED]
```

**Solutions:**
```bash
# Check certificate validity
openssl x509 -in certs/client/client-cert.pem -noout -dates

# Verify CA trust chain
openssl verify -CAfile certs/ca/ca-cert.pem certs/client/client-cert.pem

# Re-generate certificates if expired
cd utils && ./generate_certificates.sh
```

---

## 📚 Best Practices

### Development

1. **Version Control**: All configs in Git
2. **Feature Branches**: Use `feature/`, `bugfix/` prefixes
3. **Code Reviews**: Mandatory for production changes
4. **Testing**: Unit tests for critical paths
5. **Documentation**: Update README on architecture changes

### Production

1. **Monitoring**: Set up alerts for:
   - Queue depth > 5000
   - Kafka lag > 10000
   - Error rate > 1%
   - CPU > 80%

2. **Backups**:
   - MySQL: Daily automated backups
   - Kafka: Replication factor = 3
   - Configs: Store in S3

3. **Security**:
   - Rotate certificates every 90 days
   - Update dependencies monthly
   - Regular security audits
   - Log all access

4. **Capacity Planning**:
   - Review metrics weekly
   - Plan scaling 1 month ahead
   - Load test before traffic spikes

---

## 🔗 References

- **Apache Kafka**: https://kafka.apache.org/documentation/
- **Apache Spark**: https://spark.apache.org/docs/latest/
- **Terraform AWS**: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- **mTLS Guide**: https://www.cloudflare.com/learning/access-management/what-is-mutual-tls/
- **Grafana Docs**: https://grafana.com/docs/

---

## 📧 Support

For issues or questions:
- **GitHub Issues**: https://github.com/dstreambolt/dstream_cloud/issues
- **Email**: support@dstreambolt.click
- **Slack**: dstreambolt.slack.com

---

**Last Updated:** December 13, 2025  
**Version:** 1.0.0  
**Maintainer:** DStreamBolt Team

