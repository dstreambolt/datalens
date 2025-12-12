#!/bin/bash
# Diagnose Kafka connectivity from ingestion service
# Run this on the ingestion server

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       Kafka Connectivity Diagnostics                        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Check current server
echo "1️⃣  Current Server Info"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Hostname: $(hostname)"
echo "Private IP: $(hostname -I | awk '{print $1}')"
echo "User: $(whoami)"
echo ""

# Check network connectivity to Kafka
KAFKA_HOST="10.0.10.101"
KAFKA_PORT="9092"

echo "2️⃣  Network Connectivity Test"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Testing connection to Kafka: ${KAFKA_HOST}:${KAFKA_PORT}"
echo ""

# Test ping
echo "🔹 Ping test:"
if ping -c 3 -W 2 ${KAFKA_HOST} > /dev/null 2>&1; then
    echo "  ✅ Ping successful"
else
    echo "  ❌ Ping failed"
fi

# Test telnet/nc
echo ""
echo "🔹 Port connectivity test:"
if command -v nc > /dev/null; then
    if timeout 5 bash -c "echo > /dev/tcp/${KAFKA_HOST}/${KAFKA_PORT}" 2>/dev/null; then
        echo "  ✅ Port ${KAFKA_PORT} is reachable"
    else
        echo "  ❌ Port ${KAFKA_PORT} is NOT reachable"
        echo "     This is likely the problem!"
    fi
else
    echo "  ⚠️  nc command not found, installing..."
    sudo apt-get install -y netcat-openbsd > /dev/null 2>&1
    if nc -zv -w 5 ${KAFKA_HOST} ${KAFKA_PORT} 2>&1 | grep -q "succeeded"; then
        echo "  ✅ Port ${KAFKA_PORT} is reachable"
    else
        echo "  ❌ Port ${KAFKA_PORT} is NOT reachable"
    fi
fi

# Check security groups
echo ""
echo "3️⃣  Security Group Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
INSTANCE_ID=$(ec2-metadata --instance-id 2>/dev/null | awk '{print $2}')
if [ ! -z "$INSTANCE_ID" ]; then
    echo "Instance ID: $INSTANCE_ID"

    # Get security groups
    SG_IDS=$(aws ec2 describe-instances \
        --instance-ids $INSTANCE_ID \
        --query 'Reservations[0].Instances[0].SecurityGroups[*].GroupId' \
        --output text 2>/dev/null)

    if [ ! -z "$SG_IDS" ]; then
        echo "Security Groups: $SG_IDS"

        # Check if port 9092 is allowed outbound
        echo ""
        echo "Checking outbound rules for Kafka port..."
        for sg in $SG_IDS; do
            echo "Security Group: $sg"
            aws ec2 describe-security-groups \
                --group-ids $sg \
                --query 'SecurityGroups[0].IpPermissionsEgress[*].[IpProtocol,FromPort,ToPort,IpRanges[0].CidrIp]' \
                --output table 2>/dev/null | head -20
        done
    fi
else
    echo "⚠️  Cannot determine instance ID (not on EC2 or ec2-metadata not installed)"
fi

# Check environment variables
echo ""
echo "4️⃣  Environment Variables"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "KAFKA_BROKER: ${KAFKA_BROKER:-not set}"
echo "KAFKA_TOPIC: ${KAFKA_TOPIC:-not set}"
echo "AWS_DEFAULT_REGION: ${AWS_DEFAULT_REGION:-not set}"
echo ""

# Check Secrets Manager access
echo "5️⃣  AWS Secrets Manager Access"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if command -v aws > /dev/null; then
    # Check credentials
    echo "🔹 AWS Credentials:"
    if aws sts get-caller-identity > /dev/null 2>&1; then
        echo "  ✅ AWS credentials working"
        aws sts get-caller-identity
    else
        echo "  ❌ No AWS credentials or invalid"
    fi

    echo ""
    echo "🔹 Secrets Manager access:"

    # Check if dstreambolt/kafka secret exists
    if aws secretsmanager describe-secret --secret-id dstreambolt/kafka 2>/dev/null > /dev/null; then
        echo "  ✅ Secret 'dstreambolt/kafka' exists"

        # Try to get the secret value
        echo ""
        echo "  Secret content:"
        if aws secretsmanager get-secret-value --secret-id dstreambolt/kafka 2>/dev/null | jq -r '.SecretString' 2>/dev/null; then
            echo "  ✅ Can read secret value"
        else
            echo "  ❌ Cannot read secret value (permission issue?)"
        fi
    else
        echo "  ⚠️  Secret 'dstreambolt/kafka' NOT found"
        echo "     Service will use fallback: KAFKA_BROKER=10.0.10.101:9092"
    fi
else
    echo "⚠️  AWS CLI not installed"
fi

# Check ingestion service status
echo ""
echo "6️⃣  Ingestion Service Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if systemctl is-active --quiet dstreambolt-ingest; then
    echo "✅ Service is running"
    echo ""
    echo "Recent logs (Kafka-related):"
    sudo journalctl -u dstreambolt-ingest --since "5 minutes ago" | grep -i kafka | tail -20
else
    echo "❌ Service is NOT running"
fi

# Check Python Kafka library
echo ""
echo "7️⃣  Python Kafka Library Test"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ -d /opt/dstreambolt/ingest/venv ]; then
    echo "Testing Kafka connection from Python..."
    /opt/dstreambolt/ingest/venv/bin/python3 << 'PYEOF'
from kafka import KafkaProducer
import json
import sys

try:
    print(f"🔗 Attempting connection to 10.0.10.101:9092...")
    producer = KafkaProducer(
        bootstrap_servers=['10.0.10.101:9092'],
        value_serializer=lambda v: json.dumps(v).encode('utf-8'),
        request_timeout_ms=5000,
        api_version_auto_timeout_ms=5000
    )
    print("✅ Kafka connection successful!")
    producer.close()
    sys.exit(0)
except Exception as e:
    print(f"❌ Kafka connection failed: {e}")
    sys.exit(1)
PYEOF

    if [ $? -eq 0 ]; then
        echo "  ✅ Python can connect to Kafka"
    else
        echo "  ❌ Python CANNOT connect to Kafka"
        echo "     This confirms the connectivity issue"
    fi
else
    echo "⚠️  Virtual environment not found at /opt/dstreambolt/ingest/venv"
fi

# Summary
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                      Diagnosis Summary                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Kafka Server: ${KAFKA_HOST}:${KAFKA_PORT}"
echo ""
echo "Common Issues:"
echo "  1. Network connectivity - check if port 9092 is reachable"
echo "  2. Security group rules - ensure outbound to 10.0.10.101:9092"
echo "  3. Kafka not running - check Kafka server status"
echo "  4. VPC routing - check route tables and NACLs"
echo ""
echo "Next Steps:"
echo "  • If port test fails: Check security groups and NACLs"
echo "  • If Python test fails: Check Kafka server status"
echo "  • Check Kafka logs: ssh to 10.0.10.101 and check logs"
echo ""

