"""Check lock reload against a separately launched Wayland compositor.

II_LOCK_TEST_ENV names its environment JSON. Never lock the user's desktop.
"""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest


SOURCE = Path(__file__).resolve().parents[1] / "dots/.config/quickshell/ii"
QS = shutil.which("qs")


@unittest.skipUnless(QS and os.environ.get("II_LOCK_TEST_ENV"), "Set II_LOCK_TEST_ENV for an isolated compositor")
class LockReloadTests(unittest.TestCase):
    def test_locked_reload_restores_ui_before_settings_and_restarts_authentication(self):
        with tempfile.TemporaryDirectory(prefix="lock-controller-") as directory:
            base = Path(directory)

            def write(name, content):
                path = base / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content)

            write("qmldir", "singleton GlobalStates 1.0 GlobalStates.qml\n")
            write("GlobalStates.qml", "pragma Singleton\nimport Quickshell\nSingleton { property bool screenLocked: false }")
            write("modules/common/qmldir", "singleton Config 1.0 Config.qml\nsingleton Persistent 1.0 Persistent.qml\n")
            write("modules/common/Config.qml", """pragma Singleton
import QtQuick
import Quickshell
Singleton {
    property bool ready: false
    property QtObject options: QtObject {
        property string panelFamily: "ii"
        property var lock: ({useHyprlock: false, launchOnStartup: false, security: {unlockKeyring: false}})
    }
    Timer { interval: 350; running: true; onTriggered: parent.ready = true }
}
""")
            write("modules/common/Persistent.qml", "pragma Singleton\nimport Quickshell\nSingleton { property bool ready: true; property bool isNewHyprlandInstance: false }")
            write("services/qmldir", "singleton KeyringStorage 1.0 KeyringStorage.qml\nsingleton Idle 1.0 Idle.qml\nsingleton Session 1.0 Session.qml\n")
            write("services/KeyringStorage.qml", "pragma Singleton\nimport QtQml\nQtObject { function fetchKeyringData() {} }")
            write("services/Idle.qml", "pragma Singleton\nimport QtQml\nQtObject { function toggleInhibit(value) {} }")
            write("services/Session.qml", "pragma Singleton\nimport QtQml\nQtObject { function poweroff() {} function reboot() {} }")
            write("modules/common/panels/lock/LockContext.qml", """import QtQml
import Quickshell
Scope {
    enum ActionEnum { Unlock, Poweroff, Reboot }
    signal unlocked(int targetAction)
    signal shouldReFocus()
    property bool alsoInhibitIdle: false
    property bool sleepInProgress: false
    property bool fingerprintsConfigured: true
    property string pamConfigDirectory: "isolated-test"
    property string currentText: ""
    property int attempts: 0
    function reset() { currentText = ""; }
    function tryFingerUnlock() { attempts++; }
}
""")
            for filename in ("DesktopLock.qml", "LockScreen.qml"):
                content = (SOURCE / "modules/common/panels/lock" / filename).read_text()
                for before, after in {"import qs\n": 'import "../../../.."\n',
                                      "import qs.services": 'import "../../../../services"',
                                      "import qs.modules.common.functions\n": "",
                                      "import qs.modules.common\n": 'import "../.."\n'}.items():
                    content = content.replace(before, after)
                write("modules/common/panels/lock/" + filename, content)
            lock = """import QtQuick
import Quickshell.Io
import "../../common/panels/lock"
LockScreen {
    id: root
    lockSurface: Rectangle { color: "#00ef55" }
    IpcHandler {
        target: "authentication"
        function attempts(): int { return root.context.attempts; }
        function accepted(): void { root.context.unlocked(LockContext.ActionEnum.Unlock); }
        function family(): string { return "FAMILY"; }
    }
}
"""
            write("modules/ii/lock/Lock.qml", lock.replace("FAMILY", "ii"))
            write("modules/waffle/lock/WaffleLock.qml", lock.replace("FAMILY", "waffle"))
            shell = """//@ pragma Env QS_NO_RELOAD_POPUP=1
import QtQuick
import Quickshell
import Quickshell.Io
import "."
import "modules/common"
import "modules/common/panels/lock"
ShellRoot {
    id: root
    property string generation: "generation:" + Math.random()
    DesktopLock {}
    IpcHandler {
        target: "test"
        function reload(): void { Quickshell.reload(false); }
        function family(value: string): void { Config.options.panelFamily = value; }
        function ready(): bool { return Config.ready; }
        function generation(): string { return root.generation; }
    }
}
"""
            write("shell.qml", shell)
            env = os.environ.copy()
            isolated = json.loads(Path(os.environ["II_LOCK_TEST_ENV"]).read_text())
            self.assertNotEqual(isolated["HYPRLAND_INSTANCE_SIGNATURE"], env.get("HYPRLAND_INSTANCE_SIGNATURE"))
            self.assertNotEqual(isolated["XDG_RUNTIME_DIR"], env.get("XDG_RUNTIME_DIR"))
            env.update(isolated, QT_QPA_PLATFORM="wayland")
            env.pop("DISPLAY", None)
            command = [QS, "-p", str(base / "shell.qml")]

            def rpc(target, method, *args):
                result = subprocess.run(command + ["ipc", "call", target, method, *args], env=env,
                                        text=True, capture_output=True, timeout=5)
                if result.returncode:
                    raise RuntimeError(result.stdout + result.stderr)
                return result.stdout.strip()

            def wait_for(predicate):
                deadline = time.monotonic() + 8
                while time.monotonic() < deadline:
                    try:
                        if predicate():
                            return
                    except (RuntimeError, ValueError):
                        pass
                    time.sleep(0.03)
                self.fail("Lock did not become ready: " + subprocess.run(command + ["log", "-t", "35"], env=env,
                                                                       text=True, capture_output=True).stdout)

            def locked():
                state = json.loads(rpc("lock", "state"))
                return state["locked"] and state["secure"] and int(rpc("authentication", "attempts")) > 0

            def reload():
                previous = rpc("test", "generation")
                rpc("test", "reload")
                def changed():
                    current = rpc("test", "generation")
                    return current.startswith("generation:") and current != previous
                wait_for(changed)

            def check_surfaces():
                from PIL import Image
                monitors = json.loads(subprocess.check_output(["hyprctl", "monitors", "-j"], env=env, text=True))
                self.assertGreaterEqual(len(monitors), 2, "Native lock checks require two isolated outputs")
                for index, monitor in enumerate(monitors):
                    path = base / f"surface-{index}.png"
                    subprocess.run(["grim", "-o", monitor["name"], str(path)], env=env, check=True, capture_output=True)
                    with Image.open(path) as frame:
                        red, green, blue = frame.convert("RGB").getpixel((50, 50))
                    self.assertTrue(green > 180 and red < 30 and blue < 110, f"Missing lock UI on {monitor['name']}")

            started = subprocess.run(command + ["-d"], env=env, text=True, capture_output=True, timeout=10)
            try:
                self.assertEqual(started.returncode, 0, started.stdout + started.stderr)
                wait_for(lambda: rpc("test", "ready") == "true")
                wait_for(lambda: not json.loads(rpc("lock", "state"))["locked"])
                rpc("lock", "activate")
                wait_for(locked)
                check_surfaces()
                for _ in range(3):
                    reload()
                    wait_for(locked)
                    check_surfaces()
                rpc("test", "family", "waffle")
                self.assertEqual(rpc("authentication", "family"), "ii", "Switching style destroyed an active lock")
                rpc("authentication", "accepted")
                wait_for(lambda: not json.loads(rpc("lock", "state"))["locked"])
                wait_for(lambda: rpc("authentication", "family") == "waffle")
                rpc("lock", "activate")
                wait_for(locked)
                reload()
                wait_for(locked)
                self.assertEqual(rpc("authentication", "family"), "waffle")
                check_surfaces()
                rpc("authentication", "accepted")
                wait_for(lambda: not json.loads(rpc("lock", "state"))["locked"])
                reload()
                wait_for(lambda: rpc("test", "ready") == "true")
                self.assertFalse(json.loads(rpc("lock", "state"))["locked"], "Reload relocked an unlocked desktop")
            finally:
                subprocess.run(command + ["kill"], env=env, capture_output=True, timeout=5)


if __name__ == "__main__":
    unittest.main()
