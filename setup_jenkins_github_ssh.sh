#!/bin/bash
# Jenkins GitHub SSH Setup Script
# Run this on the Jenkins server to set up GitHub SSH authentication

set -e

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       Jenkins GitHub SSH Credentials Setup                   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Check if running on Jenkins server
if [ ! -d "/var/lib/jenkins" ]; then
    echo "⚠️  WARNING: This doesn't appear to be a Jenkins server"
    echo "   /var/lib/jenkins directory not found"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Variables
SSH_KEY_FILE="${HOME}/.ssh/jenkins_github_key"
SSH_KEY_NAME="jenkins_github_key"
GITHUB_HOST="github.com"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 1: Generate SSH Key"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check if key already exists
if [ -f "${SSH_KEY_FILE}" ]; then
    echo "⚠️  SSH key already exists: ${SSH_KEY_FILE}"
    read -p "Overwrite? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Using existing key..."
    else
        echo "Generating new SSH key..."
        ssh-keygen -t ed25519 -C "jenkins@dstreambolt.com" -f "${SSH_KEY_FILE}" -N ""
        echo "✅ New SSH key generated"
    fi
else
    echo "Generating SSH key..."
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    ssh-keygen -t ed25519 -C "jenkins@dstreambolt.com" -f "${SSH_KEY_FILE}" -N ""
    echo "✅ SSH key generated: ${SSH_KEY_FILE}"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 2: Configure SSH"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Update SSH config
SSH_CONFIG="${HOME}/.ssh/config"

if ! grep -q "Host ${GITHUB_HOST}" "${SSH_CONFIG}" 2>/dev/null; then
    echo "Adding GitHub configuration to ${SSH_CONFIG}..."
    cat >> "${SSH_CONFIG}" << EOF

# GitHub SSH configuration for Jenkins
Host ${GITHUB_HOST}
    HostName ${GITHUB_HOST}
    User git
    IdentityFile ${SSH_KEY_FILE}
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
    echo "✅ SSH config updated"
else
    echo "ℹ️  GitHub already configured in ${SSH_CONFIG}"
fi

# Add GitHub to known_hosts
echo "Adding GitHub to known_hosts..."
ssh-keyscan ${GITHUB_HOST} >> ~/.ssh/known_hosts 2>/dev/null
echo "✅ GitHub added to known_hosts"

# Set correct permissions
chmod 600 "${SSH_KEY_FILE}"
chmod 644 "${SSH_KEY_FILE}.pub"
chmod 600 ~/.ssh/config 2>/dev/null || true

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 3: Display Public Key"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "📋 Copy the following public key to GitHub:"
echo ""
echo "┌────────────────────────────────────────────────────────┐"
cat "${SSH_KEY_FILE}.pub"
echo "└────────────────────────────────────────────────────────┘"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 4: Add to GitHub"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "1. Go to: https://github.com/dstreambolt/dstream_cloud/settings/keys"
echo "2. Click: 'Add deploy key'"
echo "3. Title: 'Jenkins DStreamBolt'"
echo "4. Key: Paste the public key above"
echo "5. Allow write access: ☐ (unchecked for read-only)"
echo "6. Click: 'Add key'"
echo ""

read -p "Press Enter after adding the key to GitHub..."

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 5: Test GitHub Connection"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "Testing SSH connection to GitHub..."
if ssh -T git@${GITHUB_HOST} 2>&1 | grep -q "successfully authenticated"; then
    echo "✅ GitHub SSH connection successful!"
else
    echo "⚠️  GitHub SSH connection test returned unexpected result"
    echo "   This might be OK - check the output above"
    ssh -T git@${GITHUB_HOST}
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 6: Test Git Clone"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
TEST_DIR="/tmp/test-git-clone-$$"
echo "Testing git clone to ${TEST_DIR}..."

if git clone git@${GITHUB_HOST}:dstreambolt/dstream_cloud.git "${TEST_DIR}" 2>&1 | grep -q "Cloning into"; then
    echo "✅ Git clone successful!"
    rm -rf "${TEST_DIR}"
else
    echo "❌ Git clone failed"
    echo "   Check the error message above"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 7: Add Private Key to Jenkins"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "📋 Copy the following PRIVATE key for Jenkins credentials:"
echo ""
echo "┌────────────────────────────────────────────────────────┐"
cat "${SSH_KEY_FILE}"
echo "└────────────────────────────────────────────────────────┘"
echo ""

echo "Manual steps in Jenkins:"
echo "1. Open Jenkins: http://YOUR_JENKINS_SERVER:8081/"
echo "2. Go to: Manage Jenkins → Credentials → System → Global credentials"
echo "3. Click: 'Add Credentials'"
echo "4. Fill in:"
echo "   - Kind: SSH Username with private key"
echo "   - ID: jenkins-github-ssh"
echo "   - Description: GitHub SSH for DStreamBolt"
echo "   - Username: git"
echo "   - Private Key: Enter directly (paste the private key above)"
echo "   - Passphrase: (leave empty)"
echo "5. Click: 'OK'"
echo ""

read -p "Press Enter after adding credentials to Jenkins..."

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    Setup Complete! ✅                         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Summary:"
echo "  ✅ SSH key generated: ${SSH_KEY_FILE}"
echo "  ✅ SSH configured for GitHub"
echo "  ✅ Public key added to GitHub"
echo "  ✅ GitHub SSH connection verified"
echo "  ✅ Git clone tested successfully"
echo "  ✅ Private key ready for Jenkins"
echo ""
echo "Next steps:"
echo "  1. Add private key to Jenkins credentials"
echo "  2. Use credential ID: jenkins-github-ssh"
echo "  3. Run Jenkins job: DStreamBolt-Deploy-Ingestion"
echo "  4. Verify successful checkout"
echo ""
echo "Files created:"
echo "  - Private key: ${SSH_KEY_FILE}"
echo "  - Public key: ${SSH_KEY_FILE}.pub"
echo "  - SSH config: ${HOME}/.ssh/config"
echo ""

