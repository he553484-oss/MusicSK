#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
"${SWIFTC:-swiftc}" -swift-version 5 -o "$scratch/check" \
  "$repo/AppleApp/Sources/PlaybackSession/JioSaavnResponse.swift" \
  "$repo/scripts/jiosaavn-verify/main.swift"
"$scratch/check"
