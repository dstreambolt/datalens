#!/bin/bash
# Setup AWS Secrets Manager for DStreamBolt
# This script creates secrets in AWS Secrets Manager

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔐 DStreamBolt Secrets Manager Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# Configuration
AWS_REGION="${AWS_REGION:-ap-south-1}"
PROJECT="DStreamBolt"
ENVIRONMENT="${ENVIRONMENT:-Production}"

echo -e "${BLUE}Configuration:${NC}"
echo "  Region: $AWS_REGION"
echo "  Project: $PROJECT"
echo "  Environment: $ENVIRONMENT"
echo

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ AWS CLI not found${NC}"
    echo "   Install: https://aws.amazon.com/cli/"
    exit 1
fi

# Check AWS credentials
echo -e "${BLUE}Checking AWS credentials...${NC}"
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}❌ AWS credentials not configured${NC}"
    echo "   Run: aws configure"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "${GREEN}✅ AWS credentials OK (Account: $ACCOUNT_ID)${NC}"
echo

# ============================================================================
# Function to create or update secret
# ============================================================================
create_or_update_secret() {
    local secret_name=$1
    local secret_value=$2
    local description=$3

    echo -e "${BLUE}Processing secret: $secret_name${NC}"

    # Check if secret exists
    if aws secretsmanager describe-secret --secret-id "$secret_name" --region "$AWS_REGION" &> /dev/null; then
        echo "  Secret exists, updating..."
        aws secretsmanager put-secret-value \
            --secret-id "$secret_name" \
            --secret-string "$secret_value" \
            --region "$AWS_REGION" > /dev/null
        echo -e "${GREEN}  ✅ Secret updated${NC}"
    else
        echo "  Creating new secret..."
        aws secretsmanager create-secret \
            --name "$secret_name" \
            --description "$description" \
            --secret-string "$secret_value" \
            --region "$AWS_REGION" > /dev/null

        # Tag the secret
        local secret_arn="arn:aws:secretsmanager:$AWS_REGION:$ACCOUNT_ID:secret:$secret_name"
        aws secretsmanager tag-resource \
            --secret-id "$secret_arn" \
            --tags Key=Project,Value=$PROJECT \
                   Key=Environment,Value=$ENVIRONMENT \
                   Key=ManagedBy,Value=Terraform \
            --region "$AWS_REGION" > /dev/null

        echo -e "${GREEN}  ✅ Secret created and tagged${NC}"
    fi
}

# ============================================================================
# Prompt for secrets
# ============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📝 Enter secret values (or press Enter to use defaults)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# MySQL Configuration
echo -e "${YELLOW}MySQL Configuration:${NC}"
read -p "  MySQL Host [10.0.1.61]: " MYSQL_HOST
MYSQL_HOST=${MYSQL_HOST:-10.0.1.61}

read -p "  MySQL Port [3306]: " MYSQL_PORT
MYSQL_PORT=${MYSQL_PORT:-3306}

read -p "  MySQL Username [dstreambolt]: " MYSQL_USER
MYSQL_USER=${MYSQL_USER:-dstreambolt}

read -s -p "  MySQL Password: " MYSQL_PASSWORD
echo

read -p "  MySQL Database [dstreambolt_metrics]: " MYSQL_DB
MYSQL_DB=${MYSQL_DB:-dstreambolt_metrics}

echo

# Kafka Configuration
echo -e "${YELLOW}Kafka Configuration:${NC}"
read -p "  Kafka Broker(s) [10.0.10.101:9092]: " KAFKA_BROKERS
KAFKA_BROKERS=${KAFKA_BROKERS:-10.0.10.101:9092}

read -p "  Kafka Topic [dstreambolt-logs]: " KAFKA_TOPIC
KAFKA_TOPIC=${KAFKA_TOPIC:-dstreambolt-logs}

read -p "  Use SASL authentication? [y/N]: " USE_SASL
if [[ "$USE_SASL" =~ ^[Yy]$ ]]; then
    read -p "    SASL Mechanism [PLAIN]: " SASL_MECHANISM
    SASL_MECHANISM=${SASL_MECHANISM:-PLAIN}

    read -p "    SASL Username: " SASL_USERNAME
    read -s -p "    SASL Password: " SASL_PASSWORD
    echo

    SECURITY_PROTOCOL="SASL_PLAINTEXT"
else
    SASL_MECHANISM=""
    SASL_USERNAME=""
    SASL_PASSWORD=""
    SECURITY_PROTOCOL="PLAINTEXT"
fi

echo

# Application Secrets
echo -e "${YELLOW}Application Secrets (optional):${NC}"
read -p "  API Keys (comma-separated, optional): " API_KEYS

echo

# ============================================================================
# Create secrets
# ============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔐 Creating secrets in AWS Secrets Manager"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# 1. MySQL Secret
MYSQL_SECRET=$(cat <<EOF
{
  "host": "$MYSQL_HOST",
  "port": $MYSQL_PORT,
  "username": "$MYSQL_USER",
  "password": "$MYSQL_PASSWORD",
  "database": "$MYSQL_DB"
}
EOF
)

create_or_update_secret \
    "dstreambolt/mysql" \
    "$MYSQL_SECRET" \
    "DStreamBolt MySQL database credentials"

echo

# 2. Kafka Secret
if [ -n "$SASL_USERNAME" ]; then
    # With SASL
    KAFKA_SECRET=$(cat <<EOF
{
  "brokers": ["$KAFKA_BROKERS"],
  "topic": "$KAFKA_TOPIC",
  "security_protocol": "$SECURITY_PROTOCOL",
  "sasl_mechanism": "$SASL_MECHANISM",
  "sasl_username": "$SASL_USERNAME",
  "sasl_password": "$SASL_PASSWORD"
}
EOF
)
else
    # Without SASL
    KAFKA_SECRET=$(cat <<EOF
{
  "brokers": ["$KAFKA_BROKERS"],
  "topic": "$KAFKA_TOPIC",
  "security_protocol": "$SECURITY_PROTOCOL"
}
EOF
)
fi

create_or_update_secret \
    "dstreambolt/kafka" \
    "$KAFKA_SECRET" \
    "DStreamBolt Kafka broker credentials"

echo

# 3. Application Secrets (if any)
if [ -n "$API_KEYS" ]; then
    # Convert comma-separated to JSON array
    API_KEYS_ARRAY=$(echo "$API_KEYS" | awk -F',' '{printf "["; for(i=1; i<=NF; i++) {gsub(/^ +| +$/,"",$i); printf "\"%s\"", $i; if(i<NF) printf ","}; print "]"}')

    APP_SECRET=$(cat <<EOF
{
  "api_keys": $API_KEYS_ARRAY
}
EOF
)

    create_or_update_secret \
        "dstreambolt/app" \
        "$APP_SECRET" \
        "DStreamBolt application secrets"

    echo
fi

# ============================================================================
# Create/Update IAM Policy
# ============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔑 Creating IAM policy for secrets access"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

POLICY_NAME="DStreamBoltSecretsAccess"

IAM_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowSecretsAccess",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": [
        "arn:aws:secretsmanager:$AWS_REGION:$ACCOUNT_ID:secret:dstreambolt/*"
      ]
    },
    {
      "Sid": "AllowKMSDecrypt",
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt",
        "kms:DescribeKey"
      ],
      "Resource": "arn:aws:kms:$AWS_REGION:$ACCOUNT_ID:key/*"
    }
  ]
}
EOF
)

# Check if policy exists
POLICY_ARN="arn:aws:iam::$ACCOUNT_ID:policy/$POLICY_NAME"
if aws iam get-policy --policy-arn "$POLICY_ARN" &> /dev/null; then
    echo "  Policy exists, creating new version..."

    # Create new policy version
    aws iam create-policy-version \
        --policy-arn "$POLICY_ARN" \
        --policy-document "$IAM_POLICY" \
        --set-as-default > /dev/null

    echo -e "${GREEN}  ✅ Policy updated${NC}"
else
    echo "  Creating new policy..."

    aws iam create-policy \
        --policy-name "$POLICY_NAME" \
        --policy-document "$IAM_POLICY" \
        --description "Allow access to DStreamBolt secrets in AWS Secrets Manager" \
        --tags Key=Project,Value=$PROJECT Key=Environment,Value=$ENVIRONMENT > /dev/null

    echo -e "${GREEN}  ✅ Policy created${NC}"
fi

echo

# ============================================================================
# Instructions for attaching policy to roles
# ============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Next Steps"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "1. Attach IAM policy to EC2 instance roles:"
echo
echo "   # For ingestion service"
echo "   aws iam attach-role-policy \\"
echo "     --role-name dstreambolt-ingest-role \\"
echo "     --policy-arn $POLICY_ARN"
echo
echo "   # For Spark compute"
echo "   aws iam attach-role-policy \\"
echo "     --role-name dstreambolt-compute-role \\"
echo "     --policy-arn $POLICY_ARN"
echo
echo "   # For DevOps instance"
echo "   aws iam attach-role-policy \\"
echo "     --role-name dstreambolt-devops-role \\"
echo "     --policy-arn $POLICY_ARN"
echo
echo "2. Install boto3 on all instances:"
echo "   pip3 install boto3"
echo
echo "3. Deploy secrets_manager.py to /opt/dstreambolt/"
echo
echo "4. Update app.py to use secrets manager"
echo
echo "5. Test secrets access:"
echo "   python3 secrets_manager.py"
echo
echo "6. Remove environment variables from systemd units"
echo

# ============================================================================
# Summary
# ============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Secrets Manager Setup Complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "Secrets created:"
echo "  ✅ dstreambolt/mysql"
echo "  ✅ dstreambolt/kafka"
if [ -n "$API_KEYS" ]; then
    echo "  ✅ dstreambolt/app"
fi
echo
echo "IAM Policy: $POLICY_ARN"
echo
echo "Estimated monthly cost: \$1.25 USD"
echo "  - 3 secrets × \$0.40 = \$1.20"
echo "  - API calls: ~\$0.05"
echo
echo "View secrets in AWS Console:"
echo "  https://console.aws.amazon.com/secretsmanager/home?region=$AWS_REGION"
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

