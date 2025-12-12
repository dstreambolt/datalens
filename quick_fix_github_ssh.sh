#!/bin/bash
# Quick fix for GitHub SSH authentication on DevOps node
# Run this on the Jenkins/DevOps server

set -e

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       GitHub SSH Key Setup - Quick Fix                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Check if running as correct user
echo "Running as: $(whoami)"
echo "Home directory: $HOME"
echo ""

# Generate SSH key if it doesn't exist
SSH_KEY="$HOME/.ssh/jenkins_github_key"

if [ ! -f "$SSH_KEY" ]; then
    echo "🔑 Generating new SSH key..."
    ssh-keygen -t ed25519 -C "jenkins@dstreambolt.com" -f "$SSH_KEY" -N ""
    echo "✅ SSH key generated"
else
    echo "✅ SSH key already exists: $SSH_KEY"
fi

# Display public key
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 COPY THIS PUBLIC KEY TO GITHUB"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
cat "${SSH_KEY}.pub"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Steps to add to GitHub:"
echo "1. Go to: https://github.com/dstreambolt/dstream_cloud/settings/keys"
echo "2. Click: 'Add deploy key'"
echo "3. Title: Jenkins DevOps Node"
echo "4. Key: Paste the public key above"
echo "5. Click: 'Add key'"
echo ""
read -p "Press Enter after adding the key to GitHub..."

# Configure SSH for GitHub
echo ""
echo "🔧 Configuring SSH for GitHub..."

SSH_CONFIG="$HOME/.ssh/config"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# Remove old GitHub config if exists
if [ -f "$SSH_CONFIG" ]; then
    sed -i.bak '/Host github.com/,/^$/d' "$SSH_CONFIG" 2>/dev/null || true
fi

# Add GitHub configuration
cat >> "$SSH_CONFIG" << EOF

# GitHub SSH configuration for Jenkins
Host github.com
    HostName github.com
    User git
    IdentityFile $SSH_KEY
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF

chmod 600 "$SSH_CONFIG"
chmod 600 "$SSH_KEY"
chmod 644 "${SSH_KEY}.pub"

echo "✅ SSH configured"

# Test connection
echo ""
echo "🔍 Testing GitHub SSH connection..."
if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    echo "✅ GitHub SSH connection successful!"
else
    echo ""
    echo "Testing with verbose output..."
    ssh -T git@github.com
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Setup Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next: Add private key to Jenkins credentials"
echo ""
echo "Private key location: $SSH_KEY"
echo ""
echo "To view private key for Jenkins:"
echo "  cat $SSH_KEY"
echo ""

