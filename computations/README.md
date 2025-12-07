# DStreamBolt Spark Computations

Apache Spark processing jobs for real-time and batch analysis of log data.

## Features

- ✅ Batch processing of historical data
- ✅ Real-time streaming with windowed aggregations
- ✅ Kafka integration for data ingestion
- ✅ MySQL output for processed results
- ✅ Error detection and analysis
- ✅ Performance metrics

## Installation

### Requirements

- Python 3.8+
- Apache Spark 3.5.0
- Java 11+
- Kafka broker

### Install Dependencies

```bash
pip install -r requirements.txt
```

## Usage

### Batch Processing

Process all historical data from Kafka:

```bash
python spark_processor.py \
  --spark-master spark://10.0.11.80:7077 \
  --kafka-broker 10.0.10.101:9092 \
  --topic dstreambolt-logs \
  --mode batch
```

With output to Parquet:

```bash
python spark_processor.py \
  --spark-master spark://10.0.11.80:7077 \
  --kafka-broker 10.0.10.101:9092 \
  --mode batch \
  --output-path /tmp/spark-output
```

With MySQL output:

```bash
python spark_processor.py \
  --spark-master spark://10.0.11.80:7077 \
  --kafka-broker 10.0.10.101:9092 \
  --mode batch \
  --mysql-host 10.0.1.70 \
  --mysql-user root \
  --mysql-password YourPassword \
  --mysql-database dstreambolt
```

### Streaming Processing

Process real-time data with windowed aggregations:

```bash
python spark_processor.py \
  --spark-master spark://10.0.11.80:7077 \
  --kafka-broker 10.0.10.101:9092 \
  --mode streaming \
  --window-duration "30 seconds" \
  --checkpoint-dir /tmp/spark-checkpoints
```

## Command-Line Options

### Required Arguments

- `--spark-master` - Spark master URL (e.g., `spark://host:7077`)
- `--kafka-broker` - Kafka broker address (e.g., `host:9092`)

### Optional Arguments

- `--mode` - Processing mode: `batch` or `streaming` (default: `batch`)
- `--topic` - Kafka topic name (default: `dstreambolt-logs`)
- `--app-name` - Spark application name (default: `DStreamBolt-Processor`)
- `--window-duration` - Window duration for streaming (default: `30 seconds`)
- `--checkpoint-dir` - Checkpoint directory for streaming (default: `/tmp/spark-checkpoints`)
- `--output-path` - Output path for batch results

### MySQL Output Options

- `--mysql-host` - MySQL server hostname
- `--mysql-user` - MySQL username
- `--mysql-password` - MySQL password
- `--mysql-database` - MySQL database name (default: `dstreambolt`)
- `--mysql-table` - MySQL table name (default: `spark_results`)

## Processing Operations

### Batch Mode

1. **Read all data** from Kafka topic (from earliest offset)
2. **Parse JSON** log entries with schema validation
3. **Aggregate statistics**:
   - Request count by status code
   - Top 10 endpoints by request count
   - Error analysis (4xx and 5xx responses)
4. **Save results** to Parquet or MySQL (optional)

### Streaming Mode

1. **Continuously read** from Kafka (from latest offset)
2. **Parse and validate** incoming log entries
3. **Windowed aggregations**:
   - Request count per window
   - Average response size per window
   - Status code distribution
4. **Write to console** and checkpoint for fault tolerance

## Data Schema

Input log schema from Kafka:

```python
{
    "timestamp": "2025-12-05T10:30:45Z",
    "ip": "192.168.1.100",
    "method": "GET",
    "endpoint": "/api/v1/users",
    "status_code": 200,
    "response_size": 1234,
    "user_agent": "Mozilla/5.0...",
    "request_id": "req_1733395845123",
    "ingestion_timestamp": "2025-12-05T10:30:45.500Z"
}
```

## Example Outputs

### Batch Processing Output

```
📊 Starting batch processing from Kafka topic: dstreambolt-logs
✅ Read 10000 log entries

📈 Request Statistics:
+-----------+-----+
|status_code|count|
+-----------+-----+
|        200| 7000|
|        201| 1000|
|        404|  500|
|        500|  400|
|        503|  300|
+-----------+-----+

🔝 Top Endpoints:
+------------------+-----+
|          endpoint|count|
+------------------+-----+
|   /api/v1/users  | 3000|
|   /api/v1/orders | 2500|
| /api/v1/products | 2000|
+------------------+-----+

⚠️  Error Analysis:
+-----------+------------------+-----+
|status_code|          endpoint|count|
+-----------+------------------+-----+
|        404|   /api/v1/missing|  300|
|        500|   /api/v1/error  |  250|
+-----------+------------------+-----+
```

### Streaming Output

```
🔄 Starting streaming processing from Kafka topic: dstreambolt-logs
📍 Checkpoint directory: /tmp/spark-checkpoints
⏱️  Window duration: 30 seconds
✅ Streaming query started. Press Ctrl+C to stop.

-------------------------------------------
Batch: 0
-------------------------------------------
+------------------------------------------+-----------+-------------+------------------+
|window                                     |status_code|request_count|avg_response_size |
+------------------------------------------+-----------+-------------+------------------+
|{2025-12-05 10:30:00, 2025-12-05 10:30:30}|200        |150          |1234.5            |
|{2025-12-05 10:30:00, 2025-12-05 10:30:30}|404        |10           |512.3             |
+------------------------------------------+-----------+-------------+------------------+
```

## Submit to Spark Cluster

### Using spark-submit

```bash
/opt/spark/bin/spark-submit \
  --master spark://10.0.11.80:7077 \
  --packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0 \
  --driver-memory 512m \
  --executor-memory 512m \
  spark_processor.py \
  --kafka-broker 10.0.10.101:9092 \
  --mode streaming
```

### Using Jenkins Pipeline

Create a Jenkins job to submit Spark jobs:

```groovy
pipeline {
    agent any
    stages {
        stage('Submit Spark Job') {
            steps {
                sh '''
                    /opt/spark/bin/spark-submit \
                      --master spark://10.0.11.80:7077 \
                      --packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0 \
                      /path/to/spark_processor.py \
                      --kafka-broker 10.0.10.101:9092 \
                      --mode batch
                '''
            }
        }
    }
}
```

## Monitoring

### View Spark UI

Access the Spark Master UI to monitor jobs:

```
http://spark-master-ip:8080
```

Via ALB:
```
https://dstreambolt-alb.amazonaws.com/spark
```

### Check Job Status

```bash
# List running applications
curl http://10.0.11.80:8080/json/ | jq '.activeapps'

# View worker status
curl http://10.0.11.80:8081/json/ | jq
```

### View Logs

```bash
# Master logs
tail -f /opt/spark/logs/spark-*-master-*.out

# Worker logs
tail -f /opt/spark/logs/spark-*-worker-*.out

# Application logs
tail -f /opt/spark/work/*/stdout
```

## Performance Tuning

### Memory Configuration

```bash
python spark_processor.py \
  --spark-master spark://10.0.11.80:7077 \
  --kafka-broker 10.0.10.101:9092 \
  --mode streaming
```

Add Spark configurations:

```bash
export SPARK_DRIVER_MEMORY=1g
export SPARK_EXECUTOR_MEMORY=1g
```

### Parallelism

For batch processing, increase parallelism:

```python
spark.conf.set("spark.default.parallelism", "4")
spark.conf.set("spark.sql.shuffle.partitions", "4")
```

## Troubleshooting

### Kafka Connection Issues

```bash
# Test Kafka connectivity
telnet 10.0.10.101 9092

# List Kafka topics
/opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server 10.0.10.101:9092 \
  --list

# Check topic data
/opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server 10.0.10.101:9092 \
  --topic dstreambolt-logs \
  --from-beginning \
  --max-messages 10
```

### Spark Errors

```bash
# Check Spark master status
/opt/spark/sbin/spark-daemon.sh status org.apache.spark.deploy.master.Master

# Restart Spark services
sudo systemctl restart spark-master
sudo systemctl restart spark-worker

# Check connectivity
telnet 10.0.11.80 7077
```

### Memory Issues

If you encounter OOM errors:

1. Reduce batch size
2. Increase executor memory
3. Enable memory overhead: `--conf spark.executor.memoryOverhead=256m`

## Development

### Local Testing

```bash
# Start local Spark
export SPARK_HOME=/opt/spark
export PATH=$SPARK_HOME/bin:$PATH

# Run with local master
python spark_processor.py \
  --spark-master local[2] \
  --kafka-broker localhost:9092 \
  --mode batch
```

### Custom Aggregations

Modify `spark_processor.py` to add custom aggregations:

```python
# Add to process_batch function
custom_metrics = logs_df \
    .groupBy("endpoint", "method") \
    .agg(
        count("*").alias("count"),
        avg("response_size").alias("avg_size"),
        percentile_approx("response_size", 0.95).alias("p95_size")
    )
custom_metrics.show()
```

## Advanced Features

### Structured Streaming with Kafka

Read from multiple topics:

```python
stream_df = spark \
    .readStream \
    .format("kafka") \
    .option("kafka.bootstrap.servers", "broker1:9092,broker2:9092") \
    .option("subscribe", "topic1,topic2,topic3") \
    .load()
```

### Writing to Multiple Sinks

```python
# Write to both Parquet and MySQL
query1 = logs_stream.writeStream.format("parquet").start("/path/to/output")
query2 = logs_stream.writeStream.format("jdbc").start()
```

## Production Deployment

The Spark cluster is automatically deployed via Terraform.

See `../terraform/modules/compute/` for infrastructure configuration.

## License

Part of DStreamBolt Platform

