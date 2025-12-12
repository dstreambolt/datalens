#!/bin/bash
# Setup Jenkins Pipeline Job from Groovy Jenkinsfile

set -e

JENKINS_HOST="${1:-13.232.132.240}"
JENKINS_PORT="${2:-8080}"
JENKINS_USER="${3:-admin}"
JENKINS_PASS="${4:-55ed29c51ed347219370f34dd4038a6a}"
JOB_NAME="DStreamBolt-Continuous-Log-Sender"
JENKINSFILE="continuous-log-sender.jenkinsfile"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Setting up Jenkins Pipeline Job: ${JOB_NAME}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Jenkins URL: http://${JENKINS_HOST}:${JENKINS_PORT}"
echo "Jenkinsfile: ${JENKINSFILE}"
echo ""

# Check if Jenkinsfile exists
if [ ! -f "${JENKINSFILE}" ]; then
    echo "❌ Jenkinsfile not found: ${JENKINSFILE}"
    exit 1
fi

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

# Read Jenkinsfile content
JENKINSFILE_CONTENT=$(cat "${JENKINSFILE}")

# Create XML config with pipeline script from SCM
cat > /tmp/pipeline-job-config.xml << 'XML_EOF'
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <description>Continuously generates and sends log data to the ingestion endpoint. Runs until manually stopped.</description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <org.jenkinsci.plugins.workflow.job.properties.DisableConcurrentBuildsJobProperty/>
    <org.jenkinsci.plugins.workflow.job.properties.PipelineTriggersJobProperty>
      <triggers/>
    </org.jenkinsci.plugins.workflow.job.properties.PipelineTriggersJobProperty>
  </properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps">
    <script>JENKINSFILE_PLACEHOLDER</script>
    <sandbox>true</sandbox>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
XML_EOF

# Escape the Jenkinsfile content for XML
ESCAPED_JENKINSFILE=$(echo "$JENKINSFILE_CONTENT" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')

# Replace placeholder with actual Jenkinsfile content
sed -i.bak "s|JENKINSFILE_PLACEHOLDER|${ESCAPED_JENKINSFILE}|" /tmp/pipeline-job-config.xml
rm -f /tmp/pipeline-job-config.xml.bak

echo "2️⃣  Checking if job exists..."
if curl -s -f -u "${JENKINS_USER}:${JENKINS_PASS}" \
    "http://${JENKINS_HOST}:${JENKINS_PORT}/job/${JOB_NAME}/api/json" > /dev/null 2>&1; then
    echo "⚠️  Job '${JOB_NAME}' already exists"
    echo "   Updating existing job..."

    # Update existing job
    curl -X POST \
        -u "${JENKINS_USER}:${JENKINS_PASS}" \
        -H "Content-Type: application/xml" \
        --data-binary @/tmp/pipeline-job-config.xml \
        "http://${JENKINS_HOST}:${JENKINS_PORT}/job/${JOB_NAME}/config.xml"

    echo "✅ Job updated"
else
    echo "📝 Creating new job..."

    # Create new job
    curl -X POST \
        -u "${JENKINS_USER}:${JENKINS_PASS}" \
        -H "Content-Type: application/xml" \
        --data-binary @/tmp/pipeline-job-config.xml \
        "http://${JENKINS_HOST}:${JENKINS_PORT}/createItem?name=${JOB_NAME}"

    echo "✅ Job created"
fi

# Cleanup
rm -f /tmp/pipeline-job-config.xml

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Jenkins Pipeline Job Setup Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 Job Details:"
echo "  Name: ${JOB_NAME}"
echo "  Type: Pipeline (Groovy)"
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
echo "7. To stop: Click the red 'X' button or 'Abort' button"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

