#!/usr/bin/env bash
# CI signing setup for the Release workflow (macOS runners only).
#
# 1. Writes the App Store Connect API key (secret ASC_KEY_P8) to a private temp file and
#    exports ASC_KEY_PATH, so xcodebuild (-authenticationKeyPath) and notarytool (--key)
#    can use it. ASC_KEY_P8 may be the .p8 file's text or that text base64-encoded.
# 2. Optionally imports signing certificates (.p12, base64) into a throwaway keychain:
#      APPLE_DEVELOPMENT_P12_BASE64 / APPLE_DEVELOPMENT_P12_PASSWORD
#        Stops Xcode minting a fresh "Apple Development" certificate on every run.
#      DEVELOPER_ID_P12_BASE64 / DEVELOPER_ID_P12_PASSWORD
#        Developer ID Application certificate, for the Mac export when the API key can't
#        use the cloud-managed Developer ID certificate.
#    Without them, Xcode's automatic signing (-allowProvisioningUpdates) uses cloud-managed
#    certificates through the API key.
#
# Never echoes secret values. Clean up with scripts/release/cleanup-signing.sh.
set -euo pipefail

: "${RUNNER_TEMP:?RUNNER_TEMP is not set (run this on a GitHub Actions runner)}"
: "${GITHUB_ENV:?GITHUB_ENV is not set (run this on a GitHub Actions runner)}"
[[ -n "${ASC_KEY_ID:-}" ]] || { echo "::error::Repository secret ASC_KEY_ID is missing."; exit 1; }
[[ -n "${ASC_ISSUER_ID:-}" ]] || { echo "::error::Repository secret ASC_ISSUER_ID is missing."; exit 1; }
[[ -n "${ASC_KEY_P8:-}" ]] || { echo "::error::Repository secret ASC_KEY_P8 is missing."; exit 1; }

umask 077
key_dir="$RUNNER_TEMP/asc"
mkdir -p "$key_dir"
key_path="$key_dir/AuthKey_${ASC_KEY_ID}.p8"

if printf '%s' "$ASC_KEY_P8" | grep -q -- "-----BEGIN PRIVATE KEY-----"; then
  printf '%s\n' "$ASC_KEY_P8" > "$key_path"
else
  printf '%s' "$ASC_KEY_P8" | base64 --decode > "$key_path" 2>/dev/null || true
fi
grep -q -- "-----BEGIN PRIVATE KEY-----" "$key_path" \
  || { echo "::error::ASC_KEY_P8 is not a .p8 key. Paste the whole AuthKey_XXXX.p8 file, BEGIN/END lines included."; exit 1; }
echo "ASC_KEY_PATH=$key_path" >> "$GITHUB_ENV"
echo "App Store Connect API key written for key ID $ASC_KEY_ID."

# Optional certificates.
pairs=(
  "APPLE_DEVELOPMENT_P12_BASE64:APPLE_DEVELOPMENT_P12_PASSWORD"
  "DEVELOPER_ID_P12_BASE64:DEVELOPER_ID_P12_PASSWORD"
)
keychain="$RUNNER_TEMP/tf-signing.keychain-db"
keychain_password=""

for pair in "${pairs[@]}"; do
  data_var="${pair%%:*}"
  pass_var="${pair##*:}"
  data="${!data_var:-}"
  [[ -n "$data" ]] || continue

  if [[ -z "$keychain_password" ]]; then
    keychain_password="$(uuidgen)"
    security create-keychain -p "$keychain_password" "$keychain"
    security set-keychain-settings -lut 21600 "$keychain"
    security unlock-keychain -p "$keychain_password" "$keychain"
    # Put it first in the search list, keeping the login and system keychains after it.
    existing=()
    while IFS= read -r line; do
      line="${line#"${line%%[![:space:]]*}"}"
      line="${line%\"}"
      line="${line#\"}"
      [[ -n "$line" ]] && existing+=("$line")
    done < <(security list-keychains -d user)
    security list-keychains -d user -s "$keychain" "${existing[@]}"
    echo "TF_KEYCHAIN_PATH=$keychain" >> "$GITHUB_ENV"
  fi

  p12="$RUNNER_TEMP/${data_var}.p12"
  printf '%s' "$data" | base64 --decode > "$p12"
  security import "$p12" -k "$keychain" -P "${!pass_var:-}" -f pkcs12 \
    -T /usr/bin/codesign -T /usr/bin/security -T /usr/bin/productbuild
  rm -f "$p12"
  echo "Imported the certificate from $data_var."
done

if [[ -n "$keychain_password" ]]; then
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" > /dev/null
  security find-identity -v -p codesigning "$keychain"
else
  echo "No .p12 secrets set: Xcode will use cloud-managed signing through the API key."
fi
