#!/usr/bin/env python3
"""Compare, capture, and deploy the fork's curated desktop configuration."""

import argparse
from copy import deepcopy
from dataclasses import dataclass
from datetime import datetime
import json
import os
from pathlib import Path
import shutil
import stat
import tempfile
import uuid


@dataclass
class Change:
    relative: str
    data: bytes
    mode: int


def checked_path(root, relative):
    path = Path(relative)
    if path.is_absolute() or ".." in path.parts:
        raise ValueError(f"Invalid relative path: {relative}")
    destination = root / path
    if not destination.resolve().is_relative_to(root.resolve()):
        raise ValueError(f"Path escapes its destination: {relative}")
    return destination


def read_object(path, missing=False):
    if missing and not path.exists():
        return {}
    data = json.loads(path.read_text())
    if not isinstance(data, dict):
        raise ValueError(f"Expected a JSON object: {path}")
    return data


def managed_files(repo):
    paths = [line.strip() for line in (repo / "config/managed-files.txt").read_text().splitlines()
             if line.strip() and not line.lstrip().startswith("#")]
    if not paths or len(paths) != len(set(paths)):
        raise ValueError("Managed files must be nonempty and unique")
    for relative in paths:
        checked_path(repo / "dots", relative)
        allowed_files = (".config/kitty/kitty.conf", ".config/xdg-desktop-portal/hyprland-portals.conf")
        if relative not in allowed_files and not relative.startswith((".config/hypr/", ".config/quickshell/ii/")):
            raise ValueError(f"Unsupported desktop path: {relative}")
    return paths


def merge_profile(existing, profile):
    result = deepcopy(existing)
    for key, value in profile.items():
        if isinstance(value, dict):
            old = result.get(key, {})
            result[key] = merge_profile(old if isinstance(old, dict) else {}, value)
        else:
            result[key] = deepcopy(value)
    return result


def capture_profile(existing, template, prefix=""):
    """Capture only the preference keys already present in the shared profile."""
    result = {}
    for key, value in template.items():
        name = prefix + key
        if key not in existing:
            raise ValueError(f"Missing preference: {name}")
        current = existing[key]
        if isinstance(value, dict):
            if not isinstance(current, dict):
                raise ValueError(f"Expected preference object: {name}")
            result[key] = capture_profile(current, value, name + ".")
        else:
            if type(current) is not type(value):
                raise ValueError(f"Preference type changed: {name}")
            result[key] = deepcopy(current)
    return result


def json_bytes(data):
    return (json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode()


def plan_changes(repo, home, command):
    changes = []
    destination_root = repo if command == "capture" else home
    for relative in managed_files(repo):
        source = checked_path(home, relative) if command == "capture" else checked_path(repo / "dots", relative)
        target_relative = "dots/" + relative if command == "capture" else relative
        target = checked_path(destination_root, target_relative)
        data = source.read_bytes()  # Preflight every source before writing anything.
        if not target.exists() or target.read_bytes() != data:
            changes.append(Change(target_relative, data, stat.S_IMODE(source.stat().st_mode)))

    profile_path = checked_path(repo, "config/scrolling-profile.json")
    settings_path = checked_path(home, ".config/illogical-impulse/config.json")
    profile = read_object(profile_path)
    settings = read_object(settings_path, missing=command != "capture")
    if command == "capture":
        selected = capture_profile(settings, profile)
        if selected != profile:
            changes.append(Change("config/scrolling-profile.json", json_bytes(selected), 0o644))
    else:
        merged = merge_profile(settings, profile)
        if merged != settings:
            changes.append(Change(".config/illogical-impulse/config.json", json_bytes(merged), 0o600))
    return destination_root, changes


def atomic_write(path, data, mode):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix="." + path.name + ".", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def apply_changes(destination, home, changes, command):
    if not changes:
        return
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:8]
    backup = checked_path(home, f".local/state/dots-hyprland/backups/{stamp}-{command}")
    backup.mkdir(parents=True, mode=0o700)
    records = []
    for change in changes:
        target = checked_path(destination, change.relative)
        existed = target.exists()
        records.append({"path": change.relative, "existed": existed})
        if existed:
            saved = checked_path(backup, change.relative)
            saved.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(target, saved)
    atomic_write(backup / "manifest.json", json_bytes({"destination": str(destination), "files": records}), 0o600)
    for change in changes:
        atomic_write(checked_path(destination, change.relative), change.data, change.mode)
    print(f"Backup: {backup}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["status", "capture", "deploy"])
    parser.add_argument("--dry-run", action="store_true", help="Show changes without writing files")
    parser.add_argument("--home", type=Path, default=Path.home(), help="Desktop home directory")
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1], help="Fork checkout")
    args = parser.parse_args()
    try:
        destination, changes = plan_changes(args.repo.resolve(), args.home.resolve(), args.command)
        for change in changes:
            print(f"Different: {change.relative}")
        print(f"{len(changes)} file(s) differ")
        if args.command == "status":
            return int(bool(changes))
        if not args.dry_run:
            apply_changes(destination, args.home.resolve(), changes, args.command)
    except (OSError, ValueError) as error:
        parser.exit(2, f"desktop-config: {error}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
