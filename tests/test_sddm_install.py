"""The privileged SDDM installer must not replace a selected theme before validation."""

import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "tools/sddm-theme.py"
spec = importlib.util.spec_from_file_location("sddm_theme", SCRIPT)
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)

REQUIRED = ("Main.qml", "Style.qml", "PasswordShapes.qml", "PasswordShapePaths.js", "metadata.desktop", "theme.conf")


class SddmInstallTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.themes = self.root / "themes"
        self.theme = self.themes / "ii-lock"
        self.theme.mkdir(parents=True)
        (self.theme / "Main.qml").write_text("selected theme\n")
        self.bundle = self.root / "bundle"
        (self.bundle / "theme").mkdir(parents=True)
        manifest = {}
        for name in REQUIRED:
            path = self.bundle / "theme" / name
            path.write_text("new " + name + "\n")
            manifest[name] = hashlib.sha256(path.read_bytes()).hexdigest()
        (self.bundle / "manifest.json").write_text(json.dumps(manifest))
        for name, value in {"THEME": self.theme, "ASSETS": self.root / "assets",
                            "OVERRIDE": self.root / "sddm.conf.d/zz-ii-lock.conf",
                            "BACKUPS": self.root / "backups"}.items():
            patcher = patch.object(installer, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        user = SimpleNamespace(pw_uid=1000, pw_gid=1000, pw_dir=str(self.root / "home"))
        for patcher in (patch.object(installer.os, "getuid", return_value=0), patch.object(installer.os, "chown"),
                        patch.object(installer.pwd, "getpwnam", return_value=user)):
            patcher.start()
            self.addCleanup(patcher.stop)

    def install(self, validation_passes):
        def run(command, check):
            if command[:3] == ["runuser", "-u", "sddm"]:
                self.validated = Path(command[-1])
                if not validation_passes:
                    raise subprocess.CalledProcessError(1, command)
            else:
                (installer.ASSETS / "theme.conf").write_text("[General]\n")
        with patch.object(installer.subprocess, "run", side_effect=run), contextlib.redirect_stdout(io.StringIO()):
            installer.install(self.bundle, "desktop-user")

    def test_failed_validation_keeps_the_selected_theme(self):
        installer.OVERRIDE.parent.mkdir(parents=True)
        installer.OVERRIDE.write_text("[Theme]\nCurrent=ii-lock\n")
        with self.assertRaises(subprocess.CalledProcessError):
            self.install(validation_passes=False)
        self.assertNotEqual(self.validated, self.theme, "Validation must run on the staged copy")
        self.assertEqual([p.name for p in self.theme.iterdir()], ["Main.qml"])
        self.assertEqual((self.theme / "Main.qml").read_text(), "selected theme\n")
        self.assertEqual(sorted(p.name for p in self.themes.iterdir()), ["ii-lock"], "No staging directory remains")

    def test_validated_theme_replaces_the_previous_one(self):
        self.install(validation_passes=True)
        self.assertEqual((self.theme / "Main.qml").read_text(), "new Main.qml\n")
        self.assertEqual((self.theme / "theme.conf.user").resolve(), (installer.ASSETS / "theme.conf").resolve())
        self.assertEqual(sorted(p.name for p in self.themes.iterdir()), ["ii-lock"])
        self.assertIn("Current=ii-lock", installer.OVERRIDE.read_text())


if __name__ == "__main__":
    unittest.main()
