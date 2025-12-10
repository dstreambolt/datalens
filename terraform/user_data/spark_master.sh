#!/bin/bash
set -e

# DStreamBolt Spark Master Setup
# Dedicated Spark Master node

echo "=========================================="
echo "🚀 DStreamBolt Spark Master Setup"
echo "=========================================="

# Update system
apt-get update
apt-get upgrade -y

# Install Java
apt-get install -y openjdk-11-jdk wget curl

# Download and install Spark
SPARK_VERSION="3.5.0"
cd /opt
wget https://archive.apache.org/dist/spark/spark-3.5.0/spark-3.5.0-bin-hadoop3.tgz
tar -xzf spark-3.5.0-bin-hadoop3.tgz
ln -s spark-3.5.0-bin-hadoop3 spark
rm spark-3.5.0-bin-hadoop3.tgz

# Get private IP
PRIVATE_IP=$(hostname -I | awk '{print $1}')
echo "Private IP: $PRIVATE_IP"

# Configure Spark Master
cat > /opt/spark/conf/spark-defaults.conf << EOF
spark.master                     spark://$${PRIVATE_IP}:7077
spark.eventLog.enabled           true
spark.eventLog.dir               file:///var/log/spark-events
spark.history.fs.logDirectory    file:///var/log/spark-events
EOF

cat > /opt/spark/conf/spark-env.sh << EOF
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export SPARK_MASTER_HOST=$${PRIVATE_IP}
export SPARK_MASTER_PORT=7077
export SPARK_MASTER_WEBUI_PORT=8080
export SPARK_HISTORY_OPTS="-Dspark.history.ui.port=18080"
EOF

chmod +x /opt/spark/conf/spark-env.sh

# Create event log directory
mkdir -p /var/log/spark-events
chmod 777 /var/log/spark-events

# Create Spark Master service
cat > /etc/systemd/system/spark-master.service << 'EOFSERVICE'
[Unit]
Description=Apache Spark Master
After=network.target

[Service]
Type=forking
User=root
Environment="JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64"
ExecStart=/opt/spark/sbin/start-master.sh
ExecStop=/opt/spark/sbin/stop-master.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOFSERVICE

# Create Spark History Server service
cat > /etc/systemd/system/spark-history.service << 'EOFSERVICE'
[Unit]
Description=Apache Spark History Server
After=network.target

[Service]
Type=forking
User=root
Environment="JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64"
ExecStart=/opt/spark/sbin/start-history-server.sh
ExecStop=/opt/spark/sbin/stop-history-server.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOFSERVICE

# Add Spark to PATH
echo 'export PATH=$PATH:/opt/spark/bin:/opt/spark/sbin' >> /etc/profile
echo 'export SPARK_HOME=/opt/spark' >> /etc/profile

# Install Kafka libraries for Spark
cd /opt/spark/jars
wget -q https://repo1.maven.org/maven2/org/apache/spark/spark-sql-kafka-0-10_2.12/3.5.0/spark-sql-kafka-0-10_2.12-3.5.0.jar
wget -q https://repo1.maven.org/maven2/org/apache/kafka/kafka-clients/3.6.1/kafka-clients-3.6.1.jar
wget -q https://repo1.maven.org/maven2/org/apache/commons/commons-pool2/2.11.1/commons-pool2-2.11.1.jar

# Download MySQL JDBC driver for Spark
wget -q https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/8.2.0/mysql-connector-j-8.2.0.jar

# Create deployment directories for Jenkins
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

# Start services
systemctl daemon-reload
systemctl enable spark-master
systemctl enable spark-history

systemctl start spark-master
sleep 10
systemctl start spark-history

echo "✅ DStreamBolt Spark Master setup complete!"
echo ""
echo "Spark Master Status:"
systemctl status spark-master --no-pager | head -15
echo ""
echo "Spark History Server Status:"
systemctl status spark-history --no-pager | head -15
echo ""
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
echo "Access:"
echo "  Master UI:   http://$${PUBLIC_IP}:8080"
echo "  History:     http://$${PUBLIC_IP}:18080"
echo "  Master URL:  spark://$${PRIVATE_IP}:7077"
echo ""
echo "To connect workers to this master, use:"
echo "  spark://$${PRIVATE_IP}:7077"

