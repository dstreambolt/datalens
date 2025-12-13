# Apache Kafka in DStreamBolt - Technical Deep Dive

## Table of Contents
1. [Why Kafka?](#why-kafka)
2. [Kafka Architecture in DStreamBolt](#kafka-architecture-in-dstreambolt)
3. [Topic Design & Partitioning](#topic-design--partitioning)
4. [Producer Semantics (Ingestion → Kafka)](#producer-semantics-ingestion--kafka)
5. [Consumer Semantics (Kafka → Spark)](#consumer-semantics-kafka--spark)
6. [Data Durability & Replication](#data-durability--replication)
7. [Operational Challenges](#operational-challenges)
8. [Why Not S3 Directly?](#why-not-s3-directly)
9. [Failure Scenarios & Recovery](#failure-scenarios--recovery)
10. [Performance Tuning](#performance-tuning)

---

## Why Kafka?

### The Streaming Data Problem

**Scenario**: 1000 external clients sending logs → Process with Spark → Store in MySQL

**Without Kafka** (Direct S3 writes):
```
Client 1 ──┐
Client 2 ──┼──> S3 Bucket ──> Spark (batch read every 5 min) ──> MySQL
Client 3 ──┘
```

**Problems**:
1. **No Real-Time Processing**: Wait for batch interval (5 min lag)
2. **S3 Consistency**: Eventual consistency → Spark may miss files
3. **No Replay**: Once processed, data deleted (what if bug in Spark job?)
4. **Scalability**: 1000 clients × 100 req/s = 100k S3 PUTs/sec (expensive!)
5. **No Ordering**: Files processed in random order
6. **Complex State**: Spark must track which files processed (distributed state hell)

**With Kafka** (Streaming pipeline):
```
Client 1 ──┐
Client 2 ──┼──> Ingest ──> Kafka ──(streaming)──> Spark ──> MySQL
Client 3 ──┘                 ↓
                      (retention: 7 days)
```

**Benefits**:
1. ✅ **Real-Time**: Sub-second latency (not 5 min)
2. ✅ **Decoupling**: Ingestion and processing independent (different speeds)
3. ✅ **Replay**: Reprocess last 7 days anytime (bug fixes, new features)
4. ✅ **Ordering**: Per-partition ordering guarantees
5. ✅ **Backpressure**: Kafka buffers data when Spark slow
6. ✅ **Scalability**: Horizontal (add partitions)
7. ✅ **Durability**: Replication prevents data loss

### Kafka as a "Distributed Commit Log"

Think of Kafka as:
- **Database transaction log** (append-only, ordered, durable)
- **Message queue** (producers write, consumers read)
- **Event store** (replay from any point in time)

```
Partition 0:  [Msg0] [Msg1] [Msg2] [Msg3] [Msg4] ...
              offset=0  =1    =2     =3     =4
                          ↑
                     Consumer reads from offset 2
```

Key property: **Offsets** = Position in log (like a bookmark)

---

## Kafka Architecture in DStreamBolt

### Cluster Setup

```
┌─────────────────────────────────────────────────────────┐
│              Apache Kafka Cluster                       │
│                                                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│  │  Broker 1   │  │  Broker 2   │  │  Broker 3   │    │
│  │ (Leader P0) │  │ (Leader P1) │  │ (Leader P2) │    │
│  │  Port 9092  │  │  Port 9092  │  │  Port 9092  │    │
│  └─────────────┘  └─────────────┘  └─────────────┘    │
│         ↑                ↑                ↑             │
│         └────────────────┴────────────────┘             │
│                  Zookeeper                              │
│              (Coordination)                             │
└─────────────────────────────────────────────────────────┘
```

**In DStreamBolt** (Cost-optimized):
- **Single broker** (no HA, dev/test)
- **3 partitions** (parallelism for Spark)
- **Replication factor = 1** (no data loss protection in single-broker setup)

**Production Recommendation**:
- **3 brokers** (min for HA)
- **Replication factor = 3** (tolerates 2 broker failures)
- **min.insync.replicas = 2** (write must reach 2 replicas)

### Topic: `dstreambolt-logs`

**Configuration**:
```bash
kafka-topics.sh --create \
  --bootstrap-server localhost:9092 \
  --topic dstreambolt-logs \
  --partitions 3 \
  --replication-factor 1 \
  --config retention.ms=604800000    # 7 days
  --config compression.type=gzip      # Save disk space
  --config max.message.bytes=52428800 # 50 MB max
```

**Partition Strategy**:
```
Key: client_id (e.g., "client-abc123")

Ingestion Node → hash(client_id) % 3 → Partition
  - client-abc123 → Partition 0 (all logs from this client ordered)
  - client-xyz789 → Partition 1
  - client-def456 → Partition 2
```

**Why partition by client_id?**
- **Ordering**: All logs from same client processed in order
- **Locality**: Spark can process per-client analytics efficiently
- **Load Balancing**: Clients evenly distributed across partitions

---

## Producer Semantics (Ingestion → Kafka)

### Producer Configuration

```python
from kafka import KafkaProducer

producer = KafkaProducer(
    bootstrap_servers=KAFKA_BROKER,  # '10.0.10.101:9092'
    
    # Durability
    acks='all',  # Wait for leader + all in-sync replicas
    retries=3,   # Retry on transient failures
    max_in_flight_requests_per_connection=1,  # Strict ordering
    
    # Performance
    compression_type='gzip',  # Compress before send
    batch_size=16384,         # 16 KB batches
    linger_ms=10,             # Wait 10ms to batch more messages
    buffer_memory=33554432,   # 32 MB send buffer
    
    # Idempotence
    enable_idempotence=True,  # Prevent duplicates on retry
    
    # Serialization
    key_serializer=lambda k: k.encode('utf-8'),
    value_serializer=lambda v: v.encode('utf-8')
)
```

### Sending Messages

```python
# Async send (non-blocking)
future = producer.send(
    topic='dstreambolt-logs',
    key=client_id,     # Determines partition
    value=log_line     # The actual log data
)

# Block until acknowledged (for critical data)
try:
    record_metadata = future.get(timeout=10)
    print(f"Sent to partition {record_metadata.partition}, offset {record_metadata.offset}")
except KafkaException as e:
    # Handle failure (retry, DLQ, alert)
    log_error(e)
```

### Delivery Guarantees

| Configuration | Guarantee | Data Loss Risk | Latency |
|--------------|-----------|----------------|---------|
| `acks=0` | Fire-and-forget | High (no confirmation) | Lowest |
| `acks=1` | Leader only | Medium (leader crash before replication) | Low |
| `acks=all` | Leader + replicas | None (if min.insync.replicas=2) | Higher |

**DStreamBolt Choice**: `acks=all` (no data loss acceptable)

### Idempotent Producer

**Problem**: Network glitch → Producer retries → Duplicate messages

**Solution**: `enable_idempotence=True`
- Kafka assigns unique ID to each producer
- Each message tagged with sequence number
- Broker detects duplicate sequences and deduplicates

**Result**: Exactly-once delivery from producer to Kafka

---

## Consumer Semantics (Kafka → Spark)

### Consumer Group

**Concept**: Multiple Spark executors reading from same topic (parallel processing)

```
Kafka Topic (3 partitions)
  ├─ Partition 0 ──> Spark Executor 1
  ├─ Partition 1 ──> Spark Executor 2
  └─ Partition 2 ──> Spark Executor 3

Consumer Group: "dstreambolt-spark-processor"
```

**Key Properties**:
1. **Each partition** → Assigned to exactly 1 executor (no conflicts)
2. **Rebalancing**: Executor dies → Partition reassigned to another
3. **Offset Management**: Kafka tracks which messages consumed

### Spark Streaming Configuration

```scala
val df = spark.readStream
  .format("kafka")
  .option("kafka.bootstrap.servers", "10.0.10.101:9092")
  .option("subscribe", "dstreambolt-logs")
  
  // Consumer group ID
  .option("kafka.group.id", "dstreambolt-spark-processor")
  
  // Offset strategy
  .option("startingOffsets", "latest")  // Start from newest (first run)
  // OR
  .option("startingOffsets", "earliest")  // Reprocess all data
  
  // Fetch size (tuning)
  .option("kafka.fetch.min.bytes", "1048576")  // 1 MB min
  .option("kafka.max.partition.fetch.bytes", "10485760")  // 10 MB max
  
  .load()
```

### Offset Management

**Kafka stores offsets** in special topic `__consumer_offsets`:
```
Consumer Group: dstreambolt-spark-processor
  Partition 0: offset = 12345
  Partition 1: offset = 23456
  Partition 2: offset = 34567
```

**Commit Strategies**:

1. **Auto-commit** (default, risky):
   ```scala
   .option("kafka.enable.auto.commit", "true")
   .option("kafka.auto.commit.interval.ms", "5000")  // Every 5s
   ```
   **Problem**: Commit before processing → Data loss if crash

2. **Manual commit** (Spark manages):
   ```scala
   query.awaitTermination()  // Spark commits after checkpoint
   ```
   **Benefit**: Commit only after successful write to MySQL

**DStreamBolt Strategy**: Manual commit via Spark checkpointing

### Rebalancing

**Trigger**: Consumer joins/leaves group (Spark executor crash/scale)

**Process**:
```
1. Consumer leaves → Kafka detects (heartbeat timeout 10s)
2. Coordinator triggers rebalance
3. All consumers stop consuming
4. Partitions redistributed
5. Consumers resume from last committed offset
```

**Impact**:
- **Pause**: 10-30 seconds (no processing)
- **Duplicate processing**: Uncommitted messages reprocessed
- **Mitigation**: Idempotent Spark writes (MySQL `INSERT IGNORE`)

**Avoiding Frequent Rebalances**:
```scala
.option("kafka.session.timeout.ms", "30000")      // 30s tolerance
.option("kafka.heartbeat.interval.ms", "10000")   // Send heartbeat every 10s
.option("kafka.max.poll.interval.ms", "600000")   // 10 min processing time
```

---

## Data Durability & Replication

### Replication Factor

**Configuration**: `replication.factor=3` (each partition has 3 copies)

```
Partition 0:
  Leader: Broker 1 (handles all reads/writes)
  Follower: Broker 2 (replicates data)
  Follower: Broker 3 (replicates data)
```

**Leader Election**:
- Leader fails → Kafka elects new leader from in-sync replicas (ISR)
- ISR = Replicas caught up (lag < 10 seconds)
- If all ISR down → Choose `unclean.leader.election.enable`
  - `true`: Elect out-of-sync replica (data loss possible)
  - `false`: Partition unavailable until ISR returns (no data loss)

**DStreamBolt**: `unclean.leader.election.enable=false` (prefer availability loss over data loss)

### Write Path (Producer to Disk)

```
1. Producer sends message to Leader (Broker 1)
2. Leader appends to local log file
   /var/lib/kafka-logs/dstreambolt-logs-0/00000000000000000000.log
3. Leader sends to Follower 1 (Broker 2)
4. Leader sends to Follower 2 (Broker 3)
5. Followers append to their logs
6. Followers ACK leader
7. Leader ACKs producer (if acks=all)
```

**Durability Settings**:
```properties
# Flush to disk
log.flush.interval.messages=10000  # Every 10k messages
log.flush.interval.ms=1000         # OR every 1 second

# OS page cache (performance vs. durability trade-off)
# Kafka relies on OS fsync() - data in RAM until OS flushes
```

**Risk**: OS crash before fsync → Recent messages lost (but replicated to other brokers)

---

## Operational Challenges

### Challenge 1: Broker Failures

**Scenario**: Broker 1 crashes (Leader for Partition 0)

**Detection**:
```bash
# Zookeeper marks broker dead after 10 seconds
# Controller (special broker) initiates leader election
```

**Recovery**:
```
1. Partition 0 Leader: Broker 1 → Broker 2 (from ISR)
2. Producer redirects to new leader
3. Consumer reconnects to new leader
4. Processing continues (offset preserved)
```

**Data Loss**: None (if replication.factor >= 2 and min.insync.replicas >= 2)

**Downtime**: ~10 seconds (detection + election)

### Challenge 2: Partition Lag

**Scenario**: Spark slow → Kafka offsets not advancing → Disk fills up

**Monitoring**:
```bash
kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --group dstreambolt-spark-processor \
  --describe

# Output:
# PARTITION  OFFSET  LOG-END-OFFSET  LAG
#     0      12345   999999          987654  ← BAD! 987k messages behind
```

**Causes**:
- Spark executor crashes (rebalancing delays)
- Slow MySQL writes (backpressure)
- Large batches (processing takes > 30 seconds)

**Solutions**:
1. **Scale Spark**: More executors (parallel processing)
2. **Tune batch size**: Process smaller windows (5s vs. 30s)
3. **Optimize SQL**: Batch inserts, remove locks
4. **Add Kafka disk**: Increase retention (more buffer time)

### Challenge 3: Message Too Large

**Error**:
```
MessageSizeTooLargeException: The message is 52428801 bytes when serialized 
which is larger than max.message.bytes (52428800)
```

**Causes**:
- Ingestion service sent 50+ MB bundle as single message
- Bug: Entire batch serialized as one message instead of per-log

**Solutions**:
1. **Ingestion**: Split large bundles into smaller messages
2. **Kafka**: Increase `max.message.bytes` (not recommended > 100 MB)
3. **Consumer**: Increase `fetch.max.bytes`

### Challenge 4: Unbalanced Partitions

**Scenario**: 90% of data in Partition 0, Partitions 1 & 2 idle

**Cause**: Poor key distribution (e.g., all logs have same `client_id`)

**Detection**:
```bash
kafka-log-dirs.sh --describe \
  --bootstrap-server localhost:9092 \
  --topic-list dstreambolt-logs

# Output:
# PARTITION  SIZE
#     0      45 GB  ← Hotspot!
#     1      2 GB
#     2      3 GB
```

**Solutions**:
1. **Increase partitions**: `kafka-topics.sh --alter --partitions 10`
2. **Better key**: Use `hash(client_id + timestamp)` for distribution
3. **Rebalance**: Manually move data (complex, use `kafka-reassign-partitions`)

### Challenge 5: Zookeeper Failures

**Role**: Zookeeper coordinates Kafka cluster (leader election, metadata)

**Scenario**: Zookeeper down → Kafka can't elect leaders → Writes fail

**Mitigation**:
- **Zookeeper ensemble**: 3 or 5 nodes (quorum requires majority)
- **Dedicated hardware**: Don't run Zookeeper on Kafka broker
- **Monitoring**: Alert on Zookeeper lag/disconnections

**Future**: Kafka 3.x removes Zookeeper (uses Raft instead)

---

## Why Not S3 Directly?

### S3 as Data Lake (Alternative Architecture)

```
Ingest → S3 → Spark Batch (every 5 min) → MySQL
```

**Pros**:
- ✅ Cheap storage ($0.023/GB/month vs. Kafka EBS $0.10/GB)
- ✅ Infinite retention (Kafka = 7 days)
- ✅ Simple (no Kafka to manage)

**Cons**:
- ❌ **Latency**: 5 min batch vs. sub-second streaming
- ❌ **Eventual consistency**: S3 LIST may miss new files
- ❌ **No ordering**: Files processed randomly
- ❌ **State complexity**: Track which files processed (S3 metadata or DB)
- ❌ **Cost at scale**: 100k writes/sec × $0.005/1000 = $500/hr = $360k/month!
- ❌ **No replay**: Once deleted, data gone (must keep forever)

### Hybrid Approach (Best of Both Worlds)

```
Ingest → Kafka (real-time, 7 days) → Spark → MySQL
              ↓
            S3 (archive, forever)
```

**Benefits**:
- Real-time processing via Kafka
- Long-term analytics via S3 (data lake)
- Cost-effective ($100/month Kafka + $50/month S3)

**Implementation**:
```scala
// Spark job writes to both MySQL and S3
df.writeStream
  .foreachBatch { (batchDF, batchId) =>
    // 1. Write to MySQL (real-time dashboard)
    batchDF.write.jdbc(...)
    
    // 2. Archive to S3 (data lake)
    batchDF.write.parquet(s"s3://dstreambolt-archive/year=$year/month=$month/")
  }
  .start()
```

---

## Failure Scenarios & Recovery

### Scenario 1: Single Message Corruption

**Problem**: Garbled bytes in Kafka log (disk corruption)

**Detection**:
```
Consumer fails with: org.apache.kafka.common.errors.CorruptRecordException
```

**Recovery**:
```bash
# 1. Identify bad offset
kafka-run-class.sh kafka.tools.DumpLogSegments \
  --files /var/lib/kafka-logs/dstreambolt-logs-0/00000000000000012345.log \
  --print-data-log

# 2. Skip bad message (manual offset advancement)
kafka-consumer-groups.sh --reset-offsets \
  --group dstreambolt-spark-processor \
  --topic dstreambolt-logs:0 \
  --to-offset 12346  # Skip offset 12345
```

**Data Loss**: 1 message (acceptable if isolated incident)

### Scenario 2: Entire Partition Lost (All Replicas Down)

**Problem**: Rare but catastrophic (disk failures on all 3 brokers simultaneously)

**Detection**: Partition unavailable (no leader)

**Recovery Options**:

**A. Restore from Backup** (if available):
```bash
# Stop Kafka, restore log segments from backup
kafka-server-stop.sh
aws s3 sync s3://dstreambolt-kafka-backups/partition-0/ \
  /var/lib/kafka-logs/dstreambolt-logs-0/
kafka-server-start.sh
```

**B. Accept Data Loss**:
```bash
# Enable unclean leader election (elect out-of-sync replica)
kafka-configs.sh --alter \
  --entity-type topics \
  --entity-name dstreambolt-logs \
  --add-config unclean.leader.election.enable=true
```

**Data Loss**: All messages not replicated (depends on how far behind)

**Prevention**:
- **Regular backups**: `kafka-mirror-maker` to separate cluster
- **Monitoring**: Alert on ISR < replication.factor
- **Hardware**: RAID for disks, ECC memory

### Scenario 3: Consumer Data Duplication

**Problem**: Spark crashes after processing but before committing offset

**Example**:
```
1. Spark reads offset 1000-1100 from Kafka
2. Spark processes logs, writes to MySQL
3. MySQL write succeeds
4. Spark crashes BEFORE committing offset 1100 to Kafka
5. Spark restarts, reads from last committed offset 1000
6. Processes same 100 messages again → Duplicates in MySQL!
```

**Solutions**:

**A. Idempotent Writes** (recommended):
```sql
-- MySQL: Use unique constraint on request_id
CREATE TABLE logs (
  request_id VARCHAR(255) PRIMARY KEY,
  timestamp DATETIME,
  ...
);

-- Insert becomes:
INSERT IGNORE INTO logs (...) VALUES (...);
-- OR
INSERT INTO logs (...) VALUES (...)
  ON DUPLICATE KEY UPDATE timestamp=timestamp;  -- No-op update
```

**B. Exactly-Once Semantics** (Kafka Transactions):
```scala
// Enable Kafka transactions (Spark 3.x)
df.writeStream
  .option("kafka.transactional.id", "dstreambolt-spark")
  .start()
```
**Trade-off**: Higher latency, more complex

**DStreamBolt Approach**: Idempotent writes (simpler, good enough)

### Scenario 4: Kafka Cluster Complete Failure

**Problem**: All brokers down (e.g., AWS AZ outage)

**Detection**: Producers fail with `TimeoutException`

**Recovery**:
```
1. Ingestion service: Bundles queue on disk (backpressure)
2. Alert fires: "Kafka unreachable"
3. On-call engineer investigates:
   - AWS outage? Wait for recovery
   - Config error? Fix and restart brokers
4. Kafka recovers
5. Ingestion service: Queue drains automatically
6. Spark: Resumes from last committed offset
```

**Data Loss**: None (durability via ingestion disk queue)

**Downtime**: Depends on issue (minutes to hours)

**Mitigation**: Multi-AZ deployment (brokers in 3 AZs)

---

## Performance Tuning

### Throughput Optimization

**Goal**: Maximize messages/second while maintaining durability

**Producer Tuning**:
```python
# Batch more aggressively
producer = KafkaProducer(
    batch_size=65536,        # 64 KB (default 16 KB)
    linger_ms=100,           # Wait 100ms to batch (default 0)
    compression_type='lz4',  # Faster than gzip (default none)
    buffer_memory=67108864   # 64 MB (default 32 MB)
)
```

**Kafka Tuning**:
```properties
# server.properties
num.network.threads=8           # CPU cores for network (default 3)
num.io.threads=16               # Threads for disk I/O (default 8)
socket.send.buffer.bytes=1048576  # 1 MB (default 100 KB)
socket.receive.buffer.bytes=1048576
```

**Consumer Tuning**:
```scala
.option("kafka.fetch.min.bytes", "1048576")  // 1 MB min
.option("kafka.fetch.max.wait.ms", "500")    // Wait max 500ms
.option("kafka.max.partition.fetch.bytes", "10485760")  // 10 MB per partition
```

### Latency Optimization

**Goal**: Minimize end-to-end latency (ingest → Kafka → Spark → MySQL)

**Producer**:
```python
# Trade throughput for latency
linger_ms=0,              # Send immediately
batch_size=1,             # No batching
compression_type='none'   # No compression overhead
```

**Kafka**:
```properties
# In-memory instead of disk (risky!)
log.flush.interval.messages=1
log.flush.interval.ms=1
```

**Spark**:
```scala
// Smaller micro-batches
.trigger(Trigger.ProcessingTime("1 second"))  // Default 500ms
```

**Trade-offs**: Lower latency → Lower throughput, higher CPU

### Disk Usage Optimization

**Problem**: Kafka disk fills up (200 GB in 2 days)

**Solutions**:

**1. Reduce retention**:
```bash
kafka-configs.sh --alter \
  --entity-type topics \
  --entity-name dstreambolt-logs \
  --add-config retention.ms=86400000  # 1 day (default 7 days)
```

**2. Enable compression**:
```bash
kafka-configs.sh --alter \
  --add-config compression.type=lz4  # 50-70% reduction
```

**3. Cleanup policy**:
```bash
# Delete old logs (default)
--add-config cleanup.policy=delete

# OR compact (keep only latest per key)
--add-config cleanup.policy=compact
```

**4. Monitor**:
```bash
# Alert if disk > 80%
du -sh /var/lib/kafka-logs/
```

---

## Can We Achieve Exactly-Once Processing?

### The Challenge

**Goal**: Each log line processed exactly once (no duplicates, no losses)

**Reality**: Distributed systems theory says **impossible** (CAP theorem)

**Best we can do**:
- **At-most-once**: Possible data loss, no duplicates
- **At-least-once**: No data loss, possible duplicates ← **DStreamBolt**
- **Effectively-once**: At-least-once + idempotent operations

### DStreamBolt Approach: Idempotent Pipeline

**1. Ingestion → Kafka** (at-least-once):
- `acks=all` + `enable_idempotence=True`
- Duplicate on retry, but Kafka dedupes
- **Result**: Exactly-once into Kafka

**2. Kafka → Spark** (at-least-once):
- Manual offset commit after processing
- Duplicate on rebalance (before commit)
- **Result**: At-least-once into Spark

**3. Spark → MySQL** (idempotent writes):
```sql
-- Unique constraint prevents duplicates
INSERT INTO endpoint_summary (window_start, endpoint, method, request_count)
VALUES ('2025-12-13 10:00:00', '/api/users', 'GET', 100)
ON DUPLICATE KEY UPDATE 
  request_count = request_count;  -- No-op if exists
```
- **Result**: Effectively-once in MySQL

**Final Guarantee**: No data loss, no visible duplicates (idempotent writes hide them)

---

## Summary

**Why Kafka?**
- ✅ Real-time streaming (not batch)
- ✅ Decouples producers and consumers
- ✅ Durability via replication
- ✅ Horizontal scalability
- ✅ Replay capability (7 days retention)

**Key Learnings**:
1. **Replication**: Set RF=3, min.insync.replicas=2 (no data loss)
2. **Monitoring**: Track consumer lag, disk usage, ISR
3. **Tuning**: Balance throughput, latency, disk based on use case
4. **Idempotency**: Design for at-least-once + idempotent writes
5. **Operations**: Plan for broker failures, rebalancing, disk exhaustion

**Next**: Read [SPARK_DEEPDIVE.md](./SPARK_DEEPDIVE.md) to understand how Spark processes Kafka data.

