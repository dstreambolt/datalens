#!/bin/bash

# Quick Setup Script for DStreamBolt Jenkins Jobs
# This script helps you set up the Jenkins jobs quickly

set -e

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║   DStreamBolt Jenkins Jobs - Quick Setup                      ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print section headers
print_header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Check if Jenkins CLI is available
check_jenkins_cli() {
    if ! command -v jenkins-cli &> /dev/null; then
        echo -e "${YELLOW}⚠️  jenkins-cli not found. Will provide manual setup instructions.${NC}"
        return 1
    fi
    return 0
}

print_header "📋 PREREQUISITES CHECK"

echo "Checking prerequisites..."
echo ""

# Check SSH key
SSH_KEY_PATH="$HOME/dstreambolt-access-key.pem"
if [ -f "$SSH_KEY_PATH" ]; then
    echo -e "${GREEN}✓${NC} SSH key found: $SSH_KEY_PATH"
else
    echo -e "${RED}✗${NC} SSH key not found: $SSH_KEY_PATH"
    echo "  Please ensure your SSH key is at $SSH_KEY_PATH"
    exit 1
fi

# Check Jenkins files
if [ -f "deploy-ingestion.jenkinsfile" ] && [ -f "deploy-spark-jobs.jenkinsfile" ]; then
    echo -e "${GREEN}✓${NC} Jenkins pipeline files found"
else
    echo -e "${RED}✗${NC} Jenkins pipeline files not found"
    echo "  Please run this script from the jenkins/ directory"
    exit 1
fi

print_header "📝 CONFIGURATION"

# Get Jenkins URL
echo "Enter your Jenkins URL (e.g., http://jenkins.example.com:8080):"
read -r JENKINS_URL

# Get Jenkins credentials
echo "Enter your Jenkins username:"
read -r JENKINS_USER

echo "Enter your Jenkins API token (will not be displayed):"
read -sr JENKINS_TOKEN
echo ""

# Get target IPs
echo "Enter your ingestion server IP(s) (comma-separated):"
read -r INGESTION_IPS

echo "Enter your Spark master IP(s) (comma-separated):"
read -r SPARK_IPS

echo "Enter your Kafka broker address (e.g., 10.0.10.101:9092):"
read -r KAFKA_BROKER

print_header "🔑 JENKINS CREDENTIALS SETUP"

echo "To add SSH credentials to Jenkins:"
echo ""
echo "1. Go to: ${JENKINS_URL}/credentials/"
echo "2. Click 'Add Credentials'"
echo "3. Kind: SSH Username with private key"
echo "4. ID: dstreambolt-ssh-key"
echo "5. Username: ubuntu"
echo "6. Private Key: Enter directly"
echo "7. Paste contents of: $SSH_KEY_PATH"
echo "8. Click 'OK'"
echo ""
echo -e "${YELLOW}Press Enter when credentials are added...${NC}"
read -r

print_header "🚀 JENKINS JOBS SETUP"

echo "Creating Jenkins jobs..."
echo ""

# Job 1: Ingestion Deployment
cat > job-ingestion.xml << EOF
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job@2.40">
  <description>Deploy DStreamBolt Ingestion Service to specified servers</description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <hudson.model.ParametersDefinitionProperty>
      <parameterDefinitions>
        <hudson.model.StringParameterDefinition>
          <name>TARGET_IPS</name>
          <description>Comma-separated list of ingestion server IPs</description>
          <defaultValue>${INGESTION_IPS}</defaultValue>
        </hudson.model.StringParameterDefinition>
        <hudson.model.StringParameterDefinition>
          <name>GIT_BRANCH</name>
          <description>Git branch to deploy from</description>
          <defaultValue>main</defaultValue>
        </hudson.model.StringParameterDefinition>
        <hudson.model.BooleanParameterDefinition>
          <name>RESTART_SERVICE</name>
          <description>Restart the ingestion service after deployment</description>
          <defaultValue>true</defaultValue>
        </hudson.model.BooleanParameterDefinition>
        <hudson.model.BooleanParameterDefinition>
          <name>RUN_TESTS</name>
          <description>Run health checks after deployment</description>
          <defaultValue>true</defaultValue>
        </hudson.model.BooleanParameterDefinition>
      </parameterDefinitions>
    </hudson.model.ParametersDefinitionProperty>
  </properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition" plugin="workflow-cps@2.90">
    <scm class="hudson.plugins.git.GitSCM" plugin="git@4.7.1">
      <configVersion>2</configVersion>
      <userRemoteConfigs>
        <hudson.plugins.git.UserRemoteConfig>
          <url>https://github.com/dstreambolt/dstream_cloud.git</url>
        </hudson.plugins.git.UserRemoteConfig>
      </userRemoteConfigs>
      <branches>
        <hudson.plugins.git.BranchSpec>
          <name>*/main</name>
        </hudson.plugins.git.BranchSpec>
      </branches>
    </scm>
    <scriptPath>jenkins/deploy-ingestion.jenkinsfile</scriptPath>
    <lightweight>true</lightweight>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
EOF

# Job 2: Spark Deployment
cat > job-spark.xml << EOF
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job@2.40">
  <description>Deploy DStreamBolt Spark Jobs to specified masters</description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <hudson.model.ParametersDefinitionProperty>
      <parameterDefinitions>
        <hudson.model.StringParameterDefinition>
          <name>SPARK_MASTER_IPS</name>
          <description>Comma-separated list of Spark master IPs</description>
          <defaultValue>${SPARK_IPS}</defaultValue>
        </hudson.model.StringParameterDefinition>
        <hudson.model.StringParameterDefinition>
          <name>KAFKA_BROKER</name>
          <description>Kafka broker address</description>
          <defaultValue>${KAFKA_BROKER}</defaultValue>
        </hudson.model.StringParameterDefinition>
        <hudson.model.StringParameterDefinition>
          <name>GIT_BRANCH</name>
          <description>Git branch to deploy from</description>
          <defaultValue>main</defaultValue>
        </hudson.model.StringParameterDefinition>
        <hudson.model.ChoiceParameterDefinition>
          <name>PROCESSING_MODE</name>
          <description>Spark processing mode</description>
          <choices class="java.util.Arrays\$ArrayList">
            <a class="string-array">
              <string>streaming</string>
              <string>batch</string>
            </a>
          </choices>
        </hudson.model.ChoiceParameterDefinition>
        <hudson.model.BooleanParameterDefinition>
          <name>GRACEFUL_SHUTDOWN</name>
          <description>Wait for existing jobs to complete before killing</description>
          <defaultValue>true</defaultValue>
        </hudson.model.BooleanParameterDefinition>
        <hudson.model.BooleanParameterDefinition>
          <name>AUTO_START</name>
          <description>Automatically start the new Spark job</description>
          <defaultValue>true</defaultValue>
        </hudson.model.BooleanParameterDefinition>
      </parameterDefinitions>
    </hudson.model.ParametersDefinitionProperty>
  </properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition" plugin="workflow-cps@2.90">
    <scm class="hudson.plugins.git.GitSCM" plugin="git@4.7.1">
      <configVersion>2</configVersion>
      <userRemoteConfigs>
        <hudson.plugins.git.UserRemoteConfig>
          <url>https://github.com/dstreambolt/dstream_cloud.git</url>
        </hudson.plugins.git.UserRemoteConfig>
      </userRemoteConfigs>
      <branches>
        <hudson.plugins.git.BranchSpec>
          <name>*/main</name>
        </hudson.plugins.git.BranchSpec>
      </branches>
    </scm>
    <scriptPath>jenkins/deploy-spark-jobs.jenkinsfile</scriptPath>
    <lightweight>true</lightweight>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
EOF

echo "Job configuration files created:"
echo "  - job-ingestion.xml"
echo "  - job-spark.xml"
echo ""

print_header "📥 MANUAL JOB CREATION"

echo "To create the jobs in Jenkins, follow these steps:"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Job 1: DStreamBolt-Deploy-Ingestion"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Go to: ${JENKINS_URL}/view/all/newJob"
echo "2. Enter name: DStreamBolt-Deploy-Ingestion"
echo "3. Select: Pipeline"
echo "4. Click: OK"
echo "5. In Pipeline section:"
echo "   - Definition: Pipeline script from SCM"
echo "   - SCM: Git"
echo "   - Repository URL: https://github.com/dstreambolt/dstream_cloud.git"
echo "   - Branch: */main"
echo "   - Script Path: jenkins/deploy-ingestion.jenkinsfile"
echo "6. Click: Save"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Job 2: DStreamBolt-Deploy-Spark"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Go to: ${JENKINS_URL}/view/all/newJob"
echo "2. Enter name: DStreamBolt-Deploy-Spark"
echo "3. Select: Pipeline"
echo "4. Click: OK"
echo "5. In Pipeline section:"
echo "   - Definition: Pipeline script from SCM"
echo "   - SCM: Git"
echo "   - Repository URL: https://github.com/dstreambolt/dstream_cloud.git"
echo "   - Branch: */main"
echo "   - Script Path: jenkins/deploy-spark-jobs.jenkinsfile"
echo "6. Click: Save"
echo ""

print_header "✅ SETUP COMPLETE"

echo "Jenkins jobs are ready to be created!"
echo ""
echo "Next steps:"
echo "1. Create the jobs using the instructions above"
echo "2. Test deployment with 'Build with Parameters'"
echo "3. Review the deployment logs"
echo ""
echo "Default Parameters:"
echo "  Ingestion IPs: ${INGESTION_IPS}"
echo "  Spark IPs: ${SPARK_IPS}"
echo "  Kafka Broker: ${KAFKA_BROKER}"
echo ""
echo "For detailed usage, see: jenkins/README.md"
echo ""
echo -e "${GREEN}✓ Setup script completed!${NC}"

