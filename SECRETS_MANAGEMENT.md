# Secrets Management - DStreamBolt Platform

AWS Secrets Manager configuration and usage guide.

## 📋 Overview

DStreamBolt uses AWS Secrets Manager to securely store sensitive credentials:

| Secret Name | Description | Used By |
|-------------|-------------|---------|
| `dstreambolt/mysql` | MySQL root password | DevOps, Ingestion, Spark |
| `dstreambolt/kafka` | Kafka broker configuration | Ingestion, Spark |
| `dstreambolt/app` | Application API keys (optional) | Ingestion |

## 🔐 Secrets Structure

### MySQL Secret (`dstreambolt/mysql`)

```json
{
  "host": "<devops-private-ip>",
  "port": "3306",
  "username": "root",
  "password": "<generated-password>",
  "database": "dstreambolt_metrics"
}
```

### Kafka Secret (`dstreambolt/kafka`)

```json
{
  "bootstrap_servers": "<kafka-private-ip>:9092",
  "topic": "dstreambolt-logs"
}
```

### App Secret (`dstreambolt/app`) - Optional

```json
{
  "api_keys": ["key1", "key2"],
  "mtls_enabled": true
}
```

## 🚀 Setup

### 1. Create Secrets (Automated via Terraform)

Secrets are automatically created when you run `terraform apply`.

### 2. Manual Secret Creation

If you need to create secrets manually:

```bash
# Create MySQL secret
aws secretsmanager create-secret \
  --name dstreambolt/mysql \
  --description "DStreamBolt MySQL credentials" \
  --secret-string '{
    "host": "10.0.1.68",
    "port": "3306",
    "username": "root",
    "password": "YourSecurePassword123!",
    "database": "dstreambolt_metrics"
  }' \
  --region ap-south-1

# Create Kafka secret
aws secretsmanager create-secret \
  --name dstreambolt/kafka \
  --description "DStreamBolt Kafka configuration" \
  --secret-string '{
    "bootstrap_servers": "10.0.10.248:9092",
    "topic": "dstreambolt-logs"
  }' \
  --region ap-south-1
```

## 📖 Usage in Services

### Python (Ingestion Service)

```python
import boto3
import json

def get_secret(secret_name, region="ap-south-1"):
    client = boto3.client('secretsmanager', region_name=region)
    response = client.get_secret_value(SecretId=secret_name)
    return json.loads(response['SecretString'])

# Get MySQL credentials
mysql_config = get_secret('dstreambolt/mysql')
host = mysql_config['host']
password = mysql_config['password']

# Get Kafka config
kafka_config = get_secret('dstreambolt/kafka')
broker = kafka_config['bootstrap_servers']
```

### Scala (Spark Jobs)

```scala
import software.amazon.awssdk.services.secretsmanager.SecretsManagerClient
import software.amazon.awssdk.services.secretsmanager.model.GetSecretValueRequest
import com.fasterxml.jackson.databind.ObjectMapper

def getSecret(secretName: String): Map[String, String] = {
  val client = SecretsManagerClient.builder()
    .region(Region.AP_SOUTH_1)
    .build()
    
  val request = GetSecretValueRequest.builder()
    .secretId(secretName)
    .build()
    
  val response = client.getSecretValue(request)
  val mapper = new ObjectMapper()
  mapper.readValue(response.secretString(), classOf[Map[String, String]])
}

// Get MySQL config
val mysqlConfig = getSecret("dstreambolt/mysql")
val host = mysqlConfig("host")
val password = mysqlConfig("password")
```

### Bash (Shell Scripts)

```bash
# Get MySQL password
MYSQL_PASS=$(aws secretsmanager get-secret-value \
  --secret-id dstreambolt/mysql \
  --region ap-south-1 \
  --query SecretString \
  --output text | jq -r '.password')

# Get Kafka broker
KAFKA_BROKER=$(aws secretsmanager get-secret-value \
  --secret-id dstreambolt/kafka \
  --region ap-south-1 \
  --query SecretString \
  --output text | jq -r '.bootstrap_servers')
```

## 🔄 Updating Secrets

### Update MySQL Password

```bash
aws secretsmanager update-secret \
  --secret-id dstreambolt/mysql \
  --secret-string '{
    "host": "10.0.1.68",
    "port": "3306",
    "username": "root",
    "password": "NewSecurePassword456!",
    "database": "dstreambolt_metrics"
  }' \
  --region ap-south-1
```

After updating, restart affected services:

```bash
# Restart ingestion service
ssh ubuntu@<ingest-ip> 'sudo systemctl restart dstreambolt-ingest'

# Restart Spark job
ssh ubuntu@<spark-ip> 'pkill -f SparkProcessor && cd /opt/dstreambolt/computations && ./submit_job.sh'
```

### Update Kafka Configuration

```bash
aws secretsmanager update-secret \
  --secret-id dstreambolt/kafka \
  --secret-string '{
    "bootstrap_servers": "10.0.10.248:9092",
    "topic": "dstreambolt-logs"
  }' \
  --region ap-south-1
```

## 🔍 Viewing Secrets

### View Secret Value

```bash
# View MySQL secret
aws secretsmanager get-secret-value \
  --secret-id dstreambolt/mysql \
  --region ap-south-1 \
  --query SecretString \
  --output text | jq .

# View Kafka secret
aws secretsmanager get-secret-value \
  --secret-id dstreambolt/kafka \
  --region ap-south-1 \
  --query SecretString \
  --output text | jq .
```

### List All Secrets

```bash
aws secretsmanager list-secrets \
  --region ap-south-1 \
  --query "SecretList[?starts_with(Name, 'dstreambolt/')].Name" \
  --output table
```

## 🔐 IAM Permissions

EC2 instances need the following IAM policy attached:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:ap-south-1:*:secret:dstreambolt/*"
    }
  ]
}
```

This is automatically configured via Terraform in the EC2 instance profiles.

## 🗑️ Deleting Secrets

```bash
# Schedule deletion (minimum 7 days)
aws secretsmanager delete-secret \
  --secret-id dstreambolt/mysql \
  --recovery-window-in-days 7 \
  --region ap-south-1

# Cancel deletion
aws secretsmanager restore-secret \
  --secret-id dstreambolt/mysql \
  --region ap-south-1

# Force delete immediately (use with caution!)
aws secretsmanager delete-secret \
  --secret-id dstreambolt/mysql \
  --force-delete-without-recovery \
  --region ap-south-1
```

## 🔄 Secret Rotation

AWS Secrets Manager supports automatic secret rotation. To enable:

```bash
aws secretsmanager rotate-secret \
  --secret-id dstreambolt/mysql \
  --rotation-rules AutomaticallyAfterDays=30 \
  --region ap-south-1
```

⚠️ **Note:** Automatic rotation requires a Lambda function to update the password in MySQL and restart dependent services.

## 🛡️ Security Best Practices

1. ✅ **Use IAM Instance Profiles** - Never hardcode AWS credentials
2. ✅ **Least Privilege** - Grant only necessary permissions
3. ✅ **Enable CloudTrail** - Audit secret access
4. ✅ **Rotate Regularly** - Change passwords periodically
5. ✅ **Use Versioning** - Secrets Manager maintains version history
6. ✅ **Tag Secrets** - Use tags for organization and billing

## 📊 Monitoring Secret Access

### CloudTrail Events

Monitor secret access via CloudTrail:

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=GetSecretValue \
  --region ap-south-1 \
  --max-items 10
```

### CloudWatch Alarms

Set up alarms for unusual secret access patterns:

```bash
# Create metric filter for failed secret access
aws logs put-metric-filter \
  --log-group-name /aws/secretsmanager \
  --filter-name FailedSecretAccess \
  --filter-pattern '[... , status = "AccessDenied"]' \
  --metric-transformations \
    metricName=FailedSecretAccess,\
metricNamespace=DStreamBolt,\
metricValue=1
```

## 🧪 Testing Secret Access

### Test from EC2 Instance

```bash
# SSH to any DStreamBolt instance
ssh -i ~/dstreambolt-access-key.pem ubuntu@<instance-ip>

# Test secret access
aws secretsmanager get-secret-value \
  --secret-id dstreambolt/mysql \
  --region ap-south-1 \
  --query SecretString \
  --output text

# Should return the secret JSON
```

### Test from Local Machine

```bash
# Requires AWS CLI configured with credentials
aws secretsmanager get-secret-value \
  --secret-id dstreambolt/mysql \
  --region ap-south-1 \
  --query SecretString \
  --output text | jq .
```

## 💰 Costs

AWS Secrets Manager pricing:
- $0.40 per secret per month
- $0.05 per 10,000 API calls

Current setup:
- 2-3 secrets = ~$1.20/month
- API calls are minimal (fetched at service startup)

Total estimated cost: **~$1-2/month**

## 🔧 Troubleshooting

### Secret Not Found

```bash
# Check if secret exists
aws secretsmanager describe-secret \
  --secret-id dstreambolt/mysql \
  --region ap-south-1

# If not found, create it using Terraform or AWS CLI
```

### Access Denied

```bash
# Check IAM instance profile
aws sts get-caller-identity

# Check IAM policy attached to instance profile
aws iam list-attached-role-policies \
  --role-name DStreamBolt-EC2-Role

# Verify policy includes secretsmanager:GetSecretValue
```

### Service Not Reading Secrets

```bash
# Check service logs
sudo journalctl -u dstreambolt-ingest -n 100 | grep -i secret

# Verify AWS SDK configuration
python3 -c "import boto3; print(boto3.client('secretsmanager', region_name='ap-south-1').list_secrets())"
```

---

**See Also:**
- [AWS Secrets Manager Documentation](https://docs.aws.amazon.com/secretsmanager/)
- [README.md](README.md) - Main documentation
- [QUICK_REFERENCE.md](QUICK_REFERENCE.md) - Quick commands

