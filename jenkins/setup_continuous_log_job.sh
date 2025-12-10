#!/bin/bash
# Setup Jenkins Job for Continuous Log Generator

set -e

JENKINS_HOST="${1:-13.232.132.240}"
JENKINS_PORT="${2:-8081}"
JENKINS_USER="${3:-admin}"
JENKINS_PASS="${4:-admin}"  # Change this to actual password
JOB_NAME="DStreamBolt-Continuous-Log-Generator"

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
        --data-binary @job-continuous-log-generator.xml \
        "http://${JENKINS_HOST}:${JENKINS_PORT}/job/${JOB_NAME}/config.xml"

    echo "✅ Job updated"
else
    echo "📝 Creating new job..."

    # Create new job
    curl -X POST \
        -u "${JENKINS_USER}:${JENKINS_PASS}" \
        -H "Content-Type: application/xml" \
        --data-binary @job-continuous-log-generator.xml \
        "http://${JENKINS_HOST}:${JENKINS_PORT}/createItem?name=${JOB_NAME}"

    echo "✅ Job created"
fi
echo ""

# Reload Jenkins configuration
echo "3️⃣  Reloading Jenkins configuration..."
curl -X POST \
    -u "${JENKINS_USER}:${JENKINS_PASS}" \
    "http://${JENKINS_HOST}:${JENKINS_PORT}/reload" || echo "⚠️  Could not reload (might not be needed)"
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
echo "1. Open Jenkins in your browser:"
echo "   http://${JENKINS_HOST}:${JENKINS_PORT}"
echo ""
echo "2. Navigate to: ${JOB_NAME}"
echo ""
echo "3. Click 'Build with Parameters'"
echo ""
echo "4. Configure parameters (or use defaults):"
echo "   • INGESTION_URL: Target ingestion endpoint"
echo "   • INTERVAL: Seconds between batches (default: 30)"
echo "   • BATCH_SIZE: Logs per batch (default: 1000)"
echo "   • VERIFY_SSL: Enable SSL verification (default: false)"
echo ""
echo "5. Click 'Build'"
echo ""
echo "6. The job will run continuously, sending logs every 30 seconds"
echo ""
echo "7. To stop the job:"
echo "   • Go to the running build"
echo "   • Click the red 'X' button to abort"
echo ""
echo "📈 What happens:"
echo "   • Generates realistic access logs"
echo "   • Compresses them (gzip)"
echo "   • Sends to ingestion endpoint"
echo "   • Repeats every ${INTERVAL:-30} seconds"
echo "   • Shows statistics in console output"
echo ""
echo "🔍 Monitor the pipeline:"
echo "   • Check Kafka: Messages appearing in dstreambolt-logs topic"
echo "   • Check Spark: Processing metrics in Spark UI"
echo "   • Check Grafana: Data appearing in dashboards"
echo "   • Check MySQL: Records in status_summary and endpoint_summary"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

