import importlib.util
from pathlib import Path
import tempfile
import unittest
import json
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / 'dots/.config/quickshell/ii/scripts/colors/sync-sddm-theme.py'
spec = importlib.util.spec_from_file_location('sddm_assets', SCRIPT)
assets = importlib.util.module_from_spec(spec)
spec.loader.exec_module(assets)


class SddmAssetTests(unittest.TestCase):
    def test_ini_values_cannot_inject_more_settings(self):
        for value in ['font\nCurrent=other', 'font\rvalue', 'font\0value']:
            with self.assertRaises(ValueError):
                assets.ini_value(value)
        self.assertEqual(assets.ini_value('Font, "quoted"'), '"Font, \\"quoted\\""')
        self.assertEqual(assets.ini_value(False), 'false')
        with self.assertRaises(ValueError):
            assets.ini_value(float('nan'))

    def test_public_asset_does_not_inherit_private_mode(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'private-font.ttf'
            source.write_bytes(b'font fixture')
            source.chmod(0o600)
            target = root / 'public-font.ttf'
            self.assertEqual(assets.publish(source, target), target.as_uri())
            self.assertEqual(target.read_bytes(), source.read_bytes())
            self.assertEqual(target.stat().st_mode & 0o777, 0o644)

    def test_sync_exposes_only_appearance_not_private_config(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory) / 'home'
            config = home / '.config/illogical-impulse/config.json'
            colors = home / '.local/state/quickshell/user/generated/colors.json'
            config.parent.mkdir(parents=True)
            colors.parent.mkdir(parents=True)
            config.write_text(json.dumps({'ai': {'apiKey': 'do-not-publish-this'},
                                          'unrelated': 'also-private',
                                          'appearance': {'transparency': {'automatic': False}}}))
            colors.write_text(json.dumps(dict.fromkeys(assets.COLORS, '#123456')))
            font = Path(directory) / 'font.ttf'
            font.write_bytes(b'font fixture')
            output = Path(directory) / 'public'
            with patch.object(assets.subprocess, 'check_output', return_value=str(font)):
                assets.sync(output, home)
            published = b''.join(p.read_bytes() for p in output.rglob('*') if p.is_file())
            self.assertNotIn(b'do-not-publish-this', published)
            self.assertNotIn(b'also-private', published)
            self.assertNotIn(b'apiKey', published)
            self.assertIn(b'#123456', published)


if __name__ == '__main__':
    unittest.main()
