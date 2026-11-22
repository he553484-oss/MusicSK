#!/usr/bin/env bash
# Capture the real signed-out app in a fresh simulator without seeding media.
# Build the simulator frameworks and generate AppleApp/Musicsk.xcodeproj first.
set -euo pipefail

[[ $# -eq 1 ]] || { printf 'Usage: %s <capture-directory>\n' "$0" >&2; exit 2; }
repo="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$1"
output="$(cd "$1" && pwd)"
scratch="$(mktemp -d)"
device_id=""
app_pid=""
cleanup() {
    if [[ -n "$app_pid" ]]; then kill "$app_pid" 2>/dev/null || true; fi
    if [[ -n "$device_id" ]]; then
        xcrun simctl shutdown "$device_id" >/dev/null 2>&1 || true
        xcrun simctl delete "$device_id" >/dev/null 2>&1 || true
    fi
    rm -rf "$scratch"
}
trap cleanup EXIT

selection="$(xcrun simctl list devices available --json | python3 -c '
import json
import sys

available = json.load(sys.stdin)["devices"]
runtime_devices = [
    (runtime, device)
    for runtime, devices in available.items()
    if ".iOS-" in runtime
    for device in devices
    if device["name"].startswith("iPhone")
    and device.get("isAvailable")
    and device.get("deviceTypeIdentifier")
]
for preferred in ("iPhone 15 Pro", "iPhone 18 Pro", None):
    matching = [(runtime, device) for runtime, device in runtime_devices
                if preferred is None or device["name"] == preferred]
    if matching:
        runtime, device = max(matching, key=lambda item: tuple(
            int(part) for part in item[0].split(".iOS-", 1)[1].split("-")
        ))
        print(device["name"], device["deviceTypeIdentifier"], runtime, sep="\t")
        break
else:
    sys.exit("No usable iPhone simulator found")
')"
IFS=$'\t' read -r device_name device_type runtime <<< "$selection"
device_id="$(xcrun simctl create "Musicsk-Capture-${RANDOM}" "$device_type" "$runtime")"

xcodebuild \
    -project "$repo/AppleApp/Musicsk.xcodeproj" -scheme Musicsk \
    -configuration Release -sdk iphonesimulator -destination "id=$device_id" \
    -derivedDataPath "$scratch/DerivedData" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= build

xcrun simctl boot "$device_id"
xcrun simctl bootstatus "$device_id" -b
xcrun simctl ui "$device_id" appearance dark
xcrun simctl install "$device_id" "$scratch/DerivedData/Build/Products/Release-iphonesimulator/Musicsk.app"

bundle_id=app.musicsk.player
start_app() {
    xcrun simctl launch --terminate-running-process --console "$device_id" "$bundle_id" \
        -onboarding_done YES -automix_models_prompt_dismissed_v2 YES \
        -AppleLanguages '(es)' -AppleLocale es_ES \
        -last_player_screen "$1" >"$scratch/app.log" 2>&1 &
    app_pid=$!
    # Wait for the scene to render and its first-run tasks to run.
    sleep 4
}
capture() {
    if ! kill -0 "$app_pid" 2>/dev/null; then
        printf 'Musicsk exited before capture.\n' >&2
        tail -30 "$scratch/app.log" >&2
        exit 1
    fi
    xcrun simctl io "$device_id" screenshot "$output/$1"
}

start_app MAIN
capture 01-inicio-es.png
xcrun simctl openurl "$device_id" musicsk://open-player
sleep 2
capture 02-reproductor-vacio-es.png
xcrun simctl terminate "$device_id" "$bundle_id"
wait "$app_pid" || true
app_pid=""

start_app LYRICS
xcrun simctl openurl "$device_id" 'musicsk://open-player?screen=lyrics'
sleep 2
capture 03-letras-vacias-es.png

cat >"$output/LEEME.txt" <<EOF
Capturas del binario para simulador de Musicsk
Dispositivo: $device_name
Runtime: ${runtime##*.}
Git: $(git -C "$repo" rev-parse HEAD)
Idioma solicitado: es_ES

Sesión cerrada, sin pista y sin datos de prueba. El reproductor y las letras
se abrieron con la ruta existente de la app. Estas capturas sirven para
revisar el marco del reproductor y la interfaz vacía. La reproducción,
las transiciones con portada o texto sincronizado, Control Center y la
pantalla bloqueada requieren validación separada en un iPhone físico.
EOF
