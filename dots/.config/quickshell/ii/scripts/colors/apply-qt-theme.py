#!/usr/bin/env python3
"""Apply Matugen colors to Qt and KDE applications without a Plasma session."""

import configparser
import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


def read_ini(path=None):
    data = configparser.ConfigParser(interpolation=None, strict=False)
    data.optionxform = str
    if path is not None:
        data.read(path)
    return data


def ini_text(data):
    stream = io.StringIO()
    data.write(stream, space_around_delimiters=False)
    return stream.getvalue()


def write_file(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix="." + path.name, dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(text)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def palette_roles(colors):
    # QPalette::ColorRole order, including NoRole and Qt 6.6's Accent.
    names = ["on_surface", "surface_container_high", "surface_bright",
             "surface_container_highest", "surface_container_lowest", "outline_variant",
             "on_surface", "on_surface", "on_surface", "surface_container_lowest",
             "surface", "shadow", "primary", "on_primary", "primary", "tertiary",
             "surface_container_low", "on_surface", "inverse_surface", "inverse_on_surface",
             "on_surface_variant", "primary"]
    for name in set(names) | {"error", "surface_container"}:
        if not re.fullmatch(r"#[0-9a-fA-F]{6}", colors.get(name, "")):
            raise ValueError(f"Invalid or missing Matugen color: {name}")
    active = [colors[name] for name in names]
    disabled = active.copy()
    for role in (0, 6, 8, 13, 19, 20):
        disabled[role] = colors["outline_variant"]
    return {"active_colors": active, "inactive_colors": active, "disabled_colors": disabled}


def render_kvantum(config_home, colors):
    # Render from the already selected palette: no second image analysis, hooks,
    # or changes to GTK. Keep this inside the existing Qt-theming opt-in path.
    with tempfile.TemporaryDirectory(prefix="qt-material-colors-") as temporary:
        staging = Path(temporary)
        render_data = staging / "colors.json"
        render_data.write_text(json.dumps({"colors": {
            name: {"default": {"hex": value}} for name, value in colors.items()
        }}))
        configuration = ["[config]", "version_check = false"]
        for extension in ("kvconfig", "svg"):
            source = config_home / "matugen/templates/qt" / f"MaterialAdw.{extension}"
            output = staging / f"MaterialAdw.{extension}"
            configuration.extend([f"[templates.{extension}]",
                                  f"input_path = {json.dumps(str(source))}",
                                  f"output_path = {json.dumps(str(output))}"])
        config_path = staging / "matugen.toml"
        config_path.write_text("\n".join(configuration) + "\n")
        subprocess.run(["matugen", "--config", str(config_path), "json", str(render_data)], check=True)
        return {extension: (staging / f"MaterialAdw.{extension}").read_text()
                for extension in ("kvconfig", "svg")}


def apply_theme(config_home, state_home, data_home):
    colors = json.loads((state_home / "quickshell/user/generated/colors.json").read_text())
    roles = palette_roles(colors)  # Validate everything before touching configuration.
    kvantum_files = render_kvantum(config_home, colors)
    qt_path = config_home / "qt6ct/qt6ct.conf"
    palette_path = config_home / "qt6ct/colors/illogical-impulse.conf"
    qt = read_ini(qt_path)
    kde = read_ini(config_home / "kdeglobals")
    for section in ("Appearance", "Fonts"):
        if not qt.has_section(section):
            qt.add_section(section)
    appearance = qt["Appearance"]
    # MaterialAdw is rendered by Matugen; preserve fonts and custom icon themes.
    appearance["style"] = "kvantum"
    brightness = sum(weight * int(colors["surface"][offset:offset + 2], 16)
                     for weight, offset in ((0.2126, 1), (0.7152, 3), (0.0722, 5)))
    palette_icons = "breeze-plus-dark" if brightness < 128 else "breeze-plus"
    appearance.setdefault("icon_theme", kde.get("Icons", "Theme", fallback=palette_icons))
    if appearance["icon_theme"] in ("breeze-plus", "breeze-plus-dark"):
        appearance["icon_theme"] = palette_icons
    appearance["custom_palette"] = "true"
    appearance["color_scheme_path"] = str(palette_path)
    for target, source, fallback in (("general", "font", "Noto Sans,11"),
                                     ("fixed", "fixed", "monospace,11")):
        qt["Fonts"].setdefault(target, json.dumps(kde.get("General", source, fallback=fallback).strip('"')))
    palette = read_ini()
    palette["ColorScheme"] = {key: ", ".join("#ff" + value[1:] for value in values)
                              for key, values in roles.items()}

    # KDE applications may read KColorScheme directly instead of QApplication's palette.
    # Keep those application colors in sync without plasma-apply-colorscheme.
    scheme = read_ini()
    scheme["General"] = {"Name": "Illogical Impulse"}
    for group, background, foreground in (
        ("View", "surface_container_lowest", "on_surface"),
        ("Window", "surface", "on_surface"),
        ("Button", "surface_container_high", "on_surface"),
        ("Selection", "primary", "on_primary"),
        ("Tooltip", "inverse_surface", "inverse_on_surface"),
        ("Header", "surface_container", "on_surface"),
        ("Complementary", "surface_container", "on_surface"),
    ):
        section = "Colors:" + group
        values = dict(kde[section]) if kde.has_section(section) else {}
        values.update({"BackgroundNormal": colors[background], "BackgroundAlternate": colors[background],
                       "ForegroundNormal": colors[foreground], "ForegroundInactive": colors["on_surface_variant"],
                       "ForegroundActive": colors["primary"], "ForegroundLink": colors["primary"],
                       "ForegroundVisited": colors["tertiary"], "ForegroundNegative": colors["error"],
                       "DecorationFocus": colors["primary"], "DecorationHover": colors["primary"]})
        scheme[section] = values
        kde[section] = values
    scheme_text = ini_text(scheme)
    if not kde.has_section("General"):
        kde.add_section("General")
    kde["General"]["ColorScheme"] = "IllogicalImpulse"
    kde["General"]["ColorSchemeHash"] = hashlib.sha1(scheme_text.encode()).hexdigest()
    if not kde.has_section("KDE"):
        kde.add_section("KDE")
    kde["KDE"]["widgetStyle"] = "kvantum"
    if not kde.has_section("Icons"):
        kde.add_section("Icons")
    kde["Icons"]["Theme"] = appearance["icon_theme"]
    for extension, text in kvantum_files.items():
        write_file(config_home / "Kvantum/MaterialAdw" / f"MaterialAdw.{extension}", text)
    write_file(palette_path, ini_text(palette))
    write_file(data_home / "color-schemes/IllogicalImpulse.colors", scheme_text)
    write_file(config_home / "kdeglobals", ini_text(kde))
    # Updating qt6ct.conf also tells running Qt applications to reload their palette.
    write_file(qt_path, ini_text(qt))


if __name__ == "__main__":
    home = Path.home()
    apply_theme(Path(os.environ.get("XDG_CONFIG_HOME", home / ".config")),
                Path(os.environ.get("XDG_STATE_HOME", home / ".local/state")),
                Path(os.environ.get("XDG_DATA_HOME", home / ".local/share")))
