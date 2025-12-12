#!/bin/bash
# DStreamBolt Security Setup - mTLS + JWT Hybrid Authentication
# This script sets up certificates, tokens, and security infrastructure

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔐 DStreamBolt Security Setup (mTLS + JWT)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Configuration
CERT_DIR="/etc/dstreambolt/certs"
CA_DIR="$CERT_DIR/ca"
SERVER_DIR="$CERT_DIR/server"
CLIENT_DIR="$CERT_DIR/clients"
VALIDITY_DAYS_CA=3650  # 10 years
VALIDITY_DAYS_SERVER=365  # 1 year
VALIDITY_DAYS_CLIENT=90  # 90 days (short-lived, should rotate)

# JWT configuration
JWT_SECRET_FILE="/etc/dstreambolt/jwt_secret"

# ============================================================================
# Step 1: Create directory structure
# ============================================================================

echo "📁 Creating certificate directories..."
sudo mkdir -p "$CA_DIR" "$SERVER_DIR" "$CLIENT_DIR"
sudo chmod 700 "$CERT_DIR"

# ============================================================================
# Step 2: Generate CA (Certificate Authority)
# ============================================================================

if [ ! -f "$CA_DIR/ca-key.pem" ]; then
    echo "🔑 Generating CA private key..."
    sudo openssl genrsa -out "$CA_DIR/ca-key.pem" 4096
    sudo chmod 400 "$CA_DIR/ca-key.pem"
else
    echo "✅ CA key already exists"
fi

if [ ! -f "$CA_DIR/ca-cert.pem" ]; then
    echo "📜 Generating CA certificate..."
    sudo openssl req -new -x509 -key "$CA_DIR/ca-key.pem" \
        -days "$VALIDITY_DAYS_CA" \
        -out "$CA_DIR/ca-cert.pem" \
        -subj "/C=US/ST=Cloud/L=DataCenter/O=DStreamBolt/CN=DStreamBolt-CA"
    sudo chmod 444 "$CA_DIR/ca-cert.pem"

    echo "✅ CA certificate created"
    echo "   Fingerprint: $(openssl x509 -noout -fingerprint -sha256 -in $CA_DIR/ca-cert.pem)"
else
    echo "✅ CA certificate already exists"
fi

# ============================================================================
# Step 3: Generate server certificate (for ingestion service)
# ============================================================================

if [ ! -f "$SERVER_DIR/server-key.pem" ]; then
    echo "🔑 Generating server private key..."
    sudo openssl genrsa -out "$SERVER_DIR/server-key.pem" 2048
    sudo chmod 400 "$SERVER_DIR/server-key.pem"
fi

if [ ! -f "$SERVER_DIR/server-cert.pem" ]; then
    echo "📜 Generating server certificate..."

    # Create CSR
    sudo openssl req -new \
        -key "$SERVER_DIR/server-key.pem" \
        -out "$SERVER_DIR/server.csr" \
        -subj "/C=US/ST=Cloud/L=DataCenter/O=DStreamBolt/CN=dstreambolt-ingest"

    # Create SAN config
    cat > /tmp/server_san.cnf << EOF
[ req ]
default_bits = 2048
distinguished_name = req_distinguished_name
req_extensions = v3_req

[ req_distinguished_name ]

[ v3_req ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = dstreambolt-ingest
DNS.2 = localhost
DNS.3 = *.dstreambolt.dashbird.com
IP.1 = 127.0.0.1
IP.2 = 10.0.0.0/8
EOF

    # Sign with CA
    sudo openssl x509 -req \
        -in "$SERVER_DIR/server.csr" \
        -CA "$CA_DIR/ca-cert.pem" \
        -CAkey "$CA_DIR/ca-key.pem" \
        -CAcreateserial \
        -out "$SERVER_DIR/server-cert.pem" \
        -days "$VALIDITY_DAYS_SERVER" \
        -extensions v3_req \
        -extfile /tmp/server_san.cnf

    sudo chmod 444 "$SERVER_DIR/server-cert.pem"

    echo "✅ Server certificate created"
    echo "   Expires: $(openssl x509 -noout -enddate -in $SERVER_DIR/server-cert.pem)"
fi

# ============================================================================
# Step 4: Generate client certificate template function
# ============================================================================

generate_client_cert() {
    local CLIENT_NAME="$1"
    local CLIENT_CERT_DIR="$CLIENT_DIR/$CLIENT_NAME"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔑 Generating client certificate: $CLIENT_NAME"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    sudo mkdir -p "$CLIENT_CERT_DIR"

    # Generate client key
    sudo openssl genrsa -out "$CLIENT_CERT_DIR/client-key.pem" 2048
    sudo chmod 400 "$CLIENT_CERT_DIR/client-key.pem"

    # Generate CSR
    sudo openssl req -new \
        -key "$CLIENT_CERT_DIR/client-key.pem" \
        -out "$CLIENT_CERT_DIR/client.csr" \
        -subj "/C=US/ST=Cloud/L=DataCenter/O=DStreamBolt/CN=$CLIENT_NAME"

    # Sign with CA
    sudo openssl x509 -req \
        -in "$CLIENT_CERT_DIR/client.csr" \
        -CA "$CA_DIR/ca-cert.pem" \
        -CAkey "$CA_DIR/ca-key.pem" \
        -CAcreateserial \
        -out "$CLIENT_CERT_DIR/client-cert.pem" \
        -days "$VALIDITY_DAYS_CLIENT"

    sudo chmod 444 "$CLIENT_CERT_DIR/client-cert.pem"

    # Create bundle (cert + key + CA for easy distribution)
    sudo cat "$CLIENT_CERT_DIR/client-cert.pem" \
             "$CLIENT_CERT_DIR/client-key.pem" \
             "$CA_DIR/ca-cert.pem" > "$CLIENT_CERT_DIR/client-bundle.pem"

    sudo chmod 400 "$CLIENT_CERT_DIR/client-bundle.pem"

    # Get serial number for registration
    SERIAL=$(openssl x509 -noout -serial -in "$CLIENT_CERT_DIR/client-cert.pem" | cut -d= -f2)
    EXPIRY=$(openssl x509 -noout -enddate -in "$CLIENT_CERT_DIR/client-cert.pem" | cut -d= -f2)

    echo "✅ Client certificate created for: $CLIENT_NAME"
    echo "   Serial: $SERIAL"
    echo "   Expires: $EXPIRY"
    echo "   Location: $CLIENT_CERT_DIR"
    echo ""
    echo "📦 Files created:"
    echo "   Certificate: $CLIENT_CERT_DIR/client-cert.pem"
    echo "   Private Key: $CLIENT_CERT_DIR/client-key.pem"
    echo "   Bundle:      $CLIENT_CERT_DIR/client-bundle.pem"
    echo ""
}

# Generate example client certificates
echo ""
echo "📋 Generating sample client certificates..."
generate_client_cert "agent-001"
generate_client_cert "agent-002"

# ============================================================================
# Step 5: Generate JWT secret
# ============================================================================

if [ ! -f "$JWT_SECRET_FILE" ]; then
    echo "🔐 Generating JWT secret..."
    openssl rand -base64 64 | sudo tee "$JWT_SECRET_FILE" > /dev/null
    sudo chmod 400 "$JWT_SECRET_FILE"
    echo "✅ JWT secret generated: $JWT_SECRET_FILE"
else
    echo "✅ JWT secret already exists"
fi

# ============================================================================
# Step 6: Configure ALB for mTLS (if using AWS ALB)
# ============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 AWS ALB mTLS Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "To enable mTLS on AWS ALB:"
echo ""
echo "1. Upload CA certificate to ACM:"
echo "   aws acm import-certificate \\"
echo "     --certificate fileb://$CA_DIR/ca-cert.pem \\"
echo "     --private-key fileb://$CA_DIR/ca-key.pem \\"
echo "     --region ap-south-1"
echo ""
echo "2. Configure ALB listener to use mTLS:"
echo "   - Go to EC2 > Load Balancers"
echo "   - Select your ALB"
echo "   - Edit HTTPS listener"
echo "   - Add client certificate verification"
echo "   - Select uploaded CA cert"
echo "   - Mode: 'verify' (enforce mTLS)"
echo ""
echo "3. ALB will pass client cert to backend via header:"
echo "   X-Amzn-Mtls-Clientcert"
echo ""

# ============================================================================
# Step 7: Environment variables for service
# ============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⚙️  Environment Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Add these to /etc/systemd/system/dstreambolt-ingest.service:"
echo ""
echo "[Service]"
echo "Environment=\"MTLS_ENABLED=true\""
echo "Environment=\"MTLS_CA_CERT_PATH=$CA_DIR/ca-cert.pem\""
echo "Environment=\"MTLS_REQUIRE_CN_MATCH=true\""
echo "Environment=\"JWT_SECRET_KEY=$(cat $JWT_SECRET_FILE)\""
echo "Environment=\"JWT_EXPIRY_MINUTES=60\""
echo "Environment=\"TOKEN_DENYLIST_ENABLED=true\""
echo ""
echo "Then: sudo systemctl daemon-reload && sudo systemctl restart dstreambolt-ingest"
echo ""

# ============================================================================
# Step 8: Summary and next steps
# ============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Security Setup Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📂 Certificate Directory: $CERT_DIR"
echo "🔐 JWT Secret: $JWT_SECRET_FILE"
echo ""
echo "📋 Next Steps:"
echo ""
echo "1. Distribute client certificates to agents:"
echo "   - Copy files from $CLIENT_DIR/<client-name>/"
echo "   - Secure transfer (encrypted channel)"
echo ""
echo "2. Issue JWT tokens via admin API:"
echo "   curl -X POST https://your-alb/admin/token/issue \\"
echo "     -H 'Authorization: Bearer <admin-token>' \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"client_id\":\"agent-001\",\"scopes\":[\"ingest:write\"]}'"
echo ""
echo "3. Test authentication:"
echo "   curl -X POST https://your-alb/ingest \\"
echo "     --cert $CLIENT_DIR/agent-001/client-cert.pem \\"
echo "     --key $CLIENT_DIR/agent-001/client-key.pem \\"
echo "     --cacert $CA_DIR/ca-cert.pem \\"
echo "     -H 'Authorization: Bearer <jwt-token>' \\"
echo "     --data-binary @bundle.gz"
echo ""
echo "4. Monitor authentication:"
echo "   - Check auth_audit_log table in MySQL"
echo "   - Review /var/log/dstreambolt-ingest.log"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

