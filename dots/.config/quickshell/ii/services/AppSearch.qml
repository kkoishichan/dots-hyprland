pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Io

/**
 * - Eases fuzzy searching for applications by name
 * - Guesses icon name for window class name
 */
Singleton {
    id: root
    property bool sloppySearch: Config.options?.search.sloppy ?? false
    property real scoreThreshold: 0.2
    property var substitutions: ({
        "code-url-handler": "visual-studio-code",
        "Code": "visual-studio-code",
        "gnome-tweaks": "org.gnome.tweaks",
        "pavucontrol-qt": "pavucontrol",
        "wps": "wps-office2019-kprometheus",
        "wpsoffice": "wps-office2019-kprometheus",
        "footclient": "foot",
    })
    property var regexSubstitutions: [
        {
            "regex": /^steam_app_(\d+)$/,
            "replace": "steam_icon_$1"
        },
        {
            "regex": /Minecraft.*/,
            "replace": "minecraft"
        },
        {
            "regex": /.*polkit.*/,
            "replace": "system-lock-screen"
        },
        {
            "regex": /gcr.prompter/,
            "replace": "system-lock-screen"
        }
    ]

    // DesktopEntries reloads its model one entry at a time. Rebuilding the
    // search index in a values binding stalls the shell during those bursts.
    property var applicationIndex: ({ entries: [], apps: [], icons: [] })
    readonly property list<DesktopEntry> list: applicationIndex.entries
    readonly property var preppedApps: applicationIndex.apps
    readonly property var preppedIcons: applicationIndex.icons
    property var desktopEntryAliases: ({})

    function rebuildApplications() {
        const seen = new Set();
        const entries = Array.from(DesktopEntries.applications.values).filter(app => {
            if (!app || seen.has(app.id)) return false;
            seen.add(app.id);
            return true;
        });
        const apps = entries.map(entry => ({
            searchText: Fuzzy.prepare(`${appSearchText(entry)} `),
            entry: entry
        }));
        const icons = entries.map(entry => ({
            name: Fuzzy.prepare(`${entry.icon} `),
            entry: entry
        }));
        root.applicationIndex = { entries: entries, apps: apps, icons: icons };
    }

    Timer {
        id: applicationRefresh
        interval: 100
        onTriggered: root.rebuildApplications()
    }

    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { applicationRefresh.restart(); }
    }

    Connections {
        target: DesktopEntries
        function onApplicationsChanged() { applicationRefresh.restart(); }
    }

    // Existing entries can change without changing the application model.
    Instantiator {
        model: DesktopEntries.applications
        delegate: QtObject {
            required property DesktopEntry modelData
            readonly property string searchText: modelData ? root.appSearchText(modelData) : ""
            onSearchTextChanged: applicationRefresh.restart()
        }
    }

    onDesktopEntryAliasesChanged: applicationRefresh.restart()

    Component.onCompleted: {
        applicationRefresh.restart();
        desktopEntryAliasProc.running = true;
    }

    Process {
        id: desktopEntryAliasProc
        command: ["python3", "-c", `
import json
import os

data_home = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
data_dirs = os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
roots = [data_home] + [d for d in data_dirs.split(":") if d]
result = {}

def parse_desktop_file(path):
    fields = []
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            for raw_line in handle:
                line = raw_line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                if key in ("Name", "GenericName", "Keywords", "Comment"):
                    fields.append(value.replace(";", " "))
    except OSError:
        return ""
    return " ".join(fields)

for root in roots:
    app_dir = os.path.join(root, "applications")
    if not os.path.isdir(app_dir):
        continue
    for dirpath, _, filenames in os.walk(app_dir):
        for filename in filenames:
            if not filename.endswith(".desktop"):
                continue
            path = os.path.join(dirpath, filename)
            text = parse_desktop_file(path)
            if not text:
                continue
            rel_id = os.path.relpath(path, app_dir).replace(os.sep, "-")
            for entry_id in (rel_id, filename, rel_id.removesuffix(".desktop"), filename.removesuffix(".desktop")):
                result.setdefault(entry_id, text)

print(json.dumps(result, ensure_ascii=False))
`]
        stdout: SplitParser {
            onRead: data => {
                try {
                    root.desktopEntryAliases = JSON.parse(data);
                } catch (error) {
                    console.warn("[AppSearch] Failed to parse desktop entry aliases:", error);
                }
            }
        }
    }

    function normalizedSearchText(value): string {
        const text = `${value || ""}`;
        return `${text} ${text.toLowerCase().replace(/[^a-z0-9]+/g, " ")}`;
    }

    function listSearchText(value): string {
        if (!value)
            return "";
        if (value.join)
            return value.join(" ");
        return `${value}`;
    }

    function appSearchText(app): string {
        const command = listSearchText(app.command);
        const keywords = listSearchText(app.keywords);
        const categories = listSearchText(app.categories);
        const actionNames = app.actions ? app.actions.map(action => action.name).join(" ") : "";
        const appIdWithoutSuffix = `${app.id || ""}`.replace(/\.desktop$/, "");
        const desktopAliases = root.desktopEntryAliases[app.id] || root.desktopEntryAliases[appIdWithoutSuffix] || "";

        return [
            app.name,
            desktopAliases,
            app.genericName,
            app.comment,
            keywords,
            categories,
            app.icon,
            command,
            actionNames,
            app.id,
            appIdWithoutSuffix,
            normalizedSearchText(app.id),
            normalizedSearchText(appIdWithoutSuffix),
            normalizedSearchText(app.icon),
            normalizedSearchText(command),
        ].filter(text => `${text || ""}`.length > 0).join(" ");
    }

    function fuzzyQuery(search: string): var { // Idk why list<DesktopEntry> doesn't work
        if (root.sloppySearch) {
            const results = list.filter(entry => entry).map(obj => ({
                entry: obj,
                score: Levendist.computeScore(appSearchText(obj).toLowerCase(), search.toLowerCase())
            })).filter(item => item.score > root.scoreThreshold)
                .sort((a, b) => b.score - a.score)
            return results
                .map(item => item.entry)
        }

        return Fuzzy.go(search, preppedApps, {
            all: true,
            key: "searchText"
        }).map(r => {
            return r.obj.entry
        }).filter(entry => entry);
    }

    function iconExists(iconName) {
        if (!iconName || iconName.length == 0) return false;
        return (Quickshell.iconPath(iconName, true).length > 0) 
            && !iconName.includes("image-missing");
    }

    function getReverseDomainNameAppName(str) {
        return str.split('.').slice(-1)[0]
    }

    function getKebabNormalizedAppName(str) {
        return str.toLowerCase().replace(/\s+/g, "-");
    }

    function getUndescoreToKebabAppName(str) {
        return str.toLowerCase().replace(/_/g, "-");
    }

    function guessIcon(str) {
        if (!str || str.length == 0) return "image-missing";

        // Quickshell's desktop entry lookup
        const entry = DesktopEntries.byId(str);
        if (entry) return entry.icon;

        // Normal substitutions
        if (substitutions[str]) return substitutions[str];
        if (substitutions[str.toLowerCase()]) return substitutions[str.toLowerCase()];

        // Regex substitutions
        for (let i = 0; i < regexSubstitutions.length; i++) {
            const substitution = regexSubstitutions[i];
            const replacedName = str.replace(
                substitution.regex,
                substitution.replace,
            );
            if (replacedName != str) return replacedName;
        }

        // Icon exists -> return as is
        if (iconExists(str)) return str;


        // Simple guesses
        const lowercased = str.toLowerCase();
        if (iconExists(lowercased)) return lowercased;

        const reverseDomainNameAppName = getReverseDomainNameAppName(str);
        if (iconExists(reverseDomainNameAppName)) return reverseDomainNameAppName;

        const lowercasedDomainNameAppName = reverseDomainNameAppName.toLowerCase();
        if (iconExists(lowercasedDomainNameAppName)) return lowercasedDomainNameAppName;

        const kebabNormalizedGuess = getKebabNormalizedAppName(str);
        if (iconExists(kebabNormalizedGuess)) return kebabNormalizedGuess;

        const undescoreToKebabGuess = getUndescoreToKebabAppName(str);
        if (iconExists(undescoreToKebabGuess)) return undescoreToKebabGuess;

        // Search in desktop entries
        const iconSearchResults = Fuzzy.go(str, preppedIcons, {
            all: true,
            key: "name"
        }).map(r => {
            return r.obj.entry
        }).filter(entry => entry);
        if (iconSearchResults.length > 0) {
            const guess = iconSearchResults[0].icon
            if (iconExists(guess)) return guess;
        }

        const nameSearchResults = root.fuzzyQuery(str);
        if (nameSearchResults.length > 0) {
            const guess = nameSearchResults[0].icon
            if (iconExists(guess)) return guess;
        }

        // Quickshell's desktop entry lookup
        const heuristicEntry = DesktopEntries.heuristicLookup(str);
        if (heuristicEntry) return heuristicEntry.icon;

        // Give up
        return "application-x-executable";
    }
}
