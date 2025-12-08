#!/bin/bash
# Setup Jenkins job for Scala Spark Build & Deploy

set -e

JENKINS_URL="${JENKINS_URL:-http://13.232.132.240:8081}"
JENKINS_USER="${JENKINS_USER:-admin}"
JENKINS_TOKEN="${JENKINS_TOKEN}"
JOB_NAME="build-deploy-scala-spark"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 Setting up Jenkins Job: $JOB_NAME"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if Jenkins is accessible
echo "1. Checking Jenkins connectivity..."
if ! curl -s -o /dev/null -w "%{http_code}" "$JENKINS_URL" | grep -q "200\|403"; then
    echo "❌ Cannot connect to Jenkins at $JENKINS_URL"
    echo "   Please check if Jenkins is running"
    exit 1
fi
echo "✅ Jenkins is accessible"

# Check credentials
if [ -z "$JENKINS_TOKEN" ]; then
    echo ""
    echo "⚠️  JENKINS_TOKEN not set!"
    echo ""
    echo "To get your Jenkins API token:"
    echo "1. Go to: $JENKINS_URL/user/$JENKINS_USER/configure"
    echo "2. Click 'Add new Token' under 'API Token'"
    echo "3. Copy the generated token"
    echo ""
    echo "Then run:"
    echo "  export JENKINS_TOKEN='your-token-here'"
    echo "  ./setup_scala_spark_job.sh"
    echo ""
    exit 1
fi

# Check if job exists
echo ""
echo "2. Checking if job already exists..."
JOB_EXISTS=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "$JENKINS_USER:$JENKINS_TOKEN" \
    "$JENKINS_URL/job/$JOB_NAME/config.xml")

if [ "$JOB_EXISTS" = "200" ]; then
    echo "⚠️  Job '$JOB_NAME' already exists"
    read -p "   Do you want to update it? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi

    echo "Updating existing job..."
    curl -s -X POST \
        -u "$JENKINS_USER:$JENKINS_TOKEN" \
        -H "Content-Type: application/xml" \
        --data-binary @job-scala-spark.xml \
        "$JENKINS_URL/job/$JOB_NAME/config.xml"

    if [ $? -eq 0 ]; then
        echo "✅ Job updated successfully"
    else
        echo "❌ Failed to update job"
        exit 1
    fi
else
    echo "Creating new job..."
    curl -s -X POST \
        -u "$JENKINS_USER:$JENKINS_TOKEN" \
        -H "Content-Type: application/xml" \
        --data-binary @job-scala-spark.xml \
        "$JENKINS_URL/createItem?name=$JOB_NAME"

    if [ $? -eq 0 ]; then
        echo "✅ Job created successfully"
    else
        echo "❌ Failed to create job"
        exit 1
    fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ SETUP COMPLETE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🎯 Job URL: $JENKINS_URL/job/$JOB_NAME/"
echo ""
echo "📋 Next Steps:"
echo "1. Configure SSH credentials in Jenkins:"
echo "   - ID: dstreambolt-accesskey"
echo "   - Private key: ~/.ssh/dstreambolt-access-key.pem"
echo ""
echo "2. Configure Git SSH credentials:"
echo "   - ID: jenkins-github-ssh"
echo "   - Private key: Your GitHub SSH key"
echo ""
echo "3. Go to job and click 'Build with Parameters'"
echo ""

