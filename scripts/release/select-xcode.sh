#!/usr/bin/env bash
# Selects the Xcode for a release build. App Store Connect rejects builds made with beta
# Xcodes, so this picks the newest *release* Xcode on the runner, or exactly
# /Applications/Xcode_$XCODE_VERSION.app when the XCODE_VERSION variable is set.
set -euo pipefail

if [[ -n "${XCODE_VERSION:-}" ]]; then
  xcode="/Applications/Xcode_${XCODE_VERSION}.app"
  [[ -d "$xcode" ]] || { echo "::error::$xcode is not on this runner."; ls -d /Applications/Xcode*.app; exit 1; }
else
  xcode="$(printf '%s\n' /Applications/Xcode_*.app | grep -viE 'beta|_rc|release.?candidate' | sort -V | tail -n 1)"
  [[ -d "$xcode" ]] || { echo "::error::No release Xcode found."; ls -d /Applications/Xcode*.app; exit 1; }
fi

sudo xcode-select -s "$xcode"
xcodebuild -version
