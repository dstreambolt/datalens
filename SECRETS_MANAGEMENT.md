# DStreamBolt Secrets Management - Production Security

## Date
December 11, 2025

## Executive Summary

**Current Issue**: Passwords and sensitive credentials stored in environment variables  
**Security Risk**: High - Credentials visible in process lists, logs, and configuration files  
**Solution**: AWS Secrets Manager + Encrypted configuration files + IAM-based access control  
**Compliance**: Meets SOC 2, ISO 27001, PCI-DSS requirements for production systems

---

## Security Issues with Current Approach

### ❌ Environment Variables (Current Implementation)

```python
# INSECURE - Current implementation
MYSQL_PASSWORD = os.getenv('MYSQL_PASSWORD', 'DStreamBolt2025!')
```

**Problems:**
1. ✗ Visible in process lists (`ps aux | grep python`)
2. ✗ Exposed in system logs (`/var/log/syslog`, CloudWatch Logs)
3. ✗ Visible to all processes on the same host
4. ✗ Hard to rotate without service restart
5. ✗ No audit trail of secret access
6. ✗ Passwords in plain text in config files/systemd units
7. ✗ **Fails security audit requirements**

---

## Recommended Solution: AWS Secrets Manager

### ✅ Why AWS Secrets Manager?

1. **Centralized Management** - Single source of truth for all secrets
2. **Automatic Rotation** - Built-in rotation for RDS, Kafka, etc.
3. **Encryption at Rest** - AES-256 encryption using AWS KMS
4. **Encryption in Transit** - TLS 1.2+ for all API calls
5. **Audit Trail** - CloudTrail logs every secret access
6. **IAM Integration** - Fine-grained access control per service
7. **No Code Changes** - Secrets fetched at runtime
8. **Secret Versioning** - Track all changes with rollback capability
9. **Cost Effective** - $0.40 per secret per month + $0.05 per 10,000 API calls
10. **Compliance Ready** - Meets SOC 2, ISO 27001, PCI-DSS, HIPAA

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    AWS Secrets Manager                      │
│  ┌──────────────────┐  ┌──────────────────┐                │
│  │  dstreambolt/    │  │  dstreambolt/    │                │
│  │  mysql           │  │  kafka           │                │
│  │                  │  │                  │                │
│  │ {                │  │ {                │                │
│  │  "host": "...",  │  │  "brokers": [...],│               │
│  │  "user": "...",  │  │  "sasl_user":"...",│              │
│  │  "password":"..."│  │  "sasl_pass":"..."│               │
│  │ }                │  │ }                │                │
│  └──────────────────┘  └──────────────────┘                │
│           ▲                      ▲                          │
│           │                      │                          │
│           │  Encrypted (KMS)     │                          │
│           │                      │                          │
└───────────┼──────────────────────┼──────────────────────────┘
            │                      │
            │  IAM Policy          │
            │  (Get Secret)        │
            │                      │
    ┌───────┴──────────────────────┴────────┐
    │   EC2 Instance (dstreambolt-ingest)   │
    │   ┌─────────────────────────────────┐ │
    │   │  IAM Role:                      │ │
    │   │  dstreambolt-ingest-role        │ │
    │   │                                 │ │
    │   │  Allowed:                       │ │
    │   │  - secretsmanager:GetSecretValue│ │
    │   │  - kms:Decrypt                  │ │
    │   └─────────────────────────────────┘ │
    │                                       │
    │   app.py (loads secrets at startup)   │
    └───────────────────────────────────────┘
```

---

## Implementation

### Step 1: Create Secrets in AWS Secrets Manager

#### 1.1 MySQL Credentials

```bash
# Create MySQL secret
aws secretsmanager create-secret \
  --name dstreambolt/mysql \
  --description "DStreamBolt MySQL database credentials" \
  --secret-string '{
    "host": "10.0.1.61",
    "port": 3306,
    "username": "dstreambolt",
    "password": "DStreamBolt2025!",
    "database": "dstreambolt_metrics"
  }' \
  --region ap-south-1

# Tag for organization
aws secretsmanager tag-resource \
  --secret-id dstreambolt/mysql \
  --tags Key=Project,Value=DStreamBolt \
         Key=Environment,Value=Production \
         Key=Component,Value=Database \
  --region ap-south-1
```

#### 1.2 Kafka Credentials (if SASL enabled)

```bash
aws secretsmanager create-secret \
  --name dstreambolt/kafka \
  --description "DStreamBolt Kafka broker credentials" \
  --secret-string '{
    "brokers": ["10.0.10.101:9092"],
    "topic": "dstreambolt-logs",
    "sasl_mechanism": "PLAIN",
    "sasl_username": "dstreambolt",
    "sasl_password": "KafkaPassword2025!",
    "security_protocol": "SASL_PLAINTEXT"
  }' \
  --region ap-south-1
```

#### 1.3 Application Secrets

```bash
aws secretsmanager create-secret \
  --name dstreambolt/app \
  --description "DStreamBolt application secrets" \
  --secret-string '{
    "api_keys": ["key1", "key2", "key3"],
    "encryption_key": "base64_encoded_key",
    "jwt_secret": "if_needed_in_future"
  }' \
  --region ap-south-1
```

---

### Step 2: IAM Policy for Secret Access

```json
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
        "arn:aws:secretsmanager:ap-south-1:ACCOUNT_ID:secret:dstreambolt/*"
      ]
    },
    {
      "Sid": "AllowKMSDecrypt",
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt",
        "kms:DescribeKey"
      ],
      "Resource": "arn:aws:kms:ap-south-1:ACCOUNT_ID:key/KEY_ID"
    }
  ]
}
```

**Attach to IAM Role:**
```bash
# Create IAM policy
aws iam create-policy \
  --policy-name DStreamBoltSecretsAccess \
  --policy-document file://secrets-policy.json

# Attach to EC2 instance role
aws iam attach-role-policy \
  --role-name dstreambolt-ingest-role \
  --policy-arn arn:aws:iam::ACCOUNT_ID:policy/DStreamBoltSecretsAccess
```

---

### Step 3: Update app.py to Use Secrets Manager

**Create secrets helper module:**

```python
# File: ingestion/secrets_manager.py
"""
AWS Secrets Manager integration for DStreamBolt
Fetches secrets securely at runtime with caching
"""
import boto3
import json
import time
from botocore.exceptions import ClientError

class SecretsManager:
    """
    Secrets Manager with caching and error handling
    """
    
    def __init__(self, region_name='ap-south-1'):
        self.client = boto3.client('secretsmanager', region_name=region_name)
        self.cache = {}
        self.cache_ttl = 300  # 5 minutes cache
        self.cache_timestamps = {}
    
    def get_secret(self, secret_name):
        """
        Get secret from AWS Secrets Manager with caching
        
        Args:
            secret_name: Name of the secret (e.g., 'dstreambolt/mysql')
            
        Returns:
            dict: Parsed secret value
            
        Raises:
            Exception: If secret cannot be retrieved
        """
        # Check cache first
        if secret_name in self.cache:
            cached_time = self.cache_timestamps.get(secret_name, 0)
            if time.time() - cached_time < self.cache_ttl:
                return self.cache[secret_name]
        
        try:
            print(f"🔐 Fetching secret: {secret_name}")
            
            response = self.client.get_secret_value(SecretId=secret_name)
            
            # Parse secret string
            if 'SecretString' in response:
                secret = json.loads(response['SecretString'])
            else:
                # Binary secret (not expected for our use case)
                secret = response['SecretBinary']
            
            # Cache the secret
            self.cache[secret_name] = secret
            self.cache_timestamps[secret_name] = time.time()
            
            print(f"✅ Secret loaded: {secret_name}")
            return secret
            
        except ClientError as e:
            error_code = e.response['Error']['Code']
            
            if error_code == 'ResourceNotFoundException':
                raise Exception(f"Secret '{secret_name}' not found")
            elif error_code == 'InvalidRequestException':
                raise Exception(f"Invalid request for secret '{secret_name}'")
            elif error_code == 'InvalidParameterException':
                raise Exception(f"Invalid parameter for secret '{secret_name}'")
            elif error_code == 'AccessDeniedException':
                raise Exception(f"Access denied to secret '{secret_name}' - check IAM permissions")
            else:
                raise Exception(f"Error retrieving secret '{secret_name}': {str(e)}")
    
    def get_mysql_config(self):
        """Get MySQL configuration"""
        secret = self.get_secret('dstreambolt/mysql')
        return {
            'host': secret['host'],
            'port': secret.get('port', 3306),
            'user': secret['username'],
            'password': secret['password'],
            'database': secret['database']
        }
    
    def get_kafka_config(self):
        """Get Kafka configuration"""
        secret = self.get_secret('dstreambolt/kafka')
        return {
            'brokers': secret['brokers'],
            'topic': secret.get('topic', 'dstreambolt-logs'),
            'sasl_mechanism': secret.get('sasl_mechanism'),
            'sasl_username': secret.get('sasl_username'),
            'sasl_password': secret.get('sasl_password'),
            'security_protocol': secret.get('security_protocol', 'PLAINTEXT')
        }
    
    def get_app_secrets(self):
        """Get application secrets"""
        try:
            return self.get_secret('dstreambolt/app')
        except:
            # Return empty dict if app secrets don't exist yet
            return {}
    
    def refresh_cache(self):
        """Force refresh all cached secrets"""
        self.cache.clear()
        self.cache_timestamps.clear()
        print("🔄 Secrets cache cleared")


# Global instance
_secrets_manager = None

def get_secrets_manager():
    """Get or create global SecretsManager instance"""
    global _secrets_manager
    if _secrets_manager is None:
        _secrets_manager = SecretsManager()
    return _secrets_manager
```

**Update app.py to use Secrets Manager:**

```python
# File: ingestion/app.py
# Add at the top after imports:

from secrets_manager import get_secrets_manager

# Replace configuration section:

# ============================================================================
# CONFIGURATION - Load secrets from AWS Secrets Manager
# ============================================================================

# Initialize secrets manager
secrets_mgr = get_secrets_manager()

try:
    # Load MySQL configuration
    mysql_config = secrets_mgr.get_mysql_config()
    MYSQL_HOST = mysql_config['host']
    MYSQL_USER = mysql_config['user']
    MYSQL_PASSWORD = mysql_config['password']
    MYSQL_DB = mysql_config['database']
    MYSQL_PORT = mysql_config.get('port', 3306)
    
    # Load Kafka configuration
    kafka_config = secrets_mgr.get_kafka_config()
    KAFKA_BROKER = ','.join(kafka_config['brokers']) if isinstance(kafka_config['brokers'], list) else kafka_config['brokers']
    KAFKA_TOPIC = kafka_config['topic']
    
    # Optional: Load app secrets
    try:
        app_secrets = secrets_mgr.get_app_secrets()
        VALID_API_KEYS = set(app_secrets.get('api_keys', []))
    except:
        VALID_API_KEYS = set()
    
    print("✅ Secrets loaded from AWS Secrets Manager")
    
except Exception as e:
    print(f"❌ Failed to load secrets: {e}")
    print("⚠️  Falling back to environment variables (NOT RECOMMENDED FOR PRODUCTION)")
    
    # Fallback to environment variables (for dev/testing only)
    MYSQL_HOST = os.getenv('MYSQL_HOST', '10.0.1.61')
    MYSQL_USER = os.getenv('MYSQL_USER', 'dstreambolt')
    MYSQL_PASSWORD = os.getenv('MYSQL_PASSWORD', '')
    MYSQL_DB = os.getenv('MYSQL_DB', 'dstreambolt_metrics')
    MYSQL_PORT = 3306
    
    KAFKA_BROKER = os.getenv('KAFKA_BROKER', '10.0.10.101:9092')
    KAFKA_TOPIC = os.getenv('KAFKA_TOPIC', 'dstreambolt-logs')
    
    VALID_API_KEYS = set()

# Other configuration (non-secret)
QUEUE_DIR = os.getenv('QUEUE_DIR', '/opt/dstreambolt/queue')
MAX_QUEUE_SIZE = int(os.getenv('MAX_QUEUE_SIZE', '10000'))
# ... etc
```

---

### Step 4: Update Spark Processor (Scala)

**Create Secrets Manager helper for Spark:**

```scala
// File: computations/src/main/scala/com/dstreambolt/util/SecretsManager.scala
package com.dstreambolt.util

import software.amazon.awssdk.regions.Region
import software.amazon.awssdk.services.secretsmanager.SecretsManagerClient
import software.amazon.awssdk.services.secretsmanager.model.GetSecretValueRequest
import com.fasterxml.jackson.databind.ObjectMapper
import scala.util.{Try, Success, Failure}

object SecretsManager {
  
  private val client: SecretsManagerClient = SecretsManagerClient.builder()
    .region(Region.AP_SOUTH_1)
    .build()
  
  private val objectMapper = new ObjectMapper()
  
  /**
   * Get secret from AWS Secrets Manager
   */
  def getSecret(secretName: String): Map[String, Any] = {
    Try {
      val request = GetSecretValueRequest.builder()
        .secretId(secretName)
        .build()
      
      val response = client.getSecretValue(request)
      val secretString = response.secretString()
      
      // Parse JSON
      val jsonNode = objectMapper.readTree(secretString)
      val fields = jsonNode.fields()
      
      var result = Map.empty[String, Any]
      while (fields.hasNext) {
        val entry = fields.next()
        result = result + (entry.getKey -> entry.getValue.asText())
      }
      
      result
    } match {
      case Success(secret) => secret
      case Failure(e) =>
        println(s"❌ Failed to load secret '$secretName': ${e.getMessage}")
        throw e
    }
  }
  
  /**
   * Get MySQL configuration
   */
  def getMySQLConfig: (String, Int, String, String, String) = {
    val secret = getSecret("dstreambolt/mysql")
    (
      secret("host").toString,
      secret.getOrElse("port", "3306").toString.toInt,
      secret("username").toString,
      secret("password").toString,
      secret("database").toString
    )
  }
  
  /**
   * Get Kafka configuration
   */
  def getKafkaConfig: (String, String) = {
    val secret = getSecret("dstreambolt/kafka")
    val brokers = secret("brokers") match {
      case list: java.util.List[_] => list.toArray.mkString(",")
      case str: String => str
    }
    (brokers, secret.getOrElse("topic", "dstreambolt-logs").toString)
  }
}
```

**Add to build.sbt:**
```scala
libraryDependencies ++= Seq(
  // ... existing dependencies ...
  "software.amazon.awssdk" % "secretsmanager" % "2.20.0",
  "com.fasterxml.jackson.core" % "jackson-databind" % "2.15.0"
)
```

---

## Alternative: Encrypted Configuration Files

If you cannot use AWS Secrets Manager (e.g., cost constraints, on-premise), use encrypted configuration files:

### Using `ansible-vault` or `sops`

#### Option A: sops (Secrets OPerationS)

```bash
# Install sops
wget https://github.com/mozilla/sops/releases/download/v3.7.3/sops-v3.7.3.linux
sudo mv sops-v3.7.3.linux /usr/local/bin/sops
sudo chmod +x /usr/local/bin/sops

# Create KMS key for encryption
aws kms create-key --description "DStreamBolt secrets encryption"

# Create secrets file
cat > secrets.yaml << EOF
mysql:
  host: 10.0.1.61
  username: dstreambolt
  password: DStreamBolt2025!
  database: dstreambolt_metrics

kafka:
  brokers:
    - 10.0.10.101:9092
  topic: dstreambolt-logs
EOF

# Encrypt with sops + KMS
sops --encrypt --kms 'arn:aws:kms:ap-south-1:ACCOUNT_ID:key/KEY_ID' secrets.yaml > secrets.enc.yaml

# Deploy encrypted file to server
scp secrets.enc.yaml ubuntu@ingest-server:/etc/dstreambolt/

# Decrypt at runtime (requires IAM permissions)
sops --decrypt /etc/dstreambolt/secrets.enc.yaml
```

**Python code to load encrypted secrets:**
```python
import subprocess
import yaml

def load_encrypted_secrets(filepath='/etc/dstreambolt/secrets.enc.yaml'):
    """Decrypt and load secrets using sops"""
    try:
        result = subprocess.run(
            ['sops', '--decrypt', filepath],
            capture_output=True,
            text=True,
            check=True
        )
        return yaml.safe_load(result.stdout)
    except subprocess.CalledProcessError as e:
        raise Exception(f"Failed to decrypt secrets: {e}")

# Usage
secrets = load_encrypted_secrets()
MYSQL_PASSWORD = secrets['mysql']['password']
```

---

## Security Comparison

| Feature | Environment Variables | Encrypted Files | AWS Secrets Manager |
|---------|----------------------|-----------------|---------------------|
| **Encryption at rest** | ❌ No | ✅ Yes | ✅ Yes (KMS) |
| **Encryption in transit** | ❌ No | ⚠️ Manual | ✅ Yes (TLS) |
| **Audit trail** | ❌ No | ⚠️ Limited | ✅ Complete (CloudTrail) |
| **Automatic rotation** | ❌ No | ❌ No | ✅ Yes |
| **Access control** | ⚠️ OS-level | ⚠️ OS-level | ✅ IAM policies |
| **Versioning** | ❌ No | ⚠️ Manual | ✅ Automatic |
| **Secret sharing** | ❌ Insecure | ⚠️ Manual | ✅ Secure API |
| **Cost** | Free | Free | ~$0.40/month |
| **Compliance** | ❌ Fails audits | ⚠️ Depends | ✅ SOC 2, ISO 27001 |
| **Production ready** | ❌ No | ⚠️ With care | ✅ Yes |

---

## Recommended Approach for DStreamBolt

### For Production (Customer-facing after audit):
✅ **Use AWS Secrets Manager** - Best practice, audit-ready, fully managed

### For Development/Testing:
⚠️ **Use encrypted files with sops** - Cost-effective, still secure

### Never Use:
❌ Plain text environment variables
❌ Hardcoded passwords in code
❌ Unencrypted configuration files

---

## Implementation Checklist

Production deployment:

- [ ] Create AWS KMS key for encryption
- [ ] Create secrets in AWS Secrets Manager
- [ ] Configure IAM policies for secret access
- [ ] Attach IAM role to EC2 instances
- [ ] Install boto3: `pip install boto3`
- [ ] Create secrets_manager.py helper
- [ ] Update app.py to use Secrets Manager
- [ ] Update SparkProcessor.scala (if needed)
- [ ] Remove environment variables from systemd units
- [ ] Test secret rotation
- [ ] Document secret access in security audit
- [ ] Enable CloudTrail logging for secrets access
- [ ] Set up monitoring/alerting for failed secret access

---

## Cost Analysis

### AWS Secrets Manager Costs (Production)

```
Secrets stored: 3 (MySQL, Kafka, App)
Cost per secret: $0.40/month
API calls: ~10,000/month (startup + periodic refresh)
Cost per 10K calls: $0.05

Total monthly cost: (3 × $0.40) + ($0.05) = $1.25/month
Annual cost: $15/year
```

**ROI**: Worth every penny for:
- ✅ Security compliance
- ✅ Audit requirements
- ✅ Automatic rotation
- ✅ Prevented data breaches (priceless)

---

## Migration Plan

1. **Week 1**: Set up AWS Secrets Manager + IAM policies
2. **Week 2**: Implement secrets_manager.py module
3. **Week 3**: Update app.py and test in staging
4. **Week 4**: Update Spark processors
5. **Week 5**: Deploy to production with rollback plan
6. **Week 6**: Remove all environment variables, verify audit compliance

---

## Support

For questions:
- **AWS Secrets Manager Docs**: https://docs.aws.amazon.com/secretsmanager/
- **IAM Best Practices**: https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html
- **SOPS**: https://github.com/mozilla/sops

---

**Prepared by**: GitHub Copilot  
**Date**: December 11, 2025  
**Status**: Ready for implementation  
**Priority**: **HIGH** - Required before security audit

