"""Exercise the real mode controller, including persistence and lock deferral."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

REPO = Path(__file__).resolve().parents[1]
QS = shutil.which("qs")


@unittest.skipUnless(QS, "Quickshell is needed for mode switching checks")
class DesktopModeTests(unittest.TestCase):
    def test_mode_switch_waits_for_saved_settings_and_unlock(self):
        with tempfile.TemporaryDirectory(prefix="desktop-mode-") as directory:
            base = Path(directory)
            def write(name, text):
                path = base / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text)
                return path

            write("qmldir", "singleton GlobalStates 1.0 GlobalStates.qml")
            write("GlobalStates.qml", """pragma Singleton
import QtQml
QtObject { property bool overviewOpen: true; property bool screenLocked: false }
""")
            write("modules/common/qmldir", "singleton Config 1.0 Config.qml")
            write("modules/common/Config.qml", """pragma Singleton
import QtQml
QtObject {
    property bool ready: true
    property string runtimeLayout: ""
    property var options: QtObject { property string desktopLayout: "scrolling" }
    signal saved()
    signal loaded()
}
""")
            write("services/qmldir", "singleton DesktopLayout 1.0 DesktopLayout.qml")
            source = (REPO / "dots/.config/quickshell/ii/services/DesktopLayout.qml").read_text()
            write("services/DesktopLayout.qml", source.replace("import qs\n", 'import "../"\n')
                  .replace("import qs.modules.common", 'import "../modules/common"'))
            write("shell.qml", """import QtQuick
import Quickshell
import Quickshell.Io
import "services"
import "modules/common"
import "."
ShellRoot {
    Component.onCompleted: DesktopLayout.load()
    IpcHandler {
        target: "test"
        function request(mode: string): void { Config.options.desktopLayout = mode; }
        function save(): void { Config.saved(); }
        function loaded(): void { Config.loaded(); }
        function locked(value: bool): void { GlobalStates.screenLocked = value; }
        function overview(): bool { return GlobalStates.overviewOpen; }
    }
}
""")
            write("native", "scrolling")
            write("persisted", "scrolling")
            binary = write("bin/hyprctl", r"""#!/usr/bin/env python3
import json
from pathlib import Path
import sys
base = Path(__file__).resolve().parents[1]
with (base / "calls").open("a") as output: output.write(" ".join(sys.argv[1:]) + "\n")
if sys.argv[1] == "reload":
    mode = (base / "persisted").read_text()
    (base / "native").write_text("dwindle" if mode == "classic" else "scrolling")
    print("ok")
else: print(json.dumps({"str": (base / "native").read_text()}))
""")
            binary.chmod(0o755)
            runtime = base / "runtime"
            runtime.mkdir(mode=0o700)
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                       XDG_RUNTIME_DIR=str(runtime), NO_COLOR="1", PATH=str(base / "bin") + ":" + os.environ["PATH"])
            for name in ("WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
                env.pop(name, None)
            command = [QS, "-p", str(base / "shell.qml")]
            def rpc(target, method, *args):
                return subprocess.check_output(command + ["ipc", "call", target, method, *map(str, args)],
                                               env=env, text=True, stderr=subprocess.STDOUT, timeout=5).strip()
            def state(): return json.loads(rpc("desktopLayout", "state"))
            def wait_mode(mode):
                deadline = time.monotonic() + 4
                while time.monotonic() < deadline:
                    status = state()
                    if status["applied"] == mode and status["ready"]: return status
                    time.sleep(0.04)
                self.fail(str(state()))
            def reloads():
                return (base / "calls").read_text().splitlines().count("reload")
            started = subprocess.run(command + ["-d"], env=env, text=True, capture_output=True, timeout=10)
            try:
                self.assertEqual(started.returncode, 0, started.stdout + started.stderr)
                self.assertIn("Configuration Loaded", started.stdout + started.stderr)
                wait_mode("scrolling")
                rpc("test", "request", "classic")
                time.sleep(0.12)
                self.assertEqual(reloads(), 0, "Must not reload before the settings file is saved")
                self.assertFalse(state()["ready"])
                self.assertEqual(rpc("test", "overview"), "false")
                write("persisted", "classic")
                rpc("test", "save")
                wait_mode("classic")
                self.assertEqual(reloads(), 1)
                rpc("test", "save")
                time.sleep(0.1)
                self.assertEqual(reloads(), 1, "Unrelated saves must not reload the compositor")
                rpc("test", "locked", "true")
                rpc("test", "request", "scrolling")
                write("persisted", "scrolling")
                rpc("test", "loaded")
                time.sleep(0.12)
                self.assertEqual(reloads(), 1, "A locked session must defer the native reload")
                rpc("test", "locked", "false")
                wait_mode("scrolling")
                self.assertEqual(reloads(), 2)
            finally:
                subprocess.run(command + ["kill"], env=env, capture_output=True, timeout=5)
