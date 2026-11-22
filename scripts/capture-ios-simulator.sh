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
revision="$(git -C "$repo" rev-parse HEAD)"

xcodebuild \
    -project "$repo/AppleApp/Musicsk.xcodeproj" -scheme Musicsk \
    -configuration Release -sdk iphonesimulator -destination "id=$device_id" \
    -derivedDataPath "$scratch/DerivedData" \
    BITCHORD_BUILD_REVISION="${revision:0:12}" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= build

xcrun simctl boot "$device_id"
xcrun simctl bootstatus "$device_id" -b
xcrun simctl ui "$device_id" appearance dark
xcrun simctl status_bar "$device_id" override --time "9:41" --dataNetwork wifi \
    --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 \
    --batteryState unplugged --batteryLevel 100
app="$scratch/DerivedData/Build/Products/Release-iphonesimulator/Musicsk.app"
xcrun simctl install "$device_id" "$app"

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
stop_app() {
    xcrun simctl terminate "$device_id" "$bundle_id"
    wait "$app_pid" || true
    app_pid=""
}
capture() {
    if ! kill -0 "$app_pid" 2>/dev/null; then
        printf 'Musicsk exited before capture.\n' >&2
        tail -30 "$scratch/app.log" >&2
        exit 1
    fi
    xcrun simctl io "$device_id" screenshot "$output/$1"
    [[ -s "$output/$1" ]]
}

start_app MAIN
capture 01-inicio-es.png
xcrun simctl openurl "$device_id" musicsk://open-player
sleep 2
capture 02-reproductor-vacio-es.png
stop_app

start_app LYRICS
xcrun simctl openurl "$device_id" 'musicsk://open-player?screen=lyrics'
sleep 2
capture 03-letras-vacias-es.png
stop_app

start_app MAIN
xcrun simctl openurl "$device_id" 'musicsk://settings/lyrics'
sleep 2
capture 04-ajustes-letras-es.png
stop_app

version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app/Info.plist")"
toolchain="$(xcodebuild -version | paste -sd ' ' -)"

cat >"$output/LEEME.txt" <<EOF
Capturas del binario para simulador de Musicsk
Dispositivo: $device_name
Runtime: ${runtime##*.}
Git: $revision
Versión y build: $version ($build)
Herramientas: $toolchain
Idioma solicitado: es_ES
Apariencia: oscura
Barra de estado del simulador: 9:41, Wi‑Fi, batería al 100 %

Las tres primeras capturas mantienen las pantallas y nombres de 1.2.1 para
comparar el marco del reproductor y el estado vacío de Letras. La cuarta abre
Configuración → Letras con el enlace de la aplicación. El simulador se lanzó
sin sesión iniciada y sin pista. Las capturas documentan la interfaz en ese
estado. La reproducción, el vídeo, el volumen físico, Control Center y la
pantalla bloqueada requieren comprobaciones adicionales.
EOF
