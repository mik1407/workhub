#!/bin/bash
# Creates (once only) the self-signed "WorkHub Dev" certificate in the login keychain.
# With a stable signature macOS remembers permissions (keychain, microphone) from one build to the next.
set -euo pipefail
NAME="WorkHub Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning | grep -q "\"$NAME\""; then
  echo "Certificate \"$NAME\" already present, nothing to do."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<CNF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $NAME
[ ext ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

# /usr/bin/openssl (the system LibreSSL) produces a .p12 that "security import" accepts.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -config "$TMP/cert.cnf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$NAME" -out "$TMP/cert.p12" -passout pass:workhub

# -T /usr/bin/codesign: codesign can use the key without asking every time.
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P workhub -T /usr/bin/codesign

echo "Done: certificate \"$NAME\" created. Now run ./build.sh install"
