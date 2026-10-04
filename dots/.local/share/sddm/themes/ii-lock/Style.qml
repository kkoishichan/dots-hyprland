// Adapted from end-4/illogical-impulse Appearance.qml (GPL-3.0).
import QtQuick

QtObject {
    property color surface: config.surface
    property color toolbar: config.surface_container
    property color text: config.on_surface_variant
    property color clockText: config.on_background
    property color primary: config.primary
    property color onPrimary: config.on_primary
    property color secondary: config.secondary_container
    property color onSecondary: config.on_secondary_container
    property color muted: config.outline
    property color error: config.error
    property color tintedBase: config.boolValue("extraBackgroundTint") ? mix(surface, primary, 0.99) : surface
    property color field: overlay(tintedBase, config.surface_container_low, config.realValue("contentOpacity"))
    property color scrim: Qt.rgba(tintedBase.r, tintedBase.g, tintedBase.b, config.realValue("backgroundOpacity") * 0.3)
    property string font: mainFontLoader.name || config.mainFont
    property string clockFont: clockFontLoader.name || config.clockFont
    property string dateFont: dateFontLoader.name || config.dateFont
    property string iconFont: iconFontLoader.name || "Material Symbols Rounded"
    property FontLoader mainFontLoader: FontLoader { source: config.mainFontFile }
    property FontLoader clockFontLoader: FontLoader { source: config.clockFontFile }
    property FontLoader dateFontLoader: FontLoader { source: config.dateFontFile }
    property FontLoader iconFontLoader: FontLoader { source: config.iconFontFile }

    function mix(a, b, amount) {
        return Qt.rgba(a.r * amount + b.r * (1 - amount), a.g * amount + b.g * (1 - amount), a.b * amount + b.b * (1 - amount), 1);
    }
    function overlay(base, target, opacity) {
        const c = Qt.color(target);
        const a = Math.max(0.01, opacity);
        return Qt.rgba(Math.max(0, Math.min(1, (c.r - base.r * (1 - a)) / a)),
                       Math.max(0, Math.min(1, (c.g - base.g * (1 - a)) / a)),
                       Math.max(0, Math.min(1, (c.b - base.b * (1 - a)) / a)), a);
    }
}
