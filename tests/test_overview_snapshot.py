"""Render the real thumbnail's asynchronous grabs and capture-loss fallback."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

from PIL import Image, UnidentifiedImageError


SOURCE = Path(__file__).resolve().parents[1] / "dots/.config/quickshell/ii"
QS = shutil.which("qs")


@unittest.skipUnless(QS, "Quickshell is needed for rendered thumbnail checks")
class OverviewSnapshotTests(unittest.TestCase):
    def test_last_frame_survives_capture_loss_and_cross_output_handoff(self):
        with tempfile.TemporaryDirectory(prefix="overview-snapshot-") as directory:
            base = Path(directory)

            def write(name, contents):
                path = base / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(contents)

            for module, names in {"": ["GlobalStates"], "services": ["AppSearch"],
                                  "common": ["Appearance", "Config"], "functions": ["ColorUtils"]}.items():
                write(f"{module}/qmldir".lstrip("/"), "\n".join(f"singleton {name} 1.0 {name}.qml" for name in names))
            with (base / "qmldir").open("a") as descriptor:
                descriptor.write("\nOverviewWindow 1.0 OverviewWindow.qml\nFakeCapture 1.0 FakeCapture.qml\nOverviewDragController 1.0 OverviewDragController.qml\n")
            write("services/ScrollingGeometry.js", (SOURCE / "services/ScrollingGeometry.js").read_text())
            write("OverviewDragController.qml", (SOURCE / "modules/ii/overview/OverviewDragController.qml").read_text()
                  .replace('"../../../services/ScrollingGeometry.js"', '"services/ScrollingGeometry.js"'))
            write("GlobalStates.qml", "pragma Singleton\nimport QtQml\nQtObject { property bool overviewOpen: true }")
            write("services/AppSearch.qml", 'pragma Singleton\nimport QtQml\nQtObject { function guessIcon(name) { return "image-missing"; } }')
            write("common/Appearance.qml", """pragma Singleton
import QtQml
QtObject {
    property var rounding: ({small: 8})
    property var font: ({pixelSize: {smaller: 10}})
    property var colors: ({colSurfaceContainerHigh: "#333333", colLayer2Active: "transparent",
        colLayer2Hover: "transparent", colLayer2: "transparent", colSecondary: "#aaaaaa"})
    property var m3colors: ({m3outline: "transparent"})
}
""")
            write("common/Config.qml", "pragma Singleton\nimport QtQml\nQtObject { property var options: ({overview: {centerIcons: false}}) }")
            write("functions/ColorUtils.qml", "pragma Singleton\nimport QtQml\nQtObject { function transparentize(color, amount) { return color; } }")
            write("widgets/StyledImage.qml", "import QtQuick\nItem { property var source; property int fillMode; property bool asynchronous; property bool retainWhileLoading; property bool cache; property bool mipmap }")
            thumbnail = (SOURCE / "modules/ii/overview/OverviewWindow.qml").read_text()
            for before, after in {"import qs\n": 'import "."\n', "import qs.services": 'import "services"',
                                  "import qs.modules.common\n": 'import "common"\n',
                                  "import qs.modules.common.functions": 'import "functions"',
                                  "import qs.modules.common.widgets": 'import "widgets"',
                                  "ScreencopyView {": "FakeCapture {"}.items():
                thumbnail = thumbnail.replace(before, after)
            write("OverviewWindow.qml", thumbnail)
            # Render a real scene-graph texture, while controlling the protocol's
            # content/source lifecycle without a live compositor in the test.
            write("FakeCapture.qml", """import QtQuick
Rectangle {
    property var captureSource
    property bool hasContent: false
    property bool live: false
    property size constraintSize
    signal stopped()
    color: "#00ef55"
    visible: hasContent
    onCaptureSourceChanged: {
        hasContent = false;
        if (captureSource) ready.restart();
    }
    Timer { id: ready; interval: 50; onTriggered: parent.hasContent = true }
}
""")
            write("shell.qml", """import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
Scope {
    QtObject { id: token }
    OverviewDragController { id: cache }
    Window {
        id: output
        width: 500; height: 240; visible: false
        OverviewWindow { id: card; x: 10; y: 10; width: 220; height: 180;
            toplevel: token; windowData: ({address: "0xa", class: "test", viewFraction: 1});
            onSnapshotChanged: { if (snapshot) cache.rememberSnapshot(windowData.address, snapshot); } }
        OverviewWindow { id: destination; x: 250; y: 10; width: 220; height: 180;
            capturing: false; fallbackSnapshot: cache.snapshots["0xa"] ?? null;
            windowData: ({address: "0xa", class: "test", viewFraction: 0}) }
        Loader {
            id: reopened; x: 10; y: 10; active: false
            sourceComponent: OverviewWindow { width: 220; height: 180; capturing: false;
                fallbackSnapshot: cache.snapshots["0xa"] ?? null;
                windowData: ({address: "0xa", class: "test", viewFraction: 0}) }
        }
    }
    IpcHandler {
        target: "test"
        function status(): string {
            const view = card.children.find(item => item.constraintSize !== undefined);
            const timer = card.data.find(item => item.interval === 32);
            return JSON.stringify({captured: card.captured, pending: card.snapshotPending,
                snapshot: !!card.snapshot, inherited: !!destination.snapshot,
                visible: output.visible, cardWindow: card.Window.window?.visible,
                viewWindow: view?.Window.window?.visible, firstTimer: timer?.running,
                cached: !!cache.snapshots["0xa"], recreated: !!reopened.item?.snapshot});
        }
        function revealSurface(): string { output.visible = true; return JSON.stringify({visible: output.visible}); }
        function exportFrame(path: string, remote: bool): void {
            (remote ? destination : card).grabToImage(result => result.saveToFile(path));
        }
        function loseCapture(): void {
            // Clear a capture in the same event-loop turn as an asynchronous grab.
            card.saveSnapshot(); card.capturing = false;
        }
        function detach(): void { destination.fallbackSnapshot = null; card.snapshot = null; card.visible = false; reopened.active = true; }
        function exportReopened(path: string): void { reopened.item.grabToImage(result => result.saveToFile(path)); }
        function closeWindow(): void { cache.pruneSnapshots([]); }
    }
}
""")
            runtime = base / "runtime"
            runtime.mkdir(mode=0o700)
            env = os.environ.copy()
            env.update(QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", XDG_RUNTIME_DIR=str(runtime))
            for name in ("DISPLAY", "WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
                env.pop(name, None)
            command = [QS, "-p", str(base / "shell.qml")]

            def rpc(method, *arguments):
                return subprocess.check_output(command + ["ipc", "call", "test", method, *map(str, arguments)],
                                               env=env, text=True, stderr=subprocess.STDOUT, timeout=5).strip()

            def green_frame(name, remote=False, recreated=False):
                path = base / f"{name}.png"
                if recreated:
                    rpc("exportReopened", path)
                else:
                    rpc("exportFrame", path, "true" if remote else "false")
                for _ in range(50):
                    try:
                        with Image.open(path) as picture:
                            r, g, b = picture.convert("RGB").getpixel((100, 90))
                        break
                    except (OSError, UnidentifiedImageError):
                        pass
                    time.sleep(0.02)
                else:
                    self.fail(f"{name} did not finish exporting")
                self.assertTrue(g > 180 and r < 30 and b < 110, f"{name} lost its captured contents: {(r, g, b)}")

            started = subprocess.run(command + ["-d"], env=env, text=True, capture_output=True, timeout=10)
            try:
                self.assertEqual(started.returncode, 0, started.stdout + started.stderr)
                self.assertIn("Configuration Loaded", started.stdout + started.stderr)
                for _ in range(30):
                    state = json.loads(rpc("status"))
                    if state["captured"]:
                        break
                    time.sleep(0.02)
                self.assertTrue(state["captured"] and not state["snapshot"], str(state))
                revealed = rpc("revealSurface")
                deadline = time.monotonic() + 0.6
                while time.monotonic() < deadline:
                    state = json.loads(rpc("status"))
                    if state["snapshot"] and state["inherited"]:
                        break
                    time.sleep(0.02)
                self.assertTrue(state["snapshot"] and state["inherited"], str(state) + revealed +
                                subprocess.check_output(command + ["log", "-t", "40"], env=env, text=True))
                green_frame("live")
                rpc("loseCapture")
                time.sleep(0.1)
                self.assertFalse(json.loads(rpc("status"))["captured"])
                green_frame("after-loss")
                green_frame("destination", True)
                rpc("detach")
                time.sleep(0.05)
                green_frame("after-controller-clear", True)
                self.assertTrue(json.loads(rpc("status"))["recreated"])
                green_frame("after-card-recreated", recreated=True)
                rpc("closeWindow")
                self.assertFalse(json.loads(rpc("status"))["cached"], "Closed windows retained their images")
            finally:
                subprocess.run(command + ["kill"], env=env, capture_output=True, timeout=5)


if __name__ == "__main__":
    unittest.main()
