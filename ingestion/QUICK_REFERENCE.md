# Quick Reference - mTLS Authentication in app.py

## Environment Setup

```bash
# Enable mTLS authentication
export MTLS_ENABLED=true
export MTLS_CA_CERT_PATH=/etc/dstreambolt/certs/ca/ca-cert.pem
export MTLS_CHECK_CRL=true

# MySQL connection (for CRL and client registry)
export MYSQL_HOST=10.0.1.61
export MYSQL_USER=dstreambolt
export MYSQL_PASSWORD=DStreamBolt2025!
export MYSQL_DB=dstreambolt_metrics
```

## Client Usage

### Python Example
```python
import requests
import gzip

# Load mTLS credentials
CERT = '/etc/dstreambolt/credentials/client-cert.pem'
KEY = '/etc/dstreambolt/credentials/client-key.pem'
CA = '/etc/dstreambolt/credentials/ca-cert.pem'

# Prepare gzipped data
data = b'compressed log data...'

# Send with mTLS
response = requests.post(
    'https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/ingest',
    data=data,
    headers={'Content-Type': 'application/gzip'},
    cert=(CERT, KEY),
    verify=CA
)

print(response.status_code)  # 201
print(response.json())
# {
#   "status": "accepted",
#   "request_id": "uuid",
#   "client_id": "your-client-id",
#   "bundle_size_bytes": 12345,
#   "queue_position": 10,
#   "response_time_ms": 8.5
# }
```

### curl Example
```bash
curl -X POST https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/ingest \
  --cert /etc/dstreambolt/credentials/client-cert.pem \
  --key /etc/dstreambolt/credentials/client-key.pem \
  --cacert /etc/dstreambolt/credentials/ca-cert.pem \
  -H "Content-Type: application/gzip" \
  --data-binary @bundle.gz
```

## Error Responses

### 401 Unauthorized
```json
{
  "error": "Authentication failed",
  "details": "Certificate expired",
  "request_id": "uuid"
}
```

**Causes:**
- No client certificate provided
- Certificate expired
- Certificate revoked
- Client not registered
- Client status not 'active'

### 429 Rate Limited
```json
{
  "error": "Rate limit exceeded",
  "details": "150 requests in last 60s (limit: 100)",
  "request_id": "uuid",
  "retry_after": 60
}
```

### 503 Service Unavailable
```json
{
  "error": "Queue full or disk write failed",
  "details": "Queue full (10000/10000 files)",
  "request_id": "uuid"
}
```

## Admin Operations

### Check Client Status
```sql
-- View all registered clients
SELECT client_id, status, cert_expires_at 
FROM client_registry 
WHERE status = 'active';

-- Check specific client
SELECT * FROM client_registry WHERE client_id = 'company-xyz-prod';
```

### Revoke Certificate
```sql
-- Add to revocation list
INSERT INTO cert_revocation_list (serial_number, client_id, revocation_reason)
VALUES ('1A2B3C4D5E6F', 'company-xyz-prod', 'Security incident');

-- Update client status
UPDATE client_registry SET status = 'revoked' WHERE client_id = 'company-xyz-prod';
```

### View Authentication Logs
```sql
-- Recent auth failures
SELECT client_id, failure_reason, ip_address, timestamp
FROM auth_audit_log
WHERE success = FALSE
ORDER BY timestamp DESC
LIMIT 100;

-- Auth attempts by client
SELECT 
    client_id,
    COUNT(*) as total,
    SUM(CASE WHEN success THEN 1 ELSE 0 END) as successful,
    SUM(CASE WHEN NOT success THEN 1 ELSE 0 END) as failed
FROM auth_audit_log
WHERE timestamp >= NOW() - INTERVAL 1 HOUR
GROUP BY client_id;
```

## Monitoring

### Key Metrics
- `http_requests_total` - Total HTTP requests
- `http_requests_success` - Successful requests (201)
- `http_requests_failed` - Failed requests (401, 429, 503, etc.)
- `bundles_queued` - Bundles written to disk queue
- `queue_depth` - Current files in queue

### Health Check
```bash
curl https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/health
```

### Metrics Endpoint
```bash
curl https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/metrics
```

## Troubleshooting

### "No client certificate provided"
- Check ALB listener has mTLS enabled
- Verify client is sending certificate in request
- Check ALB passes certificate in `X-Amzn-Mtls-Clientcert` header

### "Certificate expired"
```bash
# Check certificate expiry
openssl x509 -in client-cert.pem -noout -dates
```

### "Certificate revoked"
```sql
-- Check if certificate is in CRL
SELECT * FROM cert_revocation_list WHERE serial_number = '1A2B3C4D5E6F';
```

### "Client not registered"
```sql
-- Register client
INSERT INTO client_registry (client_id, client_name, status, cert_serial_number)
VALUES ('company-xyz-prod', 'Company XYZ Production', 'active', '1A2B3C4D5E6F');
```

## Development/Testing

### Disable mTLS for local testing
```bash
export MTLS_ENABLED=false
python3 app.py
```

### Test with self-signed certificate
```bash
# Generate test CA and client cert
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout ca-key.pem -out ca-cert.pem \
  -days 365 -subj "/CN=Test CA"

openssl req -newkey rsa:2048 -nodes \
  -keyout client-key.pem -out client-csr.pem \
  -subj "/CN=test-client"

openssl x509 -req -in client-csr.pem \
  -CA ca-cert.pem -CAkey ca-key.pem -CAcreateserial \
  -out client-cert.pem -days 365
```

## Performance Tuning

### Rate Limiting
```bash
# Increase rate limit per IP
export RATE_LIMIT_PER_IP=200  # Default: 100

# Change rate limit window
export RATE_LIMIT_WINDOW=120  # seconds (default: 60)
```

### Queue Management
```bash
# Increase max queue size
export MAX_QUEUE_SIZE=20000  # files (default: 10000)

# Increase max bundle size
export MAX_BUNDLE_SIZE_MB=100  # MB (default: 50)
```

### Database Connection
```bash
# Connection timeout
export MYSQL_CONNECT_TIMEOUT=10  # seconds (default: 5)
```

---

**Last Updated**: December 11, 2025  
**Version**: 1.0.0 (mTLS-only)  
**Status**: Production Ready

