#!/bin/bash
# Quick fix for Kafka ClassNotFoundException
# Run this on Spark Master: ssh ubuntu@10.0.1.199 'bash -s' < fix_kafka_jars.sh

set -e

echo "=========================================="
echo "🔧 Fixing Kafka JAR Dependencies"
echo "=========================================="
echo ""

cd /opt/spark/jars

echo "1️⃣ Checking existing Kafka JARs..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ls -lh | grep -i kafka || echo "No Kafka JARs found!"
echo ""

echo "2️⃣ Downloading required Kafka connector JARs..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Download spark-sql-kafka-0-10 (main Kafka connector)
if [ ! -f "spark-sql-kafka-0-10_2.12-3.5.0.jar" ]; then
    echo "📥 Downloading spark-sql-kafka-0-10..."
    sudo wget -q https://repo1.maven.org/maven2/org/apache/spark/spark-sql-kafka-0-10_2.12/3.5.0/spark-sql-kafka-0-10_2.12-3.5.0.jar
    echo "✅ Downloaded spark-sql-kafka-0-10_2.12-3.5.0.jar"
else
    echo "✅ spark-sql-kafka-0-10 already exists"
fi

# Download kafka-clients
if [ ! -f "kafka-clients-3.6.1.jar" ]; then
    echo "📥 Downloading kafka-clients..."
    sudo wget -q https://repo1.maven.org/maven2/org/apache/kafka/kafka-clients/3.6.1/kafka-clients-3.6.1.jar
    echo "✅ Downloaded kafka-clients-3.6.1.jar"
else
    echo "✅ kafka-clients already exists"
fi

# Download commons-pool2 (required by Kafka)
if [ ! -f "commons-pool2-2.11.1.jar" ]; then
    echo "📥 Downloading commons-pool2..."
    sudo wget -q https://repo1.maven.org/maven2/org/apache/commons/commons-pool2/2.11.1/commons-pool2-2.11.1.jar
    echo "✅ Downloaded commons-pool2-2.11.1.jar"
else
    echo "✅ commons-pool2 already exists"
fi

# Download spark-token-provider-kafka (CRITICAL - contains KafkaTokenUtil)
if [ ! -f "spark-token-provider-kafka-0-10_2.12-3.5.0.jar" ]; then
    echo "📥 Downloading spark-token-provider-kafka (REQUIRED for KafkaTokenUtil)..."
    sudo wget https://repo1.maven.org/maven2/org/apache/spark/spark-token-provider-kafka-0-10_2.12/3.5.0/spark-token-provider-kafka-0-10_2.12-3.5.0.jar
    if [ $? -eq 0 ]; then
        echo "✅ Downloaded spark-token-provider-kafka-0-10_2.12-3.5.0.jar"
    else
        echo "❌ Failed to download spark-token-provider-kafka"
        exit 1
    fi
else
    echo "✅ spark-token-provider-kafka already exists"
fi

echo ""
echo "3️⃣ Verifying all Kafka JARs are present..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ls -lh | grep -i kafka
echo ""

echo "4️⃣ Setting proper permissions..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sudo chown root:root *.jar
sudo chmod 644 *.jar
echo "✅ Permissions set"
echo ""

echo "=========================================="
echo "✅ Kafka JARs Installation Complete!"
echo "=========================================="
echo ""
echo "📋 Next Steps:"
echo "  1. Stop any running Spark job"
echo "  2. Re-run Jenkins pipeline"
echo "  3. Job should now find Kafka classes"
echo ""
echo "Or manually test with:"
echo "  spark-submit --packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0 ..."
echo ""

