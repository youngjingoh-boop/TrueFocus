#!/usr/bin/env bash
# Removes what setup-signing.sh left on the runner. Safe to run when setup never ran.
set -uo pipefail

if [[ -n "${TF_KEYCHAIN_PATH:-}" && -f "$TF_KEYCHAIN_PATH" ]]; then
  security delete-keychain "$TF_KEYCHAIN_PATH" || true
fi
if [[ -n "${RUNNER_TEMP:-}" ]]; then
  rm -rf "$RUNNER_TEMP/asc" "$RUNNER_TEMP"/*.p12
fi
exit 0
