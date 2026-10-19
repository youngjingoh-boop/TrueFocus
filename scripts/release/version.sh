#!/usr/bin/env bash
# Works out the version numbers for a release build and prints them as
#
#   marketing=1.2.3     -> MARKETING_VERSION        (CFBundleShortVersionString)
#   build=142           -> CURRENT_PROJECT_VERSION  (CFBundleVersion)
#
# ready to append to $GITHUB_OUTPUT.
#
# Marketing version, first match wins:
#   1. the tag that triggered the run (v1.2.3 -> 1.2.3)
#   2. INPUT_VERSION (the workflow_dispatch "version" input)
#   3. MARKETING_VERSION in project.yml
# Build number: RUN_NUMBER (github.run_number) + BUILD_NUMBER_OFFSET (repository variable,
# default 0). It only ever goes up, which is what App Store Connect needs.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() {
  echo "::error::$*" >&2
  exit 1
}

if [[ "${GITHUB_REF_TYPE:-}" == "tag" && "${GITHUB_REF_NAME:-}" == v* ]]; then
  marketing="${GITHUB_REF_NAME#v}"
elif [[ -n "${INPUT_VERSION:-}" ]]; then
  marketing="${INPUT_VERSION#v}"
else
  marketing="$(sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"?([0-9][0-9.]*)"?.*$/\1/p' "$root/project.yml" | head -n 1)"
fi

# App Store Connect: one to three period-separated integers.
[[ "$marketing" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] \
  || fail "Version '$marketing' is not like 1.2 or 1.2.3 (tags must look like v1.2.3)."

run="${RUN_NUMBER:-${GITHUB_RUN_NUMBER:-}}"
offset="${BUILD_NUMBER_OFFSET:-}"
offset="${offset:-0}"
[[ "$run" =~ ^[0-9]+$ ]] || fail "RUN_NUMBER '$run' is not a number."
[[ "$offset" =~ ^[0-9]+$ ]] || fail "BUILD_NUMBER_OFFSET '$offset' is not a number."

echo "marketing=$marketing"
echo "build=$((run + offset))"
