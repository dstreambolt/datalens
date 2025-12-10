#!/bin/bash
# Deploy Kafka Metrics Collector using AWS SSM
# Run this script to deploy the collector on the Kafka node via AWS Systems Manager

set -e

KAFKA_INSTANCE_ID="${1:-i-0bdf20dd0b5e1cc81}"
AWS_REGION="${2:-ap-south-1}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Deploying Kafka Metrics Collector via AWS SSM"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Target Instance: $KAFKA_INSTANCE_ID"
echo "AWS Region: $AWS_REGION"
echo ""

# Check if files exist
if [ ! -f "kafka_metrics_collector.py" ]; then
    echo "❌ kafka_metrics_collector.py not found!"
    exit 1
fi

if [ ! -f "kafka-metrics-collector.service" ]; then
    echo "❌ kafka-metrics-collector.service not found!"
    exit 1
fi

# Check AWS CLI and Session Manager plugin
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI not found. Please install: https://aws.amazon.com/cli/"
    exit 1
fi

if ! aws ssm start-session --help &> /dev/null; then
    echo "❌ AWS Session Manager plugin not found."
    echo "   Install: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
    exit 1
fi

echo "✅ AWS CLI and SSM plugin found"
echo ""

# Test instance connectivity
echo "🔍 Testing connectivity to instance..."
if ! aws ssm describe-instance-information \
    --region $AWS_REGION \
    --filters "Key=InstanceIds,Values=$KAFKA_INSTANCE_ID" \
    --query "InstanceInformationList[0].PingStatus" \
    --output text | grep -q "Online"; then
    echo "❌ Instance $KAFKA_INSTANCE_ID is not online or SSM agent is not running"
    echo "   Make sure SSM agent is installed and instance has proper IAM role"
    exit 1
fi
echo "✅ Instance is online and reachable via SSM"
echo ""

echo "1️⃣  Creating directories on Kafka node..."
aws ssm send-command \
    --region $AWS_REGION \
    --instance-ids $KAFKA_INSTANCE_ID \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=[
        "sudo mkdir -p /opt/dstreambolt/observability",
        "sudo mkdir -p /var/log/dstreambolt",
        "sudo chown -R ubuntu:ubuntu /opt/dstreambolt",
        "sudo chown -R ubuntu:ubuntu /var/log/dstreambolt"
    ]' \
    --output text \
    --query "Command.CommandId" > /tmp/command_id.txt

COMMAND_ID=$(cat /tmp/command_id.txt)
echo "   Command ID: $COMMAND_ID"

# Wait for command to complete
sleep 3
STATUS=$(aws ssm get-command-invocation \
    --region $AWS_REGION \
    --command-id $COMMAND_ID \
    --instance-id $KAFKA_INSTANCE_ID \
    --query "Status" \
    --output text)

if [ "$STATUS" != "Success" ]; then
    echo "❌ Failed to create directories. Status: $STATUS"
    aws ssm get-command-invocation \
        --region $AWS_REGION \
        --command-id $COMMAND_ID \
        --instance-id $KAFKA_INSTANCE_ID \
        --query "StandardErrorContent" \
        --output text
    exit 1
fi
echo "✅ Directories created"
echo ""

echo "2️⃣  Copying collector script to S3 (temporary)..."
TEMP_BUCKET="dstreambolt-temp-$(date +%s)"
aws s3 mb s3://$TEMP_BUCKET --region $AWS_REGION 2>/dev/null || true
aws s3 cp kafka_metrics_collector.py s3://$TEMP_BUCKET/kafka_metrics_collector.py --region $AWS_REGION
aws s3 cp kafka-metrics-collector.service s3://$TEMP_BUCKET/kafka-metrics-collector.service --region $AWS_REGION
echo "✅ Files uploaded to S3"
echo ""

echo "3️⃣  Downloading files to instance..."
aws ssm send-command \
    --region $AWS_REGION \
    --instance-ids $KAFKA_INSTANCE_ID \
    --document-name "AWS-RunShellScript" \
    --parameters "commands=[
        \"aws s3 cp s3://$TEMP_BUCKET/kafka_metrics_collector.py /opt/dstreambolt/observability/kafka_metrics_collector.py --region $AWS_REGION\",
        \"aws s3 cp s3://$TEMP_BUCKET/kafka-metrics-collector.service /tmp/kafka-metrics-collector.service --region $AWS_REGION\",
        \"chmod +x /opt/dstreambolt/observability/kafka_metrics_collector.py\",
        \"sudo chown ubuntu:ubuntu /opt/dstreambolt/observability/kafka_metrics_collector.py\"
    ]" \
    --output text \
    --query "Command.CommandId" > /tmp/command_id.txt

COMMAND_ID=$(cat /tmp/command_id.txt)
sleep 3

STATUS=$(aws ssm get-command-invocation \
    --region $AWS_REGION \
    --command-id $COMMAND_ID \
    --instance-id $KAFKA_INSTANCE_ID \
    --query "Status" \
    --output text)

if [ "$STATUS" != "Success" ]; then
    echo "❌ Failed to download files. Status: $STATUS"
    exit 1
fi
echo "✅ Files downloaded to instance"
echo ""

echo "4️⃣  Cleaning up S3 temporary files..."
aws s3 rm s3://$TEMP_BUCKET/kafka_metrics_collector.py --region $AWS_REGION
aws s3 rm s3://$TEMP_BUCKET/kafka-metrics-collector.service --region $AWS_REGION
aws s3 rb s3://$TEMP_BUCKET --region $AWS_REGION 2>/dev/null || true
echo "✅ S3 cleanup done"
echo ""

echo "5️⃣  Installing Python dependencies..."
aws ssm send-command \
    --region $AWS_REGION \
    --instance-ids $KAFKA_INSTANCE_ID \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=[
        "pip3 install pymysql --quiet || sudo apt-get install -y python3-pymysql"
    ]' \
    --output text \
    --query "Command.CommandId" > /tmp/command_id.txt

COMMAND_ID=$(cat /tmp/command_id.txt)
sleep 3
echo "✅ Dependencies installed"
echo ""

echo "6️⃣  Installing systemd service..."
aws ssm send-command \
    --region $AWS_REGION \
    --instance-ids $KAFKA_INSTANCE_ID \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=[
        "sudo mv /tmp/kafka-metrics-collector.service /etc/systemd/system/",
        "sudo chmod 644 /etc/systemd/system/kafka-metrics-collector.service",
        "sudo systemctl daemon-reload"
    ]' \
    --output text \
    --query "Command.CommandId" > /tmp/command_id.txt

COMMAND_ID=$(cat /tmp/command_id.txt)
sleep 3
echo "✅ Service installed"
echo ""

echo "7️⃣  Starting and enabling service..."
aws ssm send-command \
    --region $AWS_REGION \
    --instance-ids $KAFKA_INSTANCE_ID \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=[
        "sudo systemctl enable kafka-metrics-collector.service",
        "sudo systemctl start kafka-metrics-collector.service",
        "sleep 2",
        "sudo systemctl status kafka-metrics-collector.service --no-pager"
    ]' \
    --output text \
    --query "Command.CommandId" > /tmp/command_id.txt

COMMAND_ID=$(cat /tmp/command_id.txt)
sleep 5

# Get the output
OUTPUT=$(aws ssm get-command-invocation \
    --region $AWS_REGION \
    --command-id $COMMAND_ID \
    --instance-id $KAFKA_INSTANCE_ID \
    --query "StandardOutputContent" \
    --output text)

echo "$OUTPUT"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Kafka Metrics Collector Deployed via SSM!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 Check Service Status:"
echo "   aws ssm start-session --target $KAFKA_INSTANCE_ID --region $AWS_REGION"
echo "   sudo systemctl status kafka-metrics-collector"
echo ""
echo "📋 View Logs:"
echo "   aws ssm start-session --target $KAFKA_INSTANCE_ID --region $AWS_REGION"
echo "   tail -f /var/log/dstreambolt/kafka-metrics.log"
echo "   OR"
echo "   sudo journalctl -u kafka-metrics-collector -f"
echo ""
echo "🔄 Manage Service (via SSM session):"
echo "   sudo systemctl start kafka-metrics-collector"
echo "   sudo systemctl stop kafka-metrics-collector"
echo "   sudo systemctl restart kafka-metrics-collector"
echo ""
echo "📈 Verify Data Collection:"
echo "   mysql -h 10.0.1.61 -u dstreambolt -p'DStreamBolt2025!' dstreambolt_metrics"
echo "   SELECT * FROM kafka_topic_metrics ORDER BY timestamp DESC LIMIT 5;"
echo "   SELECT * FROM kafka_consumer_lag ORDER BY timestamp DESC LIMIT 5;"
echo ""
echo "💡 To connect to instance:"
echo "   aws ssm start-session --target $KAFKA_INSTANCE_ID --region $AWS_REGION"
echo ""

