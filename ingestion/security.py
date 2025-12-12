"""
DStreamBolt Ingestion Service - Security Module
Implements mTLS + JWT Hybrid Authentication

Features:
- mTLS certificate validation (mutual TLS)
- JWT token validation with claims
- Certificate rotation support
- Token revocation via allowlist/denylist
- Comprehensive audit logging
"""
import os
import jwt
import time
import json
from datetime import datetime, timedelta
from pathlib import Path
from typing import Tuple, Optional, Dict
from functools import wraps
from flask import request, jsonify
import pymysql
from cryptography import x509
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import serialization

# ============================================================================
# CONFIGURATION
# ============================================================================

# JWT Configuration
JWT_SECRET_KEY = os.getenv('JWT_SECRET_KEY', 'change-me-in-production')
JWT_ALGORITHM = 'HS256'
JWT_EXPIRY_MINUTES = int(os.getenv('JWT_EXPIRY_MINUTES', '60'))
JWT_ISSUER = os.getenv('JWT_ISSUER', 'dstreambolt-ingestion')

# mTLS Configuration
MTLS_ENABLED = os.getenv('MTLS_ENABLED', 'false').lower() == 'true'
MTLS_CA_CERT_PATH = os.getenv('MTLS_CA_CERT_PATH', '/etc/ssl/certs/ca-cert.pem')
MTLS_REQUIRE_CN_MATCH = os.getenv('MTLS_REQUIRE_CN_MATCH', 'true').lower() == 'true'

# Token Management
TOKEN_ALLOWLIST_ENABLED = os.getenv('TOKEN_ALLOWLIST_ENABLED', 'false').lower() == 'true'
TOKEN_DENYLIST_ENABLED = os.getenv('TOKEN_DENYLIST_ENABLED', 'true').lower() == 'true'

# MySQL for credential management
MYSQL_HOST = os.getenv('MYSQL_HOST', '10.0.1.61')
MYSQL_USER = os.getenv('MYSQL_USER', 'dstreambolt')
MYSQL_PASSWORD = os.getenv('MYSQL_PASSWORD', 'DStreamBolt2025!')
MYSQL_DB = os.getenv('MYSQL_DB', 'dstreambolt_metrics')

# ============================================================================
# DATABASE HELPERS
# ============================================================================

def get_db_connection():
    """Get database connection"""
    try:
        return pymysql.connect(
            host=MYSQL_HOST,
            user=MYSQL_USER,
            password=MYSQL_PASSWORD,
            database=MYSQL_DB,
            autocommit=True,
            connect_timeout=5
        )
    except Exception as e:
        print(f"❌ Security DB connection failed: {e}")
        return None


def log_auth_attempt(client_id: str, auth_method: str, success: bool,
                     reason: str = '', ip_address: str = '', user_agent: str = ''):
    """Log authentication attempt for audit"""
    try:
        conn = get_db_connection()
        if conn:
            cursor = conn.cursor()
            cursor.execute("""
                INSERT INTO auth_audit_log 
                (client_id, auth_method, success, failure_reason, ip_address, user_agent, timestamp)
                VALUES (%s, %s, %s, %s, %s, %s, NOW())
            """, (client_id[:255], auth_method, success, reason[:500],
                  ip_address[:45], user_agent[:500]))
            conn.close()
    except Exception as e:
        print(f"⚠️  Failed to log auth attempt: {e}")


# ============================================================================
# mTLS CERTIFICATE VALIDATION
# ============================================================================

class MTLSValidator:
    """Validates client certificates for mutual TLS"""

    def __init__(self):
        self.ca_cert = None
        if MTLS_ENABLED and Path(MTLS_CA_CERT_PATH).exists():
            self._load_ca_cert()

    def _load_ca_cert(self):
        """Load CA certificate for validation"""
        try:
            with open(MTLS_CA_CERT_PATH, 'rb') as f:
                self.ca_cert = x509.load_pem_x509_certificate(f.read(), default_backend())
            print(f"✅ Loaded CA certificate from {MTLS_CA_CERT_PATH}")
        except Exception as e:
            print(f"❌ Failed to load CA cert: {e}")

    def validate_client_cert(self, cert_pem: str) -> Tuple[bool, str, Dict]:
        """
        Validate client certificate
        Returns: (valid, error_message, cert_info)
        """
        if not MTLS_ENABLED:
            return True, '', {}

        if not cert_pem:
            return False, 'No client certificate provided', {}

        try:
            # Parse certificate
            cert = x509.load_pem_x509_certificate(cert_pem.encode(), default_backend())

            # Extract certificate info
            cert_info = {
                'subject_cn': cert.subject.get_attributes_for_oid(x509.oid.NameOID.COMMON_NAME)[0].value,
                'issuer': cert.issuer.rfc4514_string(),
                'serial_number': str(cert.serial_number),
                'not_before': cert.not_valid_before.isoformat(),
                'not_after': cert.not_valid_after.isoformat(),
                'fingerprint': cert.fingerprint(cert.signature_hash_algorithm).hex()
            }

            # Check expiry
            now = datetime.utcnow()
            if now < cert.not_valid_before:
                return False, 'Certificate not yet valid', cert_info

            if now > cert.not_valid_after:
                return False, 'Certificate expired', cert_info

            # Check revocation (against DB)
            if self._is_cert_revoked(cert_info['serial_number']):
                return False, 'Certificate revoked', cert_info

            # TODO: Verify signature against CA (requires full chain validation)
            # For production, use OpenSSL or cryptography's full chain validation

            print(f"✅ mTLS validated: CN={cert_info['subject_cn']}, SN={cert_info['serial_number'][:16]}...")
            return True, '', cert_info

        except Exception as e:
            return False, f'Certificate validation error: {str(e)}', {}

    def _is_cert_revoked(self, serial_number: str) -> bool:
        """Check if certificate is revoked"""
        try:
            conn = get_db_connection()
            if conn:
                cursor = conn.cursor()
                cursor.execute("""
                    SELECT COUNT(*) FROM cert_revocation_list 
                    WHERE serial_number = %s AND revoked_at IS NOT NULL
                """, (serial_number,))
                count = cursor.fetchone()[0]
                conn.close()
                return count > 0
        except:
            pass
        return False


# ============================================================================
# JWT TOKEN VALIDATION
# ============================================================================

class JWTValidator:
    """Validates JWT tokens with claims-based authorization"""

    def __init__(self):
        self.secret_key = JWT_SECRET_KEY
        self.algorithm = JWT_ALGORITHM
        self.issuer = JWT_ISSUER

    def generate_token(self, client_id: str, scopes: list = None,
                       metadata: dict = None) -> str:
        """
        Generate JWT token for client

        Args:
            client_id: Unique client identifier
            scopes: List of authorized scopes (e.g., ['ingest:write', 'metrics:read'])
            metadata: Additional claims (project_id, environment, etc.)
        """
        now = datetime.utcnow()
        expiry = now + timedelta(minutes=JWT_EXPIRY_MINUTES)

        payload = {
            'sub': client_id,  # Subject (client ID)
            'iss': self.issuer,  # Issuer
            'iat': int(now.timestamp()),  # Issued at
            'exp': int(expiry.timestamp()),  # Expiration
            'jti': f"{client_id}-{int(now.timestamp())}",  # JWT ID (unique)
            'scopes': scopes or ['ingest:write'],
        }

        # Add metadata as custom claims
        if metadata:
            payload.update(metadata)

        token = jwt.encode(payload, self.secret_key, algorithm=self.algorithm)

        # Log token issuance
        self._log_token_issued(client_id, payload['jti'], expiry)

        return token

    def validate_token(self, token: str, required_scopes: list = None) -> Tuple[bool, str, Dict]:
        """
        Validate JWT token

        Returns: (valid, error_message, claims)
        """
        if not token:
            return False, 'No token provided', {}

        try:
            # Decode and verify token
            claims = jwt.decode(
                token,
                self.secret_key,
                algorithms=[self.algorithm],
                issuer=self.issuer,
                options={'verify_exp': True}
            )

            client_id = claims.get('sub', 'unknown')
            jti = claims.get('jti', '')

            # Check denylist
            if TOKEN_DENYLIST_ENABLED and self._is_token_denylisted(jti):
                return False, 'Token revoked', claims

            # Check allowlist (if enabled)
            if TOKEN_ALLOWLIST_ENABLED and not self._is_token_allowlisted(jti):
                return False, 'Token not in allowlist', claims

            # Verify required scopes
            if required_scopes:
                token_scopes = claims.get('scopes', [])
                if not any(scope in token_scopes for scope in required_scopes):
                    return False, f'Insufficient scopes (need: {required_scopes})', claims

            return True, '', claims

        except jwt.ExpiredSignatureError:
            return False, 'Token expired', {}
        except jwt.InvalidIssuerError:
            return False, 'Invalid issuer', {}
        except jwt.InvalidTokenError as e:
            return False, f'Invalid token: {str(e)}', {}
        except Exception as e:
            return False, f'Token validation error: {str(e)}', {}

    def _is_token_denylisted(self, jti: str) -> bool:
        """Check if token is in denylist (revoked)"""
        try:
            conn = get_db_connection()
            if conn:
                cursor = conn.cursor()
                cursor.execute("""
                    SELECT COUNT(*) FROM token_denylist 
                    WHERE jti = %s AND revoked_at IS NOT NULL
                """, (jti,))
                count = cursor.fetchone()[0]
                conn.close()
                return count > 0
        except:
            pass
        return False

    def _is_token_allowlisted(self, jti: str) -> bool:
        """Check if token is in allowlist (explicitly allowed)"""
        try:
            conn = get_db_connection()
            if conn:
                cursor = conn.cursor()
                cursor.execute("""
                    SELECT COUNT(*) FROM token_allowlist 
                    WHERE jti = %s AND expires_at > NOW()
                """, (jti,))
                count = cursor.fetchone()[0]
                conn.close()
                return count > 0
        except:
            pass
        return not TOKEN_ALLOWLIST_ENABLED  # If allowlist disabled, allow all

    def _log_token_issued(self, client_id: str, jti: str, expiry: datetime):
        """Log token issuance"""
        try:
            conn = get_db_connection()
            if conn:
                cursor = conn.cursor()

                # Add to allowlist if enabled
                if TOKEN_ALLOWLIST_ENABLED:
                    cursor.execute("""
                        INSERT INTO token_allowlist (jti, client_id, issued_at, expires_at)
                        VALUES (%s, %s, NOW(), %s)
                    """, (jti, client_id, expiry))

                # Log issuance
                cursor.execute("""
                    INSERT INTO token_issuance_log (jti, client_id, issued_at, expires_at)
                    VALUES (%s, %s, NOW(), %s)
                """, (jti, client_id, expiry))

                conn.close()
        except Exception as e:
            print(f"⚠️  Failed to log token issuance: {e}")

    def revoke_token(self, jti: str, reason: str = ''):
        """Revoke a token (add to denylist)"""
        try:
            conn = get_db_connection()
            if conn:
                cursor = conn.cursor()
                cursor.execute("""
                    INSERT INTO token_denylist (jti, revoked_at, revocation_reason)
                    VALUES (%s, NOW(), %s)
                    ON DUPLICATE KEY UPDATE revoked_at = NOW(), revocation_reason = %s
                """, (jti, reason, reason))
                conn.close()
                print(f"🔒 Token revoked: {jti} (reason: {reason})")
        except Exception as e:
            print(f"⚠️  Failed to revoke token: {e}")


# ============================================================================
# HYBRID AUTHENTICATION (mTLS + JWT)
# ============================================================================

class HybridAuthenticator:
    """Combines mTLS and JWT validation for maximum security"""

    def __init__(self):
        self.mtls_validator = MTLSValidator()
        self.jwt_validator = JWTValidator()

    def authenticate(self, request_obj) -> Tuple[bool, str, Dict]:
        """
        Authenticate request using hybrid model

        Returns: (authenticated, error_message, auth_context)
        """
        ip_address = request_obj.remote_addr
        user_agent = request_obj.headers.get('User-Agent', 'unknown')

        auth_context = {
            'ip_address': ip_address,
            'user_agent': user_agent,
            'timestamp': datetime.utcnow().isoformat()
        }

        # Step 1: mTLS validation (if enabled)
        if MTLS_ENABLED:
            cert_pem = request_obj.headers.get('X-Client-Cert', '')
            # Note: In production with ALB, cert is in X-Amzn-Mtls-Clientcert header
            cert_pem = cert_pem or request_obj.headers.get('X-Amzn-Mtls-Clientcert', '')

            cert_valid, cert_error, cert_info = self.mtls_validator.validate_client_cert(cert_pem)

            if not cert_valid:
                log_auth_attempt('unknown', 'mtls', False, cert_error, ip_address, user_agent)
                return False, f'mTLS validation failed: {cert_error}', auth_context

            auth_context['mtls'] = cert_info
            auth_context['cert_cn'] = cert_info.get('subject_cn', 'unknown')

        # Step 2: JWT validation
        auth_header = request_obj.headers.get('Authorization', '')
        token = ''

        if auth_header.startswith('Bearer '):
            token = auth_header[7:]

        token_valid, token_error, claims = self.jwt_validator.validate_token(
            token,
            required_scopes=['ingest:write']
        )

        if not token_valid:
            client_id = auth_context.get('cert_cn', 'unknown')
            log_auth_attempt(client_id, 'jwt', False, token_error, ip_address, user_agent)
            return False, f'JWT validation failed: {token_error}', auth_context

        auth_context['jwt'] = claims
        auth_context['client_id'] = claims.get('sub', 'unknown')
        auth_context['scopes'] = claims.get('scopes', [])

        # Step 3: (Optional) Verify mTLS CN matches JWT subject
        if MTLS_ENABLED and MTLS_REQUIRE_CN_MATCH:
            cert_cn = auth_context.get('cert_cn', '')
            jwt_sub = auth_context.get('client_id', '')

            if cert_cn != jwt_sub:
                log_auth_attempt(jwt_sub, 'hybrid', False,
                               f'CN mismatch: cert={cert_cn}, jwt={jwt_sub}',
                               ip_address, user_agent)
                return False, 'Certificate CN does not match JWT subject', auth_context

        # Success!
        client_id = auth_context['client_id']
        log_auth_attempt(client_id, 'hybrid', True, '', ip_address, user_agent)

        print(f"✅ Authenticated: {client_id} from {ip_address}")
        return True, '', auth_context


# ============================================================================
# FLASK DECORATORS
# ============================================================================

# Global authenticator instance
authenticator = HybridAuthenticator()


def require_auth(f):
    """Decorator to require authentication on endpoints"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        authenticated, error, auth_context = authenticator.authenticate(request)

        if not authenticated:
            return jsonify({
                'error': 'Unauthorized',
                'details': error,
                'timestamp': datetime.utcnow().isoformat()
            }), 401

        # Attach auth context to request for use in handler
        request.auth_context = auth_context

        return f(*args, **kwargs)

    return decorated_function


# ============================================================================
# CREDENTIAL MANAGEMENT ENDPOINTS
# ============================================================================

def create_credential_routes(app):
    """Create admin endpoints for credential management"""

    @app.route('/admin/token/issue', methods=['POST'])
    @require_auth  # Admin must be authenticated
    def issue_token():
        """Issue new JWT token for a client"""
        data = request.get_json()

        client_id = data.get('client_id')
        scopes = data.get('scopes', ['ingest:write'])
        metadata = data.get('metadata', {})

        if not client_id:
            return jsonify({'error': 'client_id required'}), 400

        # Generate token
        token = authenticator.jwt_validator.generate_token(client_id, scopes, metadata)

        return jsonify({
            'token': token,
            'client_id': client_id,
            'scopes': scopes,
            'expires_in_minutes': JWT_EXPIRY_MINUTES
        }), 201

    @app.route('/admin/token/revoke', methods=['POST'])
    @require_auth
    def revoke_token():
        """Revoke a token"""
        data = request.get_json()

        jti = data.get('jti')
        reason = data.get('reason', 'Manual revocation')

        if not jti:
            return jsonify({'error': 'jti (token ID) required'}), 400

        authenticator.jwt_validator.revoke_token(jti, reason)

        return jsonify({
            'status': 'revoked',
            'jti': jti,
            'reason': reason
        }), 200

    @app.route('/admin/cert/revoke', methods=['POST'])
    @require_auth
    def revoke_cert():
        """Revoke a client certificate"""
        data = request.get_json()

        serial_number = data.get('serial_number')
        reason = data.get('reason', 'Manual revocation')

        if not serial_number:
            return jsonify({'error': 'serial_number required'}), 400

        try:
            conn = get_db_connection()
            if conn:
                cursor = conn.cursor()
                cursor.execute("""
                    INSERT INTO cert_revocation_list (serial_number, revoked_at, revocation_reason)
                    VALUES (%s, NOW(), %s)
                    ON DUPLICATE KEY UPDATE revoked_at = NOW(), revocation_reason = %s
                """, (serial_number, reason, reason))
                conn.close()

                return jsonify({
                    'status': 'revoked',
                    'serial_number': serial_number,
                    'reason': reason
                }), 200
        except Exception as e:
            return jsonify({'error': str(e)}), 500


# ============================================================================
# DATABASE SCHEMA SETUP
# ============================================================================

SQL_SCHEMA = """
-- Authentication audit log
CREATE TABLE IF NOT EXISTS auth_audit_log (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    client_id VARCHAR(255),
    auth_method VARCHAR(50),
    success BOOLEAN,
    failure_reason VARCHAR(500),
    ip_address VARCHAR(45),
    user_agent VARCHAR(500),
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX(client_id),
    INDEX(timestamp),
    INDEX(success)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Token denylist (revoked tokens)
CREATE TABLE IF NOT EXISTS token_denylist (
    jti VARCHAR(255) PRIMARY KEY,
    revoked_at TIMESTAMP,
    revocation_reason VARCHAR(500),
    INDEX(revoked_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Token allowlist (optional - for strict control)
CREATE TABLE IF NOT EXISTS token_allowlist (
    jti VARCHAR(255) PRIMARY KEY,
    client_id VARCHAR(255),
    issued_at TIMESTAMP,
    expires_at TIMESTAMP,
    INDEX(client_id),
    INDEX(expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Token issuance log
CREATE TABLE IF NOT EXISTS token_issuance_log (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    jti VARCHAR(255),
    client_id VARCHAR(255),
    issued_at TIMESTAMP,
    expires_at TIMESTAMP,
    INDEX(client_id),
    INDEX(issued_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Certificate revocation list
CREATE TABLE IF NOT EXISTS cert_revocation_list (
    serial_number VARCHAR(255) PRIMARY KEY,
    revoked_at TIMESTAMP,
    revocation_reason VARCHAR(500),
    INDEX(revoked_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Client registration (for tracking authorized clients)
CREATE TABLE IF NOT EXISTS client_registry (
    client_id VARCHAR(255) PRIMARY KEY,
    client_name VARCHAR(255),
    registered_at TIMESTAMP,
    last_seen_at TIMESTAMP,
    cert_serial_number VARCHAR(255),
    status ENUM('active', 'suspended', 'revoked') DEFAULT 'active',
    metadata JSON,
    INDEX(status),
    INDEX(last_seen_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
"""


def setup_security_tables():
    """Initialize security-related database tables"""
    try:
        conn = get_db_connection()
        if conn:
            cursor = conn.cursor()
            for statement in SQL_SCHEMA.split(';'):
                if statement.strip():
                    cursor.execute(statement)
            conn.close()
            print("✅ Security tables created/verified")
    except Exception as e:
        print(f"❌ Failed to create security tables: {e}")

