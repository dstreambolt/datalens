#!/usr/bin/env python3
"""
Spark Streaming Job - Process access logs from Kafka
Aggregates metrics every 60 seconds and stores in MySQL
"""

from pyspark.sql import SparkSession
from pyspark.sql.functions import (
    from_json, col, window, count, avg, sum as spark_sum,
    min as spark_min, max as spark_max, current_timestamp, regexp_extract
)
from pyspark.sql.types import StructType, StructField, StringType, IntegerType, FloatType
import sys

# MySQL connection properties
MYSQL_PROPERTIES = {
    "user": "root",
    "password": "DStreamBolt2025!",
    "driver": "com.mysql.cj.jdbc.Driver"
}

def parse_access_log_schema():
    """
    Define schema for parsing access logs

    Log format: IP - - [timestamp] "METHOD /path HTTP/1.1" status size "referer" "user-agent" response_time
    """
    return StructType([
        StructField("ip", StringType(), True),
        StructField("timestamp", StringType(), True),
        StructField("method", StringType(), True),
        StructField("path", StringType(), True),
        StructField("status", IntegerType(), True),
        StructField("size", IntegerType(), True),
        StructField("referer", StringType(), True),
        StructField("user_agent", StringType(), True),
        StructField("response_time", FloatType(), True)
    ])

def create_spark_session(app_name="DStreamBolt-LogProcessor"):
    """Create Spark session with Kafka and MySQL support"""
    return SparkSession.builder \
        .appName(app_name) \
        .config("spark.jars.packages",
                "org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0,"
                "mysql:mysql-connector-java:8.0.33") \
        .config("spark.sql.streaming.checkpointLocation", "/tmp/spark-checkpoint") \
        .getOrCreate()

def process_streaming_logs(spark, kafka_bootstrap, mysql_host, output_table="log_metrics"):
    """
    Main streaming job: Read from Kafka → Parse → Aggregate → Write to MySQL

    Args:
        spark: SparkSession
        kafka_bootstrap: Kafka broker address (e.g., 10.0.10.101:9092)
        mysql_host: MySQL host address (e.g., 10.0.1.70)
        output_table: MySQL table name for aggregated metrics
    """

    print("╔════════════════════════════════════════════════════════════════╗")
    print("║       DStreamBolt Spark Streaming Log Processor               ║")
    print("╚════════════════════════════════════════════════════════════════╝")
    print()
    print(f"Kafka: {kafka_bootstrap}")
    print(f"MySQL: {mysql_host}")
    print(f"Output Table: {output_table}")
    print(f"Aggregation Window: 60 seconds")
    print()

    # Read from Kafka
    print("📥 Reading from Kafka topic 'dstreambolt-logs'...")
    df_raw = spark \
        .readStream \
        .format("kafka") \
        .option("kafka.bootstrap.servers", kafka_bootstrap) \
        .option("subscribe", "dstreambolt-logs") \
        .option("startingOffsets", "earliest") \
        .load()

    # Parse log lines using regex (Apache Combined Log Format)
    print("🔍 Parsing access logs...")
    df_parsed = df_raw.selectExpr("CAST(value AS STRING) as log_line", "timestamp") \
        .select(
            regexp_extract("log_line", r"^(\S+)", 1).alias("ip"),
            regexp_extract("log_line", r"\[([^\]]+)\]", 1).alias("log_timestamp"),
            regexp_extract("log_line", r'"(\w+)\s', 1).alias("method"),
            regexp_extract("log_line", r'"\w+\s+([^\s]+)\s', 1).alias("path"),
            regexp_extract("log_line", r'"\s+(\d{3})\s', 1).cast("int").alias("status"),
            regexp_extract("log_line", r'"\s+\d{3}\s+(\d+)', 1).cast("int").alias("size"),
            regexp_extract("log_line", r'(\d+\.\d+)$', 1).cast("float").alias("response_time"),
            col("timestamp").alias("event_time")
        ) \
        .filter(col("status").isNotNull())  # Filter out malformed logs

    # Aggregate metrics every 60 seconds
    print("📊 Aggregating metrics (60-second windows)...")
    df_aggregated = df_parsed \
        .withWatermark("event_time", "10 seconds") \
        .groupBy(
            window("event_time", "60 seconds"),
            "status"
        ) \
        .agg(
            count("*").alias("request_count"),
            avg("response_time").alias("avg_response_time"),
            spark_min("response_time").alias("min_response_time"),
            spark_max("response_time").alias("max_response_time"),
            spark_sum("size").alias("total_bytes"),
            count(col("status").between(200, 299)).alias("success_count"),
            count(col("status").between(400, 499)).alias("client_error_count"),
            count(col("status").between(500, 599)).alias("server_error_count")
        ) \
        .select(
            col("window.start").alias("window_start"),
            col("window.end").alias("window_end"),
            col("status"),
            col("request_count"),
            col("avg_response_time"),
            col("min_response_time"),
            col("max_response_time"),
            col("total_bytes"),
            col("success_count"),
            col("client_error_count"),
            col("server_error_count"),
            current_timestamp().alias("processed_at")
        )

    # Write to MySQL
    print(f"💾 Writing aggregated metrics to MySQL table '{output_table}'...")

    mysql_url = f"jdbc:mysql://{mysql_host}:3306/dstreambolt_metrics"

    query = df_aggregated \
        .writeStream \
        .outputMode("append") \
        .foreachBatch(lambda batch_df, batch_id: write_to_mysql(batch_df, mysql_url, output_table)) \
        .option("checkpointLocation", f"/tmp/spark-checkpoint/{output_table}") \
        .start()

    print("✅ Spark streaming job started!")
    print()
    print("📊 Processing logs in real-time...")
    print("   - Aggregating every 60 seconds")
    print("   - Writing to MySQL")
    print("   - Check Grafana for visualizations")
    print()
    print("Press Ctrl+C to stop...")

    # Wait for termination
    query.awaitTermination()

def write_to_mysql(batch_df, mysql_url, table_name):
    """
    Write batch DataFrame to MySQL

    Args:
        batch_df: Batch DataFrame from foreachBatch
        mysql_url: MySQL JDBC URL
        table_name: Target table name
    """
    if batch_df.count() > 0:
        batch_df.write \
            .jdbc(
                url=mysql_url,
                table=table_name,
                mode="append",
                properties=MYSQL_PROPERTIES
            )

        print(f"✅ Wrote {batch_df.count()} aggregated records to MySQL")

def create_mysql_table(mysql_host, table_name="log_metrics"):
    """
    Create MySQL table for storing aggregated metrics

    Args:
        mysql_host: MySQL host address
        table_name: Table name
    """
    import pymysql

    print(f"📊 Creating MySQL table '{table_name}'...")

    try:
        conn = pymysql.connect(
            host=mysql_host,
            user='root',
            password='DStreamBolt2025!',
            database='dstreambolt_metrics'
        )

        cursor = conn.cursor()

        # Create table
        create_table_sql = f"""
        CREATE TABLE IF NOT EXISTS {table_name} (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            window_start DATETIME NOT NULL,
            window_end DATETIME NOT NULL,
            status INT NOT NULL,
            request_count BIGINT,
            avg_response_time DOUBLE,
            min_response_time DOUBLE,
            max_response_time DOUBLE,
            total_bytes BIGINT,
            success_count BIGINT,
            client_error_count BIGINT,
            server_error_count BIGINT,
            processed_at DATETIME,
            INDEX idx_window_start (window_start),
            INDEX idx_status (status)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        """

        cursor.execute(create_table_sql)
        conn.commit()

        print(f"✅ Table '{table_name}' ready")

        cursor.close()
        conn.close()

    except Exception as e:
        print(f"⚠️  Warning: Could not create table: {e}")
        print("   Make sure MySQL is accessible and database 'dstreambolt_metrics' exists")

if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser(description='Spark streaming log processor')
    parser.add_argument('--kafka', required=True, help='Kafka bootstrap server (e.g., 10.0.10.101:9092)')
    parser.add_argument('--mysql', required=True, help='MySQL host (e.g., 10.0.1.70)')
    parser.add_argument('--table', default='log_metrics', help='MySQL table name (default: log_metrics)')
    parser.add_argument('--create-table', action='store_true', help='Create MySQL table before starting')

    args = parser.parse_args()

    # Create table if requested
    if args.create_table:
        create_mysql_table(args.mysql, args.table)

    # Create Spark session
    print("🚀 Starting Spark session...")
    spark = create_spark_session()

    try:
        # Start streaming job
        process_streaming_logs(spark, args.kafka, args.mysql, args.table)
    except KeyboardInterrupt:
        print()
        print("✅ Stopping Spark job...")
        spark.stop()
        print("   Job stopped")
    except Exception as e:
        print(f"❌ Error: {e}")
        spark.stop()
        sys.exit(1)

