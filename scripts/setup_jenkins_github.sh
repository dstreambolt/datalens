#!/bin/bash

###############################################################################
# Jenkins GitHub Credentials Setup Script
# Sets up SSH keys and credentials for GitHub access in Jenkins
###############################################################################

set -e

DEVOPS_IP="13.235.238.208"
SSH_KEY="$HOME/dstreambolt-access-key.pem"
GITHUB_REPO="git@github.com:dstreambolt/dstream_cloud.git"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ ${NC}$1"; }
log_success() { echo -e "${GREEN}✅${NC} $1"; }
log_error() { echo -e "${RED}❌${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠️ ${NC}$1"; }

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     Jenkins GitHub Credentials Setup                         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Check if SSH key exists
log_info "Step 1: Checking SSH access key..."
if [ ! -f "$SSH_KEY" ]; then
    log_error "SSH key not found: $SSH_KEY"
    exit 1
fi
log_success "SSH key found"

# Step 2: Check Jenkins access
log_info "Step 2: Checking Jenkins service..."
JENKINS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://$DEVOPS_IP/jenkins 2>/dev/null || echo "000")
if [ "$JENKINS_STATUS" != "200" ] && [ "$JENKINS_STATUS" != "403" ]; then
    log_error "Jenkins is not accessible at http://$DEVOPS_IP/jenkins (HTTP $JENKINS_STATUS)"
    exit 1
fi
log_success "Jenkins is accessible"

# Step 3: Setup SSH key on DevOps node
log_info "Step 3: Setting up SSH key for GitHub on DevOps node..."

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@$DEVOPS_IP << 'EOFSSH'
#!/bin/bash

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Setting up GitHub SSH key for Jenkins"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Create SSH directory for jenkins user
sudo mkdir -p /var/lib/jenkins/.ssh
sudo chown jenkins:jenkins /var/lib/jenkins/.ssh
sudo chmod 700 /var/lib/jenkins/.ssh

# Check if key already exists
if [ -f /var/lib/jenkins/.ssh/id_rsa ]; then
    echo "✅ SSH key already exists for jenkins user"
else
    echo "📝 Generating new SSH key for jenkins user..."
    sudo -u jenkins ssh-keygen -t rsa -b 4096 -C "jenkins@dstreambolt.click" -f /var/lib/jenkins/.ssh/id_rsa -N ""
    echo "✅ SSH key generated"
fi

# Add GitHub to known hosts
echo "📝 Adding GitHub to known hosts..."
sudo -u jenkins ssh-keyscan -H github.com >> /var/lib/jenkins/.ssh/known_hosts 2>/dev/null || true
sudo chmod 644 /var/lib/jenkins/.ssh/known_hosts

# Display the public key
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Jenkins SSH Public Key (Add this to GitHub):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sudo cat /var/lib/jenkins/.ssh/id_rsa.pub
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Test GitHub connection
echo ""
echo "🔍 Testing GitHub connection..."
sudo -u jenkins ssh -T git@github.com 2>&1 | head -5 || true

EOFSSH

log_success "SSH key setup complete on DevOps node"

# Step 4: Get Jenkins admin password
log_info "Step 4: Getting Jenkins admin password..."
echo ""
JENKINS_PASS=$(ssh -i "$SSH_KEY" ubuntu@$DEVOPS_IP 'sudo cat /var/lib/jenkins/secrets/initialAdminPassword 2>/dev/null || echo "NOT_FOUND"')

if [ "$JENKINS_PASS" != "NOT_FOUND" ] && [ ! -z "$JENKINS_PASS" ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔑 Jenkins Admin Password:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$JENKINS_PASS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
    log_warning "Initial admin password not found (Jenkins may already be configured)"
fi

# Step 5: Create Jenkins credential XML
log_info "Step 5: Creating Jenkins SSH credential configuration..."

ssh -i "$SSH_KEY" ubuntu@$DEVOPS_IP << 'EOFCRED'
#!/bin/bash

# Create credentials directory if it doesn't exist
sudo mkdir -p /var/lib/jenkins/credentials
sudo chown jenkins:jenkins /var/lib/jenkins/credentials

# Get the private key
PRIVATE_KEY=$(sudo cat /var/lib/jenkins/.ssh/id_rsa)

# Create credential XML file
sudo tee /tmp/jenkins-github-ssh-credential.xml > /dev/null << 'EOFXML'
<?xml version='1.1' encoding='UTF-8'?>
<com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey plugin="ssh-credentials@1.18.1">
  <scope>GLOBAL</scope>
  <id>jenkins-github-ssh</id>
  <description>GitHub SSH Key for DStreamBolt Repository</description>
  <username>git</username>
  <privateKeySource class="com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey$DirectEntryPrivateKeySource">
    <privateKey>PRIVATE_KEY_PLACEHOLDER</privateKey>
  </privateKeySource>
</com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey>
EOFXML

# Replace placeholder with actual private key (escaped)
ESCAPED_KEY=$(echo "$PRIVATE_KEY" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
sudo sed -i "s|PRIVATE_KEY_PLACEHOLDER|$ESCAPED_KEY|g" /tmp/jenkins-github-ssh-credential.xml

sudo chown jenkins:jenkins /tmp/jenkins-github-ssh-credential.xml
echo "✅ Credential XML created"

EOFCRED

log_success "Jenkins credential configuration created"

# Step 6: Install Jenkins CLI
log_info "Step 6: Setting up Jenkins CLI..."

ssh -i "$SSH_KEY" ubuntu@$DEVOPS_IP << 'EOFCLI'
#!/bin/bash

# Download Jenkins CLI
if [ ! -f /tmp/jenkins-cli.jar ]; then
    echo "📥 Downloading Jenkins CLI..."
    wget -q http://localhost:8080/jnlpJars/jenkins-cli.jar -O /tmp/jenkins-cli.jar
    echo "✅ Jenkins CLI downloaded"
else
    echo "✅ Jenkins CLI already exists"
fi

EOFCLI

log_success "Jenkins CLI ready"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              ✅ Setup Complete!                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Next Steps:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Copy the SSH public key (shown above) and add it to GitHub:"
echo "   - Go to: https://github.com/dstreambolt/dstream_cloud/settings/keys"
echo "   - Click 'Add deploy key'"
echo "   - Paste the key"
echo "   - Title: 'Jenkins DStreamBolt'"
echo "   - ✅ Allow write access (if needed)"
echo ""
echo "2. Get the SSH public key again if needed:"
echo "   ssh -i $SSH_KEY ubuntu@$DEVOPS_IP 'sudo cat /var/lib/jenkins/.ssh/id_rsa.pub'"
echo ""
echo "3. Access Jenkins UI:"
echo "   http://$DEVOPS_IP/jenkins"
if [ "$JENKINS_PASS" != "NOT_FOUND" ] && [ ! -z "$JENKINS_PASS" ]; then
    echo "   Username: admin"
    echo "   Password: $JENKINS_PASS"
fi
echo ""
echo "4. Add the credential in Jenkins UI:"
echo "   - Go to: Manage Jenkins > Credentials"
echo "   - Click: (global) domain"
echo "   - Click: Add Credentials"
echo "   - Kind: SSH Username with private key"
echo "   - ID: jenkins-github-ssh"
echo "   - Username: git"
echo "   - Private Key: Enter directly (paste from /var/lib/jenkins/.ssh/id_rsa)"
echo "   - Description: GitHub SSH Key for DStreamBolt Repository"
echo ""
echo "5. Test GitHub access in Jenkins:"
echo "   - Create a new Pipeline job"
echo "   - SCM: Git"
echo "   - Repository URL: git@github.com:dstreambolt/dstream_cloud.git"
echo "   - Credentials: jenkins-github-ssh"
echo "   - Branch: */main or */release/v1.0.0"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📖 For automated credential setup via CLI, run:"
echo "   $0 --add-credential-via-cli"
echo ""
echo "📖 To view existing Jenkins jobs, go to:"
echo "   http://$DEVOPS_IP/jenkins"
echo ""

