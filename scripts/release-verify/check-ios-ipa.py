"""Offline tests for IPA structure validation. Fixtures are never installable."""

from pathlib import Path
import plistlib
import runpy
import struct
import tempfile
import unittest
import warnings
import zipfile


verifier = runpy.run_path(str(Path(__file__).resolve().parents[1] / "verify-ios-ipa.py"))
verify_ipa = verifier["verify_ipa"]
APP = verifier["APP"]
WIDGET = verifier["WIDGET"]
REVISION = "a1b2c3d4e5f6"


def executable(platform=2, cpu_type=0x0100000C, minimum=18 << 16):
    header = struct.pack("<8I", 0xFEEDFACF, cpu_type, 0, 2, 1, 24, 0, 0)
    command = struct.pack("<6I", 0x32, 24, platform, minimum, 27 << 16, 0)
    return header + command


class IPATest(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.ipa = Path(scratch.name) / "fixture.ipa"
        common = {
            "BitChordRevision": REVISION,
            "CFBundleShortVersionString": "1.2.0",
            "CFBundleVersion": "3",
            "CFBundleSupportedPlatforms": ["iPhoneOS"],
            "MinimumOSVersion": "18.0",
        }
        self.members = {
            f"{APP}/Info.plist": plistlib.dumps(dict(
                common, CFBundleIdentifier="app.musicsk.player",
                CFBundleExecutable="Musicsk", UIBackgroundModes=["audio"],
            )),
            f"{WIDGET}/Info.plist": plistlib.dumps(dict(
                common, CFBundleIdentifier="app.musicsk.player.widget",
                CFBundleExecutable="MusicskWidget",
                NSExtension={"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"},
            )),
            f"{APP}/Musicsk": executable(),
            f"{WIDGET}/MusicskWidget": executable(),
            f"{APP}/Info.fixture": b"archive placeholder",
        }

    def archive(self):
        with zipfile.ZipFile(self.ipa, mode="w") as archive:
            for name, content in self.members.items():
                archive.writestr(name, content)

    def verify(self):
        verify_ipa(self.ipa, "1.2.0", "3", REVISION, "18.0")

    def set_plist(self, bundle, **fields):
        path = f"{bundle}/Info.plist"
        plist = plistlib.loads(self.members[path])
        plist.update(fields)
        self.members[path] = plistlib.dumps(plist)

    def expect_rejected(self, message):
        self.archive()
        with self.assertRaisesRegex(ValueError, message):
            self.verify()

    def test_device_structure(self):
        self.archive()
        self.verify()

    def test_simulator_arm64_is_not_a_device_build(self):
        self.members[f"{APP}/Musicsk"] = executable(platform=7)
        self.expect_rejected("iOS device")

    def test_non_arm64_executable(self):
        self.members[f"{WIDGET}/MusicskWidget"] = executable(cpu_type=0x01000007)
        self.expect_rejected("arm64")

    def test_executable_minimum_disagrees_with_plist(self):
        self.members[f"{WIDGET}/MusicskWidget"] = executable(minimum=19 << 16)
        self.expect_rejected("requested minimum iOS")

    def test_wrong_widget_identifier(self):
        self.set_plist(WIDGET, CFBundleIdentifier="app.other.widget")
        self.expect_rejected("CFBundleIdentifier")

    def test_wrong_build(self):
        self.set_plist(APP, CFBundleVersion="2")
        self.expect_rejected("CFBundleVersion")

    def test_wrong_source_revision(self):
        self.set_plist(WIDGET, BitChordRevision="123456789abc")
        self.expect_rejected("source revision")

    def test_wrong_plist_minimum(self):
        self.set_plist(APP, MinimumOSVersion="26.0")
        self.expect_rejected("MinimumOSVersion")

    def test_missing_background_audio(self):
        self.set_plist(APP, UIBackgroundModes=[])
        self.expect_rejected("background audio")

    def test_wrong_extension_kind(self):
        self.set_plist(WIDGET, NSExtension={"NSExtensionPointIdentifier": "com.apple.share-services"})
        self.expect_rejected("WidgetKit")

    def test_missing_executable(self):
        del self.members[f"{APP}/Musicsk"]
        self.archive()
        with self.assertRaisesRegex(KeyError, "Musicsk.app/Musicsk"):
            self.verify()

    def test_unexpected_app(self):
        self.members["Payload/Other.app/Info.plist"] = b"other"
        self.expect_rejected("exactly Musicsk.app")

    def test_profile_in_widget(self):
        self.members[f"{WIDGET}/embedded.mobileprovision"] = b"profile"
        self.expect_rejected("provisioning profile")

    def test_unsafe_path(self):
        self.members[f"{APP}/../second/Info.plist"] = b"other"
        self.expect_rejected("Unsafe ZIP path")

    def test_repeated_member(self):
        self.archive()
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            with zipfile.ZipFile(self.ipa, mode="a") as archive:
                archive.writestr(f"{APP}/Musicsk", executable())
        with self.assertRaisesRegex(ValueError, "Duplicate ZIP"):
            self.verify()

    def test_corrupt_zip_member(self):
        self.archive()
        data = self.ipa.read_bytes()
        self.ipa.write_bytes(data.replace(b"archive placeholder", b"changed placeholder", 1))
        with self.assertRaisesRegex(ValueError, "ZIP CRC"):
            self.verify()

    def test_truncated_load_command(self):
        self.members[f"{APP}/Musicsk"] = executable()[:-1]
        self.expect_rejected("load-command table")


if __name__ == "__main__":
    unittest.main()
