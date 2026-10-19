#!/usr/bin/env bash
# Notarizes and staples a Developer ID–signed TruFocus.app, then zips it for download.
#
#   scripts/release/notarize-mac.sh <path/to/TruFocus.app> <path/to/output.zip>
#
# Needs ASC_KEY_PATH, ASC_KEY_ID and ASC_ISSUER_ID (see setup-signing.sh). The API key needs
# the Developer role or higher.
set -euo pipefail

app="${1:?usage: notarize-mac.sh <TruFocus.app> <output.zip>}"
out="${2:?usage: notarize-mac.sh <TruFocus.app> <output.zip>}"
: "${ASC_KEY_PATH:?}" "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}"

[[ -d "$app" ]] || { echo "::error::$app not found"; exit 1; }

echo "Checking the signature before upload…"
codesign --verify --deep --strict --verbose=2 "$app"
codesign --display --verbose=2 "$app" 2>&1 | grep -E "^(Authority|TeamIdentifier|Runtime|Timestamp)" || true
if ! codesign --display --verbose=2 "$app" 2>&1 | grep -q "Authority=Developer ID Application"; then
  echo "::error::$app is not signed with a Developer ID Application certificate."
  exit 1
fi

work="$(mktemp -d)"
submission="$work/$(basename "$app" .app)-notarize.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$submission"

echo "Submitting to the notary service (usually 1–10 minutes)…"
result="$work/notary.json"
xcrun notarytool submit "$submission" \
  --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" \
  --wait --timeout 45m --output-format json > "$result" || true
cat "$result"
echo

status="$(/usr/bin/plutil -extract status raw -o - "$result" 2>/dev/null || echo "")"
id="$(/usr/bin/plutil -extract id raw -o - "$result" 2>/dev/null || echo "")"
if [[ "$status" != "Accepted" ]]; then
  echo "::error::Notarization finished with status '${status:-unknown}'."
  if [[ -n "$id" ]]; then
    xcrun notarytool log "$id" --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" || true
  fi
  exit 1
fi

xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=4 "$app"

ditto -c -k --sequesterRsrc --keepParent "$app" "$out"
rm -rf "$work"
echo "Notarized and stapled: $out"
