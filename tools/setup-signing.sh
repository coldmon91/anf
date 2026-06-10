#!/bin/bash
# Creates a stable self-signed code-signing identity ("anf-dev") in the login
# keychain. Signing anf.app with a fixed identity keeps macOS TCC (file-access)
# permissions across rebuilds — ad-hoc signing changes every build and re-prompts.
# Run once:  ./tools/setup-signing.sh
set -euo pipefail

IDENTITY="anf-dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "✓ signing identity '$IDENTITY' already present"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cfg" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = anf-dev
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

echo "▸ Generating self-signed code-signing certificate…"
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cfg" >/dev/null 2>&1
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/$IDENTITY.p12" -passout pass:anf -name "$IDENTITY" >/dev/null 2>&1

echo "▸ Importing into the login keychain…"
security import "$TMP/$IDENTITY.p12" -k "$KEYCHAIN" -P anf -T /usr/bin/codesign >/dev/null

echo "✓ Created signing identity '$IDENTITY'."
echo "  It is self-signed (untrusted) — that's fine; codesign uses it locally and"
echo "  TCC remembers permissions by its stable identity. Rebuild with ./build.sh."
