#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Build an unsigned Release IPA for sideloading or signing with your own team.

Usage:
  scripts/package-ios-ipa.sh <version> [--output-dir DIR] [--overwrite]

The script archives the iOS app with code signing disabled, removes embedded
provisioning profiles, and writes Musicsk-VERSION-buildBUILD-ios-unsigned.ipa.
USAGE
}
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
if [[ $# -eq 1 && ( "$1" == '-h' || "$1" == '--help' ) ]]; then usage; exit 0; fi
[[ $# -ge 1 ]] || { usage >&2; exit 2; }
version="$1"; shift
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'version must look like 1.0.0'
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="$repo_root/build/release"
overwrite=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir) [[ $# -ge 2 ]] || fail '--output-dir needs a path'; output_dir="$2"; shift 2 ;;
    --overwrite) overwrite=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown option: $1" ;;
  esac
done
command -v xcodebuild >/dev/null 2>&1 || fail 'xcodebuild is required'
command -v ditto >/dev/null 2>&1 || fail 'ditto is required'
command -v codesign >/dev/null 2>&1 || fail 'codesign is required'
command -v python3 >/dev/null 2>&1 || fail 'python3 is required'
spec_version="$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"$/\1/p' "$repo_root/AppleApp/project.yml")"
build_version="$(sed -n 's/^ *CURRENT_PROJECT_VERSION: "\(.*\)"$/\1/p' "$repo_root/AppleApp/project.yml")"
[[ "$spec_version" == "$version" ]] || fail "AppleApp/project.yml says $spec_version, not $version"
[[ "$build_version" =~ ^[1-9][0-9]*$ ]] || fail 'AppleApp/project.yml has no positive numeric build'
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
ipa="$output_dir/Musicsk-$version-build$build_version-ios-unsigned.ipa"
[[ ! -e "$ipa" || "$overwrite" -eq 1 ]] || fail "IPA already exists: $ipa (pass --overwrite to replace it)"
stage="$(mktemp -d "${TMPDIR:-/tmp}/musicsk-ipa.XXXXXX")"
output_stage=""
cleanup() {
  rm -rf "$stage"
  if [[ -n "$output_stage" ]]; then rm -rf "$output_stage"; fi
}
trap cleanup EXIT
archive="$stage/Musicsk.xcarchive"
app="$archive/Products/Applications/Musicsk.app"
staged_app="$stage/package/Payload/Musicsk.app"

# scripts/release-apple.sh passes the revision it checked clean, so the IPA and
# the Mac archive carry the same stamp even if the tree changes mid-build.
build_revision="${BITCHORD_BUILD_REVISION:-}"
if [[ -z "$build_revision" ]]; then
build_revision="$(git -C "$repo_root" rev-parse --short=12 HEAD)"
if ! git -C "$repo_root" diff --quiet HEAD -- || [[ -n "$(git -C "$repo_root" ls-files --others --exclude-standard)" ]]; then build_revision="$build_revision-dirty"; fi
fi
xcodebuild \
  -project "$repo_root/AppleApp/Musicsk.xcodeproj" \
  -scheme Musicsk \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -archivePath "$archive" \
  -derivedDataPath "$stage/DerivedData" \
  archive \
  MUSICSK_RELEASE_REPOSITORY="${MUSICSK_RELEASE_REPOSITORY:-}" \
  MUSICSK_SPARKLE_FEED="${MUSICSK_SPARKLE_FEED:-}" \
  MUSICSK_SPARKLE_PUBLIC_KEY="${MUSICSK_SPARKLE_PUBLIC_KEY:-}" \
  BITCHORD_BUILD_REVISION="$build_revision" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=
[[ -d "$app" ]] || fail "archive did not contain Musicsk.app: $app"
mkdir -p "$stage/package/Payload"
ditto "$app" "$staged_app"
find "$staged_app" -type f \( -name embedded.mobileprovision -o -name embedded.provisionprofile \) -delete

for bundle in "$staged_app" "$staged_app/PlugIns/MusicskWidget.appex"; do
  [[ -d "$bundle" ]] || fail "Archive is missing $(basename "$bundle")"
  signature_info="$stage/codesign-info.txt"
  if codesign -dv --verbose=4 "$bundle" >"$signature_info" 2>&1; then
    grep -Fq 'Signature=adhoc' "$signature_info" || fail "$(basename "$bundle") has a non-ad-hoc signature"
    if grep -q '^Authority=' "$signature_info"; then fail "$(basename "$bundle") has a signing authority"; fi
  else
    grep -Fq 'code object is not signed at all' "$signature_info" ||
      fail "could not confirm $(basename "$bundle") is unsigned or ad-hoc signed"
  fi
done

# Validate the finished ZIP before exposing it under its final name. The
# temporary output shares the destination filesystem, including during retries.
output_stage="$(mktemp -d "$output_dir/.musicsk-ipa.XXXXXX")"
candidate="$output_stage/$(basename "$ipa")"
(cd "$stage/package" && /usr/bin/zip -qry "$candidate" Payload)
python3 "$repo_root/scripts/verify-ios-ipa.py" "$candidate" \
  --version "$version" --build "$build_version" --revision "$build_revision"
if [[ "$overwrite" -eq 1 ]]; then
  mv -f "$candidate" "$ipa"
else
  ln "$candidate" "$ipa" || fail "Could not install verified IPA at $ipa"
fi
printf 'Created unsigned IPA: %s\n' "$ipa"
printf 'No developer signature or provisioning profile is included. iCloud sync requires signing with your own team and the relevant iCloud capabilities.\n'
