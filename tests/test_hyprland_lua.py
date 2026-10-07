"""Exercise Hyprland Lua planning modules with the same files Hyprland loads."""

from pathlib import Path
import shutil
import subprocess
import unittest


REPO = Path(__file__).resolve().parents[1]
# Hyprland embeds Lua 5.5; distributions without it (such as CI) provide 5.4.
LUA = next(filter(None, map(shutil.which, ("lua", "lua5.5", "lua5.4"))), None)


class HyprlandLuaTests(unittest.TestCase):
    def test_lua_scripts(self):
        self.assertIsNotNone(LUA, "A Lua interpreter is required for the Hyprland Lua tests")
        scripts = sorted((REPO / "tests").glob("*.lua"))
        self.assertTrue(scripts)
        for script in scripts:
            with self.subTest(script=script.name):
                result = subprocess.run([LUA, str(script.relative_to(REPO))], cwd=REPO,
                                        text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
