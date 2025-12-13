# Schema Evolution and System Failures Deep Dive

> **Version:** 1.0 | **Last Updated:** December 13, 2025  
> **Status:** Production-Ready | **Audience:** Engineers, Architects, DevOps

---

## 📑 Table of Contents

1. [Schema Evolution](#-schema-evolution)
   - [Understanding the Problem](#understanding-the-problem)
   - [Schema Change Scenarios](#schema-change-scenarios)
   - [Handling Strategy in DStreamBolt](#handling-strategy-in-dstreambolt)
   - [Implementation Guide](#implementation-guide)
   - [Best Practices](#best-practices)

2. [System Failure Scenarios](#-system-failure-scenarios)
   - [Comprehensive Failure Catalog](#comprehensive-failure-catalog)
   - [Detection and Prevention](#detection-and-prevention)
   - [Recovery Procedures](#recovery-procedures)

3. [Schema Registry Implementation](#-schema-registry-implementation)
4. [Backwards Compatibility](#-backwards-compatibility)
5. [Testing Schema Changes](#-testing-schema-changes)
6. [Production Rollout Strategy](#-production-rollout-strategy)

---

## 🔄 Schema Evolution

### Understanding the Problem

In a real-time streaming system like DStreamBolt, log schemas can evolve over time as:
- Clients add new fields for enhanced tracking
- Business requirements change
- New data sources are integrated
- Compliance requirements mandate new fields

**Current Log Schema:**
```
84.167.73.187 - - [07/Dec/2025:20:59:02 +0000] "PATCH /health HTTP/1.1" 200 1887 "https://app.example.com/api/v1/inventory" "Mozilla/5.0..." 0.704
```

**Parsed Fields:**
```scala
case class LogEntry(
  ip: String,                    // Client IP
  timestamp: String,             // Request timestamp
  method: String,                // HTTP method
  endpoint: String,              // Request path
  status: Int,                   // HTTP status
  size: Int,                     // Response size
  referer: String,               // Referer URL
  user_agent: String,            // User agent
  response_time: Double,         // Response time in seconds
  request_id: String,            // Generated UUID
  ingestion_timestamp: String    // When ingested
)
```

---

### Schema Change Scenarios

#### Scenario 1: Client Adds New Fields

**Before:**
```
84.167.73.187 - - [07/Dec/2025:20:59:02 +0000] "GET /api/v1/users HTTP/1.1" 200 1234 "-" "curl/7.68" 0.5
```

**After (with new fields):**
```
84.167.73.187 - - [07/Dec/2025:20:59:02 +0000] "GET /api/v1/users HTTP/1.1" 200 1234 "-" "curl/7.68" 0.5 region=us-east-1 user_id=12345 session_id=abc123
```

**Impact:**
- Spark parser may fail if not prepared
- Existing queries break
- Data loss if new fields ignored

#### Scenario 2: Field Type Changes

**Before:**
```scala
status: Int  // 200, 404, 500
```

**After:**
```scala
status: String  // "200 OK", "404 Not Found"
```

**Impact:**
- Type mismatch errors
- Spark job crashes
- Data corruption in downstream

#### Scenario 3: Field Order Changes

**Before:**
```
IP - - [TIMESTAMP] "METHOD ENDPOINT VERSION" STATUS SIZE REFERER UA RESPONSE_TIME
```

**After:**
```
IP - - [TIMESTAMP] "METHOD VERSION ENDPOINT" STATUS SIZE REFERER UA RESPONSE_TIME
```

**Impact:**
- Parsing errors
- Field misalignment
- Incorrect analytics

#### Scenario 4: Optional Fields Added

**New Optional Fields:**
```
request_id=uuid
customer_tier=premium
geo_country=US
device_type=mobile
```

#### Scenario 5: Nested JSON Fields

**Before:** Simple key-value pairs
```
user_id=12345
```

**After:** Nested JSON
```
user={"id":12345,"name":"John","tier":"premium"}
```

---

### Handling Strategy in DStreamBolt

#### 1. **Schema-on-Read Approach (Current)**

**Advantages:**
- Flexible for evolving schemas
- No upfront schema definition
- Handles missing fields gracefully

**Disadvantages:**
- Runtime parsing errors
- No compile-time safety
- Potential data quality issues

**Current Implementation:**
```scala
// Regex-based parsing (brittle)
val logPattern = """^(\S+) \S+ \S+ \[([\w:/]+\s[+\-]\d{4})\] "(\S+) (\S+).*?" (\d{3}) (\d+)""".r

df.select(
  regexp_extract($"value", logPattern, 1).as("ip"),
  regexp_extract($"value", logPattern, 2).as("timestamp"),
  // ...
)
```

**Problem:** New fields ignored, no validation

---

#### 2. **Schema Evolution Strategy (Recommended)**

##### A. Versioned Schema Approach

```scala
object LogSchemaV1 {
  val schema = StructType(Array(
    StructField("ip", StringType, nullable = false),
    StructField("timestamp", StringType, nullable = false),
    StructField("method", StringType, nullable = false),
    StructField("endpoint", StringType, nullable = false),
    StructField("status", IntegerType, nullable = false),
    StructField("size", IntegerType, nullable = false),
    StructField("referer", StringType, nullable = true),
    StructField("user_agent", StringType, nullable = false),
    StructField("response_time", DoubleType, nullable = false)
  ))
}

object LogSchemaV2 {
  val schema = StructType(Array(
    // All V1 fields
    StructField("ip", StringType, nullable = false),
    StructField("timestamp", StringType, nullable = false),
    StructField("method", StringType, nullable = false),
    StructField("endpoint", StringType, nullable = false),
    StructField("status", IntegerType, nullable = false),
    StructField("size", IntegerType, nullable = false),
    StructField("referer", StringType, nullable = true),
    StructField("user_agent", StringType, nullable = false),
    StructField("response_time", DoubleType, nullable = false),
    
    // New V2 fields (nullable for backwards compatibility)
    StructField("region", StringType, nullable = true),
    StructField("user_id", StringType, nullable = true),
    StructField("session_id", StringType, nullable = true),
    StructField("request_id", StringType, nullable = true)
  ))
}
```

##### B. Dynamic Schema Detection

```scala
/**
 * Detect schema version from log line
 */
def detectSchemaVersion(logLine: String): Int = {
  // Count fields or look for version marker
  val fieldCount = logLine.split(" ").length
  
  if (logLine.contains("region=") || logLine.contains("user_id=")) {
    2  // V2 schema
  } else if (fieldCount >= 9) {
    1  // V1 schema
  } else {
    0  // Unknown/malformed
  }
}

/**
 * Parse with appropriate schema
 */
def parseLogLine(logLine: String): Option[Row] = {
  val version = detectSchemaVersion(logLine)
  
  version match {
    case 1 => parseV1(logLine)
    case 2 => parseV2(logLine)
    case _ => 
      logger.warn(s"Unknown schema version for: $logLine")
      None
  }
}
```

##### C. Union Schema Approach

```scala
/**
 * Create union schema supporting all versions
 */
val unionSchema = StructType(
  LogSchemaV1.schema.fields ++ 
  Array(
    StructField("schema_version", IntegerType, nullable = false),
    StructField("region", StringType, nullable = true),
    StructField("user_id", StringType, nullable = true),
    StructField("session_id", StringType, nullable = true),
    StructField("request_id", StringType, nullable = true),
    StructField("custom_fields", MapType(StringType, StringType), nullable = true)
  )
)

/**
 * Parse with union schema
 */
val parsedDF = rawDF.mapPartitions { partition =>
  partition.flatMap { logLine =>
    val version = detectSchemaVersion(logLine)
    
    val baseFields = parseBaseFields(logLine)
    val additionalFields = parseAdditionalFields(logLine, version)
    
    Some(Row(
      baseFields :+ version :+ additionalFields: _*
    ))
  }
}(RowEncoder(unionSchema))
```

---

#### 3. **Flexible Parser Implementation**

```scala
/**
 * Production-ready schema-flexible parser
 */
object FlexibleLogParser {
  
  // Base regex for standard fields (always present)
  private val basePattern = 
    """^(\S+) \S+ \S+ \[([\w:/]+\s[+\-]\d{4})\] "(\S+) (\S+).*?" (\d{3}) (\d+) "([^"]*)" "([^"]*)" ([\d.]+)""".r
  
  // Pattern for key-value pairs (optional fields)
  private val kvPattern = """(\w+)=([\w\-]+)""".r
  
  /**
   * Parse log line with flexible schema support
   */
  def parse(logLine: String): Try[LogEntry] = Try {
    // Parse base fields
    val baseMatch = basePattern.findFirstMatchIn(logLine)
      .getOrElse(throw new IllegalArgumentException(s"Invalid log format: $logLine"))
    
    // Extract standard fields
    val ip = baseMatch.group(1)
    val timestamp = baseMatch.group(2)
    val method = baseMatch.group(3)
    val endpoint = baseMatch.group(4)
    val status = baseMatch.group(5).toInt
    val size = baseMatch.group(6).toInt
    val referer = baseMatch.group(7)
    val userAgent = baseMatch.group(8)
    val responseTime = baseMatch.group(9).toDouble
    
    // Parse optional key-value fields
    val remainingText = logLine.substring(baseMatch.end)
    val customFields = kvPattern.findAllMatchIn(remainingText)
      .map { m => m.group(1) -> m.group(2) }
      .toMap
    
    LogEntryV2(
      ip = ip,
      timestamp = timestamp,
      method = method,
      endpoint = endpoint,
      status = status,
      size = size,
      referer = referer,
      userAgent = userAgent,
      responseTime = responseTime,
      region = customFields.get("region"),
      userId = customFields.get("user_id"),
      sessionId = customFields.get("session_id"),
      requestId = customFields.get("request_id"),
      customFields = customFields -- Set("region", "user_id", "session_id", "request_id")
    )
  }
  
  /**
   * Batch parse with error handling
   */
  def parseBatch(logLines: Iterator[String]): (Seq[LogEntryV2], Seq[ParseError]) = {
    val (successes, failures) = logLines.map { line =>
      parse(line) match {
        case Success(entry) => Left(entry)
        case Failure(ex) => Right(ParseError(line, ex.getMessage))
      }
    }.toSeq.partition(_.isLeft)
    
    (
      successes.map(_.left.get),
      failures.map(_.right.get)
    )
  }
}

case class LogEntryV2(
  // Standard fields (always present)
  ip: String,
  timestamp: String,
  method: String,
  endpoint: String,
  status: Int,
  size: Int,
  referer: String,
  userAgent: String,
  responseTime: Double,
  
  // V2 fields (optional)
  region: Option[String] = None,
  userId: Option[String] = None,
  sessionId: Option[String] = None,
  requestId: Option[String] = None,
  
  // Catch-all for unknown fields
  customFields: Map[String, String] = Map.empty
)

case class ParseError(logLine: String, error: String)
```

---

#### 4. **Spark Streaming with Schema Evolution**

```scala
/**
 * Complete Spark job with schema evolution support
 */
object SchemaEvolutionSparkProcessor {
  
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .appName("DStreamBolt-SchemaEvolution")
      .config("spark.sql.streaming.schemaInference", "true")
      .config("spark.sql.adaptive.enabled", "true")
      .getOrCreate()
    
    import spark.implicits._
    
    // Read from Kafka
    val kafkaDF = spark.readStream
      .format("kafka")
      .option("kafka.bootstrap.servers", kafkaBroker)
      .option("subscribe", "dstreambolt-logs")
      .option("startingOffsets", "latest")
      .load()
    
    // Parse with schema evolution support
    val parsedDF = kafkaDF
      .selectExpr("CAST(value AS STRING) as log_line")
      .mapPartitions { partition =>
        partition.flatMap { row =>
          val logLine = row.getString(0)
          FlexibleLogParser.parse(logLine).toOption
        }
      }
    
    // Write to versioned tables
    val query = parsedDF.writeStream
      .foreachBatch { (batchDF: Dataset[LogEntryV2], batchId: Long) =>
        // Separate by schema version
        val v1Data = batchDF.filter(_.customFields.isEmpty)
        val v2Data = batchDF.filter(_.customFields.nonEmpty)
        
        // Write V1 data to existing table
        writeToMySQL(v1Data, "log_entries_v1")
        
        // Write V2 data to new table
        writeToMySQL(v2Data, "log_entries_v2")
        
        // Also write to unified view
        writeToMySQL(batchDF, "log_entries_union")
      }
      .option("checkpointLocation", checkpointPath)
      .start()
    
    query.awaitTermination()
  }
  
  def writeToMySQL(df: Dataset[LogEntryV2], tableName: String): Unit = {
    df.write
      .mode("append")
      .format("jdbc")
      .option("url", mysqlUrl)
      .option("dbtable", tableName)
      .option("user", mysqlUser)
      .option("password", mysqlPassword)
      .save()
  }
}
```

---

### Implementation Guide

#### Step 1: Prepare MySQL Schema

```sql
-- V1 table (existing)
CREATE TABLE IF NOT EXISTS log_entries_v1 (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  ip VARCHAR(45) NOT NULL,
  timestamp VARCHAR(50) NOT NULL,
  method VARCHAR(10) NOT NULL,
  endpoint VARCHAR(500) NOT NULL,
  status INT NOT NULL,
  size INT NOT NULL,
  referer VARCHAR(1000),
  user_agent VARCHAR(500),
  response_time DOUBLE NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_timestamp (timestamp),
  INDEX idx_endpoint (endpoint(255)),
  INDEX idx_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- V2 table (with additional fields)
CREATE TABLE IF NOT EXISTS log_entries_v2 (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  ip VARCHAR(45) NOT NULL,
  timestamp VARCHAR(50) NOT NULL,
  method VARCHAR(10) NOT NULL,
  endpoint VARCHAR(500) NOT NULL,
  status INT NOT NULL,
  size INT NOT NULL,
  referer VARCHAR(1000),
  user_agent VARCHAR(500),
  response_time DOUBLE NOT NULL,
  
  -- V2 fields
  region VARCHAR(50),
  user_id VARCHAR(100),
  session_id VARCHAR(100),
  request_id VARCHAR(100),
  
  -- JSON for unknown fields
  custom_fields JSON,
  
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_timestamp (timestamp),
  INDEX idx_endpoint (endpoint(255)),
  INDEX idx_status (status),
  INDEX idx_user_id (user_id),
  INDEX idx_session_id (session_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Union view for backwards compatibility
CREATE OR REPLACE VIEW log_entries_union AS
SELECT 
  id, ip, timestamp, method, endpoint, status, size,
  referer, user_agent, response_time,
  NULL as region,
  NULL as user_id,
  NULL as session_id,
  NULL as request_id,
  NULL as custom_fields,
  created_at,
  1 as schema_version
FROM log_entries_v1
UNION ALL
SELECT 
  id, ip, timestamp, method, endpoint, status, size,
  referer, user_agent, response_time,
  region, user_id, session_id, request_id, custom_fields,
  created_at,
  2 as schema_version
FROM log_entries_v2;
```

#### Step 2: Update Spark Job

```bash
# Deploy new Spark job with schema evolution support
cd /opt/dstreambolt/computations

# Update SparkProcessor.scala with FlexibleLogParser
nano src/main/scala/com/dstreambolt/processor/SparkProcessor.scala

# Rebuild
sbt clean package

# Test with sample data
spark-submit \
  --master spark://10.0.1.199:7077 \
  --class com.dstreambolt.processor.SchemaEvolutionSparkProcessor \
  target/scala-2.12/dstreambolt-processor_2.12-1.0.jar \
  --kafka-broker 10.0.10.248:9092 \
  --mode streaming
```

#### Step 3: Rolling Deployment

```bash
# 1. Deploy V2 tables (non-destructive)
mysql -u root -p dstreambolt_metrics < schema_v2.sql

# 2. Deploy new Spark job (parallel to existing)
# Run both V1 and V2 processors temporarily
./submit_job_v1.sh &  # Old processor
./submit_job_v2.sh &  # New processor

# 3. Monitor for 24 hours
# Check both tables are being populated

# 4. Cutover
# Stop V1 processor
# Keep only V2 processor

# 5. Migrate historical data (if needed)
INSERT INTO log_entries_v2 (ip, timestamp, method, endpoint, ...)
SELECT ip, timestamp, method, endpoint, ..., NULL, NULL, NULL, NULL, NULL
FROM log_entries_v1
WHERE created_at < NOW() - INTERVAL 7 DAY;
```

---

### Best Practices

#### 1. **Schema Registry**

**Use Apache Avro/Schema Registry:**

```scala
// Define schema in Avro
{
  "type": "record",
  "name": "LogEntry",
  "namespace": "com.dstreambolt",
  "fields": [
    {"name": "ip", "type": "string"},
    {"name": "timestamp", "type": "string"},
    {"name": "method", "type": "string"},
    {"name": "endpoint", "type": "string"},
    {"name": "status", "type": "int"},
    {"name": "size", "type": "int"},
    {"name": "referer", "type": ["null", "string"], "default": null},
    {"name": "user_agent", "type": "string"},
    {"name": "response_time", "type": "double"},
    
    // V2 fields (optional)
    {"name": "region", "type": ["null", "string"], "default": null},
    {"name": "user_id", "type": ["null", "string"], "default": null},
    {"name": "session_id", "type": ["null", "string"], "default": null}
  ]
}
```

**Integrate with Confluent Schema Registry:**

```scala
val schemaRegistryUrl = "http://localhost:8081"

val avroDF = kafkaDF
  .select(
    from_avro($"value", schemaRegistryUrl, "dstreambolt-logs-value").as("data")
  )
  .select("data.*")
```

**Benefits:**
- Centralized schema management
- Automatic schema evolution
- Backwards/forwards compatibility
- Schema validation at write time

#### 2. **Versioning Strategy**

**Semantic Versioning for Schemas:**
- **Major version:** Breaking changes (field removal, type changes)
- **Minor version:** Non-breaking additions (new optional fields)
- **Patch version:** Bug fixes (no schema changes)

**Example:**
```
v1.0.0 → Initial schema (9 fields)
v1.1.0 → Added 'region' field (optional)
v1.2.0 → Added 'user_id', 'session_id' (optional)
v2.0.0 → Changed 'status' from Int to String (BREAKING)
```

#### 3. **Backwards Compatibility Rules**

**Always Safe:**
- ✅ Add new optional fields
- ✅ Add default values
- ✅ Widen field types (Int → Long, Float → Double)

**Never Safe:**
- ❌ Remove fields
- ❌ Rename fields
- ❌ Change field types (String → Int)
- ❌ Make optional fields required

#### 4. **Testing Schema Changes**

```scala
class SchemaEvolutionTest extends AnyFlatSpec with Matchers {
  
  "FlexibleLogParser" should "parse V1 logs" in {
    val v1Log = """84.167.73.187 - - [07/Dec/2025:20:59:02 +0000] "GET /api HTTP/1.1" 200 1234 "-" "curl" 0.5"""
    
    val result = FlexibleLogParser.parse(v1Log)
    
    result.isSuccess shouldBe true
    result.get.ip shouldBe "84.167.73.187"
    result.get.region shouldBe None
  }
  
  it should "parse V2 logs with new fields" in {
    val v2Log = """84.167.73.187 - - [07/Dec/2025:20:59:02 +0000] "GET /api HTTP/1.1" 200 1234 "-" "curl" 0.5 region=us-east-1 user_id=12345"""
    
    val result = FlexibleLogParser.parse(v2Log)
    
    result.isSuccess shouldBe true
    result.get.region shouldBe Some("us-east-1")
    result.get.userId shouldBe Some("12345")
  }
  
  it should "handle malformed logs gracefully" in {
    val malformedLog = "invalid log format"
    
    val result = FlexibleLogParser.parse(malformedLog)
    
    result.isFailure shouldBe true
  }
  
  it should "handle unknown custom fields" in {
    val logWithUnknown = """84.167.73.187 - - [07/Dec/2025:20:59:02 +0000] "GET /api HTTP/1.1" 200 1234 "-" "curl" 0.5 custom_field=value"""
    
    val result = FlexibleLogParser.parse(logWithUnknown)
    
    result.isSuccess shouldBe true
    result.get.customFields should contain key "custom_field"
  }
}
```

#### 5. **Monitoring Schema Changes**

```scala
/**
 * Track schema versions in metrics
 */
def recordSchemaMetrics(batchDF: Dataset[LogEntryV2]): Unit = {
  val schemaCounts = batchDF
    .select(
      when($"region".isNotNull || $"userId".isNotNull, "v2")
        .otherwise("v1")
        .as("schema_version")
    )
    .groupBy("schema_version")
    .count()
    .collect()
  
  schemaCounts.foreach { row =>
    val version = row.getString(0)
    val count = row.getLong(1)
    
    logger.info(s"Processed $count records with schema version $version")
    
    // Send to metrics system
    metricsClient.gauge(s"schema.version.$version", count)
  }
}
```

**Grafana Dashboard:**
```sql
-- Track schema version distribution
SELECT 
  DATE(created_at) as date,
  COUNT(*) as v1_count
FROM log_entries_v1
WHERE created_at >= NOW() - INTERVAL 7 DAY
GROUP BY DATE(created_at)

UNION ALL

SELECT 
  DATE(created_at) as date,
  COUNT(*) as v2_count
FROM log_entries_v2
WHERE created_at >= NOW() - INTERVAL 7 DAY
GROUP BY DATE(created_at);
```

---

## 🚨 System Failure Scenarios

### Comprehensive Failure Catalog

#### Category 1: Data Loss Scenarios

##### 1.1 **Kafka Broker Disk Full**

**Symptom:**
```
ERROR [ReplicaManager broker=1] Error processing append operation on partition dstreambolt-logs-0
org.apache.kafka.common.errors.KafkaStorageException: Error while writing to checkpoint file
```

**Impact:**
- New messages rejected
- Producers get timeouts
- Data loss if no retries

**Detection:**
```bash
# Monitor disk usage
df -h /var/lib/kafka-logs/

# Check Kafka logs
tail -f /opt/kafka/logs/server.log | grep -i "disk\|storage"
```

**Prevention:**
```bash
# Configure retention
log.retention.hours=168  # 7 days
log.retention.bytes=10737418240  # 10 GB per partition

# Enable cleanup
log.cleanup.policy=delete

# Alert at 80% disk usage
```

**Recovery:**
```bash
# 1. Stop Kafka
sudo systemctl stop kafka

# 2. Clean old segments
cd /var/lib/kafka-logs/dstreambolt-logs-0
rm -f *.log.deleted *.index.deleted *.timeindex.deleted

# 3. Reduce retention
nano /opt/kafka/config/server.properties
# Set: log.retention.hours=72

# 4. Restart
sudo systemctl start kafka
```

---

##### 1.2 **Ingestion Queue Overflow**

**Symptom:**
```json
{
  "error": "Service Unavailable",
  "queue_full": true,
  "queue_size": 10000
}
```

**Impact:**
- HTTP 503 errors
- Clients retry
- Potential data loss

**Detection:**
```bash
# Check queue depth
ls /opt/dstreambolt/queue/*.gz | wc -l

# Alert if > 5000
if [ $(ls /opt/dstreambolt/queue/*.gz 2>/dev/null | wc -l) -gt 5000 ]; then
  echo "ALERT: Queue overflow!"
fi
```

**Prevention:**
```python
# In app.py - implement backpressure
MAX_QUEUE_SIZE = 10000
RATE_LIMIT_THRESHOLD = 8000

if get_queue_size() > RATE_LIMIT_THRESHOLD:
    # Reduce rate limit
    limiter.limit = "50 per minute"  # From 100
elif get_queue_size() > MAX_QUEUE_SIZE:
    # Reject new requests
    return jsonify({"error": "Service overloaded"}), 503
```

**Recovery:**
```bash
# 1. Check Kafka availability
nc -zv 10.0.10.248 9092

# 2. If Kafka down, restart
ssh -J ubuntu@13.235.238.208 ubuntu@10.0.10.248 \
  'sudo systemctl restart kafka'

# 3. Monitor queue draining
watch 'ls /opt/dstreambolt/queue/*.gz | wc -l'

# 4. If still stuck, add more workers
# Increase WORKER_THREADS in app.py from 4 to 8
```

---

##### 1.3 **Spark Checkpoint Corruption**

**Symptom:**
```
ERROR StateStore: Error loading version 123 of state store
org.apache.spark.sql.streaming.StreamingQueryException: Checkpoint corrupted
```

**Impact:**
- Spark job crashes
- Cannot resume from checkpoint
- Must reprocess from Kafka beginning

**Detection:**
```bash
# Check checkpoint health
ls -lh /opt/spark/checkpoints/dstreambolt/

# Look for incomplete files
find /opt/spark/checkpoints/dstreambolt/ -name "*.tmp" -o -name "*.incomplete"
```

**Prevention:**
```scala
// Use reliable checkpoint storage
.option("checkpointLocation", "hdfs://namenode:9000/checkpoints/dstreambolt")
// Or S3
.option("checkpointLocation", "s3a://dstreambolt-checkpoints/")

// Enable checkpoint compression
spark.conf.set("spark.sql.streaming.checkpointFileManagerClass",
  "org.apache.spark.sql.execution.streaming.state.RocksDBFileManager")
```

**Recovery:**
```bash
# 1. Stop Spark job
PID=$(cat /opt/dstreambolt/computations/spark_job.pid)
kill -TERM $PID

# 2. Remove corrupted checkpoint
rm -rf /opt/spark/checkpoints/dstreambolt/*

# 3. Restart from latest Kafka offset (data loss acceptable)
# Or restart from beginning (reprocess all data)
spark-submit \
  --conf spark.sql.streaming.startingOffsets=latest \
  # ... other options
  
# 4. For zero data loss, use Kafka offset management
```

---

#### Category 2: Performance Degradation

##### 2.1 **Spark Shuffle Spill to Disk**

**Symptom:**
```
WARN MemoryStore: Not enough space to cache partition
INFO ExternalSorter: Thread 123 spilling in-memory map to disk (100 MB)
```

**Impact:**
- Slower processing
- High disk I/O
- Increased latency

**Detection:**
```scala
// Monitor Spark metrics
spark.conf.get("spark.executor.metrics.enabled")

// Check Spark UI
http://52.66.171.95:8080 → Stages → Shuffle Read/Write
```

**Prevention:**
```scala
// Increase executor memory
spark.conf.set("spark.executor.memory", "2g")
spark.conf.set("spark.memory.fraction", "0.8")

// Reduce shuffle partitions
spark.conf.set("spark.sql.shuffle.partitions", "6")  // From 200

// Enable adaptive query execution
spark.conf.set("spark.sql.adaptive.enabled", "true")
```

**Resolution:**
```bash
# 1. Check executor memory
curl -s http://65.0.74.255:8081/metrics/json | jq '.gauges | with_entries(select(.key | contains("memory")))'

# 2. Upgrade executor instance
# See OPERATIONS_GUIDE.md - Task 3: Upgrade Instance Type

# 3. Reduce batch size
# In SparkProcessor.scala
.option("maxOffsetsPerTrigger", "500")  // From 1000
```

---

##### 2.2 **MySQL Connection Pool Exhaustion**

**Symptom:**
```
Exception: Cannot get connection from pool
java.sql.SQLException: Timeout: Pool empty. Unable to fetch a connection in 30 seconds
```

**Impact:**
- Spark writes fail
- Data queues in memory
- Potential OOM

**Detection:**
```sql
-- Check active connections
SHOW PROCESSLIST;

-- Check connection limits
SHOW VARIABLES LIKE 'max_connections';

-- Connection count
SELECT COUNT(*) FROM information_schema.PROCESSLIST;
```

**Prevention:**
```scala
// Configure connection pool
.option("numPartitions", "4")  // Match MySQL connection limit
.option("batchsize", "1000")
.option("isolationLevel", "READ_UNCOMMITTED")

// Use connection pooling
val connectionPool = HikariDataSource(
  jdbcUrl = mysqlUrl,
  username = mysqlUser,
  password = mysqlPassword,
  maximumPoolSize = 10,
  connectionTimeout = 30000,
  idleTimeout = 600000
)
```

**Resolution:**
```sql
-- 1. Kill long-running queries
SELECT id, user, time, state, info 
FROM information_schema.PROCESSLIST 
WHERE time > 60 AND state != 'Sleep';

KILL <connection_id>;

-- 2. Increase max connections
SET GLOBAL max_connections = 200;

-- Make permanent
sudo nano /etc/mysql/mysql.conf.d/mysqld.cnf
# Add: max_connections = 200
sudo systemctl restart mysql
```

---

##### 2.3 **Kafka Consumer Lag Growing**

**Symptom:**
```bash
TOPIC           PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG
dstreambolt-logs    0      1000000         1500000         500000  # Growing!
```

**Impact:**
- Increasing end-to-end latency
- Real-time dashboards stale
- Disk fills up on Kafka broker

**Detection:**
```bash
# Monitor lag
/opt/kafka/bin/kafka-consumer-groups.sh \
  --describe --group spark-consumer \
  --bootstrap-server localhost:9092

# Alert if lag > 50k
```

**Root Causes:**
1. Spark processing too slow
2. Kafka producing too fast
3. Downstream bottleneck (MySQL)

**Resolution:**
```bash
# 1. Scale Spark executors
# Add more executors (see OPERATIONS_GUIDE.md - Scale Up Spark)

# 2. Optimize Spark job
# Reduce shuffle, increase batch interval

# 3. Optimize MySQL writes
# Batch inserts, tune indexes

# 4. Add Kafka partitions
/opt/kafka/bin/kafka-topics.sh --alter \
  --topic dstreambolt-logs \
  --partitions 12 \
  --bootstrap-server localhost:9092
```

---

#### Category 3: Network Failures

##### 3.1 **VPC Routing Issues**

**Symptom:**
- Spark cannot reach Kafka: `Connection timeout`
- Ingestion cannot reach Kafka: `No route to host`

**Detection:**
```bash
# From Spark master
nc -zv 10.0.10.248 9092
# Connection refused or timeout

# Check route table
ip route
```

**Prevention:**
```bash
# Verify security groups allow traffic
aws ec2 describe-security-groups \
  --group-ids sg-xxx \
  --query 'SecurityGroups[*].IpPermissions'

# Check NACL rules
aws ec2 describe-network-acls \
  --filters "Name=vpc-id,Values=vpc-xxx"
```

**Resolution:**
```bash
# 1. Fix security group
aws ec2 authorize-security-group-ingress \
  --group-id sg-kafka \
  --protocol tcp \
  --port 9092 \
  --source-group sg-spark

# 2. Check route table
aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=vpc-xxx"

# 3. Restart services
sudo systemctl restart dstreambolt-ingest
sudo systemctl restart spark-job
```

---

##### 3.2 **DNS Resolution Failures**

**Symptom:**
```
ERROR: Could not resolve hostname 'kafka.dstreambolt.internal'
java.net.UnknownHostException
```

**Detection:**
```bash
# Test DNS
nslookup kafka.dstreambolt.internal
dig kafka.dstreambolt.internal

# Check /etc/hosts
cat /etc/hosts
```

**Resolution:**
```bash
# Use IP addresses instead of hostnames
# In spark-submit:
--conf spark.kafka.bootstrap.servers=10.0.10.248:9092

# Or add to /etc/hosts
echo "10.0.10.248 kafka.dstreambolt.internal" | sudo tee -a /etc/hosts
```

---

##### 3.3 **ALB Health Check Failures**

**Symptom:**
- Ingestion returns 503 via ALB
- Direct access to instance works

**Detection:**
```bash
# Check target health
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:...

# Expected: "State": "healthy"
# Actual: "State": "unhealthy", "Reason": "Target.ResponseCodeMismatch"
```

**Root Causes:**
1. Health endpoint returns wrong status code
2. Health check path incorrect
3. Security group blocks ALB

**Resolution:**
```bash
# 1. Fix health endpoint (should return 200)
curl -v http://10.0.1.72:5000/health
# Should return: {"status": "healthy"}

# 2. Update target group health check
aws elbv2 modify-target-group \
  --target-group-arn arn:... \
  --health-check-path /health \
  --health-check-interval-seconds 30 \
  --health-check-timeout-seconds 5 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 3 \
  --matcher HttpCode=200

# 3. Check security group allows ALB
aws ec2 authorize-security-group-ingress \
  --group-id sg-ingest \
  --protocol tcp \
  --port 5000 \
  --source-group sg-alb
```

---

#### Category 4: Data Quality Issues

##### 4.1 **Malformed Log Lines**

**Symptom:**
```
WARN FlexibleLogParser: Failed to parse log line: invalid format
ERROR: 1000 logs failed parsing in batch 123
```

**Impact:**
- Data loss (unparsed logs dropped)
- Incorrect analytics
- Alerts triggered

**Detection:**
```scala
// Track parse failures
val (parsed, failed) = FlexibleLogParser.parseBatch(logLines)

if (failed.size > parsed.size * 0.01) {  // > 1% failure rate
  logger.error(s"High parse failure rate: ${failed.size} / ${parsed.size + failed.size}")
  alerting.send("High log parse failure rate")
}
```

**Prevention:**
```python
# In ingestion layer - validate before accepting
def validate_log_format(log_line: str) -> bool:
    # Basic regex check
    pattern = r'^\S+ \S+ \S+ \[[\w:/]+\s[+\-]\d{4}\] ".+" \d{3} \d+'
    return re.match(pattern, log_line) is not None

@app.route('/ingest', methods=['POST'])
def ingest():
    logs = parse_gzip_bundle(request.data)
    
    # Validate each log
    invalid_logs = [log for log in logs if not validate_log_format(log)]
    
    if invalid_logs:
        return jsonify({
            "error": "Invalid log format",
            "count": len(invalid_logs),
            "samples": invalid_logs[:3]
        }), 400
```

**Recovery:**
```scala
// Store failed parses for investigation
val failedLogsDF = spark.createDataFrame(failed)

failedLogsDF.write
  .mode("append")
  .option("path", "s3://dstreambolt-dead-letter/failed-parses/")
  .save()

// Alert operations team
sendAlert("Parse failures detected", failed.size)
```

---

##### 4.2 **Duplicate Records**

**Symptom:**
```sql
-- Same request_id appears multiple times
SELECT request_id, COUNT(*) as count
FROM log_entries
GROUP BY request_id
HAVING count > 1;
```

**Root Causes:**
1. Client retries (network timeout)
2. Kafka producer retries
3. Spark exactly-once semantics not working

**Detection:**
```sql
-- Daily duplicate check
SELECT 
  DATE(created_at) as date,
  COUNT(*) as total_records,
  COUNT(DISTINCT request_id) as unique_records,
  COUNT(*) - COUNT(DISTINCT request_id) as duplicates
FROM log_entries
WHERE created_at >= NOW() - INTERVAL 1 DAY
GROUP BY DATE(created_at);
```

**Prevention:**
```scala
// Enable idempotent writes in Kafka producer
producer.config.put("enable.idempotence", "true")
producer.config.put("acks", "all")

// Spark exactly-once semantics
spark.conf.set("spark.sql.streaming.outputMode", "append")
spark.conf.set("spark.sql.streaming.checkpointLocation", checkpointPath)

// Deduplicate in Spark before writing
val dedupedDF = batchDF
  .dropDuplicates("request_id", "timestamp")
```

**Resolution:**
```sql
-- Remove duplicates
CREATE TABLE log_entries_deduped AS
SELECT * FROM (
  SELECT *,
    ROW_NUMBER() OVER (
      PARTITION BY request_id, timestamp 
      ORDER BY created_at DESC
    ) as rn
  FROM log_entries
) t
WHERE rn = 1;

-- Swap tables
RENAME TABLE log_entries TO log_entries_old;
RENAME TABLE log_entries_deduped TO log_entries;
DROP TABLE log_entries_old;
```

---

##### 4.3 **Missing Fields / NULL Values**

**Symptom:**
```sql
-- Unexpected NULLs in required fields
SELECT 
  SUM(CASE WHEN ip IS NULL THEN 1 ELSE 0 END) as null_ips,
  SUM(CASE WHEN timestamp IS NULL THEN 1 ELSE 0 END) as null_timestamps,
  SUM(CASE WHEN endpoint IS NULL THEN 1 ELSE 0 END) as null_endpoints
FROM log_entries
WHERE created_at >= NOW() - INTERVAL 1 HOUR;
```

**Prevention:**
```scala
// Add NOT NULL constraints
case class LogEntry(
  @NotNull ip: String,
  @NotNull timestamp: String,
  @NotNull method: String,
  @NotNull endpoint: String,
  // ...
)

// Validate in parser
def parse(logLine: String): Try[LogEntry] = Try {
  val entry = parseInternal(logLine)
  
  // Validate required fields
  require(entry.ip.nonEmpty, "IP is required")
  require(entry.timestamp.nonEmpty, "Timestamp is required")
  require(entry.endpoint.nonEmpty, "Endpoint is required")
  
  entry
}
```

---

#### Category 5: Security Failures

##### 5.1 **Certificate Expiration**

**Symptom:**
```
ERROR: Certificate expired
javax.net.ssl.SSLHandshakeException: PKIX path validation failed
```

**Impact:**
- mTLS authentication fails
- Clients cannot send data
- Service outage

**Detection:**
```bash
# Check certificate expiration
openssl x509 -in /opt/dstreambolt/certs/server-cert.pem -noout -enddate

# Alert 30 days before expiry
EXPIRY_DATE=$(openssl x509 -in cert.pem -noout -enddate | cut -d= -f2)
DAYS_LEFT=$(( ($(date -d "$EXPIRY_DATE" +%s) - $(date +%s)) / 86400 ))

if [ $DAYS_LEFT -lt 30 ]; then
  echo "ALERT: Certificate expires in $DAYS_LEFT days"
fi
```

**Prevention:**
```bash
# Automated certificate rotation (cron)
0 0 1 * * /opt/dstreambolt/scripts/rotate_certificates.sh

# Use shorter validity (90 days)
openssl x509 -req -in server.csr \
  -CA ca-cert.pem -CAkey ca-key.pem \
  -out server-cert.pem \
  -days 90  # Not 365
```

**Recovery:**
- See OPERATIONS_GUIDE.md - Security Operations - Certificate Rotation

---

##### 5.2 **Secrets Leaked in Logs**

**Symptom:**
```bash
# Accidentally logged password
grep -r "password" /var/log/dstreambolt/
# Output: mysql_password=DStreamBolt2025!
```

**Impact:**
- Security breach
- Compliance violation
- Must rotate all secrets

**Prevention:**
```python
# Mask secrets in logs
import logging

class SecretFilter(logging.Filter):
    def filter(self, record):
        # Redact common secret patterns
        patterns = [
            (r'password=\S+', 'password=***'),
            (r'token=\S+', 'token=***'),
            (r'key=\S+', 'key=***')
        ]
        
        for pattern, replacement in patterns:
            record.msg = re.sub(pattern, replacement, str(record.msg))
        
        return True

logger.addFilter(SecretFilter())
```

**Resolution:**
```bash
# 1. Rotate all exposed secrets immediately
aws secretsmanager update-secret \
  --secret-id dstreambolt/mysql \
  --secret-string '{"username":"root","password":"NewSecurePassword123!"}'

# 2. Restart services
sudo systemctl restart dstreambolt-ingest
sudo systemctl restart spark-job

# 3. Audit access logs
# Check if unauthorized access occurred

# 4. Clean up logs
sudo find /var/log -name "*.log" -exec sed -i 's/DStreamBolt2025!/***REDACTED***/g' {} \;
```

---

### Summary: Failure Detection Matrix

| Failure Type | Detection Time | Impact | Auto-Recovery | Manual Steps |
|--------------|----------------|--------|---------------|--------------|
| **Kafka Disk Full** | < 5 min | High | No | Clean old logs |
| **Queue Overflow** | < 1 min | Medium | Yes (backpressure) | Scale or fix Kafka |
| **Checkpoint Corrupt** | Immediate | High | No | Delete checkpoint |
| **Shuffle Spill** | < 10 min | Medium | No | Increase memory |
| **MySQL Pool Exhausted** | < 1 min | High | No | Increase connections |
| **Consumer Lag** | < 5 min | Medium | Partial | Scale Spark |
| **Network Failure** | < 30 sec | High | No | Fix security groups |
| **DNS Failure** | < 30 sec | High | No | Use IPs or fix DNS |
| **ALB Health Fail** | < 30 sec | High | No | Fix health endpoint |
| **Parse Failures** | Real-time | Low | Partial | Fix log format |
| **Duplicates** | Daily batch | Low | No | Deduplicate |
| **Missing Fields** | Real-time | Medium | No | Fix parser |
| **Cert Expiration** | 30 days before | High | No | Rotate certs |
| **Secrets Leaked** | Manual audit | Critical | No | Rotate secrets |

---

## 📚 Additional Resources

- [OPERATIONS_GUIDE.md](../OPERATIONS_GUIDE.md) - Operational procedures
- [SPARK_DEEPDIVE.md](SPARK_DEEPDIVE.md) - Spark optimization
- [KAFKA_DEEPDIVE.md](KAFKA_DEEPDIVE.md) - Kafka best practices
- [COMPLETE_TECHNICAL_GUIDE.md](COMPLETE_TECHNICAL_GUIDE.md) - Full system guide

---

**Document Version:** 1.0  
**Last Updated:** December 13, 2025  
**Maintained By:** DStreamBolt Engineering Team  
**Next Review:** March 13, 2026

