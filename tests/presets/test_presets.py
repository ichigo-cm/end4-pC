from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PRESETS = ROOT / "scripts" / "presets.sh"


class PresetTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.config_dir = self.home / ".config" / "illogical-impulse"
        self.config_dir.mkdir(parents=True)
        self.config = self.config_dir / "config.json"
        self.write_config(
            {
                "appearance": {"theme": "dark"},
                "apps": {"terminal": "trusted-terminal --safe"},
                "profile": {"userName": "local-user", "avatarPicture": "/local/avatar.png"},
            }
        )
        self.env = {**os.environ, "HOME": str(self.home)}

    def tearDown(self) -> None:
        self.temp.cleanup()

    def write_config(self, payload: dict) -> None:
        self.config.write_text(json.dumps(payload), encoding="utf-8")

    def run_presets(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", str(PRESETS), *args],
            env=self.env,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_local_save_keeps_existing_local_fields_and_unicode_name(self) -> None:
        result = self.run_presets("--save", "Café preset", "local description")
        self.assertEqual(result.returncode, 0, result.stderr)
        saved = self.home / ".config/illogical-impulse/presets/Café preset.json"
        data = json.loads(saved.read_text(encoding="utf-8"))
        self.assertEqual(data["apps"]["terminal"], "trusted-terminal --safe")
        self.assertEqual(data["profile"]["avatarPicture"], "/local/avatar.png")
        self.assertEqual(data["_presetMeta"]["description"], "local description")

    def test_traversal_names_are_rejected_before_file_operations(self) -> None:
        result = self.run_presets("--save", "../escaped")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid preset name", result.stderr)
        self.assertFalse((self.home / ".config/illogical-impulse/escaped.json").exists())

    def test_failed_save_does_not_truncate_existing_preset(self) -> None:
        presets_dir = self.home / ".config/illogical-impulse/presets"
        presets_dir.mkdir(parents=True)
        existing = presets_dir / "keep.json"
        existing.write_text('{"appearance":{"theme":"old"}}\n', encoding="utf-8")
        self.config.write_text("{ invalid json", encoding="utf-8")
        result = self.run_presets("--save", "keep")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(existing.read_text(encoding="utf-8"), '{"appearance":{"theme":"old"}}\n')

    def test_rename_rejects_traversal_destination(self) -> None:
        presets_dir = self.home / ".config/illogical-impulse/presets"
        presets_dir.mkdir(parents=True)
        (presets_dir / "original.json").write_text("{}", encoding="utf-8")
        result = self.run_presets("--rename", "original", "../../outside")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((presets_dir / "original.json").exists())
        self.assertFalse((self.home / "outside.json").exists())

    def test_zip_import_filters_commands_identity_and_copies_assets(self) -> None:
        archive = self.root / "appearance.zip"
        payload = {
            "appearance": {"theme": "dark"},
            "background": {"wallpaperPath": "wall.jpg"},
            "apps": {"terminal": "attacker-command"},
            "interactions": {"command": "attacker-command", "enabled": True},
            "profile": {"userName": "attacker", "avatarPicture": "avatar.png"},
        }
        with zipfile.ZipFile(archive, "w") as output:
            output.writestr("theme.json", json.dumps(payload))
            output.writestr("wall.jpg", b"not-a-real-image")
            output.writestr("avatar.png", b"not-a-real-image")
        result = self.run_presets("--import-zip", str(archive))
        self.assertEqual(result.returncode, 0, result.stderr)
        imported_path = self.home / ".cache/quickshell/presets_imported/theme.json"
        imported = json.loads(imported_path.read_text(encoding="utf-8"))
        self.assertEqual(imported["appearance"]["theme"], "dark")
        self.assertTrue(imported["interactions"]["enabled"])
        self.assertNotIn("command", imported["interactions"])
        self.assertNotIn("apps", imported)
        self.assertNotIn("profile", imported)
        self.assertEqual(imported["_presetMeta"]["source"], "imported")
        asset = self.home / ".cache/quickshell/presets_imported/assets/theme/wall.jpg"
        self.assertEqual(asset.read_bytes(), b"not-a-real-image")
        self.assertEqual(imported["background"]["wallpaperPath"], str(asset))

    def test_zip_traversal_is_rejected_without_publishing(self) -> None:
        archive = self.root / "traversal.zip"
        with zipfile.ZipFile(archive, "w") as output:
            output.writestr("../escaped.json", "{}")
            output.writestr("safe.json", "{}")
        result = self.run_presets("--import-zip", str(archive))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unsafe path", result.stderr)
        self.assertFalse((self.home / ".cache/quickshell/presets_imported/safe.json").exists())
        self.assertFalse((self.home / ".cache/quickshell/escaped.json").exists())

    def test_zip_expansion_limit_is_enforced(self) -> None:
        archive = self.root / "oversized.zip"
        with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_STORED) as output:
            output.writestr("large.bin", b"x" * (16 * 1024 * 1024 + 1))
        result = self.run_presets("--import-zip", str(archive))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("size limit", result.stderr)

    def test_malformed_reimport_preserves_published_json_and_assets(self) -> None:
        archive = self.root / "replace.zip"
        with zipfile.ZipFile(archive, "w") as output:
            output.writestr("theme.json", json.dumps({"appearance": {"theme": "old"}, "background": {"wallpaperPath": "wall.jpg"}}))
            output.writestr("wall.jpg", b"old-image")
        result = self.run_presets("--import-zip", str(archive))
        self.assertEqual(result.returncode, 0, result.stderr)

        imported_path = self.home / ".cache/quickshell/presets_imported/theme.json"
        asset_path = self.home / ".cache/quickshell/presets_imported/assets/theme/wall.jpg"
        previous_json = imported_path.read_bytes()
        previous_asset = asset_path.read_bytes()

        for broken_payload in ("{ invalid json", "[]", '{"valid": true}\n{"extra": true}'):
            with zipfile.ZipFile(archive, "w") as output:
                output.writestr("theme.json", broken_payload)
                output.writestr("new.jpg", b"new-image")
            result = self.run_presets("--import-zip", str(archive))
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(imported_path.read_bytes(), previous_json)
            self.assertEqual(asset_path.read_bytes(), previous_asset)
            self.assertFalse((asset_path.parent / "new.jpg").exists())

    def test_gallery_install_strips_commands_and_identity_but_local_install_is_preserved(self) -> None:
        online_dir = self.home / ".cache/quickshell/presets"
        online_dir.mkdir(parents=True)
        online = {
            "appearance": {"theme": "dark"},
            "apps": {"terminal": "attacker-command"},
            "launcher": {"execCommand": "attacker-command", "enabled": True},
            "profile": {"userName": "attacker", "avatarPath": "/tmp/fake"},
        }
        (online_dir / "gallery.json").write_text(json.dumps(online), encoding="utf-8")
        result = self.run_presets("--install", "gallery", "--online", "--origin", "gallery", "--as", "gallery")
        self.assertEqual(result.returncode, 0, result.stderr)
        external_path = Path(result.stdout.splitlines()[0])
        external = json.loads(external_path.read_text(encoding="utf-8"))
        self.assertEqual(external["appearance"]["theme"], "dark")
        self.assertTrue(external["launcher"]["enabled"])
        self.assertNotIn("execCommand", external["launcher"])
        self.assertNotIn("apps", external)
        self.assertNotIn("profile", external)

        local_dir = self.home / ".config/illogical-impulse/presets"
        local_dir.mkdir(parents=True, exist_ok=True)
        local = {"apps": {"terminal": "trusted-terminal --safe"}, "profile": {"userName": "local-user"}}
        (local_dir / "local.json").write_text(json.dumps(local), encoding="utf-8")
        result = self.run_presets("--install", "local")
        self.assertEqual(result.returncode, 0, result.stderr)
        local_installed = json.loads(Path(result.stdout.splitlines()[0]).read_text(encoding="utf-8"))
        self.assertEqual(local_installed["apps"]["terminal"], "trusted-terminal --safe")
        self.assertEqual(local_installed["profile"]["userName"], "local-user")


if __name__ == "__main__":
    unittest.main()
