#!/bin/bash
# Manual Spark job submission with correct Kafka packages
# Run this from the Spark Master to test if --packages works

set -e

MASTER_IP=$(hostname -I | awk '{print $1}')
MASTER_URL="spark://$MASTER_IP:7077"
KAFKA_BROKER="10.0.10.101:9092"
MYSQL_HOST="13.232.132.240"
MYSQL_USER="dstreambolt"
MYSQL_PASSWORD="DStreamBolt2025!"
JAR_FILE="/opt/dstreambolt/computations/dstreambolt-processor-1.0.0.jar"

echo "=========================================="
echo "🚀 Manual Spark Job Submission (with --packages)"
echo "=========================================="
echo ""
echo "Master URL: $MASTER_URL"
echo "Kafka Broker: $KAFKA_BROKER"
echo "JAR: $JAR_FILE"
echo ""

if [ ! -f "$JAR_FILE" ]; then
    echo "❌ JAR file not found: $JAR_FILE"
    echo "Please deploy via Jenkins first"
    exit 1
fi

echo "Starting Spark job with --packages..."
echo ""

/opt/spark/bin/spark-submit \
  --master "$MASTER_URL" \
  --deploy-mode client \
  --driver-memory 512m \
  --executor-memory 512m \
  --executor-cores 1 \
  --total-executor-cores 2 \
  --class com.dstreambolt.processor.SparkProcessor \
  --packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0,org.apache.spark:spark-token-provider-kafka-0-10_2.12:3.5.0 \
  --conf spark.driver.port=39499 \
  --conf spark.driver.host="$MASTER_IP" \
  --conf spark.sql.streaming.forceDeleteTempCheckpointLocation=true \
  --conf spark.streaming.stopGracefullyOnShutdown=true \
  --conf spark.ui.enabled=true \
  --conf spark.ui.port=4040 \
  --conf spark.jars.ivy=/tmp/.ivy2 \
  "$JAR_FILE" \
  --spark-master "$MASTER_URL" \
  --kafka-broker "$KAFKA_BROKER" \
  --mode batch \
  --mysql-host "$MYSQL_HOST" \
  --mysql-user "$MYSQL_USER" \
  --mysql-password "$MYSQL_PASSWORD" \
  --mysql-database "dstreambolt_metrics" \
  --mysql-table "spark_results"

echo ""
echo "=========================================="
echo "✅ Spark Job Completed"
echo "=========================================="

