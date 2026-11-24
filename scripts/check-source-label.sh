#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
swiftc "$repo/AppleApp/Sources/PlaybackSession/PlaybackSourceLabel.swift" \
  "$repo/scripts/source-label-verify/main.swift" -o "$tmp/check"
"$tmp/check"
