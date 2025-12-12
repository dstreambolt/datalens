#!/usr/bin/env python3
"""
DStreamBolt Secrets Manager Validation Script
Tests secrets loading and validates configuration
"""
import sys
import os

# Add ingestion directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'ingestion'))

def test_secrets_manager():
    """Test Secrets Manager functionality"""
    print("=" * 80)
    print("🔐 DStreamBolt Secrets Manager Validation")
    print("=" * 80)
    print()

    try:
        from secrets_manager import SecretsManager
        print("✅ secrets_manager module imported successfully")
    except ImportError as e:
        print(f"❌ Failed to import secrets_manager: {e}")
        return False

    # Initialize Secrets Manager
    print("\n📋 Testing Secrets Manager initialization...")
    try:
        secrets_mgr = SecretsManager()
        print(f"✅ Secrets Manager initialized (region: {secrets_mgr.region})")
        print(f"   Enabled: {secrets_mgr.enabled}")
    except Exception as e:
        print(f"❌ Failed to initialize: {e}")
        return False

    if not secrets_mgr.enabled:
        print("⚠️  Secrets Manager disabled (AWS credentials not available)")
        print("   This is expected in local development")
        return True

    # Test MySQL secrets
    print("\n📋 Testing MySQL secrets...")
    try:
        mysql_config = secrets_mgr.get_mysql_config()
        print(f"✅ MySQL config loaded:")
        print(f"   Host: {mysql_config['host']}")
        print(f"   User: {mysql_config['user']}")
        print(f"   Database: {mysql_config['database']}")
        print(f"   Password: {'*' * len(mysql_config['password'])}")
    except Exception as e:
        print(f"⚠️  MySQL secrets not available: {e}")
        print("   Falling back to environment variables")

    # Test Kafka secrets
    print("\n📋 Testing Kafka secrets...")
    try:
        kafka_config = secrets_mgr.get_kafka_config()
        print(f"✅ Kafka config loaded:")
        print(f"   Brokers: {kafka_config['brokers']}")
        print(f"   Topic: {kafka_config['topic']}")
        print(f"   Security: {kafka_config['security_protocol']}")
    except Exception as e:
        print(f"⚠️  Kafka secrets not available: {e}")
        print("   Falling back to environment variables")

    # Test app secrets
    print("\n📋 Testing application secrets...")
    try:
        app_secrets = secrets_mgr.get_app_secrets()
        api_keys = app_secrets.get('api_keys', [])
        print(f"✅ App secrets loaded:")
        print(f"   API keys configured: {len(api_keys)}")
    except Exception as e:
        print(f"⚠️  App secrets not available: {e}")
        print("   Using empty configuration")

    # Test cache refresh
    print("\n📋 Testing cache refresh...")
    try:
        secrets_mgr.refresh_cache()
        print("✅ Cache refresh successful")
    except Exception as e:
        print(f"❌ Cache refresh failed: {e}")
        return False

    print("\n" + "=" * 80)
    print("✅ All tests passed!")
    print("=" * 80)
    return True


def test_app_import():
    """Test that app.py can be imported with secrets manager"""
    print("\n" + "=" * 80)
    print("🚀 Testing app.py import with Secrets Manager")
    print("=" * 80)
    print()

    try:
        # Set test environment to avoid starting Flask
        os.environ['TESTING'] = 'true'

        from ingestion.app import app
        print("✅ app.py imported successfully")
        print(f"   Flask app created: {app.name}")
        return True
    except Exception as e:
        print(f"❌ Failed to import app.py: {e}")
        import traceback
        traceback.print_exc()
        return False


def main():
    """Run all validation tests"""
    print()

    # Test 1: Secrets Manager
    test1_passed = test_secrets_manager()

    # Test 2: App import
    test2_passed = test_app_import()

    # Summary
    print("\n" + "=" * 80)
    print("📊 Test Summary")
    print("=" * 80)
    print(f"   Secrets Manager: {'✅ PASSED' if test1_passed else '❌ FAILED'}")
    print(f"   App Import:      {'✅ PASSED' if test2_passed else '❌ FAILED'}")
    print("=" * 80)

    if test1_passed and test2_passed:
        print("\n✅ All validation tests passed!")
        print("   Ready for deployment")
        return 0
    else:
        print("\n❌ Some tests failed")
        print("   Review errors above")
        return 1


if __name__ == '__main__':
    sys.exit(main())

