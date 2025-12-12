#!/bin/bash
# DStreamBolt - One-Command Deployment Script

set -e

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║       🚀 DStreamBolt Infrastructure Deployment                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check prerequisites
echo "📋 Checking prerequisites..."

if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform not found. Please install Terraform >= 1.5.0"
    exit 1
fi
echo "✅ Terraform found: $(terraform version | head -1)"

if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI not found. Please install AWS CLI"
    exit 1
fi
echo "✅ AWS CLI found"

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS credentials not configured. Run: aws configure"
    exit 1
fi
echo "✅ AWS credentials configured"

echo ""
echo "📝 Configuration:"
echo "  Project: dstreambolt"
echo "  Region: ap-south-1"
echo "  SSH Key: dstreambolt-access-key"
echo ""

# Confirm deployment
read -p "🚀 Deploy DStreamBolt infrastructure? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Deployment cancelled."
    exit 0
fi

echo ""
echo "🔧 Initializing Terraform..."
terraform init

echo ""
echo "📊 Planning deployment..."
terraform plan -out=tfplan

echo ""
read -p "Review the plan above. Continue with deployment? (yes/no): " apply_confirm
if [ "$apply_confirm" != "yes" ]; then
    echo "Deployment cancelled."
    rm tfplan
    exit 0
fi

echo ""
echo "🚀 Deploying infrastructure (this will take 15-20 minutes)..."
terraform apply tfplan

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              ✅ DEPLOYMENT COMPLETE!                          ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Get outputs
ALB_DNS=$(terraform output -json | jq -r '.alb_url.value' | sed 's/https:\/\///')

echo "🎉 Your DStreamBolt platform is ready!"
echo ""
echo "📊 ACCESS YOUR SERVICES:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🏠 Landing Page:  https://$ALB_DNS/"
echo "  📥 Ingestion API: https://$ALB_DNS/ingest"
echo "  ❤️  Health Check:  https://$ALB_DNS/health"
echo "  🔧 Jenkins:       https://$ALB_DNS/jenkins"
echo "  📊 Grafana:       https://$ALB_DNS/grafana"
echo "  🎛️  Kafka Manager: https://$ALB_DNS/kafkamgr"
echo "  ⚡ Spark UI:      https://$ALB_DNS/spark"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 CREDENTIALS:"
echo "  Grafana: admin / DStreamBolt2025!"
echo "  MySQL:   root / (check terraform.tfvars)"
echo "  Jenkins: ssh to devops and check /var/lib/jenkins/secrets/initialAdminPassword"
echo ""
echo "🧪 TEST INGESTION:"
echo "  echo '[{\"log\":\"test\"}]' | gzip > test.gz"
echo "  curl -X POST https://$ALB_DNS/ingest -H 'Content-Type: application/gzip' --data-binary @test.gz"
echo ""
echo "💰 Monthly Cost: \$55-100 (depending on free tier)"
echo ""
echo "📚 Documentation: See DEPLOYMENT_COMPLETE.md for details"
echo ""
echo "✨ Enjoy your production-ready DStreamBolt platform!"

