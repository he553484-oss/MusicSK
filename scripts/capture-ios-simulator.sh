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
status_bar="valores por defecto del simulador"
if xcrun simctl status_bar "$device_id" override --time "9:41" --dataNetwork wifi \
    --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 \
    --batteryState discharging --batteryLevel 100; then
    status_bar="9:41, Wi-Fi, batería al 100 %"
else
    printf 'La barra de estado conserva sus valores por defecto.\n' >&2
fi
app="$scratch/DerivedData/Build/Products/Release-iphonesimulator/Musicsk.app"
xcrun simctl install "$device_id" "$app"

bundle_id=app.musicsk.player
start_app() {
    local screen="$1"
    shift
    xcrun simctl launch --terminate-running-process --console "$device_id" "$bundle_id" \
        -onboarding_done YES -automix_models_prompt_dismissed_v2 YES \
        -AppleLanguages '(es)' -AppleLocale es_ES \
        -last_player_screen "$screen" "$@" >"$scratch/app.log" 2>&1 &
    app_pid=$!
    # Wait for the scene to render and its first-run tasks to run.
    sleep 12
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
stop_app

start_app MAIN -musicsk_capture_player YES
capture 02-reproductor-vacio-es.png
stop_app

start_app LYRICS -musicsk_capture_player YES
capture 03-letras-vacias-es.png
stop_app

start_app MAIN -musicsk_capture_lyrics_settings YES
capture 04-ajustes-letras-es.png
stop_app

start_app QUEUE -musicsk_capture_player YES
capture 06-cola-vacia-es.png
stop_app

# Seed the persisted Replay month read by the real Library tab.
app_data="$(xcrun simctl get_app_container "$device_id" "$bundle_id" data)"
support="$app_data/Library/Application Support/BitChord"
python3 - "$support/listening" <<'PY'
import datetime
import json
import sys
from pathlib import Path

folder = Path(sys.argv[1])
folder.mkdir(parents=True, exist_ok=True)
month = datetime.datetime.now().strftime("%Y-%m")
song = dict(id="duplicate", title="Replay fixture", artist="Fixture", ms=20000, plays=1)
record = dict(version=1, month=month, tracks=[song, dict(song, ms=40000)],
              artists=[], albums=[], days={}, hours=[0] * 24)
(folder / f"{month}.json").write_text(json.dumps(record))
PY
start_app MAIN -musicsk_capture_library YES
capture 05-biblioteca-historial-duplicado-es.png
for _ in {1..12}; do
    if grep -hsF 'library replay ready songs=1' "$support"/Diagnostics/*.log >/dev/null; then break; fi
    sleep 1
done
grep -hsF 'library ' "$support"/Diagnostics/*.log | tee "$output/biblioteca-validacion.txt"
grep -qF 'library landing load finished shelves=0 failed=false' "$output/biblioteca-validacion.txt"
grep -qF 'library replay ready songs=1' "$output/biblioteca-validacion.txt"
stop_app

# Static, explicitly labelled metadata and artwork exercise layout only.
# They do not start audio or represent a successful provider stream.
start_app MAIN -musicsk_capture_fixture YES -musicsk_capture_player YES
capture 07-reproductor-fixture-es.png
stop_app

start_app QUEUE -musicsk_capture_fixture YES -musicsk_capture_player YES
capture 08-cola-fixture-es.png
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
Barra de estado del simulador: $status_bar

Las tres primeras capturas mantienen las pantallas y nombres de 1.2.1 para
comparar el marco del reproductor y el estado vacío de Letras. La cuarta abre
Configuración → Letras con un indicador exclusivo del simulador. La sexta
muestra la cola vacía. La quinta abre
Biblioteca sin sesión y con un mes sintético que repite un identificador.
El archivo biblioteca-validacion.txt acredita que la vista terminó su carga
y que Replay agrupó los registros en una sola pista. El simulador se lanzó
sin pista en reproducción. La reproducción, el vídeo, el volumen físico,
Control Center y la pantalla bloqueada requieren comprobaciones adicionales.
Las capturas 07 y 08 contienen metadatos y portada sintéticos, sin audio, para
comprobar únicamente la distribución del reproductor y la cola.
EOF
