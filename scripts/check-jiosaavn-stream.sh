#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
swiftc_bin="${SWIFTC:-swiftc}"
printf 'public struct Stub {}\n' > "$scratch/Shared.swift"
"$swiftc_bin" -emit-module -module-name BitChordShared "$scratch/Shared.swift" -emit-module-path "$scratch/BitChordShared.swiftmodule"
# FoundationNetworking is needed only by Swift on Linux.
if [[ "$(uname -s)" == Linux ]]; then
  { printf 'import FoundationNetworking\n'; cat "$repo/AppleApp/Sources/PlaybackSession/JioSaavn.swift"; } > "$scratch/JioSaavn.swift"
else
  cp "$repo/AppleApp/Sources/PlaybackSession/JioSaavn.swift" "$scratch/JioSaavn.swift"
fi
"$swiftc_bin" -parse-as-library -swift-version 5 -I "$scratch" -o "$scratch/check" \
  "$scratch/JioSaavn.swift" "$repo/AppleApp/Sources/PlaybackSession/JioSaavnResponse.swift" \
  "$repo/scripts/jiosaavn-stream-verify/Stubs.swift" "$repo/scripts/jiosaavn-stream-verify/main.swift"
"$scratch/check"
