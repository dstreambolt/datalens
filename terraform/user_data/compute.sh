#!/bin/bash
set -e

# DStreamBolt Spark Compute (dstreambolt-compute) Setup
# Single node with Master + Worker

echo "=========================================="
echo "🚀 DStreamBolt Spark Compute Setup"
echo "=========================================="

# Update system
apt-get update
apt-get upgrade -y

# Install Java
apt-get install -y openjdk-11-jdk wget

# Download and install Spark
SPARK_VERSION="3.5.0"
cd /opt
wget https://archive.apache.org/dist/spark/spark-3.5.0/spark-3.5.0-bin-hadoop3.tgz
tar -xzf spark-3.5.0-bin-hadoop3.tgz
ln -s spark-3.5.0-bin-hadoop3 spark
rm spark-3.5.0-bin-hadoop3.tgz

# Get private IP
PRIVATE_IP=$(hostname -I | awk '{print $1}')

# Configure Spark
cat > /opt/spark/conf/spark-defaults.conf << EOF
spark.master                     spark://${PRIVATE_IP}:7077
spark.eventLog.enabled           true
spark.eventLog.dir               file:///var/log/spark-events
spark.history.fs.logDirectory    file:///var/log/spark-events
spark.executor.memory            1g
spark.driver.memory              1g
EOF

cat > /opt/spark/conf/spark-env.sh << EOF
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export SPARK_MASTER_HOST=${PRIVATE_IP}
export SPARK_MASTER_PORT=7077
export SPARK_MASTER_WEBUI_PORT=8080
export SPARK_WORKER_WEBUI_PORT=8081
export SPARK_HISTORY_OPTS="-Dspark.history.ui.port=18080"
export SPARK_WORKER_MEMORY=1g
export SPARK_WORKER_CORES=2
EOF

chmod +x /opt/spark/conf/spark-env.sh

# Create event log directory
mkdir -p /var/log/spark-events
chmod 777 /var/log/spark-events

# Create Spark Master service
cat > /etc/systemd/system/spark-master.service << 'EOF'
[Unit]
Description=Apache Spark Master
After=network.target

[Service]
Type=forking
User=root
ExecStart=/opt/spark/sbin/start-master.sh
ExecStop=/opt/spark/sbin/stop-master.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Create Spark Worker service
cat > /etc/systemd/system/spark-worker.service << 'EOF'
[Unit]
Description=Apache Spark Worker
After=network.target spark-master.service
Requires=spark-master.service

[Service]
Type=forking
User=root
ExecStart=/opt/spark/sbin/start-worker.sh spark://SPARK_PRIVATE_IP_PLACEHOLDER:7077
ExecStop=/opt/spark/sbin/stop-worker.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Replace placeholder with actual private IP
sed -i "s/SPARK_PRIVATE_IP_PLACEHOLDER/${PRIVATE_IP}/g" /etc/systemd/system/spark-worker.service

# Create Spark History Server service
cat > /etc/systemd/system/spark-history.service << 'EOF'
[Unit]
Description=Apache Spark History Server
After=network.target

[Service]
Type=forking
User=root
ExecStart=/opt/spark/sbin/start-history-server.sh
ExecStop=/opt/spark/sbin/stop-history-server.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Add Spark to PATH
echo 'export PATH=$PATH:/opt/spark/bin:/opt/spark/sbin' >> /etc/profile

# Start services
systemctl daemon-reload
systemctl enable spark-master
systemctl enable spark-worker
systemctl enable spark-history

systemctl start spark-master
sleep 10
systemctl start spark-worker
sleep 5
systemctl start spark-history

# Install Kafka libraries for Spark
cd /opt/spark/jars
wget https://repo1.maven.org/maven2/org/apache/spark/spark-sql-kafka-0-10_2.12/3.5.0/spark-sql-kafka-0-10_2.12-3.5.0.jar
wget https://repo1.maven.org/maven2/org/apache/kafka/kafka-clients/3.6.1/kafka-clients-3.6.1.jar
wget https://repo1.maven.org/maven2/org/apache/commons/commons-pool2/2.11.1/commons-pool2-2.11.1.jar

echo "✅ DStreamBolt Spark Compute setup complete!"
echo ""
echo "Spark Master Status:"
systemctl status spark-master --no-pager | head -15
echo ""
echo "Spark Worker Status:"
systemctl status spark-worker --no-pager | head -15
echo ""
echo "Access:"
echo "  Master UI:  http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080"
echo "  Worker UI:  http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8081"
echo "  History:    http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):18080"
echo "  Master URL: spark://${PRIVATE_IP}:7077"

