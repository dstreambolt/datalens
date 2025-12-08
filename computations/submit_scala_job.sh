#!/bin/bash
# Submit Scala Spark job

SPARK_HOME="${SPARK_HOME:-/opt/spark}"
MASTER_URL="${1:-spark://localhost:7077}"
KAFKA_BROKER="${2:-localhost:9092}"
MODE="${3:-batch}"
DRIVER_MEM="${4:-512m}"
EXECUTOR_MEM="${5:-512m}"
DRIVER_PORT="${6:-39499}"

# Get private IP
PRIVATE_IP=$(hostname -I | awk '{print $1}')

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Starting Scala Spark Job"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Master: $MASTER_URL"
echo "Kafka: $KAFKA_BROKER"
echo "Mode: $MODE"
echo "Driver Memory: $DRIVER_MEM"
echo "Executor Memory: $EXECUTOR_MEM"
echo "Driver Port: $DRIVER_PORT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Find the JAR file
JAR_FILE=$(ls -t target/scala-2.12/dstreambolt-processor-*.jar 2>/dev/null | head -1)

if [ -z "$JAR_FILE" ]; then
    echo "❌ JAR file not found. Run ./build.sh first"
    exit 1
fi

echo "📦 Using JAR: $JAR_FILE"

$SPARK_HOME/bin/spark-submit \
    --master "$MASTER_URL" \
    --deploy-mode client \
    --driver-memory "$DRIVER_MEM" \
    --executor-memory "$EXECUTOR_MEM" \
    --executor-cores 1 \
    --total-executor-cores 2 \
    --class com.dstreambolt.processor.SparkProcessor \
    --conf spark.driver.port="$DRIVER_PORT" \
    --conf spark.driver.host="$PRIVATE_IP" \
    --conf spark.sql.streaming.forceDeleteTempCheckpointLocation=true \
    --conf spark.streaming.stopGracefullyOnShutdown=true \
    --conf spark.ui.enabled=true \
    --conf spark.ui.port=4040 \
    --conf spark.network.timeout=800s \
    --conf spark.executor.heartbeatInterval=60s \
    "$JAR_FILE" \
    --spark-master "$MASTER_URL" \
    --kafka-broker "$KAFKA_BROKER" \
    --mode "$MODE"

