#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
if command -v xcrun >/dev/null 2>&1; then compiler=(xcrun swiftc); else compiler=(swiftc); fi
"${compiler[@]}" -o "$work/check" "$repo/AppleApp/Sources/PlaybackSession/LockScreenArtworkPolicy.swift" "$repo/scripts/lockscreen-artwork-verify/main.swift"
"$work/check"
