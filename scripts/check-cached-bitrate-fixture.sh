#!/usr/bin/env bash
# A quiet VBR opening must not represent the average of a complete cache file.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
ffmpeg -v error -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=6' \
  -af "volume=enable='lt(t,1)':volume=0" -c:a libopus -b:a 128k -y "$scratch/fixture.opus"
ffprobe -v error -select_streams a:0 -show_packets -show_entries packet=size,duration_time \
  -of json "$scratch/fixture.opus" > "$scratch/packets.json"
python3 - "$scratch/packets.json" <<'PY'
import json, sys
packets = json.load(open(sys.argv[1]))['packets']
duration = 0.0
size = 0
for packet in packets:
    duration += float(packet.get('duration_time', 0))
    size += int(packet['size'])
    if duration >= 0.25:
        break
rate = size * 8 / duration / 1000
assert rate < 10, f'expected quiet initial window, got {rate:.2f} kbps'
print(f'Opening packet estimate: {rate:.2f} kbps')
PY
"${SWIFTC:-swiftc}" -swift-version 5 -o "$scratch/check" \
  "$repo/AppleApp/Sources/PlaybackSession/CachedBitrate.swift" \
  "$repo/scripts/cached-bitrate-verify/main.swift"
"$scratch/check" "$scratch/fixture.opus"
