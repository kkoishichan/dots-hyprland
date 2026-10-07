-- Scrolling layout and dynamic workspaces. Workspace positions are local to the focused monitor.
local function replace(key, dispatcher, description, repeating)
    hl.unbind(key)
    hl.bind(key, dispatcher, { description = description, repeating = repeating or false })
end
local function scrolling(command)
    return hl.dsp.exec_cmd("qs -c $qsConfig ipc call scrolling " .. command)
end

-- Preserve pre-migration shortcuts, including the user's XF86Back/Forward
-- bindings. Coordinated column layouts use the user's chosen SUPER+R; the separately
-- requested numbered-workspace/Tab removals stay.

hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), { description = "Edit user keybinds" })

for i, key in ipairs({ "Left", "Right", "Up", "Down" }) do
    local direction = ({ "l", "r", "u", "d" })[i]
    replace("SUPER + " .. key, hl.dsp.layout("focus " .. direction), "Window: Focus " .. key)
end
replace("SUPER + BracketLeft", hl.dsp.layout("focus l"), "Column: Focus previous")
replace("SUPER + BracketRight", hl.dsp.layout("focus r"), "Column: Focus next")
replace("SUPER + SHIFT + Left", hl.dsp.layout("swapcol l"), "Column: Move left")
replace("SUPER + SHIFT + Right", hl.dsp.layout("swapcol r"), "Column: Move right")
replace("SUPER + ALT + Left", hl.dsp.layout("consume_or_expel prev"), "Column: Merge or split toward left")
replace("SUPER + ALT + Right", hl.dsp.layout("consume_or_expel next"), "Column: Merge or split toward right")
replace("SUPER + Semicolon", hl.dsp.layout("colresize -conf"), "Column: Previous width", true)
replace("SUPER + Apostrophe", hl.dsp.layout("colresize +conf"), "Column: Next width", true)
local column_layout = require("custom.column_layout")
replace("SUPER + R", column_layout.cycle, "Columns: Cycle paired and triple layouts")
replace("SUPER + CTRL + C", hl.dsp.layout("center"), "Column: Center")
replace("SUPER + Space", hl.dsp.global("quickshell:searchToggle"), "Shell: Search")
hl.unbind("SUPER + Tab")

-- Disable inherited numbered-workspace shortcuts on the main row and keypad.
for i = 1, 10 do
    local digit = tostring(i % 10)
    local code = ({ 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 })[i]
    local keypad = ({ 87, 88, 89, 83, 84, 85, 79, 80, 81, 90 })[i]
    for _, key in ipairs({ digit, "code:" .. code, "code:" .. keypad }) do
        hl.unbind("SUPER + " .. key)
        hl.unbind("SUPER + ALT + " .. key)
    end
end

for i, dir in ipairs({ "Up", "Down" }) do
    local delta = i == 1 and -1 or 1
    replace("CTRL + SUPER + " .. dir, scrolling("step " .. delta), "Workspace: Focus " .. dir)
    replace("CTRL + SUPER + SHIFT + " .. dir, scrolling("reorder " .. delta), "Workspace: Move " .. dir)
    replace("SUPER + Page_" .. dir, scrolling("step " .. delta), "Workspace: Focus " .. dir)
    replace("CTRL + SUPER + Page_" .. dir, scrolling("step " .. delta), "Workspace: Focus " .. dir)
    replace("SUPER + SHIFT + Page_" .. dir, scrolling("sendStep " .. delta), "Window: Move to workspace " .. dir)
    replace("SUPER + ALT + Page_" .. dir, scrolling("sendStep " .. delta), "Window: Move to workspace " .. dir)
end
for i, key in ipairs({ "Left", "Right", "Up", "Down" }) do
    local direction = ({ "l", "r", "u", "d" })[i]
    replace("CTRL + SUPER + ALT + " .. key, hl.dsp.focus({ monitor = direction }), "Monitor: Focus " .. key)
    replace("SUPER + ALT + SHIFT + " .. key, hl.dsp.window.move({ monitor = direction, follow = true }), "Window: Move to monitor " .. key)
end
replace("CTRL + SUPER + Insert", scrolling("insert"), "Workspace: Insert above current")

for i, key in ipairs({ "Left", "Right", "BracketLeft", "BracketRight", "XF86Back", "XF86Forward" }) do
    local delta = i % 2 == 1 and -1 or 1
    replace("CTRL + SUPER + " .. key, scrolling("step " .. delta), "Workspace: Focus " .. (delta < 0 and "previous" or "next"))
end
-- These eight browser-key combinations predate the scrolling conversion.
for i, key in ipairs({ "XF86Back", "XF86Forward" }) do
    local delta = i == 1 and -1 or 1
    replace("SUPER + " .. key, scrolling("step " .. delta), "Workspace: Focus " .. (delta < 0 and "previous" or "next"))
    replace("SUPER + SHIFT + " .. key, scrolling("sendStep " .. delta), "Window: Move to adjacent workspace")
    replace("SUPER + ALT + " .. key, scrolling("sendStep " .. delta), "Window: Move to adjacent workspace")
end
for i, key in ipairs({ "Left", "Right" }) do
    local delta = i == 1 and -1 or 1
    replace("CTRL + SUPER + SHIFT + " .. key, scrolling("sendStep " .. delta), "Window: Move to adjacent workspace")
end
for i, key in ipairs({ "mouse_up", "mouse_down" }) do
    local delta = i == 1 and -1 or 1
    replace("SUPER + " .. key, hl.dsp.layout("focus " .. (delta < 0 and "l" or "r")), "Column: Scroll focus")
    replace("CTRL + SUPER + " .. key, scrolling("step " .. delta), "Workspace: Scroll focus")
    replace("SUPER + SHIFT + " .. key, scrolling("sendStep " .. delta), "Window: Move to adjacent workspace")
    replace("SUPER + ALT + " .. key, scrolling("sendStep " .. delta), "Window: Move to adjacent workspace")
end

-- Pause fingerprint authentication before requesting sleep, so fprintd cannot
-- be D-Bus activated while systemd is stopping it for sleep.target.
hl.unbind("SUPER + SHIFT + L")
hl.bind("SUPER + SHIFT + L", hl.dsp.exec_cmd(
    "qs -c $qsConfig ipc call lock prepareForSleep; " ..
    "if ! systemctl suspend && ! loginctl suspend; then " ..
    "qs -c $qsConfig ipc call lock resumeFromSleep; fi"),
    { locked = true, release = true, description = "Session: Sleep" })
