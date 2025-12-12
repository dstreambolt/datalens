# DStreamBolt Security - Quick Reference

## Authentication Flow

```
Client Request → mTLS Validation → JWT Validation → CN Matching → ✅ Authorized
```

## Configuration (Quick Start)

```bash
# Enable security
export MTLS_ENABLED=true
export MTLS_CA_CERT_PATH=/etc/dstreambolt/certs/ca/ca-cert.pem
export JWT_SECRET_KEY=$(cat /etc/dstreambolt/jwt_secret)
export TOKEN_DENYLIST_ENABLED=true
```

## Generate Client Credentials

```bash
# Certificate
sudo bash setup_security.sh generate_client_cert "client-001"

# JWT Token
curl -X POST https://your-alb/admin/token/issue \
  -H 'Authorization: Bearer <admin-token>' \
  -d '{"client_id":"client-001","scopes":["ingest:write"]}'
```

## Client Usage

```python
# Python
response = requests.post(
    'https://your-alb/ingest',
    data=bundle_gz,
    headers={'Authorization': f'Bearer {jwt_token}'},
    cert=(cert_file, key_file),
    verify=ca_file
)
```

```bash
# curl
curl -X POST https://your-alb/ingest \
  --cert client-cert.pem \
  --key client-key.pem \
  -H "Authorization: Bearer $JWT_TOKEN" \
  --data-binary @bundle.gz
```

## Revocation

```bash
# Revoke Certificate
curl -X POST https://your-alb/admin/cert/revoke \
  -H 'Authorization: Bearer <admin-token>' \
  -d '{"serial_number":"<serial>","reason":"Compromised"}'

# Revoke Token
curl -X POST https://your-alb/admin/token/revoke \
  -H 'Authorization: Bearer <admin-token>' \
  -d '{"jti":"<token-id>","reason":"Compromised"}'
```

## Monitoring

```sql
-- Failed auth attempts (last hour)
SELECT client_id, COUNT(*) FROM auth_audit_log 
WHERE success=FALSE AND timestamp >= NOW() - INTERVAL 1 HOUR 
GROUP BY client_id;

-- Revoked credentials
SELECT COUNT(*) FROM cert_revocation_list WHERE revoked_at > NOW() - INTERVAL 1 DAY;
SELECT COUNT(*) FROM token_denylist WHERE revoked_at > NOW() - INTERVAL 1 DAY;
```

## Troubleshooting

| Error | Solution |
|-------|----------|
| Certificate expired | Rotate: `bash rotate_client_cert.sh client-001` |
| Token expired | Renew: `python3 renew_token.py` |
| CN mismatch | Ensure cert CN == JWT subject |
| Token revoked | Request new token via admin API |

## Files & Locations

```
/etc/dstreambolt/certs/
├── ca/
│   ├── ca-cert.pem           (CA certificate - distribute to clients)
│   └── ca-key.pem            (CA private key - KEEP SECRET)
├── server/
│   ├── server-cert.pem       (Server certificate)
│   └── server-key.pem        (Server private key)
└── clients/
    └── <client-id>/
        ├── client-cert.pem   (Client certificate)
        ├── client-key.pem    (Client private key)
        └── client-bundle.pem (All-in-one bundle)

/etc/dstreambolt/jwt_secret   (JWT signing key - KEEP SECRET)
```

## Security Checklist

- [ ] CA certificate generated and secured
- [ ] JWT secret generated and configured
- [ ] ALB configured for mTLS
- [ ] Database tables created
- [ ] Client certificates generated
- [ ] JWT tokens issued
- [ ] Test authentication successful
- [ ] Monitoring queries configured
- [ ] Rotation procedures documented
- [ ] Revocation procedures tested

## Key Points

- **Certificates**: Short-lived (90 days), auto-rotate
- **Tokens**: Short-lived (60 min), auto-renew
- **Revocation**: Immediate via CRL + denylist
- **Audit**: All auth attempts logged
- **Performance**: ~10-15ms overhead
- **Scalability**: Stateless validation

## Support

- **Full Documentation**: ingestion/SECURITY.md
- **Setup Script**: ingestion/setup_security.sh
- **Security Module**: ingestion/security.py

