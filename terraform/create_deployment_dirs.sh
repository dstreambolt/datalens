#!/bin/bash
# Quick fix to create deployment directories on existing Spark Master
# Run this on the Spark Master: ssh ubuntu@10.0.1.199 'bash -s' < create_deployment_dirs.sh

set -e

echo "=========================================="
echo "🔧 Creating Deployment Directories"
echo "=========================================="

# Create deployment directories for Jenkins
echo "📁 Creating /opt/dstreambolt/computations..."
sudo mkdir -p /opt/dstreambolt/computations
sudo mkdir -p /opt/dstreambolt/computations-backups

# Set proper ownership (ubuntu user for Jenkins SSH deployments)
echo "👤 Setting ownership to ubuntu:ubuntu..."
sudo chown -R ubuntu:ubuntu /opt/dstreambolt
sudo chmod -R 755 /opt/dstreambolt

# Create Spark logs directory if not exists
echo "📁 Creating /opt/spark/logs..."
sudo mkdir -p /opt/spark/logs
sudo chown -R ubuntu:ubuntu /opt/spark/logs
sudo chmod -R 755 /opt/spark/logs

# Verify
echo ""
echo "✅ Directories created successfully!"
echo ""
echo "Verification:"
ls -la /opt/dstreambolt/
echo ""
ls -la /opt/spark/logs/
echo ""
echo "Ready for Jenkins deployments!"

