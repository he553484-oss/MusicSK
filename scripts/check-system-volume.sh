#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$repo" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]) / "AppleApp/Sources/UI"
transport = (source / "NowPlaying/NowPlayingView+Transport.swift").read_text()
start = transport.index("func volumeRow(")
ios, mac = transport[start:].split("#else", 1)
mac = mac.split("#endif", 1)[0]
native = (source / "NowPlaying/SystemVolumeRow.swift").read_text()
output = (source / "AudioPipelineSheet.swift").read_text().split("struct OutputDeviceSheet: View", 1)[1]

assert "SystemVolumeRow(" in ios and "controller.volume" not in ios
assert "MPVolumeView(" in native and "showsVolumeSlider = true" in native
assert "showsRouteButton = false" in native and "AVAudioSession.sharedInstance().observe(" in native
assert "outputVolume" in native and "observation?.invalidate()" in native
assert "cancelsTouchesInView = false" in native and "volumeDragging = editing" in ios
assert not any(term in native for term in ("controller.volume", "setActive(", "subviews", "UISlider"))
assert '"App Volume"' in output and "set: { controller.volume = $0 }" in output
assert "controller.volume" in mac
print("PASS: iOS volume uses the visible native control and keeps independent app gain accessible")
PY
