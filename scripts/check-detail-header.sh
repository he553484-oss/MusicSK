#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
swiftc "$root/AppleApp/Sources/UI/DetailHeaderLayout.swift" \
  "$root/scripts/detail-header-verify/main.swift" -o "$scratch/verify"
"$scratch/verify"
