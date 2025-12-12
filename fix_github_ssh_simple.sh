#!/bin/bash
# Copy-paste these commands on the DevOps node: ubuntu@ip-10-0-1-61
# This will fix the GitHub SSH authentication issue

echo "Step 1: Generate SSH key..."
ssh-keygen -t ed25519 -C "jenkins@dstreambolt.com" -f ~/.ssh/jenkins_github_key -N ""

echo ""
echo "Step 2: Show public key (copy this to GitHub)..."
cat ~/.ssh/jenkins_github_key.pub
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 ACTION REQUIRED:"
echo "1. Copy the key above"
echo "2. Go to: https://github.com/dstreambolt/dstream_cloud/settings/keys"
echo "3. Click 'Add deploy key'"
echo "4. Title: Jenkins DevOps Node (10.0.1.61)"
echo "5. Paste key and click 'Add key'"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
read -p "Press Enter after adding key to GitHub..."

echo ""
echo "Step 3: Configure SSH..."
cat >> ~/.ssh/config << 'EOF'

Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/jenkins_github_key
    StrictHostKeyChecking no
EOF

chmod 600 ~/.ssh/config
chmod 600 ~/.ssh/jenkins_github_key
chmod 644 ~/.ssh/jenkins_github_key.pub

echo ""
echo "Step 4: Test connection..."
ssh -T git@github.com

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ If you see 'successfully authenticated', you're done!"
echo ""
echo "Next: Add private key to Jenkins credentials"
echo "Run: cat ~/.ssh/jenkins_github_key"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

