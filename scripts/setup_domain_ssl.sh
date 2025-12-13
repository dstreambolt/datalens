#!/bin/bash

###############################################################################
# DStreamBolt Domain SSL Certificate Setup
# Requests and configures ACM certificate for dstreambolt.click
###############################################################################

set -e

DOMAIN="dstreambolt.click"
WILDCARD_DOMAIN="*.dstreambolt.click"
REGION="ap-south-1"
ALB_ARN="arn:aws:elasticloadbalancing:ap-south-1:771239567939:loadbalancer/app/dstreambolt-alb/755e9c234508892f"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     DStreamBolt SSL Certificate Setup                       ║"
echo "║     Domain: dstreambolt.click                                ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 Current Situation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "❌ Current certificate: *.elb.amazonaws.com (wrong domain)"
echo "✅ DNS points to ALB correctly"
echo "❌ HTTPS fails with SSL handshake error"
echo ""
echo "The issue: The ALB has a certificate for *.elb.amazonaws.com,"
echo "but the domain dstreambolt.click needs its own certificate."
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📝 Step 1: Request ACM Certificate"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Requesting certificate for:"
echo "  • $DOMAIN"
echo "  • $WILDCARD_DOMAIN"
echo ""

# Check if certificate already exists
EXISTING_CERT=$(aws acm list-certificates \
  --region $REGION \
  --query "CertificateSummaryList[?DomainName=='$DOMAIN'].CertificateArn" \
  --output text 2>/dev/null)

if [ ! -z "$EXISTING_CERT" ]; then
    echo "✅ Certificate already exists: $EXISTING_CERT"
    echo ""

    # Check status
    CERT_STATUS=$(aws acm describe-certificate \
      --certificate-arn $EXISTING_CERT \
      --region $REGION \
      --query 'Certificate.Status' \
      --output text)

    echo "   Status: $CERT_STATUS"

    if [ "$CERT_STATUS" = "ISSUED" ]; then
        echo ""
        echo "✅ Certificate is already ISSUED and ready to use!"
        CERT_ARN=$EXISTING_CERT
    elif [ "$CERT_STATUS" = "PENDING_VALIDATION" ]; then
        echo ""
        echo "⚠️  Certificate is pending DNS validation"
        CERT_ARN=$EXISTING_CERT
    else
        echo ""
        echo "⚠️  Certificate status: $CERT_STATUS"
        CERT_ARN=$EXISTING_CERT
    fi
else
    echo "Requesting new certificate..."

    CERT_ARN=$(aws acm request-certificate \
      --domain-name $DOMAIN \
      --subject-alternative-names $WILDCARD_DOMAIN \
      --validation-method DNS \
      --region $REGION \
      --query 'CertificateArn' \
      --output text)

    if [ $? -eq 0 ]; then
        echo "✅ Certificate requested: $CERT_ARN"
        echo ""
        echo "⏳ Waiting 5 seconds for DNS validation records to be generated..."
        sleep 5
    else
        echo "❌ Failed to request certificate"
        exit 1
    fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Step 2: Get DNS Validation Records"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Get validation records
aws acm describe-certificate \
  --certificate-arn $CERT_ARN \
  --region $REGION \
  --query 'Certificate.DomainValidationOptions[].[DomainName, ResourceRecord.Name, ResourceRecord.Type, ResourceRecord.Value]' \
  --output table

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎯 Step 3: Add DNS CNAME Records"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "You MUST add these CNAME records to your DNS provider (HostAsia):"
echo ""

# Get and format validation records for easy copying
aws acm describe-certificate \
  --certificate-arn $CERT_ARN \
  --region $REGION \
  --query 'Certificate.DomainValidationOptions[]' \
  --output json | python3 -c "
import sys, json
data = json.load(sys.stdin)
for item in data:
    record = item.get('ResourceRecord', {})
    print(f\"Domain: {item['DomainName']}\")
    print(f\"  Name:  {record.get('Name', 'N/A')}\")
    print(f\"  Type:  {record.get('Type', 'N/A')}\")
    print(f\"  Value: {record.get('Value', 'N/A')}\")
    print()
" 2>/dev/null || aws acm describe-certificate \
  --certificate-arn $CERT_ARN \
  --region $REGION \
  --query 'Certificate.DomainValidationOptions[0].ResourceRecord' \
  --output text

echo ""
echo "📝 Instructions for HostAsia DNS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Log in to HostAsia control panel"
echo "2. Go to DNS Management for dstreambolt.click"
echo "3. Add the CNAME record(s) shown above"
echo "4. Wait 5-10 minutes for DNS propagation"
echo "5. AWS will automatically validate and issue the certificate"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⏳ Step 4: Wait for Certificate Validation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Checking current certificate status..."

CERT_STATUS=$(aws acm describe-certificate \
  --certificate-arn $CERT_ARN \
  --region $REGION \
  --query 'Certificate.Status' \
  --output text)

if [ "$CERT_STATUS" = "ISSUED" ]; then
    echo "✅ Certificate is ISSUED!"
    echo ""
    echo "Proceeding to attach to ALB..."
elif [ "$CERT_STATUS" = "PENDING_VALIDATION" ]; then
    echo "⏳ Certificate status: PENDING_VALIDATION"
    echo ""
    echo "Please add the DNS CNAME records shown above."
    echo "Once added, run this command to wait for validation:"
    echo ""
    echo "  aws acm wait certificate-validated \\"
    echo "    --certificate-arn $CERT_ARN \\"
    echo "    --region $REGION"
    echo ""
    echo "Or run this script again after adding DNS records."
    echo ""

    # Check if running non-interactively
    if [ -t 0 ]; then
        # Interactive mode
        read -p "Have you added the DNS records? Wait for validation now? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "⏳ Waiting for certificate validation (this may take 5-30 minutes)..."
            aws acm wait certificate-validated \
              --certificate-arn $CERT_ARN \
              --region $REGION && echo "✅ Certificate validated!" || {
                echo "⚠️  Validation timeout or failed. Check DNS records and try again."
                exit 1
            }
        else
            echo ""
            echo "Once DNS records are added, run this script again or use:"
            echo "  ./$(basename $0)"
            exit 0
        fi
    else
        # Non-interactive mode - skip validation wait
        echo "⏳ Non-interactive mode: Skipping validation wait"
        echo ""
        echo "The certificate will be validated automatically once DNS records are added."
        echo "Run this script again later to complete setup:"
        echo "  ./$(basename $0)"
        echo ""
        exit 0
    fi
else
    echo "⚠️  Certificate status: $CERT_STATUS"
    echo "Please check AWS ACM console for details."
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 Step 5: Update ALB HTTPS Listener"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Get HTTPS listener ARN
LISTENER_ARN=$(aws elbv2 describe-listeners \
  --load-balancer-arn $ALB_ARN \
  --region $REGION \
  --query 'Listeners[?Port==`443`].ListenerArn' \
  --output text)

if [ -z "$LISTENER_ARN" ]; then
    echo "❌ Could not find HTTPS listener on ALB"
    exit 1
fi

echo "Updating HTTPS listener with new certificate..."
echo "  Listener: $LISTENER_ARN"
echo "  Certificate: $CERT_ARN"
echo ""

aws elbv2 modify-listener \
  --listener-arn $LISTENER_ARN \
  --certificates CertificateArn=$CERT_ARN \
  --region $REGION > /dev/null

if [ $? -eq 0 ]; then
    echo "✅ ALB HTTPS listener updated successfully!"
else
    echo "❌ Failed to update ALB listener"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Setup Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🎉 Your domain is now configured with SSL!"
echo ""
echo "Test your site:"
echo "  curl -I https://dstreambolt.click"
echo ""
echo "Access your services:"
echo "  https://dstreambolt.click/"
echo "  https://jenkins.dstreambolt.click/"
echo "  https://grafana.dstreambolt.click/"
echo "  https://spark.dstreambolt.click/"
echo "  https://kafkamgr.dstreambolt.click/"
echo ""
echo "Certificate details:"
echo "  ARN: $CERT_ARN"
echo "  Domain: $DOMAIN"
echo "  Wildcard: $WILDCARD_DOMAIN"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

