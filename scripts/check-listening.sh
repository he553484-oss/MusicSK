#!/usr/bin/env bash
# Run Replay against isolated monthly history files, including restored rows.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

swiftc_bin="${SWIFTC:-swiftc}"
"$swiftc_bin" -swift-version 5 -D DEBUG -o "$scratch/check" \
  "$repo/AppleApp/Sources/PlaybackSession/ListeningStore.swift" \
  "$repo/scripts/listening-verify/main.swift"
"$scratch/check"
