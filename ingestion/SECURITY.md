# DStreamBolt Ingestion API - Security Implementation Guide

## Overview

The DStreamBolt ingestion service implements **mutual TLS (mTLS) authentication** for secure communication with external clients. This provides strong **machine-level trust** and identity verification through client certificates signed by a private Certificate Authority (CA).

## Security Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    External Client/Agent                      │
│                                                               │
│                    ┌────────────────┐                        │
│                    │  Client Cert   │                        │
│                    │  + Private Key │                        │
│                    └────────────────┘                        │
└─────────────────────────────┬────────────────────────────────┘
                              │
                              │ mTLS Handshake
                              ▼
┌──────────────────────────────────────────────────────────────┐
│                   AWS Application Load Balancer              │
│                                                               │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  mTLS Verification (ALB Listener)                   │    │
│  │  - Validates client cert against CA                 │    │
│  │  - Verifies certificate chain                       │    │
│  │  - Passes cert in X-Amzn-Mtls-Clientcert header    │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────┬────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│              DStreamBolt Ingestion Service                    │
│                                                               │
│  ┌──────────────────────────────────────────────────┐       │
│  │  mTLS Certificate Validation                     │       │
│  │  ────────────────────────────────                │       │
│  │  ✓ Extract certificate from ALB header          │       │
│  │  ✓ Verify cert not expired                      │       │
│  │  ✓ Check Certificate Revocation List (CRL)      │       │
│  │  ✓ Extract client identity (Common Name)        │       │
│  │  ✓ Validate against client registry             │       │
│  │  ✓ Log authentication attempt                    │       │
│  └──────────────────────────────────────────────────┘       │
│                              │                               │
│                              ▼                               │
│                       ✅ Authenticated                        │
│                                                               │
│                   Process ingestion request                  │
└──────────────────────────────────────────────────────────────┘
```

## Components

### Mutual TLS (mTLS) Certificate Authentication

**Purpose**: Establish strong machine identity and prevent unauthorized clients from connecting.

**Implementation**:
- Central Certificate Authority (CA) managed by DStreamBolt
- Short-lived client certificates (90 days, recommended)
- Certificate revocation via CRL stored in MySQL
- ALB enforces mTLS at listener level
- Service validates certificate details and revocation status

**Certificate Lifecycle**:
```
1. Client Registration
   → Admin generates client cert via setup script
   → Cert signed by DStreamBolt CA
   → Serial number recorded in database
   → Client metadata stored (name, contact, purpose)

2. Distribution (Secure Transfer)
   → Transfer via encrypted channel (SSH, secure S3 bucket, etc.)
   → Client receives:
      • client-cert.pem (certificate)
      • client-key.pem (private key - KEEP SECRET)
      • ca-cert.pem (CA certificate for server verification)
   → Client stores credentials securely (encrypted filesystem, vault)

3. Authentication (Every Request)
   → Client presents cert in TLS handshake
   → ALB validates cert against CA
   → ALB passes cert to backend via X-Amzn-Mtls-Clientcert header
   → Service validates:
      ✓ Certificate not expired
      ✓ Certificate not in revocation list (CRL)
      ✓ Client registered in client_registry
      ✓ Client status is 'active'

4. Rotation (Before Expiry - Recommended 7-14 days before)
   → Admin generates new cert with same Common Name (CN)
   → New cert distributed to client via secure channel
   → Client updates cert atomically (old stays valid during update)
   → Old cert remains valid for grace period (default: 7 days)
   → Old cert automatically revoked after grace period

5. Revocation (Immediate)
   → Admin revokes via API: POST /admin/cert/revoke
   → Serial number added to CRL in database
   → Future auth attempts rejected immediately (< 1 second)
   → Client notified out-of-band to obtain new certificate
```

**Authentication Flow**:
```python
@require_auth
def ingest():
    # Extract client certificate from ALB header
    cert_pem = request.headers.get('X-Amzn-Mtls-Clientcert', '')
    
    # Validate certificate
    cert_valid, cert_error, cert_info = validate_mtls_cert(cert_pem)
    if not cert_valid:
        log_auth_failure(cert_info.get('cn', 'unknown'), cert_error)
        return 401  # Unauthorized
    
    # Extract client identity
    client_id = cert_info['subject_cn']
    client_serial = cert_info['serial_number']
    
    # Verify client is active
    if not is_client_active(client_id):
        return 403  # Forbidden - client suspended/revoked
    
    # ✅ Authenticated
    # Attach client context to request
    request.client_id = client_id
    request.client_info = cert_info
    
    # Process ingestion request...
```

## Database Schema

```sql
-- Authentication audit log
CREATE TABLE IF NOT EXISTS auth_audit_log (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    client_id VARCHAR(255),
    cert_serial_number VARCHAR(255),
    success BOOLEAN,
    failure_reason VARCHAR(500),
    ip_address VARCHAR(45),
    user_agent VARCHAR(500),
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX(client_id),
    INDEX(cert_serial_number),
    INDEX(timestamp),
    INDEX(success)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Certificate revocation list (CRL)
CREATE TABLE IF NOT EXISTS cert_revocation_list (
    serial_number VARCHAR(255) PRIMARY KEY,
    client_id VARCHAR(255),
    revoked_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    revocation_reason VARCHAR(500),
    revoked_by VARCHAR(255),
    INDEX(client_id),
    INDEX(revoked_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Client registry (authorized clients)
CREATE TABLE IF NOT EXISTS client_registry (
    client_id VARCHAR(255) PRIMARY KEY,
    client_name VARCHAR(255) NOT NULL,
    client_contact VARCHAR(255),
    organization VARCHAR(255),
    cert_serial_number VARCHAR(255),
    cert_issued_at TIMESTAMP,
    cert_expires_at TIMESTAMP,
    registered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_seen_at TIMESTAMP,
    status ENUM('active', 'suspended', 'revoked') DEFAULT 'active',
    notes TEXT,
    metadata JSON,
    INDEX(status),
    INDEX(cert_serial_number),
    INDEX(cert_expires_at),
    INDEX(last_seen_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Certificate issuance log (for auditing)
CREATE TABLE IF NOT EXISTS cert_issuance_log (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    client_id VARCHAR(255),
    serial_number VARCHAR(255),
    issued_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP,
    issued_by VARCHAR(255),
    purpose VARCHAR(500),
    INDEX(client_id),
    INDEX(serial_number),
    INDEX(issued_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

## Configuration

### Environment Variables

```bash
# mTLS Configuration
export MTLS_ENABLED=true
export MTLS_CA_CERT_PATH=/etc/dstreambolt/certs/ca/ca-cert.pem
export MTLS_VERIFY_EXPIRY=true
export MTLS_CHECK_CRL=true

# MySQL for credential management
export MYSQL_HOST=10.0.1.61
export MYSQL_USER=dstreambolt
export MYSQL_PASSWORD=DStreamBolt2025!
export MYSQL_DB=dstreambolt_metrics
```

## Setup Instructions

### 1. Initialize Security Infrastructure

```bash
# Run security setup script (on ingestion node)
sudo bash /opt/dstreambolt/agent/setup_security.sh

# This creates:
# - CA certificate and key
# - Server certificate
# - Sample client certificates
# - Database tables
```

### 2. Configure AWS ALB for mTLS

```bash
# Upload CA cert to ACM
aws acm import-certificate \
  --certificate fileb:///etc/dstreambolt/certs/ca/ca-cert.pem \
  --private-key fileb:///etc/dstreambolt/certs/ca/ca-key.pem \
  --region ap-south-1

# Get certificate ARN
CA_CERT_ARN=$(aws acm list-certificates --query 'CertificateSummaryList[?DomainName==`dstreambolt-ca`].CertificateArn' --output text)

# Update ALB listener to use mTLS
aws elbv2 modify-listener \
  --listener-arn <your-listener-arn> \
  --mutual-authentication Mode=verify,TrustStoreArn=$CA_CERT_ARN \
  --region ap-south-1
```

### 3. Generate Client Credentials

```bash
# Generate certificate for new client
sudo bash /opt/dstreambolt/agent/setup_security.sh

# When prompted, choose option to generate client certificate
# Enter client ID (e.g., "company-xyz-prod")

# This creates:
# - /etc/dstreambolt/certs/clients/<client-id>/client-cert.pem
# - /etc/dstreambolt/certs/clients/<client-id>/client-key.pem
# - /etc/dstreambolt/certs/clients/<client-id>/client-bundle.pem

# Register client in database
mysql -u dstreambolt -p dstreambolt_metrics << EOF
INSERT INTO client_registry (
    client_id, 
    client_name, 
    client_contact,
    organization,
    cert_serial_number,
    cert_issued_at,
    cert_expires_at,
    status
) VALUES (
    '<client-id>',
    '<Company Name>',
    'admin@company.com',
    'Company XYZ',
    '<serial-from-cert>',
    NOW(),
    DATE_ADD(NOW(), INTERVAL 90 DAY),
    'active'
);
EOF
```

### 4. Distribute Credentials to Client

```bash
# Secure transfer (encrypted channel options):
# Option 1: SCP over SSH
scp -r /etc/dstreambolt/certs/clients/<client-id>/ user@client-host:/tmp/

# Option 2: Secure S3 bucket with presigned URL
aws s3 cp /etc/dstreambolt/certs/clients/<client-id>/client-bundle.pem \
  s3://secure-bucket/credentials/<client-id>/ --sse
aws s3 presign s3://secure-bucket/credentials/<client-id>/client-bundle.pem \
  --expires-in 3600

# Option 3: Encrypted archive
tar czf - /etc/dstreambolt/certs/clients/<client-id>/ | \
  openssl enc -aes-256-cbc -salt -out client-creds.tar.gz.enc
# Send encrypted file + password via separate channels

# ─────────────────────────────────────────────────────────────

# On client machine:
mkdir -p /etc/dstreambolt/credentials
cd /etc/dstreambolt/credentials

# Extract credentials
tar xzf /tmp/<client-id>/client-bundle.tar.gz

# Set permissions
chmod 400 client-key.pem
chmod 444 client-cert.pem ca-cert.pem

# Verify certificate
openssl x509 -in client-cert.pem -noout -text
openssl x509 -in client-cert.pem -noout -dates
```

## Client Usage

### Python Client Example

```python
import requests
import gzip
import json
from datetime import datetime

# Load mTLS credentials
CERT_FILE = '/etc/dstreambolt/credentials/client-cert.pem'
KEY_FILE = '/etc/dstreambolt/credentials/client-key.pem'
CA_FILE = '/etc/dstreambolt/credentials/ca-cert.pem'

# Ingestion endpoint
INGEST_URL = 'https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/ingest'

def send_logs(log_entries):
    """Send log entries to DStreamBolt ingestion service"""
    
    # Convert to newline-delimited JSON
    bundle_json = '\n'.join(json.dumps(entry) for entry in log_entries)
    
    # Compress
    bundle_gz = gzip.compress(bundle_json.encode('utf-8'))
    
    # Send with mTLS authentication
    response = requests.post(
        INGEST_URL,
        data=bundle_gz,
        headers={'Content-Type': 'application/gzip'},
        cert=(CERT_FILE, KEY_FILE),  # mTLS client certificate
        verify=CA_FILE,               # Verify server certificate
        timeout=30
    )
    
    return response

# Example usage
if __name__ == '__main__':
    logs = [
        {
            "timestamp": datetime.utcnow().isoformat() + 'Z',
            "level": "INFO",
            "message": "Application started",
            "service": "web-api",
            "host": "server-01"
        },
        {
            "timestamp": datetime.utcnow().isoformat() + 'Z',
            "level": "ERROR",
            "message": "Database connection failed",
            "service": "web-api",
            "host": "server-01",
            "error_code": "DB_CONN_ERR"
        }
    ]
    
    try:
        response = send_logs(logs)
        
        if response.status_code == 201:
            result = response.json()
            print(f"✅ Logs accepted")
            print(f"   Request ID: {result['request_id']}")
            print(f"   Bundle size: {result['bundle_size_bytes']} bytes")
            print(f"   Response time: {result['response_time_ms']} ms")
        else:
            print(f"❌ Failed: HTTP {response.status_code}")
            print(f"   {response.text}")
            
    except requests.exceptions.SSLError as e:
        print(f"❌ mTLS authentication failed: {e}")
    except Exception as e:
        print(f"❌ Error: {e}")
```

### curl Example

```bash
# Test authentication with mTLS
curl -X POST https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/ingest \
  --cert /etc/dstreambolt/credentials/client-cert.pem \
  --key /etc/dstreambolt/credentials/client-key.pem \
  --cacert /etc/dstreambolt/credentials/ca-cert.pem \
  -H "Content-Type: application/gzip" \
  --data-binary @bundle.gz \
  -v

# Expected response: 201 Accepted
{
  "status": "accepted",
  "request_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "client_id": "company-xyz-prod",
  "bundle_size_bytes": 12345,
  "queue_position": 10,
  "response_time_ms": 8.5
}

# Test certificate verification
curl -v https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/health \
  --cert /etc/dstreambolt/credentials/client-cert.pem \
  --key /etc/dstreambolt/credentials/client-key.pem \
  --cacert /etc/dstreambolt/credentials/ca-cert.pem \
  2>&1 | grep -E "(SSL|certificate|subject|issuer)"
```

## Certificate Rotation for Third-Party Clients

Certificate rotation is critical for maintaining security. Certificates should be rotated **before expiry** to ensure uninterrupted service. Recommended: rotate 7-14 days before expiration.

### Rotation Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    CERTIFICATE ROTATION WORKFLOW                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Week -2: Monitor expiry alerts                                │
│           ↓                                                     │
│  Week -1: DStreamBolt generates new cert with same CN          │
│           ↓                                                     │
│  Day -7:  Send new cert bundle to client (secure channel)      │
│           ↓                                                     │
│  Day -3:  Client deploys new cert (atomic update)              │
│           Old cert still valid (grace period)                   │
│           ↓                                                     │
│  Day -1:  Verify new cert working                              │
│           ↓                                                     │
│  Day 0:   Old cert expires naturally                           │
│           OR manually revoked after grace period               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Method 1: Automated Rotation (Recommended for Tech-Savvy Clients)

**Prerequisites**:
- Client has automation capabilities (cron, systemd timers, etc.)
- Secure communication channel with DStreamBolt
- Ability to restart services

**Implementation**:

#### Step 1: Create rotation script on client machine

```bash
#!/bin/bash
# Certificate Rotation Script for DStreamBolt Third-Party Clients
# Location: /opt/dstreambolt/scripts/rotate_certificate.sh
# Usage: ./rotate_certificate.sh <client-id>

set -e

CLIENT_ID="${1:-$(hostname)}"
CERT_DIR="/etc/dstreambolt/credentials"
BACKUP_DIR="/etc/dstreambolt/credentials/backups"
SECURE_ENDPOINT="https://secure-transfer.dstreambolt.com/cert-exchange"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔄 DStreamBolt Certificate Rotation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Client ID: $CLIENT_ID"
echo "Date: $(date)"
echo ""

# Check certificate expiry
CURRENT_CERT="$CERT_DIR/client-cert.pem"
EXPIRES=$(openssl x509 -in "$CURRENT_CERT" -noout -enddate | cut -d= -f2)
EXPIRES_EPOCH=$(date -d "$EXPIRES" +%s)
NOW_EPOCH=$(date +%s)
DAYS_UNTIL_EXPIRY=$(( ($EXPIRES_EPOCH - $NOW_EPOCH) / 86400 ))

echo "📅 Current certificate expires: $EXPIRES"
echo "⏰ Days until expiry: $DAYS_UNTIL_EXPIRY"
echo ""

# Only rotate if < 14 days until expiry
if [ $DAYS_UNTIL_EXPIRY -gt 14 ]; then
    echo "✅ Certificate still valid for $DAYS_UNTIL_EXPIRY days"
    echo "   No rotation needed (threshold: 14 days)"
    exit 0
fi

echo "⚠️  Certificate expires soon - initiating rotation..."
echo ""

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup current certificates
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
echo "💾 Backing up current certificates..."
cp "$CERT_DIR/client-cert.pem" "$BACKUP_DIR/client-cert-$BACKUP_TIMESTAMP.pem"
cp "$CERT_DIR/client-key.pem" "$BACKUP_DIR/client-key-$BACKUP_TIMESTAMP.pem"
echo "   Backup: $BACKUP_DIR/client-cert-$BACKUP_TIMESTAMP.pem"
echo ""

# Request new certificate
echo "📡 Requesting new certificate from DStreamBolt..."
echo "   (Contact your DStreamBolt administrator if this fails)"
echo ""

# Option A: Pull from secure endpoint (if available)
if curl -sf --head "$SECURE_ENDPOINT/$CLIENT_ID/latest" >/dev/null; then
    echo "   Downloading from secure endpoint..."
    curl -s --cert "$CURRENT_CERT" --key "$CERT_DIR/client-key.pem" \
         "$SECURE_ENDPOINT/$CLIENT_ID/latest" \
         -o /tmp/new-cert-bundle.tar.gz
    
    cd /tmp
    tar xzf new-cert-bundle.tar.gz
    
    NEW_CERT="/tmp/new-client-cert.pem"
    NEW_KEY="/tmp/new-client-key.pem"
else
    echo "   ❌ Automated download not available"
    echo "   📧 Contact DStreamBolt support: support@dstreambolt.com"
    echo "   Subject: Certificate Rotation Request - $CLIENT_ID"
    exit 1
fi

# Verify new certificate
echo "🔍 Verifying new certificate..."
NEW_CN=$(openssl x509 -in "$NEW_CERT" -noout -subject | grep -oP 'CN\s*=\s*\K[^,]+')
OLD_CN=$(openssl x509 -in "$CURRENT_CERT" -noout -subject | grep -oP 'CN\s*=\s*\K[^,]+')

if [ "$NEW_CN" != "$OLD_CN" ]; then
    echo "   ❌ ERROR: Common Name mismatch!"
    echo "   Expected: $OLD_CN"
    echo "   Got: $NEW_CN"
    exit 1
fi

NEW_EXPIRES=$(openssl x509 -in "$NEW_CERT" -noout -enddate | cut -d= -f2)
echo "   ✅ Common Name matches: $NEW_CN"
echo "   ✅ New certificate expires: $NEW_EXPIRES"
echo ""

# Test new certificate before deploying
echo "🧪 Testing new certificate..."
if curl -sf --cert "$NEW_CERT" --key "$NEW_KEY" \
     --cacert "$CERT_DIR/ca-cert.pem" \
     https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/health \
     >/dev/null; then
    echo "   ✅ New certificate validated successfully"
else
    echo "   ❌ New certificate validation failed"
    echo "   Keeping old certificate"
    exit 1
fi
echo ""

# Deploy new certificate (atomic operation)
echo "🚀 Deploying new certificate..."
mv "$NEW_CERT" "$CERT_DIR/client-cert.pem"
mv "$NEW_KEY" "$CERT_DIR/client-key.pem"
chmod 444 "$CERT_DIR/client-cert.pem"
chmod 400 "$CERT_DIR/client-key.pem"
echo "   ✅ Certificates deployed"
echo ""

# Restart services that use certificates
echo "♻️  Restarting services..."
# Customize based on your application
# systemctl restart your-app
# docker restart your-container
# supervisorctl restart your-process
echo "   (Manual restart may be required for your application)"
echo ""

# Verify connectivity with new certificate
echo "✅ Verifying connectivity..."
if curl -sf --cert "$CERT_DIR/client-cert.pem" \
     --key "$CERT_DIR/client-key.pem" \
     --cacert "$CERT_DIR/ca-cert.pem" \
     https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/health \
     >/dev/null; then
    echo "   ✅ Connectivity verified with new certificate"
else
    echo "   ❌ Connectivity failed with new certificate"
    echo "   Rolling back..."
    cp "$BACKUP_DIR/client-cert-$BACKUP_TIMESTAMP.pem" "$CERT_DIR/client-cert.pem"
    cp "$BACKUP_DIR/client-key-$BACKUP_TIMESTAMP.pem" "$CERT_DIR/client-key.pem"
    echo "   ✅ Rolled back to previous certificate"
    exit 1
fi

# Clean up
rm -f /tmp/new-cert-bundle.tar.gz /tmp/new-client-*

# Send notification (optional)
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ CERTIFICATE ROTATION COMPLETE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Client ID: $CLIENT_ID"
echo "Old Expiry: $EXPIRES"
echo "New Expiry: $NEW_EXPIRES"
echo "Backup: $BACKUP_DIR/client-cert-$BACKUP_TIMESTAMP.pem"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
```

#### Step 2: Schedule automatic rotation

```bash
# Add to crontab (check weekly, rotate if < 14 days)
crontab -e

# Check every Monday at 2 AM
0 2 * * 1 /opt/dstreambolt/scripts/rotate_certificate.sh client-id >> /var/log/dstreambolt-cert-rotation.log 2>&1
```

#### Step 3: Monitor rotation logs

```bash
# View rotation history
tail -f /var/log/dstreambolt-cert-rotation.log

# Check certificate expiry
openssl x509 -in /etc/dstreambolt/credentials/client-cert.pem -noout -dates

# Verify certificate details
openssl x509 -in /etc/dstreambolt/credentials/client-cert.pem -noout -text
```

---

### Method 2: Manual Rotation (For Non-Technical Clients)

**Best for**: Clients without automation capabilities or strict change control processes.

#### Step 1: DStreamBolt generates new certificate

```bash
# On DStreamBolt admin side
sudo bash /opt/dstreambolt/agent/setup_security.sh

# Generate new certificate for client (same CN as old cert)
# Serial number will be different but CN must match

# Package for distribution
cd /etc/dstreambolt/certs/clients/<client-id>/
tar czf client-cert-renewal-$(date +%Y%m%d).tar.gz \
    client-cert.pem client-key.pem

# Encrypt for secure transfer
openssl enc -aes-256-cbc -salt \
    -in client-cert-renewal-$(date +%Y%m%d).tar.gz \
    -out client-cert-renewal-$(date +%Y%m%d).tar.gz.enc

# Send to client via secure channel + password separately
```

#### Step 2: Client receives and extracts new certificate

```bash
# On client machine
cd /tmp

# Decrypt certificate bundle
openssl enc -aes-256-cbc -d \
    -in client-cert-renewal-20251211.tar.gz.enc \
    -out client-cert-renewal-20251211.tar.gz

# Extract
tar xzf client-cert-renewal-20251211.tar.gz

# Verify new certificate
openssl x509 -in client-cert.pem -noout -text
openssl x509 -in client-cert.pem -noout -dates
openssl x509 -in client-cert.pem -noout -subject
```

#### Step 3: Backup old certificate

```bash
# Create backup directory
mkdir -p /etc/dstreambolt/credentials/backups

# Backup current certificates
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
cp /etc/dstreambolt/credentials/client-cert.pem \
   /etc/dstreambolt/credentials/backups/client-cert-$TIMESTAMP.pem
cp /etc/dstreambolt/credentials/client-key.pem \
   /etc/dstreambolt/credentials/backups/client-key-$TIMESTAMP.pem

echo "✅ Backup created: /etc/dstreambolt/credentials/backups/client-cert-$TIMESTAMP.pem"
```

#### Step 4: Deploy new certificate

```bash
# Copy new certificates to credentials directory
cp /tmp/client-cert.pem /etc/dstreambolt/credentials/
cp /tmp/client-key.pem /etc/dstreambolt/credentials/

# Set correct permissions
chmod 444 /etc/dstreambolt/credentials/client-cert.pem
chmod 400 /etc/dstreambolt/credentials/client-key.pem

# Verify ownership
ls -l /etc/dstreambolt/credentials/
```

#### Step 5: Test new certificate

```bash
# Test connectivity before restarting application
curl -v https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/health \
  --cert /etc/dstreambolt/credentials/client-cert.pem \
  --key /etc/dstreambolt/credentials/client-key.pem \
  --cacert /etc/dstreambolt/credentials/ca-cert.pem

# Expected: 200 OK response
```

#### Step 6: Restart application

```bash
# Restart your application to use new certificate
# Examples:
systemctl restart your-app
# OR
docker restart your-container
# OR
supervisorctl restart your-process
```

#### Step 7: Verify production traffic

```bash
# Send test log bundle
curl -X POST https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/ingest \
  --cert /etc/dstreambolt/credentials/client-cert.pem \
  --key /etc/dstreambolt/credentials/client-key.pem \
  --cacert /etc/dstreambolt/credentials/ca-cert.pem \
  -H "Content-Type: application/gzip" \
  --data-binary @test-bundle.gz

# Expected: 201 Accepted
```

---

### Method 3: Zero-Downtime Rotation (Enterprise Clients)

**Best for**: Mission-critical applications requiring 100% uptime.

**Strategy**: Run dual certificates during transition period.

#### Implementation

```bash
# 1. Store new cert in alternate location
cp /tmp/new-client-cert.pem /etc/dstreambolt/credentials/client-cert-new.pem
cp /tmp/new-client-key.pem /etc/dstreambolt/credentials/client-key-new.pem

# 2. Configure application to try new cert first, fallback to old
# (Application-specific - example for Python)
```

```python
# Python example: Dual certificate support
import requests
from requests.exceptions import SSLError

OLD_CERT = ('/etc/dstreambolt/credentials/client-cert.pem',
            '/etc/dstreambolt/credentials/client-key.pem')
NEW_CERT = ('/etc/dstreambolt/credentials/client-cert-new.pem',
            '/etc/dstreambolt/credentials/client-key-new.pem')

def send_with_retry(url, data):
    # Try new certificate first
    try:
        response = requests.post(url, data=data, cert=NEW_CERT, verify=CA_FILE)
        if response.ok:
            return response
    except SSLError:
        pass  # Fall back to old cert
    
    # Fallback to old certificate
    return requests.post(url, data=data, cert=OLD_CERT, verify=CA_FILE)
```

```bash
# 3. After confirming new cert works, make it primary
mv /etc/dstreambolt/credentials/client-cert-new.pem \
   /etc/dstreambolt/credentials/client-cert.pem
mv /etc/dstreambolt/credentials/client-key-new.pem \
   /etc/dstreambolt/credentials/client-key.pem
```

---

### Troubleshooting Certificate Rotation

#### Issue: "Certificate verification failed"

```bash
# Check certificate details
openssl x509 -in /etc/dstreambolt/credentials/client-cert.pem -noout -text

# Verify Common Name matches
openssl x509 -in /etc/dstreambolt/credentials/client-cert.pem -noout -subject

# Check certificate chain
openssl verify -CAfile /etc/dstreambolt/credentials/ca-cert.pem \
               /etc/dstreambolt/credentials/client-cert.pem
```

#### Issue: "Old certificate still being used"

```bash
# Check which cert file application is reading
lsof | grep client-cert.pem

# Ensure application restarted after cert update
systemctl status your-app
ps aux | grep your-app
```

#### Issue: "New certificate doesn't work"

```bash
# Rollback to old certificate
LATEST_BACKUP=$(ls -t /etc/dstreambolt/credentials/backups/ | head -1)
cp /etc/dstreambolt/credentials/backups/$LATEST_BACKUP \
   /etc/dstreambolt/credentials/client-cert.pem

# Contact DStreamBolt support
echo "Certificate rotation failed for $(hostname)" | \
  mail -s "DStreamBolt Cert Rotation Issue" support@dstreambolt.com
```

---

### Certificate Expiry Monitoring

#### Setup Expiry Alerts

```bash
#!/bin/bash
# Check certificate expiry and send alerts
# Location: /opt/dstreambolt/scripts/check_cert_expiry.sh

CERT_FILE="/etc/dstreambolt/credentials/client-cert.pem"
ALERT_DAYS=14
EMAIL="ops@your-company.com"

EXPIRES=$(openssl x509 -in "$CERT_FILE" -noout -enddate | cut -d= -f2)
EXPIRES_EPOCH=$(date -d "$EXPIRES" +%s)
NOW_EPOCH=$(date +%s)
DAYS_UNTIL_EXPIRY=$(( ($EXPIRES_EPOCH - $NOW_EPOCH) / 86400 ))

if [ $DAYS_UNTIL_EXPIRY -lt $ALERT_DAYS ]; then
    SUBJECT="⚠️  DStreamBolt Certificate Expires in $DAYS_UNTIL_EXPIRY days"
    BODY="Certificate for $(hostname) expires: $EXPIRES\n\nRotate ASAP!"
    echo -e "$BODY" | mail -s "$SUBJECT" "$EMAIL"
fi
```

```bash
# Add to crontab (check daily)
0 9 * * * /opt/dstreambolt/scripts/check_cert_expiry.sh
```


## Monitoring & Auditing

### Authentication Audit Queries

```sql
-- Failed authentication attempts (last 24 hours)
SELECT 
    client_id,
    failure_reason,
    ip_address,
    COUNT(*) as attempts,
    MAX(timestamp) as last_attempt
FROM auth_audit_log
WHERE success = FALSE 
    AND timestamp >= NOW() - INTERVAL 24 HOUR
GROUP BY client_id, failure_reason, ip_address
ORDER BY attempts DESC;

-- Successful authentications by client
SELECT 
    client_id,
    COUNT(*) as auth_count,
    MIN(timestamp) as first_seen,
    MAX(timestamp) as last_seen
FROM auth_audit_log
WHERE success = TRUE
GROUP BY client_id
ORDER BY auth_count DESC;

-- Revoked certificates still being used
SELECT 
    a.client_id,
    a.cert_serial_number,
    a.ip_address,
    a.failure_reason,
    a.timestamp,
    c.revocation_reason,
    c.revoked_at
FROM auth_audit_log a
JOIN cert_revocation_list c ON a.cert_serial_number = c.serial_number
WHERE a.timestamp >= c.revoked_at
    AND a.success = FALSE
ORDER BY a.timestamp DESC;

-- Certificate expiry status
SELECT 
    client_id,
    client_name,
    cert_serial_number,
    cert_expires_at,
    DATEDIFF(cert_expires_at, NOW()) as days_until_expiry,
    CASE 
        WHEN DATEDIFF(cert_expires_at, NOW()) < 0 THEN '🔴 EXPIRED'
        WHEN DATEDIFF(cert_expires_at, NOW()) < 7 THEN '🟠 URGENT'
        WHEN DATEDIFF(cert_expires_at, NOW()) < 14 THEN '🟡 WARNING'
        ELSE '🟢 OK'
    END as status
FROM client_registry
WHERE status = 'active'
ORDER BY cert_expires_at ASC;

-- Authentication activity by client (last 7 days)
SELECT 
    client_id,
    DATE(timestamp) as date,
    COUNT(*) as auth_attempts,
    SUM(CASE WHEN success = TRUE THEN 1 ELSE 0 END) as successful,
    SUM(CASE WHEN success = FALSE THEN 1 ELSE 0 END) as failed
FROM auth_audit_log
WHERE timestamp >= NOW() - INTERVAL 7 DAY
GROUP BY client_id, DATE(timestamp)
ORDER BY date DESC, auth_attempts DESC;
```

### Security Alerts

```bash
# Alert on repeated auth failures (possible attack)
SELECT 
    client_id,
    ip_address,
    failure_reason,
    COUNT(*) as failures,
    MAX(timestamp) as last_attempt
FROM auth_audit_log
WHERE success = FALSE 
    AND timestamp >= NOW() - INTERVAL 15 MINUTE
GROUP BY client_id, ip_address, failure_reason
HAVING failures > 10
ORDER BY failures DESC;

# Alert on revoked certificates still in use
SELECT 
    a.client_id,
    a.cert_serial_number,
    a.ip_address,
    COUNT(*) as attempts,
    MAX(a.timestamp) as last_attempt,
    c.revocation_reason
FROM auth_audit_log a
JOIN cert_revocation_list c ON a.cert_serial_number = c.serial_number
WHERE a.timestamp >= NOW() - INTERVAL 1 HOUR
GROUP BY a.client_id, a.cert_serial_number, a.ip_address, c.revocation_reason
ORDER BY attempts DESC;

# Alert on certificates expiring soon
SELECT 
    client_id,
    client_name,
    client_contact,
    cert_expires_at,
    DATEDIFF(cert_expires_at, NOW()) as days_left
FROM client_registry
WHERE status = 'active'
    AND cert_expires_at IS NOT NULL
    AND DATEDIFF(cert_expires_at, NOW()) <= 14
ORDER BY days_left ASC;

# Alert on suspicious IP changes
SELECT 
    client_id,
    ip_address,
    COUNT(DISTINCT DATE(timestamp)) as days_active,
    MIN(timestamp) as first_seen,
    MAX(timestamp) as last_seen
FROM auth_audit_log
WHERE success = TRUE
    AND timestamp >= NOW() - INTERVAL 7 DAY
GROUP BY client_id, ip_address
HAVING days_active = 1  -- New IP recently
ORDER BY last_seen DESC;
```

### Setup Monitoring Script

```bash
#!/bin/bash
# Security monitoring script
# Location: /opt/dstreambolt/scripts/security_monitor.sh

MYSQL_CMD="mysql -u dstreambolt -pDStreamBolt2025! dstreambolt_metrics"
ALERT_EMAIL="security@dstreambolt.com"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔒 DStreamBolt Security Monitor - $(date)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check for expiring certificates
EXPIRING=$($MYSQL_CMD -sN -e "
SELECT COUNT(*) FROM client_registry 
WHERE status='active' AND DATEDIFF(cert_expires_at, NOW()) <= 14
")

if [ "$EXPIRING" -gt 0 ]; then
    echo "⚠️  WARNING: $EXPIRING certificate(s) expiring soon"
    $MYSQL_CMD -e "
    SELECT client_id, client_contact, cert_expires_at, 
           DATEDIFF(cert_expires_at, NOW()) as days_left
    FROM client_registry 
    WHERE status='active' AND DATEDIFF(cert_expires_at, NOW()) <= 14
    " | mail -s "⚠️  DStreamBolt: Certificates Expiring Soon" $ALERT_EMAIL
fi

# Check for auth failures
FAILURES=$($MYSQL_CMD -sN -e "
SELECT COUNT(*) FROM auth_audit_log 
WHERE success=FALSE AND timestamp >= NOW() - INTERVAL 1 HOUR
")

if [ "$FAILURES" -gt 100 ]; then
    echo "🚨 ALERT: High authentication failure rate ($FAILURES in last hour)"
    $MYSQL_CMD -e "
    SELECT client_id, ip_address, failure_reason, COUNT(*) as attempts
    FROM auth_audit_log
    WHERE success=FALSE AND timestamp >= NOW() - INTERVAL 1 HOUR
    GROUP BY client_id, ip_address, failure_reason
    ORDER BY attempts DESC LIMIT 20
    " | mail -s "🚨 DStreamBolt: High Auth Failure Rate" $ALERT_EMAIL
fi

# Check for revoked cert usage
REVOKED_USAGE=$($MYSQL_CMD -sN -e "
SELECT COUNT(*) FROM auth_audit_log a
JOIN cert_revocation_list c ON a.cert_serial_number = c.serial_number
WHERE a.timestamp >= NOW() - INTERVAL 1 HOUR
")

if [ "$REVOKED_USAGE" -gt 0 ]; then
    echo "🚨 CRITICAL: Revoked certificate used $REVOKED_USAGE time(s)"
    $MYSQL_CMD -e "
    SELECT a.client_id, a.cert_serial_number, a.ip_address, 
           a.timestamp, c.revocation_reason
    FROM auth_audit_log a
    JOIN cert_revocation_list c ON a.cert_serial_number = c.serial_number
    WHERE a.timestamp >= NOW() - INTERVAL 1 HOUR
    " | mail -s "🚨 DStreamBolt: REVOKED CERTIFICATE USAGE DETECTED" $ALERT_EMAIL
fi

echo ""
echo "✅ Security check complete"
```

```bash
# Schedule monitoring (every 15 minutes)
crontab -e
*/15 * * * * /opt/dstreambolt/scripts/security_monitor.sh >> /var/log/dstreambolt-security.log 2>&1
```

## Security Best Practices

### Certificate Management
- ✅ Use short-lived client certificates (60-90 days)
- ✅ Automate certificate rotation before expiry (14 days warning)
- ✅ Revoke compromised certificates immediately
- ✅ Store private keys encrypted at rest (chmod 400)
- ✅ Never log or transmit private keys
- ✅ Use hardware-backed storage (TPM, HSM) if available
- ✅ Maintain unique Common Name (CN) per client
- ✅ Keep detailed certificate issuance audit trail

### Access Control
- ✅ Implement rate limiting per client ID
- ✅ Monitor authentication patterns for anomalies
- ✅ Alert on repeated failures (possible brute force)
- ✅ Track and investigate IP address changes
- ✅ Maintain client registry with active status
- ✅ Require certificate + ALB-level validation

### Operational Security
- ✅ Audit all authentication attempts (success + failure)
- ✅ Review access logs daily
- ✅ Automate credential lifecycle management
- ✅ Test revocation procedures quarterly
- ✅ Maintain incident response runbooks
- ✅ Monitor certificate expiry (alerts at 30, 14, 7 days)
- ✅ Backup certificate revocation list (CRL)
- ✅ Document all certificate issuances and revocations

### Client Security (Third-Party Guidelines)
- ✅ Store certificates in secure locations (not /tmp)
- ✅ Use encrypted filesystems for credential storage
- ✅ Restrict file permissions (cert: 444, key: 400)
- ✅ Rotate certificates before expiry
- ✅ Monitor certificate expiry locally
- ✅ Implement automatic rotation where possible
- ✅ Report security incidents immediately
- ✅ Never commit certificates to version control
- ✅ Use separate certificates per environment (dev/prod)

## Troubleshooting

### "mTLS validation failed: Certificate expired"
```bash
# Check certificate expiry
openssl x509 -noout -dates -in /etc/dstreambolt/credentials/client-cert.pem

# View days until expiry
EXPIRES=$(openssl x509 -noout -enddate -in /etc/dstreambolt/credentials/client-cert.pem | cut -d= -f2)
echo "Certificate expires: $EXPIRES"
echo "Days remaining: $(( ($(date -d "$EXPIRES" +%s) - $(date +%s)) / 86400 ))"

# Rotate certificate immediately
bash /opt/dstreambolt/scripts/rotate_certificate.sh your-client-id
```

### "Certificate revoked"
```bash
# Check if certificate is in revocation list
SERIAL=$(openssl x509 -noout -serial -in /etc/dstreambolt/credentials/client-cert.pem | cut -d= -f2)

mysql -u dstreambolt -p dstreambolt_metrics -e \
  "SELECT * FROM cert_revocation_list WHERE serial_number='$SERIAL'"

# If revoked, contact DStreamBolt to obtain new certificate
# If incorrectly revoked (rare), admin must remove from CRL
```

### "Connection refused" or "SSL handshake failed"
```bash
# Test connectivity to ALB
curl -v https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/health \
  --cert /etc/dstreambolt/credentials/client-cert.pem \
  --key /etc/dstreambolt/credentials/client-key.pem \
  --cacert /etc/dstreambolt/credentials/ca-cert.pem

# Check certificate chain
openssl verify -CAfile /etc/dstreambolt/credentials/ca-cert.pem \
               /etc/dstreambolt/credentials/client-cert.pem

# Verify certificate details
openssl x509 -in /etc/dstreambolt/credentials/client-cert.pem -noout -text | grep -A5 "Subject:"
```

### "Client not registered" or "Client status: revoked"
```bash
# Check client status in database
mysql -u dstreambolt -p dstreambolt_metrics -e \
  "SELECT * FROM client_registry WHERE client_id='your-client-id'"

# If status is 'suspended' or 'revoked', contact DStreamBolt support
# Admin can reactivate: UPDATE client_registry SET status='active' WHERE client_id='...'
```

### "Permission denied" accessing certificate files
```bash
# Check file permissions
ls -la /etc/dstreambolt/credentials/

# Fix permissions
chmod 400 /etc/dstreambolt/credentials/client-key.pem
chmod 444 /etc/dstreambolt/credentials/client-cert.pem
chmod 444 /etc/dstreambolt/credentials/ca-cert.pem

# Ensure correct ownership
chown your-app-user:your-app-group /etc/dstreambolt/credentials/*
```

## Performance Impact

- **mTLS overhead**: ~5-10ms per request (TLS handshake cached by ALB)
- **Certificate validation**: ~1-2ms per request (expiry check)
- **CRL lookup**: ~2-5ms per request (database query)
- **Total auth overhead**: ~8-17ms per request

**Optimization**:
- ALB caches TLS sessions (reduces handshake overhead)
- In-memory cache for CRL (refresh every 60s, not per-request)
- Certificate validation is CPU-bound (fast)
- Database connection pooling for CRL checks
- Index on cert_serial_number for fast lookups

## Conclusion

The mTLS authentication model provides:
- ✅ Strong machine-level trust (client certificates)
- ✅ Simple architecture (single authentication mechanism)
- ✅ Immediate revocation (certificate revocation list)
- ✅ Audit trail (comprehensive logging of all attempts)
- ✅ Scalability (ALB handles TLS termination)
- ✅ Production-ready security

This design meets enterprise security requirements for external-facing ingestion APIs while maintaining high performance and operational simplicity.

