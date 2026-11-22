#!/usr/bin/env bash
#
# The player's window-shape rules.
#
# A build proves these compile. It does not prove they are *right*, and every one
# of them is a judgement about an edge case: a square window, a window one point
# either side of the floor, a tablet held upright, a landscape window too short
# for the row under its sleeve. Those are exactly the cases nobody notices until
# a device has that shape.
#
# Compiled from the app's own source, so this cannot drift from what ships.
#
# Needs no window server session and no human, which is the point: it is a
# geometry question and is answered as one.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK_DIR="${TMPDIR:-/tmp}/bitchord-player-layout-check"

rm -rf "$CHECK_DIR"
mkdir -p "$CHECK_DIR"

if command -v xcrun >/dev/null 2>&1; then
  swift_compiler=(xcrun swiftc -sdk "$(xcrun --show-sdk-path --sdk macosx)" -target arm64-apple-macos15.0)
else
  swift_compiler=(swiftc)
fi

"${swift_compiler[@]}" \
  -swift-version 5 \
  -o "$CHECK_DIR/check" \
  "$ROOT/AppleApp/Sources/UI/PlayerLayout.swift" \
  "$ROOT/AppleApp/Sources/UI/DetailHeaderLayout.swift" \
  "$HERE/player-layout-verify/main.swift"

"$CHECK_DIR/check"
