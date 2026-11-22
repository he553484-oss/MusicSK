#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch="$(mktemp -d "${TMPDIR:-/tmp}/bitchord-settings-audio.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
if command -v xcrun >/dev/null 2>&1; then
  swift_compiler=(xcrun swiftc)
else
  swift_compiler=(swiftc)
fi
"${swift_compiler[@]}" -parse-as-library \
  AppleApp/Sources/UI/Settings/AudioSettingsCatalog.swift \
  AppleApp/Sources/UI/ReleaseIdentity.swift scripts/settings-audio-verify/check.swift -o "$scratch/check"
"$scratch/check"
python3 scripts/release-verify/check.py
