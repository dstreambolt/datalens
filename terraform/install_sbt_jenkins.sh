#!/bin/bash
# Install SBT on Jenkins/DevOps node
# Run this on the DevOps instance: ssh ubuntu@13.232.132.240

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 Installing SBT on Jenkins Node"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if already installed
if command -v sbt &> /dev/null; then
    echo "✅ SBT is already installed:"
    sbt --version
    exit 0
fi

echo "📦 Installing dependencies..."
sudo apt-get update -qq
sudo apt-get install -y apt-transport-https curl gnupg

echo "🔑 Adding GPG key..."
curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x2EE0EA64E40A89B84B2DF73499E82A75642AC823" | sudo apt-key add -

echo "📝 Adding SBT repository..."
echo "deb https://repo.scala-sbt.org/scalasbt/debian all main" | sudo tee /etc/apt/sources.list.d/sbt.list
echo "deb https://repo.scala-sbt.org/scalasbt/debian /" | sudo tee /etc/apt/sources.list.d/sbt_old.list


echo "📦 Updating package list..."
sudo apt-get update -qq

echo "📥 Installing SBT..."
sudo apt-get install -y sbt

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ SBT Installation Complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
sbt --version
echo ""
echo "✅ Jenkins can now build Scala Spark jobs!"
echo ""

