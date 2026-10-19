#!/usr/bin/env bash
# Exports (and, for App Store Connect, uploads) an archive with automatic signing.
#
#   scripts/release/export.sh <archive-path> <export-options.plist> <export-path>
#
# Copies the export options, adds the team ID the project builds with, and runs
# xcodebuild -exportArchive with the App Store Connect API key. With
# Config/ExportOptions/AppStore.plist (destination = upload) this is the TestFlight upload.
set -euo pipefail

archive="${1:?usage: export.sh <archive> <options.plist> <export-path>}"
options="${2:?usage: export.sh <archive> <options.plist> <export-path>}"
export_path="${3:?usage: export.sh <archive> <options.plist> <export-path>}"
: "${ASC_KEY_PATH:?}" "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}"

team="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:Team' "$archive/Info.plist" 2>/dev/null || true)"
if [[ -z "$team" ]]; then
  team="$(xcodebuild -showBuildSettings -project TrueFocus.xcodeproj -scheme TrueFocus -configuration Release 2>/dev/null \
    | awk -F' = ' '/^[[:space:]]*DEVELOPMENT_TEAM = /{print $2; exit}')"
fi
[[ "$team" =~ ^[A-Z0-9]{10}$ ]] || { echo "::error::Couldn't work out the team ID (got '$team')."; exit 1; }

mkdir -p "$export_path"
plist="$export_path/ExportOptions.plist"
cp "$options" "$plist"
/usr/libexec/PlistBuddy -c "Add :teamID string $team" "$plist"

log="$export_path/export.log"
echo "Exporting $(basename "$archive") with $(basename "$options") for team $team…"
if ! xcodebuild -exportArchive \
    -archivePath "$archive" \
    -exportPath "$export_path" \
    -exportOptionsPlist "$plist" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$ASC_KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
    > "$log" 2>&1; then
  grep -E "error|Error|permission|entitlement|No (suitable|profiles)|already been used|bundle version" "$log" | sort -u | head -100 || true
  echo "::error::Export failed. See docs/RELEASE.md > Troubleshooting. Full log in the release-logs artifact."
  exit 1
fi
tail -n 5 "$log"
