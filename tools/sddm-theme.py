#!/usr/bin/env python3
"""Build, install or roll back the SDDM theme without restarting the display manager."""
import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import pwd
import shutil
import subprocess
import sys
import tempfile

REPO = Path(__file__).resolve().parents[1]
SOURCE = REPO / 'dots/.local/share/sddm/themes/ii-lock'
SYNC = Path('.config/quickshell/ii/scripts/colors/sync-sddm-theme.py')
THEME = Path('/usr/share/sddm/themes/ii-lock')
ASSETS = Path('/var/lib/illogical-impulse/sddm')
OVERRIDE = Path('/etc/sddm.conf.d/zz-ii-lock.conf')
BACKUPS = Path('/var/lib/illogical-impulse/sddm-backups')


def build(output):
    output = output.resolve()
    if output.exists():
        raise ValueError('Build destination must be new: ' + str(output))
    output.mkdir(parents=True)
    shutil.copytree(SOURCE, output / 'theme')
    paths = subprocess.check_output(['node', str(REPO / 'tools/export-sddm-shapes.cjs')])
    (output / 'theme/PasswordShapePaths.js').write_bytes(paths)
    shutil.copy2(REPO / 'dots/.config/quickshell/ii/modules/common/widgets/shapes/LICENSE', output / 'theme/LICENSE-shapes')
    shutil.copy2(REPO / 'LICENSE', output / 'theme/LICENSE')
    subprocess.run([sys.executable, str(REPO / 'dots' / SYNC), '--output', str(output / 'assets')], check=True)
    (output / 'theme/theme.conf.user').symlink_to('../assets/theme.conf')
    manifest = {p.relative_to(output / 'theme').as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in (output / 'theme').rglob('*') if p.is_file() and not p.is_symlink()}
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(output)


def install(bundle, username):
    if os.getuid() != 0:
        raise ValueError('Installation requires root; run this command with pkexec.')
    user = pwd.getpwnam(username)
    if user.pw_uid < 1000:
        raise ValueError('Asset owner must be a desktop user.')
    manifest = json.loads((bundle / 'manifest.json').read_text())
    for relative, expected in manifest.items():
        path = bundle / 'theme' / relative
        if Path(relative).is_absolute() or '..' in Path(relative).parts or path.is_symlink():
            raise ValueError('Invalid theme file: ' + relative)
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError('Theme changed after validation: ' + relative)
    required = {'Main.qml', 'Style.qml', 'PasswordShapes.qml', 'PasswordShapePaths.js', 'metadata.desktop', 'theme.conf', 'fontconfig.conf'}
    if not required.issubset(manifest):
        raise ValueError('Incomplete theme bundle.')
    backup = BACKUPS / datetime.now().strftime('%Y%m%d-%H%M%S')
    backup.mkdir(parents=True, mode=0o700)
    if OVERRIDE.exists():
        shutil.copy2(OVERRIDE, backup / 'override.conf')
    if THEME.exists():
        shutil.copytree(THEME, backup / 'theme', symlinks=True)
    (backup / 'record.json').write_text(json.dumps({'override_existed': OVERRIDE.exists(), 'theme_existed': THEME.exists()}, indent=2) + '\n')
    THEME.parent.mkdir(parents=True, exist_ok=True)
    # Stage beside the live theme: a selected theme must stay intact until the
    # replacement has passed validation. The fresh root-owned directory also
    # keeps the privileged copy from following any pre-existing symlink.
    staged = Path(tempfile.mkdtemp(prefix='.ii-lock-', dir=THEME.parent))
    try:
        staged.chmod(0o755)
        for relative in manifest:
            target = staged / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((bundle / 'theme' / relative).read_bytes())
            target.chmod(0o644)
            os.chown(target, 0, 0)
        ASSETS.mkdir(parents=True, exist_ok=True, mode=0o755)
        os.chown(ASSETS, user.pw_uid, user.pw_gid)
        subprocess.run(['runuser', '-u', username, '--', sys.executable, str(Path(user.pw_dir) / SYNC), '--output', str(ASSETS)], check=True)
        (staged / 'theme.conf.user').symlink_to(ASSETS / 'theme.conf')
        # Validate under the actual greeter account before selecting the new theme.
        # The checker uses a mock backend, so it cannot log in or power off.
        with tempfile.TemporaryDirectory(prefix='ii-sddm-validate-') as directory:
            Path(directory).chmod(0o755)
            checker = Path(directory) / 'check.py'
            shutil.copyfile(REPO / 'tools/check-sddm-theme.py', checker)
            checker.chmod(0o644)
            subprocess.run(['runuser', '-u', 'sddm', '--', sys.executable, str(checker), str(staged)], check=True)
        previous = staged.with_name(staged.name + '-previous')
        if THEME.exists():
            THEME.rename(previous)
        try:
            staged.rename(THEME)
        except BaseException:
            if previous.exists():
                previous.rename(THEME)
            raise
        shutil.rmtree(previous, ignore_errors=True)
    except BaseException:
        shutil.rmtree(staged, ignore_errors=True)
        raise
    OVERRIDE.parent.mkdir(parents=True, exist_ok=True)
    temporary = OVERRIDE.with_suffix('.tmp')
    temporary.write_text('[General]\nGreeterEnvironment=QML_XHR_ALLOW_FILE_READ=1,'
                         f'FONTCONFIG_FILE={THEME / "fontconfig.conf"}\n\n[Theme]\nCurrent=ii-lock\n')
    temporary.chmod(0o644)
    temporary.replace(OVERRIDE)
    print('Installed. The next greeter uses ii-lock; the active session was not restarted.')
    print('Rollback backup: ' + str(backup))


def rollback(backup):
    if os.getuid() != 0:
        raise ValueError('Rollback requires root.')
    backup = backup.resolve(strict=True)
    if backup.parent != BACKUPS:
        raise ValueError('Not an SDDM theme backup.')
    record = json.loads((backup / 'record.json').read_text())
    if record['override_existed']:
        shutil.copy2(backup / 'override.conf', OVERRIDE)
    else:
        OVERRIDE.unlink(missing_ok=True)
    if record['theme_existed']:
        for source in (backup / 'theme').rglob('*'):
            target = THEME / source.relative_to(backup / 'theme')
            if target.is_symlink():
                target.unlink()
        shutil.copytree(backup / 'theme', THEME, symlinks=True, dirs_exist_ok=True)
    print('Previous theme selection restored. The active session was not restarted.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('build'); p.add_argument('--output', type=Path, required=True)
    p = sub.add_parser('install'); p.add_argument('--bundle', type=Path, required=True); p.add_argument('--user', required=True)
    p = sub.add_parser('rollback'); p.add_argument('--backup', type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == 'build': build(args.output)
        elif args.command == 'install': install(args.bundle.resolve(), args.user)
        else: rollback(args.backup)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, str(error) + '\n')


if __name__ == '__main__':
    main()
