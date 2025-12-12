#!/bin/bash
# Fix Jenkins GitHub SSH Authentication
# Run this on the Jenkins server (DevOps node)

set -e

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       Jenkins GitHub SSH Fix - Automated Setup              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
GITHUB_HOST="github.com"
GITHUB_REPO="git@github.com:dstreambolt/dstream_cloud.git"
SSH_KEY_FILE="${HOME}/.ssh/jenkins_github_key"
JENKINS_USER="${USER}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 1: Check Current User"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Running as: $JENKINS_USER"
echo "Home directory: $HOME"

if [ "$JENKINS_USER" != "ubuntu" ] && [ "$JENKINS_USER" != "jenkins" ]; then
    echo -e "${YELLOW}⚠️  WARNING: Not running as ubuntu or jenkins user${NC}"
    echo "   Jenkins typically runs as 'jenkins' user"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 2: Check if SSH Key Exists"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -f "${SSH_KEY_FILE}" ]; then
    echo -e "${GREEN}✅ SSH key already exists: ${SSH_KEY_FILE}${NC}"

    # Test if key is valid
    if ssh-keygen -l -f "${SSH_KEY_FILE}" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ SSH key is valid${NC}"
    else
        echo -e "${RED}❌ SSH key is corrupt or invalid${NC}"
        read -p "Regenerate key? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Generating new SSH key..."
            ssh-keygen -t ed25519 -C "jenkins@dstreambolt.com" -f "${SSH_KEY_FILE}" -N ""
            echo -e "${GREEN}✅ New SSH key generated${NC}"
        else
            exit 1
        fi
    fi
else
    echo -e "${YELLOW}⚠️  SSH key not found${NC}"
    echo "Generating new SSH key..."
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    ssh-keygen -t ed25519 -C "jenkins@dstreambolt.com" -f "${SSH_KEY_FILE}" -N ""
    echo -e "${GREEN}✅ SSH key generated: ${SSH_KEY_FILE}${NC}"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 3: Configure SSH for GitHub"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

SSH_CONFIG="${HOME}/.ssh/config"

# Backup existing config
if [ -f "${SSH_CONFIG}" ]; then
    cp "${SSH_CONFIG}" "${SSH_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
    echo "✅ Backed up existing SSH config"
fi

# Remove old GitHub config if exists
if grep -q "Host ${GITHUB_HOST}" "${SSH_CONFIG}" 2>/dev/null; then
    echo "Removing old GitHub configuration..."
    sed -i.bak "/Host ${GITHUB_HOST}/,/^$/d" "${SSH_CONFIG}"
fi

# Add new GitHub configuration
cat >> "${SSH_CONFIG}" << EOF

# GitHub SSH configuration for Jenkins
Host ${GITHUB_HOST}
    HostName ${GITHUB_HOST}
    User git
    IdentityFile ${SSH_KEY_FILE}
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
EOF

echo -e "${GREEN}✅ SSH config updated${NC}"

# Set permissions
chmod 600 "${SSH_KEY_FILE}"
chmod 644 "${SSH_KEY_FILE}.pub"
chmod 600 "${SSH_CONFIG}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 4: Add GitHub to Known Hosts"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Remove old GitHub entries
ssh-keygen -R ${GITHUB_HOST} 2>/dev/null || true

# Add GitHub to known_hosts
ssh-keyscan ${GITHUB_HOST} >> ~/.ssh/known_hosts 2>/dev/null
echo -e "${GREEN}✅ GitHub added to known_hosts${NC}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 5: Display Public Key"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo -e "${YELLOW}📋 IMPORTANT: Add this public key to GitHub${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
cat "${SSH_KEY_FILE}.pub"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Steps to add to GitHub:"
echo "1. Copy the key above"
echo "2. Go to: https://github.com/dstreambolt/dstream_cloud/settings/keys"
echo "3. Click: 'Add deploy key'"
echo "4. Title: 'Jenkins DStreamBolt DevOps'"
echo "5. Key: Paste the public key"
echo "6. Allow write access: ☐ (optional, not needed for read-only)"
echo "7. Click: 'Add key'"
echo ""

read -p "Press Enter after adding the key to GitHub..."

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 6: Test GitHub SSH Connection"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "Testing SSH connection to GitHub..."
if ssh -T git@${GITHUB_HOST} 2>&1 | grep -q "successfully authenticated"; then
    echo -e "${GREEN}✅ GitHub SSH connection successful!${NC}"
else
    echo -e "${RED}❌ GitHub SSH connection failed${NC}"
    echo ""
    echo "Running verbose test..."
    ssh -vT git@${GITHUB_HOST}
    echo ""
    echo -e "${RED}Please check:${NC}"
    echo "1. Public key added to GitHub deploy keys"
    echo "2. GitHub repository URL is correct"
    echo "3. Network connectivity to GitHub"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 7: Test Git Clone"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

TEST_DIR="/tmp/test-git-clone-$$"
echo ""
echo "Testing git clone to ${TEST_DIR}..."

if git clone ${GITHUB_REPO} "${TEST_DIR}" 2>&1; then
    echo -e "${GREEN}✅ Git clone successful!${NC}"
    rm -rf "${TEST_DIR}"
else
    echo -e "${RED}❌ Git clone failed${NC}"
    echo ""
    echo "Trying with verbose output..."
    GIT_SSH_COMMAND="ssh -v" git clone ${GITHUB_REPO} "${TEST_DIR}"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 8: Check Jenkins User"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "Checking if Jenkins service exists..."
if systemctl list-units --type=service | grep -q jenkins; then
    echo -e "${GREEN}✅ Jenkins service found${NC}"

    # Get Jenkins user
    JENKINS_SERVICE_USER=$(ps aux | grep jenkins.war | grep -v grep | awk '{print $1}' | head -1)
    if [ ! -z "$JENKINS_SERVICE_USER" ]; then
        echo "Jenkins is running as user: ${JENKINS_SERVICE_USER}"

        if [ "$JENKINS_SERVICE_USER" != "$JENKINS_USER" ]; then
            echo -e "${YELLOW}⚠️  WARNING: Jenkins runs as '${JENKINS_SERVICE_USER}' but you're configuring for '${JENKINS_USER}'${NC}"
            echo ""
            echo "You need to run this script as the Jenkins user:"
            echo "  sudo -u ${JENKINS_SERVICE_USER} bash $0"
            echo ""
            read -p "Do you want to copy SSH keys to ${JENKINS_SERVICE_USER}? (y/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo "Copying SSH keys to ${JENKINS_SERVICE_USER}..."
                sudo mkdir -p /var/lib/jenkins/.ssh
                sudo cp "${SSH_KEY_FILE}" /var/lib/jenkins/.ssh/
                sudo cp "${SSH_KEY_FILE}.pub" /var/lib/jenkins/.ssh/
                sudo cp "${SSH_CONFIG}" /var/lib/jenkins/.ssh/config
                sudo chown -R ${JENKINS_SERVICE_USER}:${JENKINS_SERVICE_USER} /var/lib/jenkins/.ssh
                sudo chmod 700 /var/lib/jenkins/.ssh
                sudo chmod 600 /var/lib/jenkins/.ssh/jenkins_github_key
                sudo chmod 644 /var/lib/jenkins/.ssh/jenkins_github_key.pub
                sudo chmod 600 /var/lib/jenkins/.ssh/config
                echo -e "${GREEN}✅ SSH keys copied to Jenkins user${NC}"

                # Test as Jenkins user
                echo "Testing SSH as Jenkins user..."
                if sudo -u ${JENKINS_SERVICE_USER} ssh -T git@${GITHUB_HOST} 2>&1 | grep -q "successfully authenticated"; then
                    echo -e "${GREEN}✅ GitHub SSH works for Jenkins user!${NC}"
                else
                    echo -e "${RED}❌ GitHub SSH failed for Jenkins user${NC}"
                fi
            fi
        fi
    fi
else
    echo -e "${YELLOW}⚠️  Jenkins service not found (might be containerized or not running)${NC}"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 9: Jenkins Credentials Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo -e "${YELLOW}📋 Manual step required in Jenkins UI${NC}"
echo ""
echo "1. Open Jenkins: http://YOUR_JENKINS_IP:8081/"
echo "2. Go to: Manage Jenkins → Credentials → System → Global credentials"
echo "3. Click: 'Add Credentials'"
echo "4. Fill in:"
echo "   - Kind: SSH Username with private key"
echo "   - ID: jenkins-github-ssh"
echo "   - Description: GitHub SSH for DStreamBolt"
echo "   - Username: git"
echo "   - Private Key: Enter directly (see below)"
echo "   - Passphrase: (leave empty)"
echo "5. Click: 'OK'"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PRIVATE KEY (copy everything between the lines):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cat "${SSH_KEY_FILE}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

read -p "Press Enter after adding credentials to Jenkins..."

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 10: Verify Job Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo -e "${YELLOW}📋 Update Jenkins job configuration:${NC}"
echo ""
echo "1. Open Jenkins job: DStreamBolt-Deploy-Ingestion"
echo "2. Click: 'Configure'"
echo "3. Check 'Pipeline' section:"
echo "   - Definition: Pipeline script from SCM"
echo "   - SCM: Git"
echo "   - Repository URL: git@github.com:dstreambolt/dstream_cloud.git"
echo "   - Credentials: jenkins-github-ssh"
echo "   - Branch: */main"
echo "   - Script Path: jenkins/deploy-ingestion.jenkinsfile"
echo "4. Click: 'Save'"
echo ""
echo "OR if using 'Pipeline script':"
echo "   - Make sure the pipeline code uses: git@github.com:dstreambolt/dstream_cloud.git"
echo "   - And uses credentialsId: 'jenkins-github-ssh'"
echo ""

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    Setup Complete! ✅                         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Summary:"
echo "  ✅ SSH key generated/verified: ${SSH_KEY_FILE}"
echo "  ✅ SSH configured for GitHub"
echo "  ✅ GitHub SSH connection tested"
echo "  ✅ Git clone tested"
echo "  ✅ Keys copied to Jenkins user (if applicable)"
echo ""
echo "Next steps:"
echo "  1. ✅ Add private key to Jenkins credentials (ID: jenkins-github-ssh)"
echo "  2. ✅ Update Jenkins job to use SSH repository URL"
echo "  3. ✅ Run Jenkins job: DStreamBolt-Deploy-Ingestion"
echo ""
echo "Test command:"
echo "  ssh -T git@${GITHUB_HOST}"
echo ""
echo "Expected output:"
echo "  Hi dstreambolt/dstream_cloud! You've successfully authenticated..."
echo ""

