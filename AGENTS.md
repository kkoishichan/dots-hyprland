# Fork maintenance

- This is a fork of `end-4/dots-hyprland`. Preserve upstream history, licensing, and attribution.
- The checkout is the source of truth for the maintained desktop configuration. Edit `dots/`, then deploy the curated changes with `python3 tools/desktop-config.py deploy`.
- Add new customized desktop files to `config/managed-files.txt`; keep `config/scrolling-profile.json` limited to shareable interface preferences.
- Keep runtime state, credentials, generated theme colors, monitor arrangements, design backups, and screenshots on the local machine.
- Preserve the user's scrolling layout, per-monitor dynamic workspaces, unified Win/Win+Space overview, simple rounded previews, and animated centered window ribbon. Clicking a ribbon icon must preserve the cursor position. Standard keyboard focus keeps its normal warp behavior.
- Numbered workspace shortcuts and Win+Tab are intentionally removed. Do not add workarounds for the external keyboard's dropped Win+left-Shift+Right chord.
- Run `node tests/scrolling-workspaces.cjs`, `python3 -m unittest discover -s tests -p 'test_*.py'`, and `git diff --check` for configuration maintenance. Use actual Hyprland session checks when changing interactive behavior.
- Keep `origin` on the personal fork and `upstream` on the original repository. Merge upstream changes without discarding the fork's commits.
