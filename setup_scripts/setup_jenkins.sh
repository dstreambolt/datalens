#!/bin/bash

###############################################################################
# Jenkins Setup Script
# Installs and configures Jenkins with GitHub integration
###############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/jenkins-setup.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN:${NC} $1" | tee -a "$LOG_FILE"
}

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              Jenkins Setup Script                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    error "Please run as root or with sudo"
    exit 1
fi

# Detect if Jenkins is already installed
if systemctl is-active --quiet jenkins 2>/dev/null; then
    log "✅ Jenkins is already running"
    read -p "Do you want to reinstall? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Skipping installation, starting configuration..."
        SKIP_INSTALL=true
    else
        log "Stopping Jenkins for reinstall..."
        systemctl stop jenkins
        SKIP_INSTALL=false
    fi
else
    SKIP_INSTALL=false
fi

if [ "$SKIP_INSTALL" != "true" ]; then
    log "📦 Installing Java 17..."
    apt-get update -qq
    apt-get install -y openjdk-17-jdk wget gnupg2 curl git

    # Verify Java installation
    java -version 2>&1 | head -1 | tee -a "$LOG_FILE"

    log "📦 Adding Jenkins repository..."
    wget -q -O - https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | apt-key add -
    sh -c 'echo deb https://pkg.jenkins.io/debian-stable binary/ > /etc/apt/sources.list.d/jenkins.list'

    log "📦 Installing Jenkins..."
    apt-get update -qq
    apt-get install -y jenkins

    log "🔧 Configuring Jenkins..."

    # Create Jenkins override directory
    mkdir -p /etc/systemd/system/jenkins.service.d

    # Set Jenkins to run on port 8080 without prefix
    cat > /etc/systemd/system/jenkins.service.d/override.conf << 'EOFJENKINS'
[Service]
Environment="JENKINS_PORT=8080"
Environment="JENKINS_PREFIX="
Environment="JENKINS_OPTS=--httpPort=8080"
Environment="JAVA_OPTS=-Djava.awt.headless=true -Xmx512m"
EOFJENKINS

    systemctl daemon-reload
fi

log "🚀 Starting Jenkins..."
systemctl enable jenkins
systemctl start jenkins

# Wait for Jenkins to start
log "⏳ Waiting for Jenkins to initialize..."
for i in {1..60}; do
    if systemctl is-active --quiet jenkins && [ -f /var/lib/jenkins/secrets/initialAdminPassword ]; then
        sleep 5  # Additional wait for full startup
        break
    fi
    sleep 2
done

if ! systemctl is-active --quiet jenkins; then
    error "Jenkins failed to start"
    journalctl -u jenkins -n 50 --no-pager
    exit 1
fi

log "✅ Jenkins is running"

# Get initial admin password
if [ -f /var/lib/jenkins/secrets/initialAdminPassword ]; then
    JENKINS_PASSWORD=$(cat /var/lib/jenkins/secrets/initialAdminPassword)
    log "📝 Jenkins Initial Password: $JENKINS_PASSWORD"
    echo "$JENKINS_PASSWORD" > /tmp/jenkins_initial_password.txt
    chmod 600 /tmp/jenkins_initial_password.txt
else
    warn "Initial admin password file not found"
fi

log "🔧 Setting up GitHub SSH key..."
if [ ! -f /var/lib/jenkins/.ssh/id_rsa ]; then
    sudo -u jenkins mkdir -p /var/lib/jenkins/.ssh
    sudo -u jenkins ssh-keygen -t rsa -b 4096 -f /var/lib/jenkins/.ssh/id_rsa -N "" -C "jenkins@dstreambolt"
    log "✅ Jenkins SSH key generated"
    log "📋 Public key:"
    cat /var/lib/jenkins/.ssh/id_rsa.pub | tee -a "$LOG_FILE"
    echo ""
    log "Add this key to GitHub: https://github.com/settings/keys"
else
    log "✅ Jenkins SSH key already exists"
fi

# Configure Jenkins known_hosts
sudo -u jenkins ssh-keyscan github.com >> /var/lib/jenkins/.ssh/known_hosts 2>/dev/null

log "🔧 Installing recommended plugins..."
# Wait for Jenkins to be fully ready
sleep 10

# Install plugins via CLI (if jenkins-cli.jar is available)
if [ -f /var/cache/jenkins/war/WEB-INF/jenkins-cli.jar ]; then
    JENKINS_CLI="java -jar /var/cache/jenkins/war/WEB-INF/jenkins-cli.jar -s http://localhost:8080/"

    # Install essential plugins
    PLUGINS="git github github-branch-source workflow-aggregator docker-workflow kubernetes pipeline-stage-view"

    for plugin in $PLUGINS; do
        log "Installing plugin: $plugin"
        $JENKINS_CLI install-plugin $plugin || warn "Failed to install $plugin"
    done

    log "🔄 Restarting Jenkins to apply plugins..."
    systemctl restart jenkins
    sleep 15
fi

log "📊 Jenkins Status:"
systemctl status jenkins --no-pager -l | head -20 | tee -a "$LOG_FILE"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Jenkins Setup Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🔗 Access Jenkins:"
echo "   Local:  http://localhost:8080"
echo "   Public: http://$(curl -s ifconfig.me):8080"
echo ""
if [ -f /tmp/jenkins_initial_password.txt ]; then
    echo "🔑 Initial Admin Password:"
    cat /tmp/jenkins_initial_password.txt
    echo ""
fi
echo "🔐 GitHub SSH Public Key:"
cat /var/lib/jenkins/.ssh/id_rsa.pub
echo ""
echo "📝 Log file: $LOG_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

