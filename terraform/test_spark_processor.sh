#!/bin/bash

# Test Spark Processor with Kafka Data
# This script runs the Spark processor in batch mode to consume and print all Kafka logs

SPARK_MASTER="spark://10.0.1.128:7077"
KAFKA_BROKER="10.0.10.101:9092"
COMPUTE_IP="13.127.201.0"
SSH_KEY="$HOME/dstreambolt-access-key.pem"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧪 Testing Spark Processor - Batch Mode"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Spark Master: $SPARK_MASTER"
echo "Kafka Broker: $KAFKA_BROKER"
echo "Compute Node: $COMPUTE_IP"
echo ""

# First, upload the latest spark_processor.py
echo "📤 Uploading latest spark_processor.py..."
scp -o StrictHostKeyChecking=no -i "$SSH_KEY" \
    ../computations/spark_processor.py \
    ubuntu@${COMPUTE_IP}:/opt/dstreambolt/computations/

echo ""
echo "🚀 Running Spark processor in batch mode..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" ubuntu@${COMPUTE_IP} << 'ENDSSH'
set -e

cd /opt/dstreambolt/computations

# Get private IP for Spark master URL
PRIVATE_IP=$(hostname -I | awk '{print $1}')
MASTER_URL="spark://$PRIVATE_IP:7077"

echo "🔧 Configuration:"
echo "  Private IP: $PRIVATE_IP"
echo "  Spark Master: $MASTER_URL"
echo "  Kafka Broker: 10.0.10.101:9092"
echo ""

# Run Spark processor in batch mode
echo "🚀 Starting Spark batch processor..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

/opt/spark/bin/spark-submit \
    --master "$MASTER_URL" \
    --deploy-mode client \
    --driver-memory 512m \
    --executor-memory 512m \
    --packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0 \
    spark_processor.py \
    --spark-master "$MASTER_URL" \
    --kafka-broker "10.0.10.101:9092" \
    --topic "dstreambolt-logs" \
    --mode batch

ENDSSH

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Test Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

