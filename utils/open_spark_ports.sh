#!/bin/bash

# Fix AWS Security Group for Spark Ports
# Opens ports 7077, 8080, 8081, 18080 for Spark access

set -e

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║     Opening Spark Ports in AWS Security Group                 ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

REGION="ap-south-1"

# Get the Spark instance ID
echo "📋 Finding Spark compute instance..."
INSTANCE_ID=$(aws ec2 describe-instances \
    --region $REGION \
    --filters "Name=tag:Name,Values=*compute*" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text 2>/dev/null)

if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "None" ]; then
    echo "❌ Could not find Spark compute instance"
    echo "Trying alternative filter..."

    INSTANCE_ID=$(aws ec2 describe-instances \
        --region $REGION \
        --filters "Name=tag:Name,Values=*spark*" "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text 2>/dev/null)
fi

if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "None" ]; then
    echo "❌ Could not find instance. Please provide manually:"
    read -p "Enter Spark instance ID (e.g., i-0123456789abcdef): " INSTANCE_ID
fi

echo "✅ Found instance: $INSTANCE_ID"

# Get security group ID
echo "📋 Getting security group..."
SG_ID=$(aws ec2 describe-instances \
    --region $REGION \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
    --output text)

if [ -z "$SG_ID" ] || [ "$SG_ID" = "None" ]; then
    echo "❌ Could not find security group"
    exit 1
fi

echo "✅ Found security group: $SG_ID"
echo ""

# Get current rules
echo "📋 Current inbound rules for Spark ports:"
aws ec2 describe-security-groups \
    --region $REGION \
    --group-ids $SG_ID \
    --query 'SecurityGroups[0].IpPermissions[?FromPort!=`null` && (FromPort==`7077` || FromPort==`8080` || FromPort==`8081` || FromPort==`18080`)]' \
    --output table 2>/dev/null || echo "No existing Spark port rules"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Adding Spark Port Rules"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Array of ports to open
PORTS=(7077 8080 8081 18080)
PORT_NAMES=("Spark Master" "Master UI" "Worker UI" "History Server")

for i in "${!PORTS[@]}"; do
    PORT="${PORTS[$i]}"
    NAME="${PORT_NAMES[$i]}"

    echo "Adding rule for $NAME (port $PORT)..."

    # Try to add the rule
    aws ec2 authorize-security-group-ingress \
        --region $REGION \
        --group-id $SG_ID \
        --protocol tcp \
        --port $PORT \
        --cidr 0.0.0.0/0 \
        --output text 2>&1 | grep -v "already exists" || echo "  ✅ Port $PORT rule added (or already exists)"
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Get instance public IP
PUBLIC_IP=$(aws ec2 describe-instances \
    --region $REGION \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

echo "Instance: $INSTANCE_ID"
echo "Public IP: $PUBLIC_IP"
echo "Security Group: $SG_ID"
echo ""

# Show updated rules
echo "Updated security group rules for Spark ports:"
aws ec2 describe-security-groups \
    --region $REGION \
    --group-ids $SG_ID \
    --query 'SecurityGroups[0].IpPermissions[?FromPort!=`null` && (FromPort==`7077` || FromPort==`8080` || FromPort==`8081` || FromPort==`18080`)].[FromPort,ToPort,IpProtocol,IpRanges[0].CidrIp]' \
    --output table

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Testing Connectivity"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Waiting 5 seconds for rules to propagate..."
sleep 5

for i in "${!PORTS[@]}"; do
    PORT="${PORTS[$i]}"
    NAME="${PORT_NAMES[$i]}"

    echo -n "Testing $NAME (port $PORT)... "
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 http://$PUBLIC_IP:$PORT 2>/dev/null || echo "000")

    if [ "$HTTP_CODE" = "200" ]; then
        echo "✅ Accessible (HTTP $HTTP_CODE)"
    elif [ "$HTTP_CODE" = "000" ]; then
        echo "⚠️  Timeout (may still be starting)"
    else
        echo "⚠️  HTTP $HTTP_CODE"
    fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Done!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Access URLs:"
echo "  Spark Master:   http://$PUBLIC_IP:8080"
echo "  Spark Worker:   http://$PUBLIC_IP:8081"
echo "  History Server: http://$PUBLIC_IP:18080"
echo ""
echo "Open these in your browser to verify!"
echo ""

