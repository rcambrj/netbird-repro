#!/usr/bin/env bash

# Configuration
ISSUER=${ISSUER:-"http://localhost:8787"}
OUTPUT_DIR=${OUTPUT_DIR:-"/var/lib/fake-idp"}
KEY_ID=${KEY_ID:-"test-key"}
SUBJECT=${SUBJECT:-"test-user"}
AUDIENCE=${AUDIENCE:-"test-service"}

set -euo pipefail

# Install dependencies if needed
if ! command -v openssl &> /dev/null; then
    echo "openssl is required"
    exit 1
fi

# Create output directory structure
mkdir -p "$OUTPUT_DIR/.well-known"

# Generate RSA key pair
openssl genrsa -out $OUTPUT_DIR/private.pem 2048 2>/dev/null
openssl rsa -in $OUTPUT_DIR/private.pem -pubout -out $OUTPUT_DIR/public.pem 2>/dev/null

# Extract modulus and exponent for JWKS
MODULUS=$(openssl rsa -in $OUTPUT_DIR/private.pem -noout -modulus 2>/dev/null | sed 's/Modulus=//' | xxd -r -p | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')
EXPONENT=$(printf '%06x' 65537 | xxd -r -p | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')

# Create OIDC Discovery document
cat > "$OUTPUT_DIR/.well-known/openid-configuration" <<EOF
{
  "issuer": "$ISSUER",
  "jwks_uri": "$ISSUER/jwks.json",
  "authorization_endpoint": "$ISSUER/authorize",
  "token_endpoint": "$ISSUER/token",
  "userinfo_endpoint": "$ISSUER/userinfo",
  "response_types_supported": ["code", "token", "id_token"],
  "subject_types_supported": ["public"],
  "id_token_signing_alg_values_supported": ["RS256"]
}
EOF

# Create JWKS (JSON Web Key Set)
cat > "$OUTPUT_DIR/jwks.json" <<EOF
{
  "keys": [
    {
      "kty": "RSA",
      "kid": "$KEY_ID",
      "use": "sig",
      "alg": "RS256",
      "n": "$MODULUS",
      "e": "$EXPONENT"
    }
  ]
}
EOF

# Generate JWT with very long expiration (10 years from now)
NOW=$(date +%s)
EXP=$((NOW + 315360000))

# Create JWT header
HEADER=$(echo -n '{"alg":"RS256","typ":"JWT","kid":"'$KEY_ID'"}' | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')

# Create JWT payload
PAYLOAD=$(echo -n '{
  "iss":"'$ISSUER'",
  "sub":"'$SUBJECT'",
  "aud":"'$AUDIENCE'",
  "exp":'$EXP',
  "iat":'$NOW',
  "email":"test@example.com",
  "email_verified":true,
  "name":"Test User"
}' | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')

# Sign the JWT
SIGNATURE=$(echo -n "${HEADER}.${PAYLOAD}" | openssl dgst -sha256 -sign $OUTPUT_DIR/private.pem | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')

# Complete JWT
JWT="${HEADER}.${PAYLOAD}.${SIGNATURE}"

# Save JWT to file
echo "$JWT" > "$OUTPUT_DIR/token.jwt"

echo "✅ Fake OIDC Provider Setup Complete!"
echo ""
echo "📁 Files created in: $OUTPUT_DIR"
echo "  - private.pem"
echo "  - public.pem"
echo "  - .well-known/openid-configuration"
echo "  - jwks.json"
echo "  - token.jwt"
echo ""
echo "🔑 JWT Token (valid until $(date -d @$EXP '+%Y-%m-%d %H:%M:%S')):"
echo "$JWT"
echo ""
echo "🚀 Start your web server serving $OUTPUT_DIR on port $ISSUER"