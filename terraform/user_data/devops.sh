#!/bin/bash
set -e

# DStreamBolt DevOps Instance (dstreambolt-devops) Setup
# Jenkins + Grafana + Kafka Manager + MySQL

echo "=========================================="
echo "🚀 DStreamBolt DevOps Setup"
echo "=========================================="

# Update system
apt-get update
apt-get upgrade -y

# Install common dependencies
apt-get install -y wget curl apt-transport-https software-properties-common gnupg2

# ==========================================
# 1. INSTALL MYSQL
# ==========================================
echo "Installing MySQL..."
apt-get install -y mysql-server

# Configure MySQL
systemctl start mysql
systemctl enable mysql

# Secure MySQL and create database
mysql -u root -p'DStreamBolt2025!' -e "CREATE DATABASE IF NOT EXISTS dstreambolt_metrics;"
mysql -u root -p'DStreamBolt2025!' -e "CREATE USER IF NOT EXISTS 'dstreambolt'@'%' IDENTIFIED BY 'DStreamBolt2025!';"
mysql -u root -p'DStreamBolt2025!' -e "GRANT ALL PRIVILEGES ON dstreambolt_metrics.* TO 'dstreambolt'@'%';"
mysql -u root -p'DStreamBolt2025!' -e "FLUSH PRIVILEGES;"

# Configure MySQL to listen on all interfaces
sed -i 's/bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf
systemctl restart mysql

echo "✅ MySQL installed and configured"

# ==========================================
# 2. INSTALL JENKINS ON PORT 8081
# ==========================================
echo "Installing Jenkins on port 8081..."

# Add Jenkins repository
wget -q -O - https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | apt-key add -
sh -c 'echo deb https://pkg.jenkins.io/debian-stable binary/ > /etc/apt/sources.list.d/jenkins.list'

# Install Java 17 (required for Jenkins)
apt-get update
apt-get install -y openjdk-17-jdk jenkins

# Configure Jenkins to use port 8081 and Java 17
mkdir -p /etc/systemd/system/jenkins.service.d
cat > /etc/systemd/system/jenkins.service.d/override.conf << 'JENKINSCONF'
[Service]
Environment="JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64"
Environment="JENKINS_PORT=8081"
JENKINSCONF

# Update Jenkins default port
sed -i 's/HTTP_PORT=8080/HTTP_PORT=8081/' /etc/default/jenkins || echo "HTTP_PORT=8081" >> /etc/default/jenkins

# Reload and start Jenkins
systemctl daemon-reload
systemctl enable jenkins
systemctl start jenkins

echo "✅ Jenkins installed on port 8081"

# ==========================================
# 3. INSTALL GRAFANA
# ==========================================
echo "Installing Grafana..."

# Add Grafana repository
wget -q -O - https://packages.grafana.com/gpg.key | apt-key add -
add-apt-repository "deb https://packages.grafana.com/oss/deb stable main"

# Install Grafana
apt-get update
apt-get install -y grafana

# Configure Grafana
cat >> /etc/grafana/grafana.ini << EOF

[server]
http_addr = 0.0.0.0
http_port = 3000

[security]
admin_user = admin
admin_password = DStreamBolt2025!

[auth.anonymous]
enabled = false
EOF

# Start Grafana
systemctl start grafana-server
systemctl enable grafana-server

echo "✅ Grafana installed"

# ==========================================
# 4. INSTALL AKHQ (Kafka UI)
# ==========================================
echo "Installing AKHQ (Kafka UI)..."

# Install Java if not already installed (AKHQ needs Java)
apt-get install -y openjdk-17-jre-headless

# Download AKHQ
AKHQ_VERSION="0.25.0"
cd /opt
wget https://github.com/tchiotludo/akhq/releases/download/${AKHQ_VERSION}/akhq-${AKHQ_VERSION}-all.jar -O akhq.jar

# Create AKHQ configuration
mkdir -p /opt/akhq/config
cat > /opt/akhq/config/application.yml << 'AKHQCONF'
akhq:
  connections:
    dstreambolt-kafka:
      properties:
        bootstrap.servers: "KAFKA_IP_PLACEHOLDER:9092"
      schema-registry:
        url: "http://KAFKA_IP_PLACEHOLDER:8081"
        type: "confluent"
      connect:
        - name: "connect"
          url: "http://KAFKA_IP_PLACEHOLDER:8083"

  server:
    access-log:
      enabled: true
      name: org.akhq.log.access

micronaut:
  server:
    port: 8080
  security:
    enabled: false
AKHQCONF

# Create AKHQ systemd service
cat > /etc/systemd/system/akhq.service << 'AKHQSVC'
[Unit]
Description=AKHQ - Kafka GUI
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/akhq
ExecStart=/usr/bin/java -Dmicronaut.config.files=/opt/akhq/config/application.yml -jar /opt/akhq.jar
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
AKHQSVC

# Start AKHQ
systemctl daemon-reload
systemctl enable akhq
systemctl start akhq

echo "✅ AKHQ (Kafka UI) installed on port 9000"

# ==========================================
# 5. CONFIGURE FIREWALL (UFW)
# ==========================================
echo "Configuring firewall..."
ufw --force enable
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 3000/tcp  # Grafana
ufw allow 8080/tcp  # AKHQ (Kafka UI)
ufw allow 8081/tcp  # Jenkins
ufw allow from 10.0.0.0/16 to any port 3306  # MySQL from VPC only

echo "✅ Firewall configured"

# ==========================================
# 6. CREATE MONITORING DASHBOARD
# ==========================================
echo "Setting up monitoring..."

# Create Grafana datasource for MySQL
sleep 20  # Wait for Grafana to fully start

curl -X POST -H "Content-Type: application/json" -d '{
  "name":"DStreamBolt MySQL",
  "type":"mysql",
  "url":"localhost:3306",
  "access":"proxy",
  "database":"dstreambolt_metrics",
  "user":"root",
  "password":"DStreamBolt2025!",
  "basicAuth":false
}' http://admin:DStreamBolt2025!@localhost:3000/api/datasources || true

echo "✅ Monitoring configured"

# ==========================================
# 7. CREATE STATUS PAGE
# ==========================================
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

cat > /var/www/html/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DStreamBolt DevOps Platform</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); min-height: 100vh; padding: 40px 20px; }
        .container { max-width: 1200px; margin: 0 auto; background: white; border-radius: 20px; box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3); overflow: hidden; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 40px; text-align: center; }
        .header h1 { font-size: 2.5em; margin-bottom: 10px; }
        .header p { font-size: 1.2em; opacity: 0.9; }
        .services { padding: 40px; display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 25px; }
        .service-card { background: #f8f9fa; border: 2px solid #e9ecef; border-radius: 15px; padding: 30px; transition: all 0.3s ease; position: relative; overflow: hidden; }
        .service-card::before { content: ''; position: absolute; top: 0; left: 0; width: 5px; height: 100%; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); }
        .service-card:hover { transform: translateY(-5px); box-shadow: 0 10px 30px rgba(102, 126, 234, 0.3); border-color: #667eea; }
        .service-card h3 { color: #333; font-size: 1.5em; margin-bottom: 15px; display: flex; align-items: center; gap: 10px; }
        .service-card .icon { font-size: 1.8em; }
        .service-card .description { color: #666; margin-bottom: 20px; line-height: 1.6; }
        .service-card .access-btn { display: inline-block; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; text-decoration: none; padding: 12px 30px; border-radius: 25px; font-weight: 600; transition: all 0.3s ease; box-shadow: 0 4px 15px rgba(102, 126, 234, 0.4); }
        .service-card .access-btn:hover { transform: scale(1.05); box-shadow: 0 6px 20px rgba(102, 126, 234, 0.6); }
        .service-card .details { margin-top: 15px; padding-top: 15px; border-top: 1px solid #e9ecef; font-size: 0.9em; color: #888; }
        .service-card .details strong { color: #333; }
        .status-badge { display: inline-block; padding: 5px 15px; background: #28a745; color: white; border-radius: 20px; font-size: 0.85em; font-weight: 600; margin-bottom: 15px; }
        .footer { background: #f8f9fa; padding: 30px; text-align: center; color: #666; border-top: 1px solid #e9ecef; }
        .footer p { margin: 5px 0; }
        .footer .tech-stack { margin-top: 15px; display: flex; justify-content: center; gap: 15px; flex-wrap: wrap; }
        .footer .tech { background: white; padding: 8px 15px; border-radius: 20px; font-size: 0.9em; border: 1px solid #e9ecef; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 DStreamBolt DevOps Platform</h1>
            <p>Real-Time Data Streaming Infrastructure</p>
        </div>
        <div class="services">
            <div class="service-card">
                <span class="status-badge">✓ RUNNING</span>
                <h3><span class="icon">🔧</span> Jenkins CI/CD</h3>
                <p class="description">Continuous Integration and Deployment platform for building, testing, and deploying applications.</p>
                <a href="http://PUBLIC_IP:8081" class="access-btn" target="_blank">Access Jenkins →</a>
                <div class="details"><strong>Port:</strong> 8081<br><strong>Password:</strong> Check /var/lib/jenkins/secrets/initialAdminPassword</div>
            </div>
            <div class="service-card">
                <span class="status-badge">✓ RUNNING</span>
                <h3><span class="icon">🎛️</span> AKHQ (Kafka UI)</h3>
                <p class="description">Web-based GUI for Apache Kafka cluster management and monitoring.</p>
                <a href="http://PUBLIC_IP:8080" class="access-btn" target="_blank">Access AKHQ →</a>
                <div class="details"><strong>Port:</strong> 8080<br><strong>Auth:</strong> None required</div>
            </div>
            <div class="service-card">
                <span class="status-badge">✓ RUNNING</span>
                <h3><span class="icon">📊</span> Grafana Monitoring</h3>
                <p class="description">Real-time metrics visualization and monitoring dashboards.</p>
                <a href="http://PUBLIC_IP:3000" class="access-btn" target="_blank">Access Grafana →</a>
                <div class="details"><strong>Port:</strong> 3000<br><strong>Login:</strong> admin / DStreamBolt2025!</div>
            </div>
            <div class="service-card">
                <span class="status-badge">✓ RUNNING</span>
                <h3><span class="icon">🗄️</span> MySQL Database</h3>
                <p class="description">Central database for application metrics and operational data.</p>
                <div style="display: inline-block; background: #6c757d; color: white; padding: 12px 30px; border-radius: 25px; font-weight: 600;">Internal Access Only</div>
                <div class="details"><strong>Port:</strong> 3306<br><strong>Access:</strong> VPC only (10.0.0.0/16)</div>
            </div>
        </div>
        <div class="footer">
            <p><strong>DStreamBolt Platform</strong> | Production Infrastructure</p>
            <p>AWS Region: ap-south-1 (Mumbai)</p>
            <div class="tech-stack">
                <span class="tech">☁️ AWS</span>
                <span class="tech">📡 Kafka</span>
                <span class="tech">⚡ Spark</span>
                <span class="tech">🔄 CI/CD</span>
                <span class="tech">📊 Monitoring</span>
            </div>
        </div>
    </div>
</body>
</html>
HTMLEOF

# Replace PUBLIC_IP placeholder with actual IP
sed -i "s/PUBLIC_IP/$PUBLIC_IP/g" /var/www/html/index.html

# Install nginx for status page
apt-get install -y nginx
systemctl restart nginx

echo ""
echo "=========================================="
echo "✅ DStreamBolt DevOps Setup Complete!"
echo "=========================================="
echo ""
echo "Services Status:"
echo "  Jenkins:       $(systemctl is-active jenkins)"
echo "  Grafana:       $(systemctl is-active grafana-server)"
echo "  AKHQ:          $(systemctl is-active akhq)"
echo "  MySQL:         $(systemctl is-active mysql)"
echo ""
echo "Access URLs:"
echo "  Status Page:   http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
echo "  Jenkins:       http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8081"
echo "  AKHQ:          http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080"
echo "  Grafana:       http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):3000"
echo ""
echo "Jenkins Initial Password:"
cat /var/lib/jenkins/secrets/initialAdminPassword 2>/dev/null || echo "Not yet available (wait 2 minutes)"
echo ""

