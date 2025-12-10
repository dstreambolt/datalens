#!/bin/bash
set -e

# DStreamBolt Spark Executor Setup
# Dedicated Spark Worker/Executor node

echo "=========================================="
echo "🚀 DStreamBolt Spark Executor Setup"
echo "=========================================="

# Spark Master IP passed from Terraform
SPARK_MASTER_IP="${spark_master_ip}"

echo "Spark Master IP: $SPARK_MASTER_IP"

# Check if Spark is already installed
if [ -d "/opt/spark" ]; then
    echo "✅ Spark already installed at /opt/spark"
    echo "Skipping installation, will configure and start executor..."
else
    echo "📦 Installing Spark..."

    # Update system
    apt-get update
    apt-get upgrade -y

    # Install Java if not present
    if ! command -v java &> /dev/null; then
        echo "📦 Installing Java..."
        apt-get install -y openjdk-11-jdk wget curl
    else
        echo "✅ Java already installed"
        apt-get install -y wget curl
    fi

    # Download and install Spark
    SPARK_VERSION="3.5.0"
    cd /opt
    wget https://archive.apache.org/dist/spark/spark-3.5.0/spark-3.5.0-bin-hadoop3.tgz
    tar -xzf spark-3.5.0-bin-hadoop3.tgz
    ln -s spark-3.5.0-bin-hadoop3 spark
    rm spark-3.5.0-bin-hadoop3.tgz

    echo "✅ Spark installation complete"
fi

# Get private IP
PRIVATE_IP=$(hostname -I | awk '{print $1}')
echo "Executor Private IP: $PRIVATE_IP"

# Configure Spark Worker
cat > /opt/spark/conf/spark-defaults.conf << EOF
spark.master                     spark://$${SPARK_MASTER_IP}:7077
EOF

cat > /opt/spark/conf/spark-env.sh << EOF
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export SPARK_WORKER_WEBUI_PORT=8081
export SPARK_WORKER_MEMORY=1500m
export SPARK_WORKER_CORES=2
EOF

chmod +x /opt/spark/conf/spark-env.sh

# Create Spark Worker service
cat > /etc/systemd/system/spark-worker.service << EOFSERVICE
[Unit]
Description=Apache Spark Worker
After=network.target

[Service]
Type=forking
User=root
Environment="JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64"
ExecStart=/opt/spark/sbin/start-worker.sh spark://$${SPARK_MASTER_IP}:7077
ExecStop=/opt/spark/sbin/stop-worker.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOFSERVICE

# Add Spark to PATH
echo 'export PATH=$PATH:/opt/spark/bin:/opt/spark/sbin' >> /etc/profile
echo 'export SPARK_HOME=/opt/spark' >> /etc/profile

# Install Kafka libraries for Spark (needed for executors)
echo "📦 Installing Spark dependencies..."
cd /opt/spark/jars

[ ! -f "spark-sql-kafka-0-10_2.12-3.5.0.jar" ] && \
  wget -q https://repo1.maven.org/maven2/org/apache/spark/spark-sql-kafka-0-10_2.12/3.5.0/spark-sql-kafka-0-10_2.12-3.5.0.jar

[ ! -f "spark-token-provider-kafka-0-10_2.12-3.5.0.jar" ] && \
  wget -q https://repo1.maven.org/maven2/org/apache/spark/spark-token-provider-kafka-0-10_2.12/3.5.0/spark-token-provider-kafka-0-10_2.12-3.5.0.jar

[ ! -f "kafka-clients-3.6.1.jar" ] && \
  wget -q https://repo1.maven.org/maven2/org/apache/kafka/kafka-clients/3.6.1/kafka-clients-3.6.1.jar

[ ! -f "commons-pool2-2.11.1.jar" ] && \
  wget -q https://repo1.maven.org/maven2/org/apache/commons/commons-pool2/2.11.1/commons-pool2-2.11.1.jar

# Download MySQL JDBC driver
[ ! -f "mysql-connector-j-8.2.0.jar" ] && \
  wget -q https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/8.2.0/mysql-connector-j-8.2.0.jar

echo "✅ Spark dependencies ready"

# Create deployment directories for Jenkins (in case jobs are deployed here)
echo "📁 Creating deployment directories..."
mkdir -p /opt/dstreambolt/computations
mkdir -p /opt/dstreambolt/computations-backups
chown -R ubuntu:ubuntu /opt/dstreambolt
chmod -R 755 /opt/dstreambolt

# Create Spark logs directory with proper permissions
mkdir -p /opt/spark/logs
chown -R ubuntu:ubuntu /opt/spark/logs
chmod -R 755 /opt/spark/logs

echo "✅ Deployment directories created"

# Wait for master to be ready
echo "Waiting for Spark Master at $${SPARK_MASTER_IP}:7077 to be ready..."
for i in {1..30}; do
  if timeout 2 bash -c "echo > /dev/tcp/$${SPARK_MASTER_IP}/7077" 2>/dev/null; then
    echo "✅ Spark Master is ready!"
    break
  fi
  echo "Attempt $i/30: Master not ready yet, waiting..."
  sleep 10
done

# Start worker service
systemctl daemon-reload
systemctl enable spark-worker

# Check if worker is already running
if systemctl is-active --quiet spark-worker; then
    echo "⚠️  Worker already running, restarting..."
    systemctl restart spark-worker
else
    echo "🚀 Starting worker for the first time..."
    systemctl start spark-worker
fi

# Wait a moment for worker to start
sleep 10

echo "✅ DStreamBolt Spark Executor setup complete!"
echo ""
echo "Spark Worker Status:"
systemctl status spark-worker --no-pager | head -15
echo ""
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
echo "Access:"
echo "  Worker UI:      http://$${PUBLIC_IP}:8081"
echo "  Master UI:      http://$${SPARK_MASTER_IP}:8080"
echo "  Connected to:   spark://$${SPARK_MASTER_IP}:7077"
echo ""
echo "This executor is registered with Spark Master at $${SPARK_MASTER_IP}"

