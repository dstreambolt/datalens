"""
DStreamBolt Spark Processor - Raw Log Parser
Parses raw Apache Combined Log Format logs from Kafka with configurable schema
"""
from pyspark.sql import SparkSession
from pyspark.sql.functions import *
from pyspark.sql.types import *
import sys
import argparse
import re
import yaml

# Apache Combined Log Format Regex Pattern
# Format: IP - - [timestamp] "METHOD /path HTTP/1.1" status size "referer" "user-agent" response_time
APACHE_LOG_PATTERN = r'^(\S+) (\S+) (\S+) \[([\w:/]+\s[+\-]\d{4})\] "(\S+) (\S+)\s*(\S*)" (\d{3}) (\d+|-) "([^"]*)" "([^"]*)" (\d+\.\d+)'

# Default schema configuration (can be overridden)
DEFAULT_SCHEMA_CONFIG = {
    'columns': [
        {'name': 'ip', 'type': 'string', 'position': 1},
        {'name': 'user', 'type': 'string', 'position': 2},
        {'name': 'auth', 'type': 'string', 'position': 3},
        {'name': 'timestamp', 'type': 'string', 'position': 4},
        {'name': 'method', 'type': 'string', 'position': 5},
        {'name': 'endpoint', 'type': 'string', 'position': 6},
        {'name': 'protocol', 'type': 'string', 'position': 7},
        {'name': 'status', 'type': 'integer', 'position': 8},
        {'name': 'size', 'type': 'integer', 'position': 9},
        {'name': 'referer', 'type': 'string', 'position': 10},
        {'name': 'user_agent', 'type': 'string', 'position': 11},
        {'name': 'response_time', 'type': 'double', 'position': 12}
    ],
    'timestamp_format': 'dd/MMM/yyyy:HH:mm:ss Z'
}


def load_schema_config(config_path=None):
    """Load schema configuration from YAML file or use default"""
    if config_path:
        try:
            with open(config_path, 'r') as f:
                return yaml.safe_load(f)
        except Exception as e:
            print(f"⚠️  Could not load schema config: {e}")
            print("Using default schema")

    return DEFAULT_SCHEMA_CONFIG


def parse_apache_log(log_line):
    """
    Parse Apache Combined Log Format line using regex
    Returns tuple of parsed fields
    """
    match = re.match(APACHE_LOG_PATTERN, log_line)
    if match:
        return match.groups()
    return None


def create_spark_session(app_name="DStreamBolt-RawLogProcessor", master=None):
    """Create Spark session with Kafka support"""
    builder = SparkSession.builder.appName(app_name)

    if master:
        builder = builder.master(master)

    # Add Kafka and MySQL packages
    builder = builder.config(
        "spark.jars.packages",
        "org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0,"
        "mysql:mysql-connector-java:8.0.33"
    )

    # Optimize for small cluster
    builder = builder.config("spark.sql.shuffle.partitions", "4")
    builder = builder.config("spark.default.parallelism", "4")

    return builder.getOrCreate()


def parse_log_line_udf(schema_config):
    """Create UDF to parse log lines based on schema configuration"""

    def parser(log_line):
        """Parse single log line and return dict"""
        if not log_line:
            return None

        match = re.match(APACHE_LOG_PATTERN, log_line)
        if not match:
            return None

        groups = match.groups()
        result = {}

        for col_def in schema_config['columns']:
            idx = col_def['position'] - 1  # 0-indexed
            value = groups[idx] if idx < len(groups) else None

            # Type conversion
            if value and value != '-':
                try:
                    if col_def['type'] == 'integer':
                        result[col_def['name']] = int(value)
                    elif col_def['type'] == 'double':
                        result[col_def['name']] = float(value)
                    else:
                        result[col_def['name']] = value
                except:
                    result[col_def['name']] = None
            else:
                result[col_def['name']] = None

        return result

    return parser


def process_batch(spark, kafka_broker, topic, mysql_config, schema_config):
    """
    Batch processing of raw logs from Kafka
    """
    print(f"📊 Starting batch processing from Kafka topic: {topic}")
    print(f"Using schema with {len(schema_config['columns'])} columns")

    # Read from Kafka
    df = spark \
        .read \
        .format("kafka") \
        .option("kafka.bootstrap.servers", kafka_broker) \
        .option("subscribe", topic) \
        .option("startingOffsets", "earliest") \
        .load()

    # Extract raw log lines from Kafka value
    raw_logs = df.select(col("value").cast("string").alias("raw_log"))

    total_messages = raw_logs.count()
    print(f"✅ Read {total_messages} messages from Kafka")

    # Create schema for parsed logs
    fields = []
    for col_def in schema_config['columns']:
        if col_def['type'] == 'string':
            field_type = StringType()
        elif col_def['type'] == 'integer':
            field_type = IntegerType()
        elif col_def['type'] == 'double':
            field_type = DoubleType()
        else:
            field_type = StringType()

        fields.append(StructField(col_def['name'], field_type, True))

    log_schema = StructType(fields)

    # Register UDF for parsing
    parse_udf = udf(parse_log_line_udf(schema_config), log_schema)

    # Parse logs
    parsed_logs = raw_logs \
        .withColumn("parsed", parse_udf(col("raw_log"))) \
        .select("parsed.*") \
        .filter(col("ip").isNotNull())  # Filter out unparseable lines

    # Add processing metadata
    parsed_logs = parsed_logs \
        .withColumn("processing_timestamp", current_timestamp()) \
        .withColumn("event_timestamp", to_timestamp(col("timestamp"), schema_config['timestamp_format']))

    parsed_count = parsed_logs.count()
    print(f"✅ Successfully parsed {parsed_count} log lines")

    if parsed_count < total_messages:
        print(f"⚠️  {total_messages - parsed_count} lines could not be parsed")

    # Show sample
    print("\n" + "=" * 80)
    print("📋 SAMPLE DATA:")
    print("=" * 80)
    parsed_logs.select("ip", "timestamp", "method", "endpoint", "status", "response_time").show(10, truncate=False)

    # Aggregations
    print("\n" + "=" * 80)
    print("📈 REQUEST STATISTICS BY STATUS CODE:")
    print("=" * 80)
    status_stats = parsed_logs.groupBy("status").agg(
        count("*").alias("count"),
        avg("response_time").alias("avg_response_time"),
        max("response_time").alias("max_response_time")
    ).orderBy("count", ascending=False)
    status_stats.show(truncate=False)

    print("\n" + "=" * 80)
    print("🔝 TOP 10 ENDPOINTS BY TRAFFIC:")
    print("=" * 80)
    parsed_logs.groupBy("endpoint", "method").agg(
        count("*").alias("requests"),
        avg("response_time").alias("avg_response_time")
    ).orderBy("requests", ascending=False).limit(10).show(truncate=False)

    print("\n" + "=" * 80)
    print("⚠️  ERROR ANALYSIS (Status >= 400):")
    print("=" * 80)
    error_df = parsed_logs.filter(col("status") >= 400)
    error_count = error_df.count()
    if error_count > 0:
        error_df.groupBy("status", "endpoint").agg(
            count("*").alias("count")
        ).orderBy("count", ascending=False).limit(10).show(truncate=False)
    else:
        print("✅ No errors found!")

    # Write to MySQL
    if mysql_config:
        write_to_mysql(parsed_logs, status_stats, mysql_config)

    print("\n" + "=" * 80)
    print(f"📊 SUMMARY: Processed {parsed_count} logs, {error_count} errors")
    print("=" * 80)

    return parsed_logs


def process_streaming(spark, kafka_broker, topic, mysql_config, schema_config,
                     checkpoint_dir="/tmp/spark-checkpoints", window_duration="30 seconds"):
    """
    Streaming processing of raw logs from Kafka
    """
    print(f"🔄 Starting streaming from Kafka topic: {topic}")
    print(f"Window duration: {window_duration}")
    print(f"Using schema with {len(schema_config['columns'])} columns")

    # Read stream from Kafka
    df = spark \
        .readStream \
        .format("kafka") \
        .option("kafka.bootstrap.servers", kafka_broker) \
        .option("subscribe", topic) \
        .option("startingOffsets", "latest") \
        .option("failOnDataLoss", "false") \
        .load()

    # Extract raw log lines
    raw_logs = df.select(col("value").cast("string").alias("raw_log"))

    # Create schema
    fields = []
    for col_def in schema_config['columns']:
        if col_def['type'] == 'string':
            field_type = StringType()
        elif col_def['type'] == 'integer':
            field_type = IntegerType()
        elif col_def['type'] == 'double':
            field_type = DoubleType()
        else:
            field_type = StringType()
        fields.append(StructField(col_def['name'], field_type, True))

    log_schema = StructType(fields)

    # Register UDF
    parse_udf = udf(parse_log_line_udf(schema_config), log_schema)

    # Parse logs
    parsed_logs = raw_logs \
        .withColumn("parsed", parse_udf(col("raw_log"))) \
        .select("parsed.*") \
        .filter(col("ip").isNotNull()) \
        .withColumn("processing_timestamp", current_timestamp()) \
        .withColumn("event_timestamp", to_timestamp(col("timestamp"), schema_config['timestamp_format']))

    # Windowed aggregations
    windowed_stats = parsed_logs \
        .withWatermark("event_timestamp", "2 minutes") \
        .groupBy(
            window("event_timestamp", window_duration),
            "endpoint",
            "method"
        ).agg(
            count("*").alias("request_count"),
            avg("response_time").alias("avg_response_time"),
            expr("percentile_approx(response_time, 0.95)").alias("p95_response_time"),
            expr("percentile_approx(response_time, 0.99)").alias("p99_response_time"),
            approx_count_distinct("ip").alias("unique_ips"),
            sum(when(col("status") >= 400, 1).otherwise(0)).alias("error_count")
        ).select(
            col("window.start").alias("window_start"),
            col("window.end").alias("window_end"),
            col("endpoint"),
            col("method"),
            col("request_count"),
            col("avg_response_time"),
            col("p95_response_time"),
            col("p99_response_time"),
            col("unique_ips"),
            col("error_count")
        )

    # Write to console and MySQL
    console_query = windowed_stats \
        .writeStream \
        .outputMode("complete") \
        .format("console") \
        .option("truncate", "false") \
        .option("numRows", "20") \
        .trigger(processingTime=window_duration) \
        .start()

    # Write to MySQL (if configured)
    if mysql_config:
        mysql_query = windowed_stats \
            .writeStream \
            .outputMode("complete") \
            .foreachBatch(lambda batch_df, batch_id: write_streaming_to_mysql(batch_df, mysql_config)) \
            .trigger(processingTime=window_duration) \
            .option("checkpointLocation", checkpoint_dir) \
            .start()

        return [console_query, mysql_query]

    return [console_query]


def write_to_mysql(df, stats_df, mysql_config):
    """Write aggregated data to MySQL"""
    print("\n💾 Writing to MySQL...")

    try:
        # Write status summary
        stats_df \
            .withColumn("window_start", current_timestamp()) \
            .withColumn("window_end", current_timestamp()) \
            .withColumn("processing_timestamp", current_timestamp()) \
            .write \
            .format("jdbc") \
            .option("url", f"jdbc:mysql://{mysql_config['host']}:{mysql_config['port']}/{mysql_config['database']}") \
            .option("driver", "com.mysql.cj.jdbc.Driver") \
            .option("dbtable", "status_summary") \
            .option("user", mysql_config['user']) \
            .option("password", mysql_config['password']) \
            .mode("append") \
            .save()

        print("✅ Data written to MySQL successfully")
    except Exception as e:
        print(f"⚠️  MySQL write failed: {e}")


def write_streaming_to_mysql(batch_df, mysql_config):
    """Write streaming batch to MySQL"""
    if batch_df.isEmpty():
        return

    try:
        batch_df \
            .withColumn("processing_timestamp", current_timestamp()) \
            .write \
            .format("jdbc") \
            .option("url", f"jdbc:mysql://{mysql_config['host']}:{mysql_config['port']}/{mysql_config['database']}") \
            .option("driver", "com.mysql.cj.jdbc.Driver") \
            .option("dbtable", "endpoint_summary") \
            .option("user", mysql_config['user']) \
            .option("password", mysql_config['password']) \
            .mode("append") \
            .save()
    except Exception as e:
        print(f"⚠️  MySQL write failed: {e}")


def main():
    parser = argparse.ArgumentParser(description='DStreamBolt Spark Processor for Raw Logs')
    parser.add_argument('--spark-master', required=True, help='Spark master URL')
    parser.add_argument('--kafka-broker', required=True, help='Kafka broker address')
    parser.add_argument('--kafka-topic', default='dstreambolt-logs', help='Kafka topic name')
    parser.add_argument('--mode', choices=['batch', 'streaming'], default='batch', help='Processing mode')
    parser.add_argument('--mysql-host', help='MySQL host')
    parser.add_argument('--mysql-port', default='3306', help='MySQL port')
    parser.add_argument('--mysql-user', default='dstreambolt', help='MySQL user')
    parser.add_argument('--mysql-password', help='MySQL password')
    parser.add_argument('--mysql-database', default='dstreambolt_metrics', help='MySQL database')
    parser.add_argument('--schema-config', help='Path to schema configuration YAML file')
    parser.add_argument('--window-duration', default='30 seconds', help='Window duration for streaming')
    parser.add_argument('--checkpoint-dir', default='/tmp/spark-checkpoints', help='Checkpoint directory')

    args = parser.parse_args()

    # Load schema configuration
    schema_config = load_schema_config(args.schema_config)

    print("=" * 80)
    print("🚀 DStreamBolt Spark Processor - Raw Log Parser")
    print("=" * 80)
    print(f"Mode: {args.mode}")
    print(f"Kafka: {args.kafka_broker} / topic: {args.kafka_topic}")
    print(f"Spark Master: {args.spark-master}")
    print(f"Schema columns: {', '.join([c['name'] for c in schema_config['columns']])}")
    print("=" * 80)

    # Create Spark session
    spark = create_spark_session(master=args.spark_master)
    spark.sparkContext.setLogLevel("WARN")

    # MySQL configuration
    mysql_config = None
    if args.mysql_host and args.mysql_password:
        mysql_config = {
            'host': args.mysql_host,
            'port': args.mysql_port,
            'user': args.mysql_user,
            'password': args.mysql_password,
            'database': args.mysql_database
        }
        print(f"✅ MySQL configured: {args.mysql_user}@{args.mysql_host}/{args.mysql_database}")

    # Process based on mode
    if args.mode == 'batch':
        process_batch(spark, args.kafka_broker, args.kafka_topic, mysql_config, schema_config)
    else:
        queries = process_streaming(
            spark,
            args.kafka_broker,
            args.kafka_topic,
            mysql_config,
            schema_config,
            args.checkpoint_dir,
            args.window_duration
        )

        print("\n🔄 Streaming queries running...")
        print("Press Ctrl+C to stop")

        try:
            for query in queries:
                query.awaitTermination()
        except KeyboardInterrupt:
            print("\n⏸️  Stopping streaming queries...")
            for query in queries:
                query.stop()

    # Stop Spark
    print("✅ Spark session stopped")
    spark.stop()


if __name__ == "__main__":
    main()

