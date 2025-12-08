#!/bin/bash
# Setup the pre-built JAR deployment job in Jenkins

set -e

JENKINS_URL="${JENKINS_URL:-http://13.232.132.240:8081}"
JENKINS_USER="${JENKINS_USER:-admin}"
JENKINS_TOKEN="${JENKINS_TOKEN}"
JOB_NAME="deploy-prebuilt-scala-spark"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 Setting up Jenkins Job: $JOB_NAME"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ -z "$JENKINS_TOKEN" ]; then
    echo "⚠️  JENKINS_TOKEN not set!"
    echo ""
    echo "Get your token:"
    echo "  $JENKINS_URL/user/$JENKINS_USER/configure"
    echo ""
    echo "Then run:"
    echo "  export JENKINS_TOKEN='your-token'"
    echo "  ./setup_prebuilt_job.sh"
    exit 1
fi

echo "Checking if job exists..."
JOB_EXISTS=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "$JENKINS_USER:$JENKINS_TOKEN" \
    "$JENKINS_URL/job/$JOB_NAME/config.xml")

if [ "$JOB_EXISTS" = "200" ]; then
    echo "Updating existing job..."
    curl -s -X POST \
        -u "$JENKINS_USER:$JENKINS_TOKEN" \
        -H "Content-Type: application/xml" \
        --data-binary @job-deploy-prebuilt-scala.xml \
        "$JENKINS_URL/job/$JOB_NAME/config.xml"
    echo "✅ Job updated"
else
    echo "Creating new job..."
    curl -s -X POST \
        -u "$JENKINS_USER:$JENKINS_TOKEN" \
        -H "Content-Type: application/xml" \
        --data-binary @job-deploy-prebuilt-scala.xml \
        "$JENKINS_URL/createItem?name=$JOB_NAME"
    echo "✅ Job created"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ SETUP COMPLETE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🎯 Job URL: $JENKINS_URL/job/$JOB_NAME/"
echo ""
echo "📋 Workflow:"
echo "1. Build JAR locally:"
echo "     cd computations && ./build_and_commit.sh"
echo ""
echo "2. Push to Git:"
echo "     git push"
echo ""
echo "3. Run Jenkins job:"
echo "     $JENKINS_URL/job/$JOB_NAME/build"
echo ""

