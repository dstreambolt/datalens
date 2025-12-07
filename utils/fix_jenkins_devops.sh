#!/bin/bash

# Fix Jenkins Installation on DevOps Instance
# Run this on the DevOps instance to manually install Jenkins

set -e

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║         Fixing Jenkins Installation on DevOps Instance        ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# Update system
echo "Updating system packages..."
sudo apt-get update

# Install Java 17 if not installed
echo "Installing Java 17..."
sudo apt-get install -y openjdk-17-jdk

# Add Jenkins repository (correct method)
echo "Adding Jenkins repository..."
sudo wget -O /usr/share/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

# Update package list
sudo apt-get update

# Install Jenkins
echo "Installing Jenkins..."
sudo apt-get install -y jenkins

# Configure Jenkins to use port 8081 and Java 17
echo "Configuring Jenkins..."
sudo mkdir -p /etc/systemd/system/jenkins.service.d

cat | sudo tee /etc/systemd/system/jenkins.service.d/override.conf << 'JENKINSCONF'
[Service]
Environment="JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64"
Environment="JENKINS_PORT=8081"
JENKINSCONF

# Update Jenkins default port in /etc/default/jenkins
if [ -f /etc/default/jenkins ]; then
    sudo sed -i 's/HTTP_PORT=8080/HTTP_PORT=8081/' /etc/default/jenkins
else
    echo "HTTP_PORT=8081" | sudo tee /etc/default/jenkins
fi

# Also set in Jenkins config
sudo sed -i 's/JENKINS_PORT=8080/JENKINS_PORT=8081/' /usr/lib/systemd/system/jenkins.service || true
sudo sed -i 's/--httpPort=8080/--httpPort=8081/' /usr/lib/systemd/system/jenkins.service || true

# Reload systemd and start Jenkins
echo "Starting Jenkins..."
sudo systemctl daemon-reload
sudo systemctl enable jenkins
sudo systemctl start jenkins

# Wait for Jenkins to start
echo "Waiting for Jenkins to start (30 seconds)..."
sleep 30

# Check status
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Jenkins Status:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sudo systemctl status jenkins --no-pager | head -15

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Port Check:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sudo ss -tlnp | grep 8081 || echo "Port 8081 not yet listening (wait a bit longer)"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Jenkins Initial Admin Password:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sudo cat /var/lib/jenkins/secrets/initialAdminPassword 2>/dev/null || echo "Not yet available - wait 2 more minutes"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Jenkins Installation Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
echo "Access Jenkins at: http://$PUBLIC_IP:8081"
echo ""

