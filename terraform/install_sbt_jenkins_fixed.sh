#!/bin/bash
# Install SBT on Jenkins/DevOps node - Fixed version
# Run this on the DevOps instance

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

echo "🧹 Cleaning old SBT repository files..."
sudo rm -f /etc/apt/sources.list.d/sbt.list
sudo rm -f /etc/apt/sources.list.d/sbt_old.list

echo "📦 Installing dependencies..."
sudo apt-get update -qq
sudo apt-get install -y apt-transport-https curl gnupg

echo "🔑 Adding SBT GPG key..."
curl -fsSL https://www.scala-sbt.org/release/pubkey.asc | sudo apt-key add -

echo "📝 Adding SBT repository..."
echo "deb https://repo.scala-sbt.org/scalasbt/debian all main" | sudo tee /etc/apt/sources.list.d/sbt.list

echo "📦 Updating package list..."
sudo apt-get update -qq

echo "📥 Installing SBT..."
sudo apt-get install -y sbt

# Run sbt once to download dependencies
echo "⏳ Initializing SBT (first run downloads dependencies)..."
sbt about

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ SBT Installation Complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
sbt --version
echo ""
echo "✅ Jenkins can now build Scala Spark jobs!"
echo ""

