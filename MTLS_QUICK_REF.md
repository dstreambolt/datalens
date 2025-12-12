# mTLS Quick Reference

## Quick Setup (5 minutes)

### 1. Generate Certificates
```bash
cd /Users/skalaise/apps/cloud/terraform/dstream_bolt
./generate_mtls_certs.sh
```

### 2. Test Locally (Without Server mTLS)
```bash
# Generate test logs
python3 examples/01-generate-logs.py --count 100 --output logs/test.log

# Send without mTLS (server doesn't require it yet)
python3 examples/02-send-to-ingest.py logs/test.log \
  --alb-url https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com \
  --no-verify
```

### 3. Deploy Certificates to Server
```bash
# Get ingestion server IP
INGEST_IP="<your-ingestion-server-ip>"

# Create cert directory
ssh ubuntu@$INGEST_IP "sudo mkdir -p /etc/dstreambolt/certs && sudo chown -R ubuntu:ubuntu /etc/dstreambolt/certs"

# Copy certificates
scp -r certs/ca certs/server ubuntu@$INGEST_IP:/etc/dstreambolt/certs/
```

### 4. Enable mTLS on Server
```bash
ssh ubuntu@$INGEST_IP

# Configure service
sudo mkdir -p /etc/systemd/system/dstreambolt-ingest.service.d
sudo tee /etc/systemd/system/dstreambolt-ingest.service.d/mtls.conf << EOF
[Service]
Environment="MTLS_ENABLED=true"
Environment="MTLS_CA_CERT_PATH=/etc/dstreambolt/certs/ca/ca-cert.pem"
EOF

# Restart
sudo systemctl daemon-reload
sudo systemctl restart dstreambolt-ingest

# Verify
sudo journalctl -u dstreambolt-ingest -n 20 | grep mTLS
```

### 5. Test with mTLS
```bash
# Send with client certificate
python3 examples/02-send-to-ingest.py logs/test.log \
  --alb-url https://ingest.dstreambolt.dashbird.com \
  --client-cert certs/client/client-cert.pem \
  --client-key certs/client/client-key.pem \
  --ca-cert certs/ca/ca-cert.pem
```

## Common Commands

### Send Logs (No mTLS)
```bash
python3 examples/02-send-to-ingest.py logs/access.log \
  --alb-url https://your-alb-url.amazonaws.com
```

### Send Logs (With mTLS)
```bash
python3 examples/02-send-to-ingest.py logs/access.log \
  --alb-url https://ingest.example.com \
  --client-cert certs/client/client-cert.pem \
  --client-key certs/client/client-key.pem \
  --ca-cert certs/ca/ca-cert.pem
```

### Streaming Mode
```bash
python3 examples/02-send-to-ingest.py logs/access.log \
  --alb-url https://ingest.example.com \
  --mode stream \
  --batch-size 100 \
  --delay 1.0 \
  --client-cert certs/client/client-cert.pem \
  --client-key certs/client/client-key.pem
```

### Check Certificate Details
```bash
# View certificate
openssl x509 -in certs/client/client-cert.pem -text -noout

# Check expiration
openssl x509 -in certs/client/client-cert.pem -noout -enddate

# Verify certificate chain
openssl verify -CAfile certs/ca/ca-cert.pem certs/client/client-cert.pem
```

### Troubleshooting

#### Check if mTLS is enabled on server
```bash
ssh ubuntu@<ingestion-ip>
sudo journalctl -u dstreambolt-ingest -n 50 | grep -i mtls
```

#### Test connection without certificate
```bash
curl -v https://ingest.example.com/health
# Should fail with mTLS enabled
```

#### Test connection with certificate
```bash
curl -v \
  --cert certs/client/client-cert.pem \
  --key certs/client/client-key.pem \
  --cacert certs/ca/ca-cert.pem \
  https://ingest.example.com/health
```

## Certificate Files

| File | Description | Keep Secret? |
|------|-------------|--------------|
| `ca/ca-cert.pem` | CA certificate (public) | No |
| `ca/ca-key.pem` | CA private key | **YES** |
| `server/server-cert.pem` | Server certificate | No |
| `server/server-key.pem` | Server private key | **YES** |
| `client/client-cert.pem` | Client certificate | No |
| `client/client-key.pem` | Client private key | **YES** |

## Environment Variables (Server)

```bash
MTLS_ENABLED=true                                    # Enable mTLS
MTLS_CA_CERT_PATH=/etc/dstreambolt/certs/ca/ca-cert.pem
MTLS_SERVER_CERT_PATH=/etc/dstreambolt/certs/server/server-cert.pem  # Optional
MTLS_SERVER_KEY_PATH=/etc/dstreambolt/certs/server/server-key.pem    # Optional
MTLS_CHECK_CRL=false                                 # CRL checking (future)
```

## Security Checklist

- [ ] Certificates generated with strong keys (4096-bit RSA)
- [ ] Private keys have restricted permissions (600)
- [ ] Certificates not in version control (.gitignore)
- [ ] CA private key stored securely
- [ ] Certificate expiration monitoring in place
- [ ] Client certificates unique per client
- [ ] Revocation process documented
- [ ] Certificates backed up securely

## Current Status

✅ Client-side implementation complete
✅ Certificate generation script ready
⏳ Server-side mTLS disabled (default)
⏳ Ready to enable and test

## Support

For issues or questions, check:
- `MTLS_IMPLEMENTATION.md` - Full implementation guide
- `examples/README.md` - Detailed examples
- Server logs: `sudo journalctl -u dstreambolt-ingest -f`

