"""
Spark ETL Job: Process Akamai DataStream Logs
==============================================
Architecture: S3 → Lambda → SQS → Spark Cluster → RDS PostgreSQL
Version: 2.0.0
Author: DataLens Team

This Spark job runs as a daemon on Spark Master, polling SQS every 5 minutes.
"""

import sys
import json
import boto3
import time
import argparse
from datetime import datetime
from pyspark.sql import SparkSession, DataFrame
from pyspark.sql.functions import *
from pyspark.sql.types import *

# ============================================================================
# Parse Arguments
# ============================================================================

parser = argparse.ArgumentParser(description='Process Akamai logs from SQS')
parser.add_argument('--sqs-queue-url', required=True, help='SQS queue URL')
parser.add_argument('--db-secret-arn', required=True, help='RDS secret ARN')
parser.add_argument('--error-bucket', required=True, help='S3 error bucket')
parser.add_argument('--poll-interval', type=int, default=300, help='Poll interval in seconds (default: 300)')
parser.add_argument('--max-messages', type=int, default=10, help='Max SQS messages per batch (default: 10)')
parser.add_argument('--batch-size', type=int, default=1000, help='JDBC batch size (default: 1000)')

args = parser.parse_args()

# ============================================================================
# Initialize Spark Session
# ============================================================================

spark = SparkSession.builder \
    .appName("DataLens-Akamai-Processor") \
    .config("spark.sql.adaptive.enabled", "true") \
    .config("spark.sql.adaptive.coalescePartitions.enabled", "true") \
    .config("spark.sql.shuffle.partitions", "10") \
    .config("spark.driver.memory", "1g") \
    .config("spark.executor.memory", "1g") \
    .config("spark.driver.maxResultSize", "512m") \
    .config("spark.network.timeout", "600s") \
    .config("spark.sql.broadcastTimeout", "600") \
    .getOrCreate()

spark.sparkContext.setLogLevel("WARN")

# AWS clients
sqs = boto3.client('sqs')
s3 = boto3.client('s3')
secrets = boto3.client('secretsmanager')

# Configuration
SQS_QUEUE_URL = args.sqs_queue_url
DB_SECRET_ARN = args.db_secret_arn
ERROR_BUCKET = args.error_bucket
POLL_INTERVAL = args.poll_interval
MAX_MESSAGES = args.max_messages
BATCH_SIZE = args.batch_size

print(f"🔧 Configuration:")
print(f"   SQS Queue: {SQS_QUEUE_URL}")
print(f"   Poll Interval: {POLL_INTERVAL} seconds")
print(f"   Max Messages: {MAX_MESSAGES}")
print(f"   Batch Size: {BATCH_SIZE}")

# ============================================================================
# Akamai DataStream Schema (70 fields)
# ============================================================================

AKAMAI_SCHEMA = StructType([
    StructField("version", StringType(), True),
    StructField("cp", StringType(), True),
    StructField("reqId", StringType(), True),
    StructField("reqTimeSec", LongType(), True),
    StructField("bytes", LongType(), True),
    StructField("cliIP", StringType(), True),
    StructField("statusCode", IntegerType(), True),
    StructField("proto", StringType(), True),
    StructField("reqHost", StringType(), True),
    StructField("reqMethod", StringType(), True),
    StructField("reqPath", StringType(), True),
    StructField("reqPort", IntegerType(), True),
    StructField("rspContentLen", LongType(), True),
    StructField("rspContentType", StringType(), True),
    StructField("UA", StringType(), True),
    StructField("tlsOverheadTimeMSec", IntegerType(), True),
    StructField("tlsVersion", StringType(), True),
    StructField("objSize", LongType(), True),
    StructField("uncompressedSize", LongType(), True),
    StructField("overheadBytes", LongType(), True),
    StructField("totalBytes", LongType(), True),
    StructField("queryStr", StringType(), True),
    StructField("breadcrumbs", StringType(), True),
    StructField("accLang", StringType(), True),
    StructField("cookie", StringType(), True),
    StructField("range", StringType(), True),
    StructField("referer", StringType(), True),
    StructField("xForwardedFor", StringType(), True),
    StructField("maxAgeSec", IntegerType(), True),
    StructField("reqEndTimeMSec", IntegerType(), True),
    StructField("errorCode", StringType(), True),
    StructField("turnAroundTimeMSec", IntegerType(), True),
    StructField("transferTimeMSec", IntegerType(), True),
    StructField("dnsLookupTimeMSec", IntegerType(), True),
    StructField("lastByte", IntegerType(), True),
    StructField("edgeIP", StringType(), True),
    StructField("country", StringType(), True),
    StructField("state", StringType(), True),
    StructField("city", StringType(), True),
    StructField("serverCountry", StringType(), True),
    StructField("billingRegion", StringType(), True),
    StructField("cacheStatus", IntegerType(), True),
    StructField("cacheable", IntegerType(), True),
    StructField("asn", IntegerType(), True),
    StructField("securityRules", StringType(), True),
    StructField("ewUsageInfo", StringType(), True),
    StructField("ewExecutionInfo", StringType(), True),
    StructField("customField", StringType(), True)
])

# ============================================================================
# Helper Functions
# ============================================================================

def get_db_credentials():
    """Fetch database credentials from Secrets Manager"""
    try:
        response = secrets.get_secret_value(SecretId=DB_SECRET_ARN)
        secret = json.loads(response['SecretString'])
        return {
            'host': secret['host'],
            'port': secret['port'],
            'database': secret['dbname'],
            'user': secret['username'],
            'password': secret['password']
        }
    except Exception as e:
        print(f"❌ Failed to get DB credentials: {e}")
        raise

def poll_sqs_messages(max_messages=10):
    """Poll messages from SQS queue"""
    try:
        response = sqs.receive_message(
            QueueUrl=SQS_QUEUE_URL,
            MaxNumberOfMessages=max_messages,
            WaitTimeSeconds=0,
            MessageAttributeNames=['All']
        )
        messages = response.get('Messages', [])
        print(f"📥 Received {len(messages)} messages from SQS")
        return messages
    except Exception as e:
        print(f"❌ Failed to poll SQS: {e}")
        return []

def delete_sqs_message(receipt_handle):
    """Delete processed message from SQS"""
    try:
        sqs.delete_message(
            QueueUrl=SQS_QUEUE_URL,
            ReceiptHandle=receipt_handle
        )
        print(f"✅ Deleted SQS message")
    except Exception as e:
        print(f"⚠️  Failed to delete SQS message: {e}")

def read_csv_from_s3(bucket, key):
    """Read CSV file from S3 (supports gzip)"""
    try:
        s3_path = f"s3://{bucket}/{key}"
        print(f"📖 Reading: {s3_path}")

        df = spark.read.csv(
            s3_path,
            schema=AKAMAI_SCHEMA,
            sep=' ',  # Space-delimited
            header=False,
            mode='DROPMALFORMED',  # Skip malformed rows
            encoding='UTF-8'
        )

        row_count = df.count()
        print(f"✅ Read {row_count} rows from {key}")
        return df

    except Exception as e:
        print(f"❌ Failed to read {key}: {e}")
        # Log error to S3
        log_error(bucket, key, str(e))
        return None

def log_error(bucket, key, error_msg):
    """Log processing errors to S3"""
    try:
        error_key = f"errors/{datetime.utcnow().strftime('%Y/%m/%d')}/{key.split('/')[-1]}.error.txt"
        s3.put_object(
            Bucket=ERROR_BUCKET,
            Key=error_key,
            Body=f"File: s3://{bucket}/{key}\nError: {error_msg}\nTimestamp: {datetime.utcnow().isoformat()}"
        )
        print(f"📝 Logged error to: s3://{ERROR_BUCKET}/{error_key}")
    except Exception as e:
        print(f"⚠️  Failed to log error: {e}")

def enrich_data(df: DataFrame) -> DataFrame:
    """Add derived fields and clean data"""
    return df \
        .withColumn("timestamp", from_unixtime(col("reqTimeSec"))) \
        .withColumn("hour", date_trunc("hour", col("timestamp"))) \
        .withColumn("date", to_date(col("timestamp"))) \
        .withColumn("is_error", when(col("statusCode") >= 400, 1).otherwise(0)) \
        .withColumn("is_cache_hit", when(col("cacheStatus") == 1, 1).otherwise(0)) \
        .withColumn("response_time_ms", col("turnAroundTimeMSec") + col("transferTimeMSec")) \
        .withColumn("is_mobile", when(col("UA").like("%Mobile%"), 1).otherwise(0)) \
        .withColumn("processing_timestamp", current_timestamp())

def aggregate_hourly_metrics(df: DataFrame) -> DataFrame:
    """Aggregate data by hour, country, and status"""
    return df.groupBy("hour", "country", "statusCode", "cacheStatus") \
        .agg(
            count("*").alias("request_count"),
            sum("bytes").alias("total_bytes"),
            avg("response_time_ms").alias("avg_response_time"),
            expr("percentile_approx(response_time_ms, 0.95)").alias("p95_response_time"),
            expr("percentile_approx(response_time_ms, 0.99)").alias("p99_response_time"),
            sum("is_error").alias("error_count"),
            sum("is_cache_hit").alias("cache_hits"),
            countDistinct("cliIP").alias("unique_ips")
        ) \
        .withColumn("window_start", col("hour")) \
        .withColumn("window_end", col("hour") + expr("INTERVAL 1 HOUR")) \
        .withColumn("processing_timestamp", current_timestamp()) \
        .select(
            "window_start",
            "window_end",
            "country",
            "statusCode",
            "cacheStatus",
            "request_count",
            "total_bytes",
            "avg_response_time",
            "p95_response_time",
            "p99_response_time",
            "error_count",
            "cache_hits",
            "unique_ips",
            "processing_timestamp"
        )

def aggregate_endpoint_metrics(df: DataFrame) -> DataFrame:
    """Aggregate by endpoint and method"""
    return df.groupBy("hour", "reqHost", "reqPath", "reqMethod") \
        .agg(
            count("*").alias("request_count"),
            avg("response_time_ms").alias("avg_response_time"),
            expr("percentile_approx(response_time_ms, 0.95)").alias("p95_response_time"),
            expr("percentile_approx(response_time_ms, 0.99)").alias("p99_response_time"),
            sum("is_error").alias("error_count"),
            sum("bytes").alias("total_bytes")
        ) \
        .withColumn("window_start", col("hour")) \
        .withColumn("window_end", col("hour") + expr("INTERVAL 1 HOUR")) \
        .withColumn("processing_timestamp", current_timestamp()) \
        .select(
            "window_start",
            "window_end",
            "reqHost",
            "reqPath",
            "reqMethod",
            "request_count",
            "avg_response_time",
            "p95_response_time",
            "p99_response_time",
            "error_count",
            "total_bytes",
            "processing_timestamp"
        )

def aggregate_security_events(df: DataFrame) -> DataFrame:
    """Aggregate security events (errors, suspicious patterns)"""
    security_df = df.filter(col("is_error") == 1)

    return security_df.groupBy("hour", "country", "statusCode", "errorCode") \
        .agg(
            count("*").alias("event_count"),
            countDistinct("cliIP").alias("unique_ips"),
            collect_list("cliIP").alias("source_ips")
        ) \
        .withColumn("window_start", col("hour")) \
        .withColumn("window_end", col("hour") + expr("INTERVAL 1 HOUR")) \
        .withColumn("processing_timestamp", current_timestamp()) \
        .withColumn("source_ips", array_join(slice(col("source_ips"), 1, 100), ",")) \
        .select(
            "window_start",
            "window_end",
            "country",
            "statusCode",
            "errorCode",
            "event_count",
            "unique_ips",
            "source_ips",
            "processing_timestamp"
        )

def aggregate_device_metrics(df: DataFrame) -> DataFrame:
    """Aggregate by device type and browser"""
    return df.groupBy("hour", "is_mobile") \
        .agg(
            count("*").alias("request_count"),
            avg("response_time_ms").alias("avg_response_time"),
            sum("is_error").alias("error_count")
        ) \
        .withColumn("device_type", when(col("is_mobile") == 1, "Mobile").otherwise("Desktop")) \
        .withColumn("window_start", col("hour")) \
        .withColumn("window_end", col("hour") + expr("INTERVAL 1 HOUR")) \
        .withColumn("processing_timestamp", current_timestamp()) \
        .select(
            "window_start",
            "window_end",
            "device_type",
            "request_count",
            "avg_response_time",
            "error_count",
            "processing_timestamp"
        )

def write_to_postgres(df: DataFrame, table: str, db_creds: dict, batch_size: int = 1000):
    """Write DataFrame to PostgreSQL in batches"""
    try:
        jdbc_url = f"jdbc:postgresql://{db_creds['host']}:{db_creds['port']}/{db_creds['database']}"

        row_count = df.count()
        print(f"📊 Writing {row_count} rows to {table}...")

        if row_count == 0:
            print(f"⚠️  No data to write to {table}")
            return

        df.write \
            .format("jdbc") \
            .option("url", jdbc_url) \
            .option("dbtable", table) \
            .option("user", db_creds['user']) \
            .option("password", db_creds['password']) \
            .option("driver", "org.postgresql.Driver") \
            .option("batchsize", batch_size) \
            .mode("append") \
            .save()

        print(f"✅ Successfully wrote {row_count} rows to {table}")

    except Exception as e:
        print(f"❌ Failed to write to {table}: {e}")
        raise

def log_job_run(db_creds: dict, status: str, files_processed: int, rows_processed: int, duration: float, error_msg: str = None):
    """Log Spark job run to PostgreSQL"""
    try:
        jdbc_url = f"jdbc:postgresql://{db_creds['host']}:{db_creds['port']}/{db_creds['database']}"

        import socket
        hostname = socket.gethostname()

        job_run_df = spark.createDataFrame([{
            'job_name': 'spark-akamai-processor',
            'run_id': datetime.utcnow().strftime('%Y%m%d-%H%M%S'),
            'hostname': hostname,
            'status': status,
            'files_processed': files_processed,
            'rows_processed': rows_processed,
            'duration_seconds': int(duration),
            'error_message': error_msg,
            'started_at': datetime.utcnow(),
            'completed_at': datetime.utcnow()
        }])

        job_run_df.write \
            .format("jdbc") \
            .option("url", jdbc_url) \
            .option("dbtable", "spark_job_runs") \
            .option("user", db_creds['user']) \
            .option("password", db_creds['password']) \
            .option("driver", "org.postgresql.Driver") \
            .mode("append") \
            .save()

        print(f"✅ Logged job run: {status}")

    except Exception as e:
        print(f"⚠️  Failed to log job run: {e}")

# ============================================================================
# Main Processing Logic (Runs as Daemon)
# ============================================================================

def process_batch():
    """Process one batch of messages from SQS"""
    start_time = datetime.utcnow()
    files_processed = 0
    rows_processed = 0

    try:
        # Get database credentials (cached)
        if not hasattr(process_batch, 'db_creds'):
            process_batch.db_creds = get_db_credentials()
            print("✅ Database credentials retrieved")

        db_creds = process_batch.db_creds

        # Poll SQS for batch of files
        messages = poll_sqs_messages(MAX_MESSAGES)

        if not messages:
            print(f"⏳ No messages in SQS queue - sleeping {POLL_INTERVAL}s...")
            return

        print(f"📦 Processing batch of {len(messages)} files")

        # Process each file
        all_dfs = []

        for message in messages:
            try:
                body = json.loads(message['Body'])
                bucket = body['bucket']
                key = body['key']

                # Read CSV from S3
                df = read_csv_from_s3(bucket, key)

                if df is not None:
                    all_dfs.append(df)
                    files_processed += 1

                # Delete SQS message (success or failure)
                delete_sqs_message(message['ReceiptHandle'])

            except Exception as e:
                print(f"❌ Failed to process message: {e}")
                # Message will become visible again after visibility timeout

        if not all_dfs:
            print("⚠️  No data to process")
            return

        # Combine all DataFrames
        print(f"🔗 Combining {len(all_dfs)} DataFrames...")
        combined_df = all_dfs[0]
        for df in all_dfs[1:]:
            combined_df = combined_df.union(df)

        rows_processed = combined_df.count()
        print(f"✅ Combined DataFrame: {rows_processed} rows")

        # Enrich data
        print("🔧 Enriching data...")
        enriched_df = enrich_data(combined_df)
        enriched_df.cache()  # Cache for multiple aggregations

        # Aggregate metrics
        print("📊 Aggregating hourly metrics...")
        hourly_df = aggregate_hourly_metrics(enriched_df)
        write_to_postgres(hourly_df, "hourly_metrics", db_creds, BATCH_SIZE)

        print("📊 Aggregating endpoint metrics...")
        endpoint_df = aggregate_endpoint_metrics(enriched_df)
        write_to_postgres(endpoint_df, "endpoint_metrics", db_creds, BATCH_SIZE)

        print("📊 Aggregating security events...")
        security_df = aggregate_security_events(enriched_df)
        write_to_postgres(security_df, "security_events", db_creds, BATCH_SIZE)

        print("📊 Aggregating device metrics...")
        device_df = aggregate_device_metrics(enriched_df)
        write_to_postgres(device_df, "device_metrics", db_creds, BATCH_SIZE)

        # Unpersist cached DataFrame
        enriched_df.unpersist()

        # Calculate duration
        duration = (datetime.utcnow() - start_time).total_seconds()

        # Log job run
        log_job_run(db_creds, 'success', files_processed, rows_processed, duration)

        print("============================================================================")
        print(f"✅ Batch Completed Successfully")
        print(f"   Files Processed: {files_processed}")
        print(f"   Rows Processed: {rows_processed}")
        print(f"   Duration: {duration:.2f} seconds")
        print("============================================================================")

    except Exception as e:
        print("============================================================================")
        print(f"❌ Batch Failed: {e}")
        print("============================================================================")

        duration = (datetime.utcnow() - start_time).total_seconds()

        try:
            if hasattr(process_batch, 'db_creds'):
                log_job_run(process_batch.db_creds, 'failed', files_processed, rows_processed, duration, str(e))
        except:
            print("⚠️  Could not log job failure")

def main():
    """Main daemon loop - polls SQS continuously"""
    print("============================================================================")
    print("🚀 Spark SQS Processor Started")
    print("============================================================================")
    print(f"Poll Interval: {POLL_INTERVAL} seconds")
    print(f"Max Messages per Batch: {MAX_MESSAGES}")
    print(f"SQS Queue: {SQS_QUEUE_URL}")
    print("============================================================================")

    iteration = 0

    while True:
        try:
            iteration += 1
            print(f"\n🔄 Iteration #{iteration} - {datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')}")

            # Process one batch
            process_batch()

            # Sleep until next poll
            print(f"⏰ Sleeping {POLL_INTERVAL} seconds until next poll...")
            time.sleep(POLL_INTERVAL)

        except KeyboardInterrupt:
            print("\n🛑 Received interrupt signal - shutting down gracefully...")
            break
        except Exception as e:
            print(f"❌ Unexpected error in main loop: {e}")
            print(f"⏰ Sleeping {POLL_INTERVAL} seconds before retry...")
            time.sleep(POLL_INTERVAL)

    print("============================================================================")
    print("✅ Spark SQS Processor Stopped")
    print("============================================================================")
    spark.stop()

# ============================================================================
# Entry Point
# ============================================================================

if __name__ == "__main__":
    main()

