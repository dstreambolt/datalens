"""
DStreamBolt Spark Processor
Real-time and batch processing of log data from Kafka
"""
from pyspark.sql import SparkSession
from pyspark.sql.functions import *
from pyspark.sql.types import *
import sys
import argparse

# Define log schema
LOG_SCHEMA = StructType([
    StructField("timestamp", StringType(), True),
    StructField("ip", StringType(), True),
    StructField("method", StringType(), True),
    StructField("endpoint", StringType(), True),
    StructField("status_code", IntegerType(), True),
    StructField("response_size", IntegerType(), True),
    StructField("user_agent", StringType(), True),
    StructField("request_id", StringType(), True),
    StructField("ingestion_timestamp", StringType(), True)
])


def create_spark_session(app_name="DStreamBolt-Processor", master=None):
    """Create Spark session"""
    builder = SparkSession.builder.appName(app_name)

    if master:
        builder = builder.master(master)

    # Add Kafka package
    builder = builder.config(
        "spark.jars.packages",
        "org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0"
    )

    return builder.getOrCreate()


def process_batch(spark, kafka_broker, topic="dstreambolt-logs", output_path=None):
    """
    Batch processing of Kafka messages
    """
    print(f"📊 Starting batch processing from Kafka topic: {topic}")

    # Read from Kafka
    df = spark \
        .read \
        .format("kafka") \
        .option("kafka.bootstrap.servers", kafka_broker) \
        .option("subscribe", topic) \
        .option("startingOffsets", "earliest") \
        .load()

    # Parse JSON
    logs_df = df.select(
        from_json(col("value").cast("string"), LOG_SCHEMA).alias("data")
    ).select("data.*")

    # Add processing timestamp
    logs_df = logs_df.withColumn("processing_timestamp", current_timestamp())

    print(f"✅ Read {logs_df.count()} log entries")

    # Aggregations
    print("\n📈 Request Statistics:")
    logs_df.groupBy("status_code").count().orderBy("count", ascending=False).show()

    print("\n🔝 Top Endpoints:")
    logs_df.groupBy("endpoint").count().orderBy("count", ascending=False).limit(10).show()

    print("\n⚠️  Error Analysis:")
    error_df = logs_df.filter(col("status_code") >= 400)
    error_df.groupBy("status_code", "endpoint").count().orderBy("count", ascending=False).limit(10).show()

    # Save results if output path provided
    if output_path:
        print(f"\n💾 Saving results to: {output_path}")
        logs_df.write.mode("overwrite").parquet(output_path)

    return logs_df


def process_streaming(spark, kafka_broker, topic="dstreambolt-logs",
                     checkpoint_dir="/tmp/spark-checkpoints",
                     window_duration="30 seconds"):
    """
    Streaming processing of Kafka messages
    """
    print(f"🔄 Starting streaming processing from Kafka topic: {topic}")
    print(f"📍 Checkpoint directory: {checkpoint_dir}")
    print(f"⏱️  Window duration: {window_duration}")

    # Read stream from Kafka
    stream_df = spark \
        .readStream \
        .format("kafka") \
        .option("kafka.bootstrap.servers", kafka_broker) \
        .option("subscribe", topic) \
        .option("startingOffsets", "latest") \
        .load()

    # Parse JSON
    logs_stream = stream_df.select(
        from_json(col("value").cast("string"), LOG_SCHEMA).alias("data"),
        col("timestamp").alias("kafka_timestamp")
    ).select("data.*", "kafka_timestamp")

    # Add processing timestamp
    logs_stream = logs_stream.withColumn("processing_timestamp", current_timestamp())

    # Windowed aggregations
    windowed_stats = logs_stream \
        .withWatermark("kafka_timestamp", "1 minute") \
        .groupBy(
            window(col("kafka_timestamp"), window_duration),
            col("status_code")
        ) \
        .agg(
            count("*").alias("request_count"),
            avg("response_size").alias("avg_response_size")
        )

    # Write to console
    query = windowed_stats \
        .writeStream \
        .outputMode("update") \
        .format("console") \
        .option("truncate", "false") \
        .option("checkpointLocation", checkpoint_dir) \
        .start()

    print("✅ Streaming query started. Press Ctrl+C to stop.")
    query.awaitTermination()


def write_to_mysql(df, mysql_config):
    """
    Write DataFrame to MySQL
    """
    print(f"💾 Writing to MySQL: {mysql_config['host']}/{mysql_config['database']}")

    df.write \
        .format("jdbc") \
        .option("url", f"jdbc:mysql://{mysql_config['host']}:3306/{mysql_config['database']}") \
        .option("dbtable", mysql_config.get('table', 'spark_results')) \
        .option("user", mysql_config['user']) \
        .option("password", mysql_config['password']) \
        .option("driver", "com.mysql.cj.jdbc.Driver") \
        .mode("append") \
        .save()

    print("✅ Data written to MySQL successfully")


def main():
    parser = argparse.ArgumentParser(description='DStreamBolt Spark Processor')

    # Spark configuration
    parser.add_argument('--spark-master', required=True, help='Spark master URL (e.g., spark://host:7077)')
    parser.add_argument('--app-name', default='DStreamBolt-Processor', help='Spark application name')

    # Kafka configuration
    parser.add_argument('--kafka-broker', required=True, help='Kafka broker address (e.g., host:9092)')
    parser.add_argument('--topic', default='dstreambolt-logs', help='Kafka topic to consume')

    # Processing mode
    parser.add_argument('--mode', choices=['batch', 'streaming'], default='batch',
                       help='Processing mode')
    parser.add_argument('--window-duration', default='30 seconds',
                       help='Window duration for streaming aggregations')

    # Output configuration
    parser.add_argument('--output-path', help='Output path for batch processing results')
    parser.add_argument('--checkpoint-dir', default='/tmp/spark-checkpoints',
                       help='Checkpoint directory for streaming')

    # MySQL configuration (optional)
    parser.add_argument('--mysql-host', help='MySQL host')
    parser.add_argument('--mysql-user', help='MySQL user')
    parser.add_argument('--mysql-password', help='MySQL password')
    parser.add_argument('--mysql-database', default='dstreambolt', help='MySQL database')
    parser.add_argument('--mysql-table', default='spark_results', help='MySQL table')

    args = parser.parse_args()

    print("=" * 60)
    print("🚀 DStreamBolt Spark Processor")
    print("=" * 60)
    print(f"Mode: {args.mode}")
    print(f"Kafka Broker: {args.kafka_broker}")
    print(f"Topic: {args.topic}")
    print(f"Spark Master: {args.spark_master}")
    print("=" * 60)

    # Create Spark session
    spark = create_spark_session(
        app_name=args.app_name,
        master=args.spark_master
    )

    spark.sparkContext.setLogLevel("WARN")

    try:
        if args.mode == 'batch':
            df = process_batch(
                spark,
                args.kafka_broker,
                args.topic,
                args.output_path
            )

            # Write to MySQL if configured
            if args.mysql_host and args.mysql_user and args.mysql_password:
                mysql_config = {
                    'host': args.mysql_host,
                    'user': args.mysql_user,
                    'password': args.mysql_password,
                    'database': args.mysql_database,
                    'table': args.mysql_table
                }
                write_to_mysql(df, mysql_config)

        elif args.mode == 'streaming':
            process_streaming(
                spark,
                args.kafka_broker,
                args.topic,
                args.checkpoint_dir,
                args.window_duration
            )

    except KeyboardInterrupt:
        print("\n⏹️  Stopping Spark processor...")
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    finally:
        spark.stop()
        print("✅ Spark session stopped")


if __name__ == "__main__":
    main()

