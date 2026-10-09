local drop = dofile("dots/.config/hypr/custom/overview_drop.lua")
local windows, spaces, monitors, current_monitor, current_window, no_warps, calls, failure, focus_denied, blocked
local follow_focus, layer_handlers, layers
local workspace_animation, special_animations, workspace_shifts
local function action(kind)
    return function(value) return { kind = kind, value = value } end
end
local function native_column(w)
    for index, c in ipairs(w.workspace.columns) do
        for _, member in ipairs(c.windows) do
            if member == w then return { index = index - 1, width = c.width, windows = c.windows } end
        end
    end
end
local function remove(w)
    for index, c in ipairs(w.workspace.columns) do
        for i, member in ipairs(c.windows) do
            if member == w then
                table.remove(c.windows, i)
                if #c.windows == 0 then table.remove(w.workspace.columns, index) end
                return
            end
        end
    end
end
local function switch_workspace(monitor, workspace)
    if monitor.active ~= workspace then
        if workspace_animation.enabled and workspace_animation.style ~= "slidevert 0%" then
            workspace_shifts = workspace_shifts + 1
        end
        monitor.active = workspace
    end
end
local function focus(w)
    if w == current_window then return end -- Native focus skips monitor/special-workspace routing here.
    if blocked then return end
    current_window, current_monitor = w, w.monitor
    if w.workspace.special then current_monitor.special = w.workspace
    else current_monitor.special = nil; switch_workspace(current_monitor, w.workspace) end
    if not w.workspace.inhibited and not w.floating then
        w.workspace.camera = (native_column(w) or { index = 0 }).index * 1000
    end
end
hl = {
    dsp = { focus = action("focus"), layout = action("layout"), event = action("event"),
        workspace = { toggle_special = action("special") }, window = { move = action("move") } },
    get_window = function(selector) return windows[selector:gsub("^address:", "")] end,
    get_monitor = function(name) return monitors[name] end,
    get_workspace = function(id) return spaces[id] end,
    get_active_window = function() return current_window end,
    get_active_monitor = function() return current_monitor end,
    get_active_workspace = function(monitor) return (monitor or current_monitor).active end,
    get_active_special_workspace = function(monitor) return (monitor or current_monitor).special end,
    get_workspace_windows = function(ws)
        local result = {}
        for _, w in pairs(windows) do if w.workspace == ws then result[#result + 1] = w end end
        return result
    end,
    get_config = function(key)
        if key == "scrolling:follow_focus" then return follow_focus end
        return no_warps
    end,
    config = function(config)
        if config.cursor then no_warps = config.cursor.no_warps end
        if config.scrolling then follow_focus = config.scrolling.follow_focus end
    end,
    on = function(event, callback)
        layer_handlers[event] = layer_handlers[event] or {}
        table.insert(layer_handlers[event], callback)
    end,
    get_layers = function() return layers end,
    animation = function(config)
        if config.leaf == "workspaces" then workspace_animation = config
        else
            assert(config.leaf == "specialWorkspaceIn" or config.leaf == "specialWorkspaceOut", "placement changed window or layer animations")
            special_animations[config.leaf] = config
        end
    end,
    window_rule = function()
        return { is_enabled = function() return blocked end, set_enabled = function(_, value) blocked = value end }
    end,
    dispatch = function(a)
        if type(a) == "function" then return a() end
        calls[#calls + 1] = a
        if a.kind ~= "event" then assert(no_warps, "drop warped the pointer") end
        if a.kind == "focus" then
            if a.value.window then
                if not focus_denied then focus(a.value.window) end
            elseif a.value.monitor then
                current_monitor = a.value.monitor
                local ws = current_monitor.special or current_monitor.active
                if ws.columns[1] then
                    if not focus_denied then focus(ws.columns[1].windows[1]) end
                elseif not focus_denied then current_window = nil end
            else
                local id = type(a.value.workspace) == "table" and a.value.workspace.id or a.value.workspace
                if not spaces[id] then
                    spaces[id] = { id = id, monitor = current_monitor, columns = {}, tiled_layout = "scrolling", camera = 0 }
                end
                switch_workspace(current_monitor, spaces[id])
                if spaces[id].columns[1] then focus(spaces[id].columns[1].windows[1]) end
            end
        elseif a.kind == "special" then
            local ws = spaces[-98]
            assert(ws and ws.name == "special:" .. a.value)
            local opening = current_monitor.special ~= ws
            current_monitor.special = opening and ws or nil
            local animation = special_animations[opening and "specialWorkspaceIn" or "specialWorkspaceOut"]
            if animation.enabled and animation.style ~= "slidevert 0%" then workspace_shifts = workspace_shifts + 1 end
            local target = opening and ws or current_monitor.active
            if not focus_denied and target.columns[1] then focus(target.columns[1].windows[1]) end
        elseif a.kind == "move" then
            local w, id = a.value.window, a.value.workspace
            remove(w)
            if not spaces[id] then spaces[id] = { id = id, monitor = current_monitor, columns = {}, tiled_layout = "scrolling", camera = 0 } end
            w.workspace, w.monitor = spaces[id], spaces[id].monitor
            if not w.floating then
                table.insert(w.workspace.columns, { width = 0.5, windows = { w } })
            end
            if a.value.follow then focus(w) end
        elseif a.kind == "layout" then
            local effective = current_monitor.special or current_monitor.active
            if a.value:match("^inhibit_scroll") then
                effective.inhibited = a.value:sub(-1) == "1"
                return { ok = true }
            end
            if failure then return { ok = false, error = "test failure" } end
            if not current_window or current_window.workspace ~= effective then return { ok = false, error = "no window" } end
            local ws, c = current_window.workspace, native_column(current_window)
            if a.value == "promote" then
                remove(current_window)
                table.insert(ws.columns, c.index + 2, { width = 0.5, windows = { current_window } })
            elseif a.value:match("^colresize") then
                ws.columns[c.index + 1].width = tonumber(a.value:match(" ([%d.]+)$"))
            else
                local to = c.index + (a.value == "swapcol l" and 0 or 2)
                assert(to >= 1 and to <= #ws.columns, "swap wrapped past an edge")
                ws.columns[c.index + 1], ws.columns[to] = ws.columns[to], ws.columns[c.index + 1]
            end
            if not ws.inhibited then ws.camera = native_column(current_window).index * 1000 end
        end
        return { ok = true }
    end,
}
local function setup()
    windows, calls, no_warps, failure, focus_denied, blocked = {}, {}, false, false, false, false
    follow_focus, layer_handlers, layers = true, {}, {}
    workspace_shifts = 0
    special_animations = {}
    drop.configure_workspace_animation({ leaf = "workspaces", enabled = true, speed = 7,
        bezier = "menu_decel", style = "slidevert" })
    for _, leaf in ipairs({ "specialWorkspaceIn", "specialWorkspaceOut" }) do
        drop.configure_workspace_animation({ leaf = leaf, enabled = true, speed = 2,
            bezier = "default", style = "slidevert" })
    end
    monitors = { laptop = { name = "laptop" }, external = { name = "external" } }
    spaces = { [1] = { id = 1, monitor = monitors.laptop, columns = {}, tiled_layout = "scrolling", camera = 125 },
        [2] = { id = 2, monitor = monitors.external, columns = {}, tiled_layout = "scrolling", camera = 375 },
        [3] = { id = 3, monitor = monitors.external, columns = {}, tiled_layout = "scrolling", camera = 625 },
        [-98] = { id = -98, name = "special:special", special = true, monitor = monitors.laptop,
            columns = {}, tiled_layout = "scrolling", camera = 40 } }
    monitors.laptop.active, monitors.external.active = spaces[1], spaces[3]
    current_monitor, current_window = monitors.laptop, nil
end
local function add(id, address, width, members)
    local ws = spaces[id]
    local w = { address = address, mapped = true, fullscreen = 0, workspace = ws, monitor = ws.monitor }
    setmetatable(w, { __index = function(self, key)
        if key == "layout" then return { name = "scrolling", column = native_column(self) } end
    end })
    windows[address] = w
    if members then table.insert(members.windows, w)
    else table.insert(ws.columns, { width = width or .5, windows = { w } }) end
    return w
end
local function order(id)
    local result = {}
    for _, c in ipairs(spaces[id].columns) do
        local members = {}
        for _, w in ipairs(c.windows) do members[#members + 1] = w.address end
        result[#result + 1] = table.concat(members, "+")
    end
    return table.concat(result, ",")
end
local function place(address, id, anchor, before)
    local monitor, ws, w = current_monitor, current_monitor.active, current_window
    local special = current_monitor.special
    local cameras = {}
    local shifts = workspace_shifts
    local animation = workspace_animation
    for key, space in pairs(spaces) do cameras[key] = space.camera end
    drop.place({ address = address, workspace = id, anchor = anchor, before = before, monitor = "external" })
    assert(not no_warps, "cursor configuration leaked")
    assert(not blocked, "preparation focus rule leaked")
    assert(workspace_shifts == shifts, "placement started a rendered workspace slide")
    assert(workspace_animation == animation, "placement did not restore the configured workspace animation")
    for key, camera in pairs(cameras) do
        assert(not spaces[key].inhibited, "scroll inhibitor leaked")
        assert(spaces[key].camera == camera, "placement panned a desktop camera")
    end
    assert(current_monitor == monitor and monitor.active == ws, "desktop selection changed")
    assert(current_monitor.special == special, "Scratch was not restored")
    if w and w.workspace == ws then assert(current_window == w, "original focus was lost") end
    assert(calls[#calls].kind == "event", "shell did not refresh")
end

-- An exclusive overview can retain a normal window while Scratch is open.
-- Native layout messages still go to Scratch, and refocusing the same window
-- does not correct that routing. Both dragging the focus and another window work.
for _, focused in ipairs({ "a", "b" }) do
    setup()
    add(1, "a", .5); add(1, "b", .5); add(1, "c", .5); add(-98, "scratch", .5)
    focus(windows[focused])
    monitors.laptop.special = spaces[-98]
    place("a", 1, "c", false)
    assert(order(1) == "b,c,a", "Scratch intercepted the normal-workspace insertion")
    assert(special_animations.specialWorkspaceIn.style == "slidevert"
        and special_animations.specialWorkspaceOut.style == "slidevert", "Scratch animation was not restored")
end

-- Restore the native Scratch focus as well as its open state after a drop.
setup()
add(1, "a", .5); add(1, "b", .5); add(-98, "scratch", .5)
focus(windows.scratch)
place("a", 1, "b", false)
assert(current_window == windows.scratch, "Scratch lost its keyboard focus")

-- Every before/after pair must match removing one item and inserting at the anchor.
for from = 1, 5 do
    for anchor = 1, 5 do
        if from ~= anchor then
            for _, before in ipairs({ true, false }) do
                setup()
                for i = 1, 5 do add(1, tostring(i), i / 10) end
                focus(windows["1"])
                local expected = {}
                for i = 1, 5 do
                    if i == anchor and before then expected[#expected + 1] = tostring(from) end
                    if i ~= from then expected[#expected + 1] = tostring(i) end
                    if i == anchor and not before then expected[#expected + 1] = tostring(from) end
                end
                place(tostring(from), 1, tostring(anchor), before)
                assert(order(1) == table.concat(expected, ","), "wrong same-workspace insertion")
                assert(math.abs(native_column(windows[tostring(from)]).width - from / 10) < 1e-8)
            end
        end
    end
end
setup()
local a, b = add(1, "a", .8), add(1, "b", .3)
add(1, "stacked", nil, spaces[1].columns[1])
focus(b)
place("a", 1, "b", false)
assert(order(1) == "stacked,b,a", "drag moved an entire stacked column")
assert(native_column(a).width == .8)

for _, before in ipairs({ true, false }) do
    setup()
    a, b = add(1, "a", .8), add(1, "b", .3)
    add(2, "c", .4); add(2, "d", .6); add(2, "e", .5)
    focus(b)
    place("a", 2, "d", before)
    assert(order(1) == "b")
    assert(order(2) == (before and "c,a,d,e" or "c,d,a,e"), "wrong destination insertion")
    assert(monitors.external.active == spaces[3], "destination output switched workspace")
    assert(native_column(a).width == .8)
end
setup()
a, b = add(1, "a", .8), add(1, "b", .3); focus(b)
a.fullscreen = 1
place("a", 9, "", false)
assert(a.monitor == monitors.external and a.fullscreen == 1, "new workspace/fullscreen movement failed")
assert(monitors.external.active == spaces[3])

setup()
a, b = add(1, "a", .8), add(1, "b", .3); focus(a)
place("a", 2, "", false)
assert(current_window == b and current_window.workspace == current_monitor.active,
    "moving the original focus left keyboard focus on the other workspace")

setup()
a, b = add(1, "a", .8), add(1, "b", .3); focus(b)
place("a", 1, "closed", true)
assert(order(1) == "b,a", "missing anchor did not fall back to append")
failure = true
local ok = pcall(function() place("a", 1, "b", true) end)
assert(not ok and not no_warps and current_window == b, "error cleanup failed")
assert(not blocked and not spaces[1].inhibited, "failed placement left scrolling/focus blocked")
assert(workspace_animation.style == "slidevert", "failed placement left workspace animation overridden")

setup()
a, b = add(1, "a", .8), add(1, "b", .3); focus(b)
windows.closing = { address = "closing", mapped = false, workspace = spaces[1],
    layout = { name = "scrolling", column = { index = 8 } } }
place("a", 1, "closing", false)
assert(order(1) == "b,a", "unmapped closing windows must not supply an append index")

setup()
a, b = add(1, "a", .8), add(1, "b", .3); focus(b)
focus_denied = true
ok = pcall(function() place("a", 1, "b", false) end)
assert(not ok and order(1) == "a,b", "exclusive layer focus silently moved the wrong column")
assert(not no_warps and current_window == b, "refused focus cleanup failed")
assert(not blocked and not spaces[1].inhibited, "refused focus left scrolling/focus blocked")
assert(workspace_animation.style == "slidevert", "refused focus changed workspace animation")

setup()
a, b = add(1, "a", .5), add(1, "b", .5)
add(1, "offscreen", .5); focus(a)
spaces[1].camera = 275 -- The focused column is only partially on screen.
place("offscreen", 1, "b", true)
assert(spaces[1].camera == 275, "restoring a partially visible focus panned the desktop")
assert(order(1) == "a,offscreen,b")
for _, call in ipairs(calls) do
    assert(call.kind ~= "layout" or not call.value:match("^colresize"), "unchanged column width was resized")
end
setup()
a, b = add(1, "a", .5), add(1, "b", .5); focus(b)
drop.configure_workspace_animation({ leaf = "workspaces", enabled = true, speed = 4,
    bezier = "default", style = "slidefadevert 60%" })
place("a", 2, "", false)
assert(workspace_animation.speed == 4 and workspace_animation.bezier == "default"
    and workspace_animation.style == "slidefadevert 60%", "placement hardcoded the restored animation")
local shifts = workspace_shifts
focus(a)
assert(workspace_shifts > shifts, "ordinary workspace navigation lost its animation")
-- A real pointer release reaches the native scrolling layout before QML's
-- delayed placement. Guard the entire mapped overview, including remote views.
setup()
a, b = add(1, "a", .5), add(1, "b", .5); focus(a)
spaces[1].camera = 275
drop.watch_overview(); drop.watch_overview()
assert(#layer_handlers["layer.opened"] == 1, "overview watcher registered twice")
local function layer_event(event, namespace, address)
    for _, callback in ipairs(layer_handlers["layer." .. event]) do
        callback({ namespace = namespace, address = address })
    end
end
local function pointer_release()
    if follow_focus then current_window.workspace.camera = native_column(current_window).index * 1000 end
end
layer_event("opened", "quickshell:bar", "bar")
assert(follow_focus, "unrelated layer disabled focus follow")
layer_event("opened", "quickshell:overview", "main")
layer_event("opened", "quickshell:overview", "main")
layer_event("opened", "quickshell:overview-drop", "remote")
pointer_release()
assert(spaces[1].camera == 275, "pointer release under the overview panned the desktop")
focus(b)
assert(spaces[1].camera == 1000, "hard keyboard focus stopped following")
layer_event("closed", "quickshell:overview", "main")
assert(not follow_focus, "remote drag view lost its pointer-release guard")
layer_event("closed", "quickshell:overview-drop", "remote")
assert(follow_focus, "closing overview layers did not restore focus follow")
focus(a); spaces[1].camera = 275; pointer_release()
assert(spaces[1].camera == 0, "normal desktop pointer follow was not restored")

-- Bootstrap already-mapped surfaces after a config reload, and preserve an
-- explicitly disabled baseline instead of replacing it with a hardcoded true.
setup()
layers = { { namespace = "quickshell:overview", address = "mapped", mapped = true },
    { namespace = "quickshell:overview-drop", address = "unmapped", mapped = false } }
local reloaded = dofile("dots/.config/hypr/custom/overview_drop.lua")
reloaded.watch_overview()
assert(not follow_focus, "mapped overview was not guarded after config reload")
layer_event("closed", "quickshell:overview", "mapped")
assert(follow_focus, "mapped overview did not restore its baseline after reload")
follow_focus = false
layer_event("opened", "quickshell:overview", "mapped")
layer_event("closed", "quickshell:overview", "mapped")
assert(follow_focus == false, "overview guard overwrote a disabled baseline")
follow_focus = true
layer_event("opened", "quickshell:overview", "reopened")
assert(not follow_focus)
layer_event("closed", "quickshell:overview", "reopened")
assert(follow_focus, "reopened overview did not restore its current baseline")
print("overview-drop: insertions, cameras, pointer release, focus, cross-output moves and cleanup passed")
