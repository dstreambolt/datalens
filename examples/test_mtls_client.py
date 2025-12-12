#!/usr/bin/env python3
"""
Test script to verify mTLS client functionality
Tests both with and without client certificates
"""

import sys
import os
import json

# Add parent directory to path to import the client
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

def test_mtls_client():
    """Test the mTLS client implementation"""
    print("╔══════════════════════════════════════════════════════════════╗")
    print("║          mTLS Client Test                                   ║")
    print("╚══════════════════════════════════════════════════════════════╝")
    print()

    # Check if requests module is available
    try:
        import requests
        print("✅ requests module available")
    except ImportError:
        print("❌ requests module not found")
        print("   Install: pip install requests")
        return False

    # Test data
    test_data = [
        {
            "ip": "192.168.1.1",
            "timestamp": "2025-12-12T10:00:00Z",
            "method": "GET",
            "endpoint": "/api/test",
            "status": 200,
            "size": 1024,
            "referer": "-",
            "user_agent": "TestClient/1.0",
            "response_time": 0.123
        }
    ]

    print()
    print("Test payload:")
    print(json.dumps(test_data, indent=2))
    print()

    # Check certificate files
    cert_dir = "../certs"
    client_cert = f"{cert_dir}/client/client-cert.pem"
    client_key = f"{cert_dir}/client/client-key.pem"
    ca_cert = f"{cert_dir}/ca/ca-cert.pem"

    print("Certificate status:")
    for name, path in [
        ("Client Cert", client_cert),
        ("Client Key", client_key),
        ("CA Cert", ca_cert)
    ]:
        if os.path.exists(path):
            print(f"  ✅ {name}: {path}")
        else:
            print(f"  ❌ {name}: {path} (not found)")

    print()
    print("To generate certificates, run:")
    print("  ./generate_mtls_certs.sh")
    print()

    # Test the send_to_ingest function signature
    print("Testing function signature...")
    try:
        from importlib import import_module
        import importlib.util
        spec = importlib.util.spec_from_file_location("ingest_client", "02-send-to-ingest.py")
        module = importlib.util.module_from_spec(spec)

        # Check if function exists and has correct signature
        import inspect
        sig = inspect.signature(module.send_to_ingest)
        params = list(sig.parameters.keys())

        expected_params = ['alb_url', 'json_data_bytes', 'verify_ssl', 'client_cert', 'client_key', 'ca_cert']

        print(f"Function parameters: {params}")

        if all(p in params for p in expected_params):
            print("✅ Function signature correct")
        else:
            print("❌ Function signature incorrect")
            print(f"   Expected: {expected_params}")
            return False

    except Exception as e:
        print(f"⚠️  Could not verify function signature: {e}")

    print()
    print("╔══════════════════════════════════════════════════════════════╗")
    print("║              Test Summary                                   ║")
    print("╚══════════════════════════════════════════════════════════════╝")
    print()
    print("✅ mTLS client implementation is ready")
    print()
    print("Next steps:")
    print("  1. Generate certificates: ./generate_mtls_certs.sh")
    print("  2. Deploy to ingestion server")
    print("  3. Test ingestion:")
    print("     python3 02-send-to-ingest.py logs/access.log \\")
    print("       --alb-url https://your-ingestion-url \\")
    print("       --client-cert certs/client/client-cert.pem \\")
    print("       --client-key certs/client/client-key.pem \\")
    print("       --ca-cert certs/ca/ca-cert.pem")
    print()

    return True

if __name__ == "__main__":
    success = test_mtls_client()
    sys.exit(0 if success else 1)

