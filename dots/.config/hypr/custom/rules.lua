-- Feishu Meetings uses separate XWayland windows for its meeting UI and
-- sharing controls. Their observed initial title is "Feishu Meetings";
-- WM_CLASS can be "Meeting" or empty. Keep them out of the tiling layout.
-- The chat window (class/title "Feishu") does not match this rule.
hl.window_rule({
    name = "feishu-meetings-float",
    match = { initial_title = "^Feishu Meetings$" },
    float = true,
    no_anim = true,
})

-- The fixed-size ShareScreenFloatingPanelWindowBase has an empty class.
-- Do not let this auxiliary panel take focus when it is first mapped.
hl.window_rule({
    name = "feishu-sharing-panel-focus",
    match = { initial_class = "^$", initial_title = "^Feishu Meetings$" },
    no_initial_focus = true,
})

-- Only Feishu's X11 NOTIFICATION toolbars receive fixed size hints.
-- The helper verifies the executable, title, class, type and natural geometry.
-- It runs briefly on popup creation; there is no persistent background process.
local function lock_feishu_toolbars(window)
    if window and window.initial_title == "Feishu Meetings"
        and (window.initial_class == "Meeting" or window.initial_class == "")
        and window.pid > 0 then
        hl.exec_cmd('/usr/bin/python3 "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/custom/feishu_toolbar_size.py" --pid ' .. tostring(window.pid))
    end
end
hl.on("window.open", lock_feishu_toolbars)

-- Also cover toolbars that are already open when this file is reloaded.
local feishu_pids = {}
for _, window in ipairs(hl.get_windows()) do
    if window.initial_title == "Feishu Meetings" and not feishu_pids[window.pid] then
        feishu_pids[window.pid] = true
        lock_feishu_toolbars(window)
    end
end
