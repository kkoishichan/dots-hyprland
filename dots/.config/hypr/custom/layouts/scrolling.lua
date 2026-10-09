-- Native horizontal scrolling. Quickshell supplies the dynamic vertical workspace sequence.
hl.config({
    general = {
        layout = "scrolling",
        border_size = 0,
        gaps_in = 2,
        -- Horizontal outer gaps must match the column geometry.
        gaps_out = { top = 4, right = 2, bottom = 4, left = 2 },
    },
    scrolling = {
        direction = "right",
        column_width = 0.5,
        fullscreen_on_one_column = false,
        focus_fit_method = 1,
        follow_focus = true,
        -- Hovering partial columns must not pan; explicit focus still follows.
        follow_min_visible = 1.0,
        -- Three rounded 0.333 columns leave a visible sliver of the next column.
        explicit_column_widths = "0.3333333, 0.5, 0.6666667, 1.0",
        wrap_focus = false,
        wrap_swapcol = false
    }
})

local overview_drop = require("custom.overview_drop")
overview_drop.configure_workspace_animation({ leaf = "workspaces", enabled = true, speed = 7, bezier = "menu_decel", style = "slidevert" })
overview_drop.configure_workspace_animation({ leaf = "specialWorkspaceIn", enabled = true, speed = 2.8, bezier = "emphasizedDecel", style = "slidevert" })
overview_drop.configure_workspace_animation({ leaf = "specialWorkspaceOut", enabled = true, speed = 1.2, bezier = "emphasizedAccel", style = "slidevert" })
overview_drop.watch_overview()

-- Remove the old drag and numbered-workspace gestures before adding scrolling gestures.
hl.gesture({ fingers = 3, direction = "swipe", action = "unset" })
hl.gesture({ fingers = 4, direction = "horizontal", action = "unset" })
hl.gesture({ fingers = 4, direction = "up", action = "unset" })
hl.gesture({ fingers = 4, direction = "down", action = "unset" })
-- Three-finger horizontal scrolling follows the fingers; a slow release settles at the
-- nearest centered or edge stop in view, and a flick pages by edges (custom/column_swipe.lua).
local column_swipe = require("custom.column_swipe")
hl.gesture({ fingers = 3, direction = "horizontal", action = {
    start = column_swipe.start, update = column_swipe.update, finish = column_swipe.finish,
} })
hl.gesture({ fingers = 3, direction = "up", action = function()
    hl.dispatch(hl.dsp.exec_cmd("qs -c $qsConfig ipc call scrolling step 1"))
end })
hl.gesture({ fingers = 3, direction = "down", action = function()
    hl.dispatch(hl.dsp.exec_cmd("qs -c $qsConfig ipc call scrolling step -1"))
end })
hl.gesture({ fingers = 4, direction = "swipe", action = "move" })
hl.gesture({ fingers = 4, direction = "pinch", action = function()
    hl.dispatch(hl.dsp.global("quickshell:overviewWorkspacesToggle"))
end })
