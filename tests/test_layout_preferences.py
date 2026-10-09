"""Run the real Config adapter to verify migration and independent persistence."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

REPO = Path(__file__).resolve().parents[1]
SOURCE = REPO / 'dots/.config/quickshell/ii/modules/common'
QS = shutil.which('qs')


@unittest.skipUnless(QS, 'Quickshell is needed to exercise the JSON adapter')
class LayoutPreferencesTests(unittest.TestCase):
    def test_migration_edits_reload_and_runtime_handoff(self):
        with tempfile.TemporaryDirectory(prefix='layout-preferences-') as directory:
            base = Path(directory)
            def write(name, value):
                path = base / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(value)
                return path

            settings = write('settings.json', json.dumps({
                'desktopLayout': 'classic',
                'bar': {'bottom': True, 'workspaces': {'shown': 7, 'numberMap': ['一', '二']}},
                'overview': {'scale': 0.23, 'centerIcons': False, 'columns': 4},
                # A partially migrated profile must win over its legacy seed.
                'desktopLayouts': {'scrolling': {'overview': {'scale': 0.16}}},
            }))
            write('common/qmldir', '\n'.join([
                'singleton Config 1.0 Config.qml', 'singleton Directories 1.0 Directories.qml',
                'singleton Appearance 1.0 Appearance.qml',
                *[f'{name} 1.0 {name}.qml' for name in
                  ('DesktopBarOptions', 'DesktopOverviewOptions', 'DesktopLayoutProfile')],
            ]))
            for name in ('Config', 'DesktopBarOptions', 'DesktopOverviewOptions', 'DesktopLayoutProfile'):
                source = (SOURCE / f'{name}.qml').read_text()
                write(f'common/{name}.qml', source.replace('import qs.modules.common.functions', 'import "functions"'))
            write('common/functions/qmldir', 'singleton Placeholder 1.0 Placeholder.qml')
            write('common/functions/Placeholder.qml', 'pragma Singleton\nimport QtQml\nQtObject {}')
            write('common/Directories.qml', 'pragma Singleton\nimport QtQml\nQtObject { property string shellConfigPath: '
                  + json.dumps(str(settings)) + '; property string videos: "/tmp" }')
            write('common/Appearance.qml', 'pragma Singleton\nimport QtQml\nQtObject { property var font: ({pixelSize: {smaller: 12}}) }')
            write('shell.qml', '''import QtQuick
import Quickshell
import Quickshell.Io
import "common"
ShellRoot {
    IpcHandler {
        target: "test"
        function mode(value: string): void { Config.options.desktopLayout = value; }
        function runtime(value: string): void { Config.runtimeLayout = value; }
        function edit(key: string, value: string): void { Config.setNestedValue(key, JSON.parse(value)); }
        function snapshot(): string {
            function profile(value) {
                return {scale: value.overview.scale, center: value.overview.centerIcons,
                    columns: value.overview.columns, bottom: value.bar.bottom,
                    shown: value.bar.workspaces.shown, numbers: value.bar.workspaces.numberMap};
            }
            return JSON.stringify({ready: Config.ready, mode: Config.options.desktopLayout,
                active: profile(Config.layout), classic: profile(Config.layoutFor("classic")),
                scrolling: profile(Config.layoutFor("scrolling"))});
        }
    }
}
''')
            runtime = base / 'runtime'
            runtime.mkdir(mode=0o700)
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                       XDG_RUNTIME_DIR=str(runtime), NO_COLOR='1')
            for name in ('WAYLAND_DISPLAY', 'DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE'):
                env.pop(name, None)
            command = [QS, '-p', str(base / 'shell.qml')]
            def rpc(method, *args):
                return subprocess.check_output(command + ['ipc', 'call', 'test', method, *args], env=env,
                                               text=True, stderr=subprocess.STDOUT, timeout=5).strip()
            def snapshot(): return json.loads(rpc('snapshot'))
            def wait_for(predicate):
                deadline = time.monotonic() + 4
                while time.monotonic() < deadline:
                    if predicate(): return
                    time.sleep(0.04)
                self.fail(str(snapshot()))
            def start():
                result = subprocess.run(command + ['-d'], env=env, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('Configuration Loaded', result.stdout + result.stderr)
                wait_for(lambda: snapshot()['ready'])
            def stop(): subprocess.run(command + ['kill'], env=env, capture_output=True, timeout=5)
            try:
                start()
                wait_for(lambda: json.loads(settings.read_text()).get('desktopLayouts', {}).get('version') == 1)
                initial = snapshot()
                self.assertEqual(initial['classic']['scale'], 0.23)
                self.assertEqual(initial['scrolling']['scale'], 0.16)
                self.assertEqual(initial['classic']['numbers'], ['一', '二'])
                self.assertEqual(initial['scrolling']['numbers'], ['一', '二'])
                rpc('edit', 'overview.scale', '0.28')
                rpc('edit', 'bar.bottom', 'false')
                rpc('edit', 'bar.workspaces.numberMap', '["甲"]')
                rpc('runtime', 'classic')
                rpc('mode', 'scrolling')
                self.assertEqual(snapshot()['active']['scale'], 0.28, 'Old native surfaces changed profile before reload')
                rpc('edit', 'overview.scale', '0.12')
                rpc('edit', 'bar.workspaces.shown', '5')
                rpc('runtime', 'scrolling')
                changed = snapshot()
                self.assertEqual(changed['active']['scale'], 0.12)
                self.assertEqual(changed['classic']['shown'], 7)
                self.assertFalse(changed['classic']['bottom'])
                self.assertTrue(changed['scrolling']['bottom'])
                self.assertEqual(changed['scrolling']['numbers'], ['一', '二'], 'Array edits leaked between profiles')
                wait_for(lambda: json.loads(settings.read_text())['desktopLayouts']['scrolling']['overview']['scale'] == 0.12)
                stop()
                start()
                persisted = snapshot()
                self.assertEqual(persisted['classic'], changed['classic'])
                self.assertEqual(persisted['scrolling'], changed['scrolling'])
                self.assertEqual(persisted['mode'], 'scrolling')
                self.assertNotIn('bar', json.loads(settings.read_text()), 'Legacy shared preferences must be retired')
                # An old external writer may leave legacy fields; they must not
                # overwrite either already migrated profile on a file reload.
                saved = json.loads(settings.read_text())
                saved['bar'] = {'bottom': False}
                saved['overview'] = {'scale': 0.99}
                temporary = settings.with_suffix('.next')
                temporary.write_text(json.dumps(saved)); temporary.replace(settings)
                time.sleep(0.25)
                self.assertEqual(snapshot()['classic'], changed['classic'])
                self.assertEqual(snapshot()['scrolling'], changed['scrolling'])
            finally:
                stop()
