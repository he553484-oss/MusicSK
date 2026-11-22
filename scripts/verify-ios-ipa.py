#!/usr/bin/env python3
"""Check the structure and device compatibility of a packaged Musicsk IPA."""

import argparse
from collections import Counter
from pathlib import PurePosixPath
import plistlib
import re
import struct
import sys
import zipfile


APP = "Payload/Musicsk.app"
WIDGET = f"{APP}/PlugIns/MusicskWidget.appex"
BUNDLE_ID = "app.musicsk.player"

MACHO_HEADER = struct.Struct("<8I")
LOAD_COMMAND = struct.Struct("<2I")
BUILD_VERSION = struct.Struct("<6I")
MH_MAGIC_64 = 0xFEEDFACF
CPU_TYPE_ARM64 = 0x0100000C
MH_EXECUTE = 2
LC_BUILD_VERSION = 0x32
PLATFORM_IOS = 2


def require(condition, description):
    if not condition:
        raise ValueError(description)


def packed_version(version):
    parts = [int(part) for part in version.split(".")]
    require(len(parts) in (2, 3), f"Invalid iOS version: {version}")
    major, minor, patch = (parts + [0])[:3]
    require(0 <= major <= 0xFFFF and 0 <= minor <= 0xFF and 0 <= patch <= 0xFF,
            f"Invalid iOS version: {version}")
    return (major << 16) | (minor << 8) | patch


def check_executable(archive, member, minimum):
    with archive.open(member) as binary:
        header = binary.read(MACHO_HEADER.size)
        require(len(header) == MACHO_HEADER.size, f"{member}: truncated Mach-O header")
        magic, cpu_type, _, file_type, command_count, command_bytes, _, _ = MACHO_HEADER.unpack(header)
        require((magic, cpu_type, file_type) == (MH_MAGIC_64, CPU_TYPE_ARM64, MH_EXECUTE),
                f"{member}: expected a thin arm64 Mach-O executable")
        member_size = archive.getinfo(member).file_size
        require(command_count <= command_bytes // LOAD_COMMAND.size
                and command_bytes <= member_size - MACHO_HEADER.size,
                f"{member}: invalid load-command table")
        remaining = command_bytes
        build = None
        for _ in range(command_count):
            fields = binary.read(LOAD_COMMAND.size)
            require(remaining >= LOAD_COMMAND.size and len(fields) == LOAD_COMMAND.size,
                    f"{member}: truncated load command")
            command, size = LOAD_COMMAND.unpack(fields)
            require(LOAD_COMMAND.size <= size <= remaining, f"{member}: invalid load-command size")
            payload_size = size - LOAD_COMMAND.size
            if command == LC_BUILD_VERSION:
                require(build is None and size >= BUILD_VERSION.size,
                        f"{member}: invalid LC_BUILD_VERSION")
                payload = binary.read(BUILD_VERSION.size - LOAD_COMMAND.size)
                require(len(payload) == BUILD_VERSION.size - LOAD_COMMAND.size,
                        f"{member}: truncated LC_BUILD_VERSION")
                _, _, platform, min_os, _, _ = BUILD_VERSION.unpack(fields + payload)
                build = (platform, min_os)
                payload_size -= len(payload)
            if payload_size:
                binary.seek(payload_size, 1)
            remaining -= size
        require(remaining == 0, f"{member}: mismatched load-command table")
        require(build == (PLATFORM_IOS, minimum),
                f"{member}: expected an iOS device binary with the requested minimum iOS")


def check_bundle(archive, directory, identifier, version, build, revision, minimum_ios):
    plist = plistlib.loads(archive.read(f"{directory}/Info.plist"))
    require(isinstance(plist, dict), f"{directory}: invalid Info.plist dictionary")
    expected = {
        "CFBundleIdentifier": identifier,
        "CFBundleShortVersionString": version,
        "CFBundleVersion": build,
        "CFBundleSupportedPlatforms": ["iPhoneOS"],
    }
    for key, expected_value in expected.items():
        require(plist.get(key) == expected_value,
                f"{directory}: {key} expected {expected_value!r}, got {plist.get(key)!r}")
    require(plist.get("BitChordRevision") == revision, f"{directory}: unexpected source revision")
    minimum = packed_version(minimum_ios)
    detected_minimum = plist.get("MinimumOSVersion")
    require(isinstance(detected_minimum, str) and packed_version(detected_minimum) == minimum,
            f"{directory}: MinimumOSVersion expected {minimum_ios}, got {detected_minimum!r}")
    executable = plist.get("CFBundleExecutable")
    require(isinstance(executable, str) and executable == PurePosixPath(directory).stem,
            f"{directory}: unexpected CFBundleExecutable")
    check_executable(archive, f"{directory}/{executable}", minimum)
    return plist


def verify_ipa(path, version, build, revision, minimum_ios):
    with zipfile.ZipFile(path) as archive:
        members = Counter(archive.namelist())
        for member, count in members.items():
            path_in_zip = PurePosixPath(member)
            require(count == 1, f"Duplicate ZIP member: {member}")
            require(not path_in_zip.is_absolute() and ".." not in path_in_zip.parts
                    and "\\" not in member, f"Unsafe ZIP path: {member}")
            require(path_in_zip.name not in ("embedded.mobileprovision", "embedded.provisionprofile"),
                    f"IPA contains a provisioning profile: {member}")
        require({PurePosixPath(member).parts[1] for member in members
                 if len(PurePosixPath(member).parts) >= 2 and PurePosixPath(member).parts[0] == "Payload"}
                == {"Musicsk.app"}, "Payload must contain exactly Musicsk.app")
        bad_member = archive.testzip()
        require(bad_member is None, f"ZIP CRC failed for {bad_member}")

        app = check_bundle(archive, APP, BUNDLE_ID, version, build, revision, minimum_ios)
        require("audio" in app.get("UIBackgroundModes", []), "App bundle lacks background audio mode")
        for framework in ("BitChordShared", "NativeCoreFFI"):
            require(f"{APP}/Frameworks/{framework}.framework/{framework}" in members,
                    f"Missing embedded framework: {framework}")

        widget = check_bundle(archive, WIDGET, f"{BUNDLE_ID}.widget", version, build, revision, minimum_ios)
        require(widget.get("NSExtension", {}).get("NSExtensionPointIdentifier") == "com.apple.widgetkit-extension",
                "MusicskWidget is not declared as a WidgetKit extension")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa")
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--minimum-ios", default="18.0")
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", args.version):
        parser.error("--version must look like 1.2.0")
    if not re.fullmatch(r"[1-9][0-9]*", args.build):
        parser.error("--build must be a positive integer")
    if not re.fullmatch(r"[0-9a-f]{7,40}(?:-dirty)?", args.revision):
        parser.error("--revision must be the embedded Git revision")
    try:
        verify_ipa(args.ipa, args.version, args.build, args.revision, args.minimum_ios)
    except (OSError, ValueError, KeyError, AttributeError, RuntimeError,
            zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        print(f"IPA verification failed: {error}", file=sys.stderr)
        return 1
    print(f"PASS iOS device arm64 IPA, iOS {args.minimum_ios} minimum, "
          f"{BUNDLE_ID} and WidgetKit, build {args.build} at {args.revision}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
