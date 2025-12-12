# DStreamBolt Ingestion Service - mTLS Deployment Guide

## ✅ COMPLETE - app.py Fixed for mTLS

### Changes Made to app.py:

1. **Startup Validation** - Verifies mTLS configuration at service start:
   - Checks if `cryptography` library is installed
   - Validates CA certificate exists and is readable
   - Verifies certificate format
   - Provides clear error messages

2. **Robust Error Handling** - Graceful degradation:
   - Service starts even if mTLS config has issues
   - Clear error messages in logs
   - Certificate validation errors don't crash the service

3. **Import Safety** - Protected imports:
   - `cryptography` imports are wrapped in try/except
   - Service won't fail if library is missing
   - Error messages guide admin to fix

### Current Status:

- ✅ **app.py syntax validated** - No Python errors
- ✅ **mTLS configuration** - Properly loaded from environment
- ✅ **Startup checks** - Certificate validation at boot
- ✅ **Error handling** - Graceful failures with clear messages
- ✅ **cryptography library** - Already in requirements.txt

## Deployment Steps

### Option 1: Enable mTLS (Secure - Recommended for Production)

#### Step 1: Generate Certificates (One-time)
```bash
cd /Users/skalaise/apps/cloud/terraform/dstream_bolt
./generate_mtls_certs.sh
```

This creates:
- `certs/ca/ca-cert.pem` - CA certificate
- `certs/server/server-cert.pem` - Server certificate (optional)
- `certs/client/client-cert.pem` - Client certificate

#### Step 2: Deploy Certificates to Ingestion Server
```bash
INGEST_IP="<your-ingestion-server-ip>"

# Create cert directory on server
ssh ubuntu@$INGEST_IP "sudo mkdir -p /etc/dstreambolt/certs && sudo chown -R ubuntu:ubuntu /etc/dstreambolt/certs"

# Copy certificates
scp -r certs/ca certs/server ubuntu@$INGEST_IP:/etc/dstreambolt/certs/
```

#### Step 3: Deploy Updated Code
```bash
# Via Jenkins (Recommended)
# Run job: DStreamBolt-Deploy-Ingestion
# Parameters:
#   TARGET_IPS: <your-ingestion-server-ip>
#   GIT_BRANCH: release/v1.0.1

# OR manually
scp ingestion/app.py ubuntu@$INGEST_IP:/opt/dstreambolt/ingest/
scp ingestion/requirements.txt ubuntu@$INGEST_IP:/opt/dstreambolt/ingest/
scp ingestion/gunicorn_config.py ubuntu@$INGEST_IP:/opt/dstreambolt/ingest/
```

#### Step 4: Enable mTLS on Server
```bash
# Copy enable script to server
scp enable_mtls.sh ubuntu@$INGEST_IP:/tmp/

# SSH to server and run
ssh ubuntu@$INGEST_IP
sudo bash /tmp/enable_mtls.sh
```

This script will:
- ✅ Verify certificates exist
- ✅ Check cryptography library
- ✅ Configure systemd environment variables
- ✅ Restart service
- ✅ Verify mTLS is enabled
- ✅ Test health endpoint

#### Step 5: Verify mTLS is Enabled
```bash
ssh ubuntu@$INGEST_IP

# Check service logs
sudo journalctl -u dstreambolt-ingest -n 50 | grep -i mtls

# Should see:
# 🔐 mTLS authentication enabled
#    CA Certificate: /etc/dstreambolt/certs/ca/ca-cert.pem
#    ✅ cryptography library available
#    ✅ CA certificate found
#    ✅ CA certificate format valid
```

#### Step 6: Test with mTLS Client
```bash
# From your local machine
python3 examples/02-send-to-ingest.py logs/access.log \
  --alb-url https://ingest.dstreambolt.dashbird.com \
  --client-cert certs/client/client-cert.pem \
  --client-key certs/client/client-key.pem \
  --ca-cert certs/ca/ca-cert.pem
```

### Option 2: Deploy Without mTLS (Default - Current Setup)

#### Just Deploy Code
```bash
# Via Jenkins
# Run job: DStreamBolt-Deploy-Ingestion
# No mTLS configuration needed

# Service will log:
# ⚠️  mTLS authentication disabled - running in open mode
```

## Verification Commands

### Check Service Status
```bash
ssh ubuntu@<ingest-ip>

# Service status
sudo systemctl status dstreambolt-ingest

# Check if mTLS is enabled
sudo journalctl -u dstreambolt-ingest --since "5 minutes ago" | grep mTLS

# Check for errors
sudo journalctl -u dstreambolt-ingest --since "5 minutes ago" | grep -i error
```

### View Startup Messages
```bash
# Full startup log
sudo journalctl -u dstreambolt-ingest --since "5 minutes ago" | head -50

# Look for these lines:
# ✅ Secrets Manager initialized
# ✅ Kafka config loaded: 10.0.10.101:9092
# 🔐 mTLS authentication enabled (if enabled)
# ✅ cryptography library available (if mTLS enabled)
# ✅ CA certificate found (if mTLS enabled)
# 🔗 Testing Kafka connection...
# ✅ Kafka connected successfully
```

### Test Health Endpoint
```bash
# From ingestion server
curl http://localhost:5000/health | python3 -m json.tool

# Should show:
{
  "kafka": "connected",
  "service": "ingest-api", 
  "status": "healthy",
  "timestamp": 1734012345.67,
  "version": "1.0.0"
}
```

### Test Ingestion
```bash
# Without mTLS (if mTLS disabled)
curl -X POST http://localhost:5000/ingest \
  -H "Content-Type: application/gzip" \
  --data-binary @test.gz

# With mTLS (via ALB - client cert required)
python3 examples/02-send-to-ingest.py logs/access.log \
  --alb-url https://ingest.dstreambolt.dashbird.com \
  --client-cert certs/client/client-cert.pem \
  --client-key certs/client/client-key.pem
```

## Troubleshooting

### Issue: "cryptography library not found"
```bash
# SSH to server
ssh ubuntu@<ingest-ip>

# Install in venv
cd /opt/dstreambolt/ingest
source venv/bin/activate
pip install cryptography>=41.0.0

# Restart service
sudo systemctl restart dstreambolt-ingest
```

### Issue: "CA certificate not found"
```bash
# Check if certificate exists
ssh ubuntu@<ingest-ip>
ls -la /etc/dstreambolt/certs/ca/ca-cert.pem

# If not, copy from local machine
scp certs/ca/ca-cert.pem ubuntu@<ingest-ip>:/etc/dstreambolt/certs/ca/
```

### Issue: "Service fails to start with mTLS enabled"
```bash
# Check logs for specific error
ssh ubuntu@<ingest-ip>
sudo journalctl -u dstreambolt-ingest -n 100 | grep -i error

# Temporarily disable mTLS to isolate issue
sudo rm /etc/systemd/system/dstreambolt-ingest.service.d/mtls.conf
sudo systemctl daemon-reload
sudo systemctl restart dstreambolt-ingest
```

### Issue: "Kafka still disconnected"
```bash
# This is unrelated to mTLS - see complete_ingestion_fix.sh
# mTLS only affects client authentication, not Kafka connectivity

# Verify Kafka is reachable
nc -zv 10.0.10.101 9092

# Check Kafka config in logs
sudo journalctl -u dstreambolt-ingest --since "2 minutes ago" | grep "Kafka config loaded"
```

## Environment Variables Reference

### mTLS Configuration
```bash
# Enable/disable mTLS
MTLS_ENABLED=true                # or 'false' (default)

# CA certificate path
MTLS_CA_CERT_PATH=/etc/dstreambolt/certs/ca/ca-cert.pem

# Certificate revocation list checking
MTLS_CHECK_CRL=false             # or 'true' (requires CRL table in DB)

# Optional: Server certificates (if using native HTTPS, not via ALB)
MTLS_SERVER_CERT_PATH=/etc/dstreambolt/certs/server/server-cert.pem
MTLS_SERVER_KEY_PATH=/etc/dstreambolt/certs/server/server-key.pem
```

### Set via systemd override
```bash
sudo tee /etc/systemd/system/dstreambolt-ingest.service.d/mtls.conf << EOF
[Service]
Environment="MTLS_ENABLED=true"
Environment="MTLS_CA_CERT_PATH=/etc/dstreambolt/certs/ca/ca-cert.pem"
Environment="MTLS_CHECK_CRL=false"
EOF

sudo systemctl daemon-reload
sudo systemctl restart dstreambolt-ingest
```

## Security Best Practices

1. **Certificate Management**
   - Generate certificates with 4096-bit RSA keys
   - Set expiration to 90-365 days
   - Monitor expiration dates
   - Have renewal process documented

2. **Private Key Security**
   - Never commit private keys to git
   - Set permissions: `chmod 600 *.key.pem`
   - Store in encrypted volumes
   - Use secrets management (AWS Secrets Manager, Vault)

3. **Certificate Distribution**
   - Distribute via secure channels only
   - Unique certificates per client
   - Maintain client registry
   - Document revocation procedure

4. **Monitoring**
   - Alert on certificate expiration (30 days before)
   - Log all authentication attempts
   - Monitor for repeated failures
   - Track certificate usage

## Files Updated

### Core Changes:
- ✅ `ingestion/app.py` - Added mTLS startup validation
- ✅ `ingestion/requirements.txt` - Already has cryptography
- ✅ `examples/02-send-to-ingest.py` - Already has mTLS client support

### New Scripts:
- ✅ `enable_mtls.sh` - Enable mTLS on deployed server
- ✅ `generate_mtls_certs.sh` - Generate certificates
- ✅ `MTLS_IMPLEMENTATION.md` - Full implementation guide
- ✅ `MTLS_QUICK_REF.md` - Quick reference guide

## Next Steps

1. ✅ **Code Ready** - app.py is fixed and validated
2. ⏳ **Generate Certificates** - Run `./generate_mtls_certs.sh`
3. ⏳ **Deploy Code** - Via Jenkins or manual copy
4. ⏳ **Deploy Certificates** - Copy to `/etc/dstreambolt/certs/`
5. ⏳ **Enable mTLS** - Run `enable_mtls.sh` on server
6. ⏳ **Test** - Verify with client certificate
7. ⏳ **Monitor** - Check logs and metrics

## Status

**✅ READY TO DEPLOY**

The ingestion service is now fully prepared for mTLS:
- Code is fixed and validated
- Startup checks are in place
- Error handling is robust
- Scripts are ready
- Documentation is complete

You can deploy with or without mTLS - the service handles both cases gracefully!

