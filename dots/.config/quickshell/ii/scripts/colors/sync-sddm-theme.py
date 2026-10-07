#!/usr/bin/env python3
"""Publish only wallpaper, fonts and appearance settings for the SDDM greeter."""
import argparse
import colorsys
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

DEFAULT_OUTPUT = Path('/var/lib/illogical-impulse/sddm')
COLORS = ('surface', 'surface_container', 'surface_container_low', 'on_background',
          'on_surface', 'on_surface_variant', 'primary', 'on_primary',
          'secondary_container', 'on_secondary_container', 'outline', 'error')


def atomic_write(path, data):
    fd, temporary = tempfile.mkstemp(prefix='.' + path.name, dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
        os.chmod(temporary, 0o644)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def publish(source, target):
    source = source.resolve(strict=True)
    if not target.exists() or source.stat().st_size != target.stat().st_size or source.stat().st_mtime_ns != target.stat().st_mtime_ns:
        atomic_write(target, source.read_bytes())
        shutil.copystat(source, target)
        target.chmod(0o644)
    return target.resolve().as_uri()


def ini_value(value):
    if isinstance(value, bool):
        return str(value).lower()
    if isinstance(value, (int, float)):
        if not math.isfinite(value):
            raise ValueError('Non-finite appearance setting')
        return str(value)
    if any(c in str(value) for c in '\n\r\0'):
        raise ValueError('Multiline appearance setting')
    return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"') + '"'


def sync(output, home):
    settings = json.loads((home / '.config/illogical-impulse/config.json').read_text())
    colors = json.loads((home / '.local/state/quickshell/user/generated/colors.json').read_text())
    appearance = settings.get('appearance', {})
    fonts = appearance.get('fonts', {})
    background = settings.get('background', {})
    clock = background.get('widgets', {}).get('clock', {}).get('digital', {})
    lock = settings.get('lock', {})
    blur = lock.get('blur', {})
    output.mkdir(parents=True, exist_ok=True, mode=0o755)
    output.chmod(0o755)
    fontdir = output / 'fonts'
    fontdir.mkdir(exist_ok=True, mode=0o755)
    fontdir.chmod(0o755)
    values = {key: colors[key] for key in COLORS}
    batteries = [p for p in Path('/sys/class/power_supply').glob('*')
                 if (p / 'type').read_text().strip() == 'Battery' and (p / 'capacity').is_file()]
    if batteries:
        values['batteryCapacityFile'] = (batteries[0] / 'capacity').as_uri()
        values['batteryStatusFile'] = (batteries[0] / 'status').as_uri()
    wallpaper = Path(background.get('wallpaperPath', '')).expanduser()
    if wallpaper.suffix.lower() in {'.mp4', '.mkv', '.webm', '.avi', '.mov'}:
        wallpaper = Path(background.get('thumbnailPath', '')).expanduser()
    if wallpaper.is_file():
        values['background'] = publish(wallpaper, output / ('wallpaper' + wallpaper.suffix.lower()))
    else:
        values['background'] = ''
    clockfont = clock.get('font', {})
    for key, family in {'main': fonts.get('main', 'Noto Sans'),
                        'clock': clockfont.get('family', 'Noto Sans'),
                        'date': fonts.get('expressive', 'Space Grotesk'),
                        'icon': 'Material Symbols Rounded'}.items():
        source = Path(subprocess.check_output(['fc-match', '-f', '%{file}', family], text=True))
        values[key + 'FontFile'] = publish(source, fontdir / (key + source.suffix))
        values[key + 'Font'] = family
    transparency = appearance.get('transparency', {})
    bg_transparency = float(transparency.get('backgroundTransparency', 0.11))
    if transparency.get('automatic', True) and wallpaper.is_file():
        # Match Appearance.qml's adaptive opacity, using the wallpaper's mean colour.
        from PIL import Image
        with Image.open(wallpaper) as image:
            rgb = image.convert('RGB').resize((1, 1)).getpixel((0, 0))
        _, lightness, saturation = colorsys.rgb_to_hls(*(v / 255 for v in rgb))
        vibrancy = (lightness + saturation) / 2
        bg_transparency = max(0, min(0.22, 0.5768 * vibrancy ** 2 - 0.759 * vibrancy + 0.2896))
        surface = colors['surface'].lstrip('#')
        is_dark = sum(int(surface[i:i + 2], 16) for i in (0, 2, 4)) < 384
        if not is_dark:
            bg_transparency -= 0.12
    values.update({
        'clockSize': clockfont.get('size', 91), 'clockWeight': clockfont.get('weight', 350),
        'clockWidth': clockfont.get('width', 100), 'clockRoundness': clockfont.get('roundness', 0),
        'clockVertical': clock.get('vertical', False), 'showDate': clock.get('showDate', True),
        'showLockedText': lock.get('showLockedText', True),
        'timeFormat': settings.get('time', {}).get('format', 'hh:mm'),
        'dateFormat': settings.get('time', {}).get('dateFormat', 'dddd, d MMMM yyyy'),
        'blurEnabled': blur.get('enable', True), 'blurRadius': blur.get('radius', 100),
        'wallpaperZoom': background.get('parallax', {}).get('workspaceZoom', 1.07),
        'blurZoom': blur.get('extraZoom', 1.1),
        'materialShapeChars': lock.get('materialShapeChars', True),
        'contentOpacity': 1 - (0.9 if transparency.get('automatic', True) else transparency.get('contentTransparency', 0.9)),
        'backgroundOpacity': 1 - bg_transparency if transparency.get('enable', False) else 1,
        'extraBackgroundTint': appearance.get('extraBackgroundTint', False),
    })
    atomic_write(output / 'theme.conf', ('[General]\n' + ''.join(f'{key}={ini_value(value)}\n' for key, value in values.items())).encode())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument('--home', type=Path, default=Path.home())
    parser.add_argument('--if-installed', action='store_true')
    args = parser.parse_args()
    if args.if_installed and not args.output.is_dir():
        return
    sync(args.output, args.home)
    print('SDDM appearance assets synchronized.')


if __name__ == '__main__':
    main()
