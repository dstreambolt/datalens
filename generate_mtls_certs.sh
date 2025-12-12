#!/bin/bash
# Generate self-signed certificates for mTLS testing
# Run this script to create CA, server, and client certificates

set -e

CERT_DIR="certs"
DAYS_VALID=365

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           mTLS Certificate Generation                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Create certs directory
mkdir -p $CERT_DIR/{ca,server,client}

echo "1️⃣  Generating CA (Certificate Authority)..."
# Generate CA private key
openssl genrsa -out $CERT_DIR/ca/ca-key.pem 4096

# Generate CA certificate
openssl req -new -x509 -days $DAYS_VALID -key $CERT_DIR/ca/ca-key.pem \
    -out $CERT_DIR/ca/ca-cert.pem \
    -subj "/C=US/ST=CA/L=SanFrancisco/O=DStreamBolt/OU=Security/CN=DStreamBolt-CA"

echo "✅ CA certificate generated: $CERT_DIR/ca/ca-cert.pem"
echo ""

echo "2️⃣  Generating Server Certificate..."
# Generate server private key
openssl genrsa -out $CERT_DIR/server/server-key.pem 4096

# Generate server CSR
openssl req -new -key $CERT_DIR/server/server-key.pem \
    -out $CERT_DIR/server/server.csr \
    -subj "/C=US/ST=CA/L=SanFrancisco/O=DStreamBolt/OU=Ingestion/CN=*.dstreambolt.com"

# Sign server certificate with CA
openssl x509 -req -days $DAYS_VALID \
    -in $CERT_DIR/server/server.csr \
    -CA $CERT_DIR/ca/ca-cert.pem \
    -CAkey $CERT_DIR/ca/ca-key.pem \
    -CAcreateserial \
    -out $CERT_DIR/server/server-cert.pem

echo "✅ Server certificate generated: $CERT_DIR/server/server-cert.pem"
echo ""

echo "3️⃣  Generating Client Certificate..."
# Generate client private key
openssl genrsa -out $CERT_DIR/client/client-key.pem 4096

# Generate client CSR
openssl req -new -key $CERT_DIR/client/client-key.pem \
    -out $CERT_DIR/client/client.csr \
    -subj "/C=US/ST=CA/L=SanFrancisco/O=DStreamBolt/OU=Client/CN=client-001"

# Sign client certificate with CA
openssl x509 -req -days $DAYS_VALID \
    -in $CERT_DIR/client/client.csr \
    -CA $CERT_DIR/ca/ca-cert.pem \
    -CAkey $CERT_DIR/ca/ca-key.pem \
    -CAcreateserial \
    -out $CERT_DIR/client/client-cert.pem

echo "✅ Client certificate generated: $CERT_DIR/client/client-cert.pem"
echo ""

# Set proper permissions
chmod 600 $CERT_DIR/ca/ca-key.pem
chmod 600 $CERT_DIR/server/server-key.pem
chmod 600 $CERT_DIR/client/client-key.pem
chmod 644 $CERT_DIR/ca/ca-cert.pem
chmod 644 $CERT_DIR/server/server-cert.pem
chmod 644 $CERT_DIR/client/client-cert.pem

echo "4️⃣  Verifying certificates..."
echo ""
echo "CA Certificate:"
openssl x509 -in $CERT_DIR/ca/ca-cert.pem -noout -subject -issuer -dates
echo ""
echo "Server Certificate:"
openssl x509 -in $CERT_DIR/server/server-cert.pem -noout -subject -issuer -dates
echo ""
echo "Client Certificate:"
openssl x509 -in $CERT_DIR/client/client-cert.pem -noout -subject -issuer -dates
echo ""

# Verify certificate chain
echo "5️⃣  Verifying certificate chain..."
if openssl verify -CAfile $CERT_DIR/ca/ca-cert.pem $CERT_DIR/server/server-cert.pem; then
    echo "✅ Server certificate chain valid"
fi
if openssl verify -CAfile $CERT_DIR/ca/ca-cert.pem $CERT_DIR/client/client-cert.pem; then
    echo "✅ Client certificate chain valid"
fi
echo ""

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                   Certificates Generated                    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "CA Certificate:     $CERT_DIR/ca/ca-cert.pem"
echo "CA Key:             $CERT_DIR/ca/ca-key.pem"
echo ""
echo "Server Certificate: $CERT_DIR/server/server-cert.pem"
echo "Server Key:         $CERT_DIR/server/server-key.pem"
echo ""
echo "Client Certificate: $CERT_DIR/client/client-cert.pem"
echo "Client Key:         $CERT_DIR/client/client-key.pem"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Next Steps:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Deploy certificates to ingestion server:"
echo "   scp -r $CERT_DIR/ca ubuntu@<ingestion-ip>:/etc/dstreambolt/certs/"
echo "   scp -r $CERT_DIR/server ubuntu@<ingestion-ip>:/etc/dstreambolt/certs/"
echo ""
echo "2. Enable mTLS on ingestion service:"
echo "   Set environment variables:"
echo "     MTLS_ENABLED=true"
echo "     MTLS_CA_CERT_PATH=/etc/dstreambolt/certs/ca/ca-cert.pem"
echo ""
echo "3. Test with client:"
echo "   python3 examples/02-send-to-ingest.py logs/access.log \\"
echo "     --alb-url https://ingest.example.com \\"
echo "     --client-cert $CERT_DIR/client/client-cert.pem \\"
echo "     --client-key $CERT_DIR/client/client-key.pem \\"
echo "     --ca-cert $CERT_DIR/ca/ca-cert.pem"
echo ""

