#!/bin/bash
set -euo pipefail

KEYSTORE_DIR="$HOME/Library/Application Support/DisplayWeave/Signing"
KEYSTORE_PATH="$KEYSTORE_DIR/android-preview.jks"
KEY_ALIAS="displayweave-preview"
KEYCHAIN_SERVICE="app.displayweave.android-preview-signing"
KEYCHAIN_ACCOUNT="displayweave-preview"

if [[ -e "$KEYSTORE_PATH" ]]; then
  echo "Refusing to overwrite existing keystore: $KEYSTORE_PATH" >&2
  exit 2
fi

if security find-generic-password \
    -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" >/dev/null 2>&1; then
  echo "Refusing to replace an existing Keychain signing password." >&2
  echo "Restore the matching keystore backup instead." >&2
  exit 3
fi

install -d -m 700 "$KEYSTORE_DIR"
password="$(openssl rand -base64 48 | tr -d '\n')"
export DISPLAYWEAVE_KEYSTORE_PASSWORD="$password"

cleanup() {
  unset DISPLAYWEAVE_KEYSTORE_PASSWORD password
}
trap cleanup EXIT

keytool -genkeypair \
  -keystore "$KEYSTORE_PATH" \
  -storepass:env DISPLAYWEAVE_KEYSTORE_PASSWORD \
  -keypass:env DISPLAYWEAVE_KEYSTORE_PASSWORD \
  -alias "$KEY_ALIAS" \
  -keyalg RSA \
  -keysize 4096 \
  -validity 9125 \
  -dname "CN=DisplayWeave Preview, O=DisplayWeave"

chmod 600 "$KEYSTORE_PATH"
security add-generic-password \
  -s "$KEYCHAIN_SERVICE" \
  -a "$KEYCHAIN_ACCOUNT" \
  -w "$password"

echo "Created DisplayWeave Android Preview signing identity."
echo "Keystore: $KEYSTORE_PATH"
echo "Alias: $KEY_ALIAS"
echo "Certificate fingerprint:"
keytool -exportcert -rfc \
  -keystore "$KEYSTORE_PATH" \
  -storepass:env DISPLAYWEAVE_KEYSTORE_PASSWORD \
  -alias "$KEY_ALIAS" \
  | openssl x509 -noout -fingerprint -sha256
echo "Back up the JKS and keep its Keychain password available; losing it prevents APK updates."
