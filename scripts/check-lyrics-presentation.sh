#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

"${SWIFTC:-swiftc}" \
  "$root/AppleApp/Sources/UI/NowPlaying/LyricsPresentation.swift" \
  "$root/scripts/lyrics-presentation-verify/main.swift" \
  -o "$work/lyrics-presentation"
"$work/lyrics-presentation"
