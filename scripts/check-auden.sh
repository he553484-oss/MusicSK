#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rmdir "$scratch" 2>/dev/null || true' EXIT
swiftc_bin="${SWIFTC:-swiftc}"
"$swiftc_bin" -o "$scratch/check" \
  "$repo/AppleApp/Sources/UI/Auden/MusicAppearance.swift" \
  "$repo/AppleApp/Sources/UI/Auden/AudenLibrarySections.swift" \
  "$repo/scripts/auden-verify/main.swift"
"$scratch/check"
unlink "$scratch/check"
