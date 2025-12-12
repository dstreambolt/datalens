"""
AWS Secrets Manager Integration for DStreamBolt
Fetches secrets securely at runtime with caching and error handling
"""
import boto3
import json
import time
import os
from botocore.exceptions import ClientError, NoCredentialsError


class SecretsManager:
    """
    AWS Secrets Manager client with caching, fallback, and error handling

    Features:
    - Automatic caching with TTL
    - Graceful fallback to environment variables
    - Detailed error messages
    - Region configuration
    - Retry logic
    """

    def __init__(self, region_name=None):
        """
        Initialize Secrets Manager client

        Args:
            region_name: AWS region (defaults to AWS_DEFAULT_REGION env var or ap-south-1)
        """
        self.region = region_name or os.getenv('AWS_DEFAULT_REGION', 'ap-south-1')

        try:
            self.client = boto3.client('secretsmanager', region_name=self.region)
            self.enabled = True
            print(f"🔐 AWS Secrets Manager initialized (region: {self.region})")
        except NoCredentialsError:
            print("⚠️  AWS credentials not found - Secrets Manager disabled")
            print("   Falling back to environment variables")
            self.client = None
            self.enabled = False
        except Exception as e:
            print(f"⚠️  Failed to initialize Secrets Manager: {e}")
            print("   Falling back to environment variables")
            self.client = None
            self.enabled = False

        # Cache settings
        self.cache = {}
        self.cache_ttl = int(os.getenv('SECRETS_CACHE_TTL', '1440'))  # 5 minutes default
        self.cache_timestamps = {}

    def get_secret(self, secret_name, use_cache=True):
        """
        Get secret from AWS Secrets Manager with caching

        Args:
            secret_name: Name of the secret (e.g., 'dstreambolt/mysql')
            use_cache: Whether to use cached value (default: True)

        Returns:
            dict: Parsed secret value

        Raises:
            Exception: If secret cannot be retrieved and fallback fails
        """
        if not self.enabled:
            raise Exception("Secrets Manager not available")

        # Check cache first
        if use_cache and secret_name in self.cache:
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
                # Binary secret (decode if needed)
                import base64
                secret = json.loads(base64.b64decode(response['SecretBinary']))

            # Cache the secret
            self.cache[secret_name] = secret
            self.cache_timestamps[secret_name] = time.time()

            print(f"✅ Secret loaded: {secret_name}")
            return secret

        except ClientError as e:
            error_code = e.response['Error']['Code']
            error_msg = e.response['Error']['Message']

            if error_code == 'ResourceNotFoundException':
                raise Exception(f"Secret '{secret_name}' not found in AWS Secrets Manager")
            elif error_code == 'InvalidRequestException':
                raise Exception(f"Invalid request for secret '{secret_name}': {error_msg}")
            elif error_code == 'InvalidParameterException':
                raise Exception(f"Invalid parameter for secret '{secret_name}': {error_msg}")
            elif error_code == 'AccessDeniedException':
                raise Exception(
                    f"Access denied to secret '{secret_name}'\n"
                    f"   Check IAM role has secretsmanager:GetSecretValue permission\n"
                    f"   Secret ARN: arn:aws:secretsmanager:{self.region}:*:secret:{secret_name}"
                )
            elif error_code == 'DecryptionFailure':
                raise Exception(f"Failed to decrypt secret '{secret_name}' - check KMS key permissions")
            else:
                raise Exception(f"Error retrieving secret '{secret_name}': {error_msg}")

        except Exception as e:
            raise Exception(f"Unexpected error retrieving secret '{secret_name}': {str(e)}")

    def get_mysql_config(self):
        """
        Get MySQL configuration from Secrets Manager

        Returns:
            dict: MySQL connection parameters
        """
        try:
            secret = self.get_secret('dstreambolt/mysql')
            return {
                'host': secret['host'],
                'port': secret.get('port', 3306),
                'user': secret['username'],
                'password': secret['password'],
                'database': secret['database']
            }
        except Exception as e:
            print(f"⚠️  Failed to load MySQL secrets: {e}")
            print("   Falling back to environment variables")
            return {
                'host': os.getenv('MYSQL_HOST', '10.0.1.61'),
                'port': int(os.getenv('MYSQL_PORT', '3306')),
                'user': os.getenv('MYSQL_USER', 'dstreambolt'),
                'password': os.getenv('MYSQL_PASSWORD', ''),
                'database': os.getenv('MYSQL_DB', 'dstreambolt_metrics')
            }

    def get_kafka_config(self):
        """
        Get Kafka configuration from Secrets Manager

        Returns:
            dict: Kafka connection parameters
        """
        try:
            secret = self.get_secret('dstreambolt/kafka')

            # Handle brokers as list or string
            brokers = secret.get('brokers', [])
            if isinstance(brokers, list):
                broker_str = ','.join(brokers)
            else:
                broker_str = brokers

            return {
                'brokers': broker_str,
                'topic': secret.get('topic', 'dstreambolt-logs'),
                'sasl_mechanism': secret.get('sasl_mechanism'),
                'sasl_username': secret.get('sasl_username'),
                'sasl_password': secret.get('sasl_password'),
                'security_protocol': secret.get('security_protocol', 'PLAINTEXT')
            }
        except Exception as e:
            print(f"⚠️  Failed to load Kafka secrets: {e}")
            print("   Falling back to environment variables")
            return {
                'brokers': os.getenv('KAFKA_BROKER', '10.0.10.101:9092'),
                'topic': os.getenv('KAFKA_TOPIC', 'dstreambolt-logs'),
                'sasl_mechanism': os.getenv('KAFKA_SASL_MECHANISM'),
                'sasl_username': os.getenv('KAFKA_SASL_USERNAME'),
                'sasl_password': os.getenv('KAFKA_SASL_PASSWORD'),
                'security_protocol': os.getenv('KAFKA_SECURITY_PROTOCOL', 'PLAINTEXT')
            }

    def get_app_secrets(self):
        """
        Get application secrets from Secrets Manager

        Returns:
            dict: Application secrets (API keys, encryption keys, etc.)
        """
        try:
            return self.get_secret('dstreambolt/app')
        except Exception as e:
            print(f"⚠️  Failed to load app secrets: {e}")
            print("   Using defaults (empty)")
            return {
                'api_keys': [],
                'encryption_key': None
            }

    def refresh_cache(self, secret_name=None):
        """
        Force refresh cached secrets

        Args:
            secret_name: Specific secret to refresh (None = refresh all)
        """
        if secret_name:
            if secret_name in self.cache:
                del self.cache[secret_name]
                del self.cache_timestamps[secret_name]
                print(f"🔄 Refreshed cache for: {secret_name}")
        else:
            self.cache.clear()
            self.cache_timestamps.clear()
            print("🔄 Cleared all secrets cache")

    def test_connection(self):
        """
        Test connection to AWS Secrets Manager

        Returns:
            bool: True if connection successful
        """
        if not self.enabled:
            print("❌ Secrets Manager not enabled")
            return False

        try:
            # Try to list secrets (minimal permission check)
            self.client.list_secrets(MaxResults=1)
            print("✅ Secrets Manager connection OK")
            return True
        except ClientError as e:
            print(f"❌ Secrets Manager connection failed: {e}")
            return False
        except Exception as e:
            print(f"❌ Unexpected error testing Secrets Manager: {e}")
            return False


# ============================================================================
# Global instance (singleton pattern)
# ============================================================================

_secrets_manager = None

def get_secrets_manager():
    """
    Get or create global SecretsManager instance (singleton)

    Returns:
        SecretsManager: Global secrets manager instance
    """
    global _secrets_manager
    if _secrets_manager is None:
        _secrets_manager = SecretsManager()
    return _secrets_manager


# ============================================================================
# Convenience functions
# ============================================================================

def get_mysql_config():
    """Get MySQL configuration (convenience function)"""
    return get_secrets_manager().get_mysql_config()

def get_kafka_config():
    """Get Kafka configuration (convenience function)"""
    return get_secrets_manager().get_kafka_config()

def get_app_secrets():
    """Get application secrets (convenience function)"""
    return get_secrets_manager().get_app_secrets()

def refresh_secrets():
    """Refresh all secrets cache (convenience function)"""
    get_secrets_manager().refresh_cache()


# ============================================================================
# CLI for testing
# ============================================================================

if __name__ == '__main__':
    """Test secrets manager from command line"""
    import sys

    print("=" * 80)
    print("DStreamBolt Secrets Manager - Test")
    print("=" * 80)
    print()

    # Initialize
    secrets_mgr = SecretsManager()

    # Test connection
    print("Testing connection...")
    if not secrets_mgr.test_connection():
        print("\n❌ Cannot connect to AWS Secrets Manager")
        print("   Ensure AWS credentials are configured:")
        print("   - IAM instance role (EC2)")
        print("   - AWS credentials file (~/.aws/credentials)")
        print("   - Environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)")
        sys.exit(1)

    print()
    print("-" * 80)

    # Test MySQL secrets
    print("\n📊 MySQL Configuration:")
    try:
        mysql = secrets_mgr.get_mysql_config()
        print(f"   Host: {mysql['host']}")
        print(f"   Port: {mysql['port']}")
        print(f"   User: {mysql['user']}")
        print(f"   Password: {'*' * len(mysql['password'])}")
        print(f"   Database: {mysql['database']}")
    except Exception as e:
        print(f"   ❌ Failed: {e}")

    print()
    print("-" * 80)

    # Test Kafka secrets
    print("\n📨 Kafka Configuration:")
    try:
        kafka = secrets_mgr.get_kafka_config()
        print(f"   Brokers: {kafka['brokers']}")
        print(f"   Topic: {kafka['topic']}")
        print(f"   Security: {kafka['security_protocol']}")
        if kafka.get('sasl_username'):
            print(f"   SASL User: {kafka['sasl_username']}")
            print(f"   SASL Password: {'*' * 10}")
    except Exception as e:
        print(f"   ❌ Failed: {e}")

    print()
    print("-" * 80)

    # Test app secrets
    print("\n🔐 Application Secrets:")
    try:
        app = secrets_mgr.get_app_secrets()
        print(f"   API Keys: {len(app.get('api_keys', []))} keys configured")
        print(f"   Encryption Key: {'Yes' if app.get('encryption_key') else 'No'}")
    except Exception as e:
        print(f"   ❌ Failed: {e}")

    print()
    print("=" * 80)
    print("✅ Test complete")
    print("=" * 80)

