#!/bin/bash
# Setup Jenkins Job for Continuous Log Sender

set -e

JENKINS_HOST="${1:-13.232.132.240}"
JENKINS_PORT="${2:-8081}"
JENKINS_USER="${3:-admin}"
JENKINS_PASS="${4:-55ed29c51ed347219370f34dd4038a6a}"
JOB_NAME="DStreamBolt-Continuous-Log-Sender"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Setting up Jenkins Job: ${JOB_NAME}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Jenkins URL: http://${JENKINS_HOST}:${JENKINS_PORT}"
echo ""

# Check if Jenkins is accessible
echo "1️⃣  Testing Jenkins connection..."
if ! curl -s -f -u "${JENKINS_USER}:${JENKINS_PASS}" \
    "http://${JENKINS_HOST}:${JENKINS_PORT}/api/json" > /dev/null; then
    echo "❌ Cannot connect to Jenkins"
    echo "   Please check if Jenkins is running and credentials are correct"
    exit 1
fi
echo "✅ Jenkins is accessible"
echo ""

# Check if job already exists
echo "2️⃣  Checking if job exists..."
if curl -s -f -u "${JENKINS_USER}:${JENKINS_PASS}" \
    "http://${JENKINS_HOST}:${JENKINS_PORT}/job/${JOB_NAME}/api/json" > /dev/null 2>&1; then
    echo "⚠️  Job '${JOB_NAME}' already exists"
    echo "   Updating existing job..."

    # Update existing job
    curl -X POST \
        -u "${JENKINS_USER}:${JENKINS_PASS}" \
        -H "Content-Type: application/xml" \
        --data-binary @job-continuous-log-sender.xml \
        "http://${JENKINS_HOST}:${JENKINS_PORT}/job/${JOB_NAME}/config.xml"

    echo "✅ Job updated"
else
    echo "📝 Creating new job..."

    # Create new job
    curl -X POST \
        -u "${JENKINS_USER}:${JENKINS_PASS}" \
        -H "Content-Type: application/xml" \
        --data-binary @job-continuous-log-sender.xml \
        "http://${JENKINS_HOST}:${JENKINS_PORT}/createItem?name=${JOB_NAME}"

    echo "✅ Job created"
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Jenkins Job Setup Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 Job Details:"
echo "  Name: ${JOB_NAME}"
echo "  URL:  http://${JENKINS_HOST}:${JENKINS_PORT}/job/${JOB_NAME}"
echo ""
echo "🎯 How to Use:"
echo ""
echo "1. Open Jenkins: http://${JENKINS_HOST}:${JENKINS_PORT}"
echo ""
echo "2. Navigate to: ${JOB_NAME}"
echo ""
echo "3. Click 'Build with Parameters'"
echo ""
echo "4. Configure parameters:"
echo "   • INGESTION_URL: https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/ingest"
echo "   • INTERVAL: 30 (seconds between batches)"
echo "   • BATCH_SIZE: 1000 (logs per batch)"
echo "   • VERIFY_SSL: false (for self-signed certs)"
echo "   • MAX_BATCHES: 0 (unlimited)"
echo ""
echo "5. Click 'Build'"
echo ""
echo "6. Monitor in Console Output"
echo ""
echo "7. To stop: Click the red 'X' button"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

