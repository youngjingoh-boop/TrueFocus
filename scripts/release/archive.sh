#!/usr/bin/env bash
# Archives one scheme with automatic signing through the App Store Connect API key.
#
#   scripts/release/archive.sh <scheme> <destination> <archive-path>
#   e.g. scripts/release/archive.sh TrueFocus 'generic/platform=iOS' "$RUNNER_TEMP/TrueFocus-iOS.xcarchive"
#
# Needs: TrueFocus.xcodeproj (run `xcodegen generate` first), ASC_KEY_PATH / ASC_KEY_ID /
# ASC_ISSUER_ID (setup-signing.sh), MARKETING_VERSION and BUILD_NUMBER (version.sh).
# The full log goes to <archive-path>.log.
set -euo pipefail

scheme="${1:?usage: archive.sh <scheme> <destination> <archive-path>}"
destination="${2:?usage: archive.sh <scheme> <destination> <archive-path>}"
archive="${3:?usage: archive.sh <scheme> <destination> <archive-path>}"
: "${ASC_KEY_PATH:?}" "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}" "${MARKETING_VERSION:?}" "${BUILD_NUMBER:?}"

log="$archive.log"
echo "Archiving $scheme $MARKETING_VERSION ($BUILD_NUMBER) for $destination…"
if ! xcodebuild archive \
    -project TrueFocus.xcodeproj \
    -scheme "$scheme" \
    -configuration Release \
    -destination "$destination" \
    -archivePath "$archive" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$ASC_KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
    MARKETING_VERSION="$MARKETING_VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    > "$log" 2>&1; then
  grep -E "error:|Provisioning profile|requires a provisioning profile|doesn't (include|support)" "$log" | sort -u | head -100 || true
  echo "::error::Archive of $scheme failed. Full log in the release-logs artifact."
  exit 1
fi
tail -n 3 "$log"

# The numbers every bundle in the archive ended up with (apps and extensions must agree).
find "$archive/Products" -maxdepth 6 \( -name "*.app" -o -name "*.appex" \) | while read -r bundle; do
  plist="$bundle/Info.plist"
  [[ -f "$plist" ]] || plist="$bundle/Contents/Info.plist"
  [[ -f "$plist" ]] || continue
  printf '%-40s %s (%s)\n' "$(basename "$bundle")" \
    "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" \
    "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
done
