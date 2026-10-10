#!/bin/bash
# Crea (una volta sola) il certificato self-signed "WorkHub Dev" nel portachiavi di login.
# Con una firma stabile macOS ricorda i permessi (portachiavi, microfono) tra una build e l'altra.
set -euo pipefail
NAME="WorkHub Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning | grep -q "\"$NAME\""; then
  echo "Certificato \"$NAME\" già presente, niente da fare."
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

# /usr/bin/openssl (LibreSSL di sistema) produce un .p12 che "security import" accetta.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -config "$TMP/cert.cnf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$NAME" -out "$TMP/cert.p12" -passout pass:workhub

# -T /usr/bin/codesign: codesign può usare la chiave senza chiedere ogni volta.
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P workhub -T /usr/bin/codesign

echo "Fatto: certificato \"$NAME\" creato. Ora lancia ./build.sh install"
