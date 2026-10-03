import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "tools/desktop-config.py"


class DesktopConfigTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.repo = self.root / "repo"
        self.home = self.root / "home"
        self.relative = ".config/quickshell/ii/GlobalStates.qml"
        self.kitty_relative = ".config/kitty/kitty.conf"
        (self.repo / "config").mkdir(parents=True)
        (self.repo / "config/managed-files.txt").write_text(self.relative + "\n" + self.kitty_relative + "\n")
        (self.repo / "config/scrolling-profile.json").write_text(json.dumps({"bar": {"verbose": True}}))
        source = self.repo / "dots" / self.relative
        source.parent.mkdir(parents=True)
        source.write_text("fork version\n")
        target = self.home / self.relative
        target.parent.mkdir(parents=True)
        target.write_text("live version\n")
        kitty_source = self.repo / "dots" / self.kitty_relative
        kitty_source.parent.mkdir(parents=True)
        kitty_source.write_text("remember_window_size no\n")
        kitty_target = self.home / self.kitty_relative
        kitty_target.parent.mkdir(parents=True)
        kitty_target.write_text("remember_window_size yes\n")
        self.settings = self.home / ".config/illogical-impulse/config.json"
        self.settings.parent.mkdir(parents=True)
        self.settings.write_text(json.dumps({"bar": {"verbose": False, "bottom": True},
                                             "ai": {"apiKey": "private-token"}}))

    def run_command(self, command, *options):
        return subprocess.run([sys.executable, str(SCRIPT), command, "--repo", str(self.repo),
                               "--home", str(self.home), *options], capture_output=True, text=True)

    def test_deploy_preserves_unmanaged_settings_and_backs_up_originals(self):
        result = self.run_command("deploy")
        self.assertEqual(result.returncode, 0, result.stderr)
        settings = json.loads(self.settings.read_text())
        self.assertEqual(settings["bar"], {"verbose": True, "bottom": True})
        self.assertEqual(settings["ai"]["apiKey"], "private-token")
        backup = next((self.home / ".local/state/dots-hyprland/backups").iterdir())
        self.assertEqual((backup / self.relative).read_text(), "live version\n")
        self.assertEqual((backup / self.kitty_relative).read_text(), "remember_window_size yes\n")
        self.assertEqual((self.home / self.kitty_relative).read_text(), "remember_window_size no\n")
        self.assertFalse(json.loads((backup / ".config/illogical-impulse/config.json").read_text())["bar"]["verbose"])
        self.assertEqual(backup.stat().st_mode & 0o777, 0o700)
        self.assertNotIn("private-token", result.stdout + result.stderr)
        self.assertEqual(self.run_command("status").returncode, 0)
        self.assertEqual(self.run_command("deploy").returncode, 0)
        self.assertEqual(len(list(backup.parent.iterdir())), 1, "An unchanged deployment creates no backup")

    def test_capture_uses_only_shared_preference_keys(self):
        result = self.run_command("capture")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.repo / "dots" / self.relative).read_text(), "live version\n")
        self.assertEqual((self.repo / "dots" / self.kitty_relative).read_text(), "remember_window_size yes\n")
        profile = json.loads((self.repo / "config/scrolling-profile.json").read_text())
        self.assertEqual(profile, {"bar": {"verbose": False}})
        self.assertNotIn("private-token", json.dumps(profile) + result.stdout + result.stderr)

    def test_dry_run_writes_nothing(self):
        before = {path: path.read_bytes() for path in self.root.rglob("*") if path.is_file()}
        self.assertEqual(self.run_command("deploy", "--dry-run").returncode, 0)
        after = {path: path.read_bytes() for path in self.root.rglob("*") if path.is_file()}
        self.assertEqual(before, after)
        self.assertEqual(self.run_command("status").returncode, 1)

    def test_missing_source_and_path_escape_fail_before_writes(self):
        original = (self.home / self.relative).read_bytes()
        manifest = self.repo / "config/managed-files.txt"
        manifest.write_text(self.relative + "\n.config/quickshell/ii/missing.qml\n")
        self.assertEqual(self.run_command("deploy").returncode, 2)
        self.assertEqual((self.home / self.relative).read_bytes(), original)
        self.assertFalse((self.home / ".local").exists())
        manifest.write_text(".config/hypr/../../outside\n")
        self.assertEqual(self.run_command("deploy").returncode, 2)
        manifest.write_text(self.relative + "\n")
        (self.home / self.relative).unlink()
        (self.home / self.relative).symlink_to(self.root / "outside")
        self.assertEqual(self.run_command("deploy").returncode, 2)


if __name__ == "__main__":
    unittest.main()
