"""Generated terminal themes must be complete before readers can see them."""

import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time
import unittest


REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / "dots/.config/quickshell/ii/scripts/colors/applycolor.sh"
TEMPLATES = SCRIPT.parent / "terminal"


class TerminalColorTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        config = self.root / "config"
        (config / "quickshell/ii").mkdir(parents=True)
        (config / "illogical-impulse").mkdir()
        (config / "illogical-impulse/config.json").write_text(json.dumps({
            "appearance": {"wallpaperTheming": {"enableTerminal": False}},
        }))
        self.generated = self.root / "state/quickshell/user/generated"
        self.output = self.generated / "terminal"
        self.output.mkdir(parents=True)
        commands = self.root / "bin"
        commands.mkdir()
        # Tests must not signal the user's running terminals.
        (commands / "pgrep").write_text("#!/bin/sh\nexit 1\n")
        (commands / "pgrep").chmod(0o755)
        self.env = dict(os.environ, XDG_CONFIG_HOME=str(config),
                        XDG_STATE_HOME=str(self.root / "state"),
                        XDG_CACHE_HOME=str(self.root / "cache"),
                        PATH=str(commands) + os.pathsep + os.environ["PATH"])
        names = set()
        for filename in ("kitty-theme.conf", "sequences.txt"):
            names.update(re.findall(r"\$([A-Za-z_]\w*)", (TEMPLATES / filename).read_text()))
        names.discard("alpha")
        self.colors = {name: f"#{0x334400 + index:06x}" for index, name in enumerate(sorted(names))}
        self.write_palette()

    def write_palette(self, missing=None):
        # Referenced colors come after many other material colors.
        entries = [f"$unused{i}: #123456;\n" for i in range(80)]
        entries += [f"${name}: {value};\n" for name, value in self.colors.items() if name != missing]
        (self.generated / "material_colors.scss").write_text("".join(entries))

    def command(self, body):
        return ["bash", "-c", 'source "$1"; ' + body, "terminal-colors-test", str(SCRIPT)]

    def run_shell(self, body):
        return subprocess.run(self.command(body), env=self.env, text=True,
                              capture_output=True, timeout=10)

    def test_complete_palette_for_both_templates(self):
        result = self.run_shell(
            'apply_kitty && render_terminal_template "$SCRIPT_DIR/terminal/sequences.txt" '
            '"$STATE_DIR/user/generated/terminal/sequences.txt"')
        self.assertEqual(result.returncode, 0, result.stderr)
        kitty = (self.output / "kitty-theme.conf").read_text()
        for index in range(16):
            self.assertRegex(kitty, rf"(?m)^color{index}\s+{self.colors[f'term{index}']}$")
        for filename in ("kitty-theme.conf", "sequences.txt"):
            self.assertNotRegex((self.output / filename).read_text(), r"\$[A-Za-z_]\w*")

    def test_incomplete_palette_keeps_previous_files(self):
        self.write_palette(missing="term15")
        for filename in ("kitty-theme.conf", "sequences.txt"):
            with self.subTest(filename=filename):
                target = self.output / filename
                target.write_text("previous valid theme\n")
                result = self.run_shell(
                    f'render_terminal_template "$SCRIPT_DIR/terminal/{filename}" '
                    f'"$STATE_DIR/user/generated/terminal/{filename}"')
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(target.read_text(), "previous valid theme\n")
                self.assertEqual(list(self.output.glob(filename + ".*")), [])

    def test_readers_never_see_template_placeholders(self):
        target = self.output / "kitty-theme.conf"
        target.write_text("foreground #abcdef\n")
        incomplete_seen = False
        with subprocess.Popen(self.command("apply_kitty"), env=self.env,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) as process:
            deadline = time.monotonic() + 10
            while process.poll() is None:
                data = target.read_bytes()
                incomplete_seen |= not data or b"$" in data
                if time.monotonic() >= deadline:
                    process.kill()
                    self.fail("Theme generation timed out")
                time.sleep(0.001)
            _, stderr = process.communicate()
        self.assertEqual(process.returncode, 0, stderr)
        self.assertFalse(incomplete_seen)

    def test_apply_waits_for_workers_and_propagates_failure(self):
        result = self.run_shell(
            'apply_kitty() { sleep 0.03; touch "$STATE_DIR/kitty-done"; }; '
            'apply_anyterm() { sleep 0.03; touch "$STATE_DIR/term-done"; }; '
            'apply_term; [[ -f "$STATE_DIR/kitty-done" && -f "$STATE_DIR/term-done" ]]')
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.run_shell('apply_kitty() { return 7; }; apply_anyterm() { :; }; apply_term')
        self.assertEqual(result.returncode, 7)


if __name__ == "__main__":
    unittest.main()
