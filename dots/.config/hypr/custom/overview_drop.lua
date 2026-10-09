-- Place an overview window relative to a stable window address, not a stale index.
local M = {}

local function dispatch(action)
    local result, message = hl.dispatch(action)
    if result == false or type(result) == "table" and result.ok == false then
        error(message or type(result) == "table" and result.error or "overview drop failed")
    end
end

local function column(window)
    local layout = window and window.layout
    return layout and layout.name == "scrolling" and layout.column or nil
end

local function valid(window)
    return window and window.mapped and window.workspace
end

local workspace_animations = {}
function M.configure_workspace_animation(config)
    local animation = {}
    for key, value in pairs(config) do animation[key] = value end
    workspace_animations[config.leaf] = animation
    hl.animation(animation)
end

local function quiet_workspace_switches()
    for _, animation in pairs(workspace_animations) do
        local config = {}
        for key, value in pairs(animation) do config[key] = value end
        -- Turning animation back on before the next frame can still animate an
        -- offset already set by changeWorkspace. A zero-distance slide never sets
        -- that render offset; window movement animations remain enabled.
        config.style = "slidevert 0%"
        hl.animation(config)
    end
end

local overview_surfaces, saved_follow_focus, watching_overview = {}, nil, false
local function overview_surface(layer, opened)
    if not layer or (layer.namespace ~= "quickshell:overview" and layer.namespace ~= "quickshell:overview-drop") then return end
    local was_open = next(overview_surfaces) ~= nil
    overview_surfaces[layer.address] = opened and true or nil
    local is_open = next(overview_surfaces) ~= nil
    if was_open == is_open then return end
    if is_open then
        saved_follow_focus = hl.get_config("scrolling:follow_focus")
        hl.config({ scrolling = { follow_focus = false } })
    elseif saved_follow_focus ~= nil then
        hl.config({ scrolling = { follow_focus = saved_follow_focus } })
        saved_follow_focus = nil
    end
end

function M.watch_overview()
    if watching_overview then return end
    watching_overview = true
    -- Native pointer release fits the desktop's last window even when the
    -- pointer belongs to a layer surface. It runs before Quickshell receives
    -- the drop, so the placement transaction alone cannot prevent that pan.
    -- Hard keyboard/window focus still follows while this soft follow is off.
    hl.on("layer.opened", function(layer) overview_surface(layer, true) end)
    hl.on("layer.closed", function(layer) overview_surface(layer, false) end)
    -- A config reload can happen while the overview is already mapped.
    for _, layer in ipairs(hl.get_layers()) do
        if layer.mapped then overview_surface(layer, true) end
    end
end

local preparation_focus_rule
local function block_preparation_focus(blocked)
    if blocked and not preparation_focus_rule then
        preparation_focus_rule = hl.window_rule({ name = "overview-placement-preparation",
            enabled = false, match = { class = ".*" }, no_focus = true })
    end
    if preparation_focus_rule and preparation_focus_rule:is_enabled() ~= blocked then
        preparation_focus_rule:set_enabled(blocked)
    end
end

function M.place(options)
    local window = hl.get_window("address:" .. options.address)
    if not valid(window) or not options.workspace or options.workspace <= 0 then
        error("overview drop: window or destination is no longer available")
    end
    local anchor = options.anchor and options.anchor ~= ""
        and hl.get_window("address:" .. options.anchor) or nil
    if not valid(anchor) or anchor.workspace.id ~= options.workspace or anchor.address == window.address then
        anchor = nil
    end

    local original_monitor = hl.get_active_monitor()
    local original_workspace = hl.get_active_workspace()
    local original_special = hl.get_active_special_workspace()
    local original_window = hl.get_active_window()
    local destination = hl.get_workspace(options.workspace)
    local destination_monitor = destination and destination.monitor or hl.get_monitor(options.monitor)
    local source_column = column(window)
    local source_width = source_column and source_column.width
    local source_workspace = window.workspace
    local contexts, context_names, inhibited = {}, {}, {}
    local function remember(monitor)
        if not monitor or context_names[monitor.name] then return end
        context_names[monitor.name] = true
        contexts[#contexts + 1] = { monitor = monitor, workspace = hl.get_active_workspace(monitor),
            special = hl.get_active_special_workspace(monitor) }
    end
    remember(original_monitor)
    remember(window.monitor)
    remember(destination_monitor)
    local function select(monitor, workspace)
        local active_monitor = hl.get_active_monitor()
        if monitor and (not active_monitor or active_monitor.name ~= monitor.name) then
            dispatch(hl.dsp.focus({ monitor = monitor }))
        end
        if not workspace or not workspace.id then return end
        -- Native layout messages prefer an open special workspace, even when
        -- the already-focused window belongs to the underlying normal workspace.
        local special = hl.get_active_special_workspace()
        if special and special.id ~= workspace.id then
            dispatch(hl.dsp.workspace.toggle_special(special.name:gsub("^special:", "")))
        end
        if workspace.special then
            if not special or special.id ~= workspace.id then
                dispatch(hl.dsp.workspace.toggle_special(workspace.name:gsub("^special:", "")))
            end
            return
        end
        local active = hl.get_active_workspace()
        if workspace and workspace.id and (not active or active.id ~= workspace.id) then
            dispatch(hl.dsp.focus({ workspace = workspace }))
        end
    end
    local function inhibit(workspace)
        if not workspace or not workspace.id or inhibited[workspace.id] or workspace.tiled_layout ~= "scrolling" then return end
        select(workspace.monitor, workspace)
        dispatch(hl.dsp.layout("inhibit_scroll 1"))
        inhibited[workspace.id] = workspace
    end
    local no_warps = hl.get_config("cursor:no_warps")
    hl.config({ cursor = { no_warps = true } })
    local function focus(target)
        select(target.monitor, target.workspace)
        dispatch(hl.dsp.focus({ window = target }))
        local active = hl.get_active_window()
        if not active or active.address ~= target.address then
            error("overview drop: compositor refused window focus")
        end
    end

    local ok, message = pcall(function()
        quiet_workspace_switches()
        -- Freeze native camera offsets before any temporary window focus,
        -- promotion, resize or swap. Context preparation must not itself focus
        -- the other monitor's last window and fit its column into view.
        block_preparation_focus(true)
        for _, context in ipairs(contexts) do
            inhibit(context.workspace)
            inhibit(context.special)
        end
        inhibit(source_workspace)
        if not destination and destination_monitor then
            select(destination_monitor)
            dispatch(hl.dsp.focus({ workspace = options.workspace }))
            destination = hl.get_workspace(options.workspace)
        end
        inhibit(destination)
        block_preparation_focus(false)
        if window.workspace.id ~= options.workspace then
            if not destination and destination_monitor then
                dispatch(hl.dsp.focus({ monitor = destination_monitor }))
            end
            -- Following keeps the moved window's maximized/fullscreen state.
            dispatch(hl.dsp.window.move({ window = window, workspace = options.workspace, follow = true }))
            inhibit(window.workspace) -- An initially empty space may create its algorithm on insertion.
        else
            focus(window)
            -- A dragged preview is one window, rather than all windows stacked in its column.
            if source_column and #source_column.windows > 1 then
                dispatch(hl.dsp.layout("promote"))
            end
        end
        focus(window)
        if not column(window) then return end -- Floating windows retain their native placement.
        if source_width and window.fullscreen == 0 and math.abs(column(window).width - source_width) > 1e-8 then
            dispatch(hl.dsp.layout("colresize " .. string.format("%.9f", source_width)))
        end

        -- Native adjacent swaps preserve other columns and their sizes. Re-read
        -- both indices after every swap; promotion/removal can shift either one.
        local count = #hl.get_workspace_windows(window.workspace) + 1
        for _ = 1, count do
            local current, reference = column(window), column(anchor)
            if not current then break end
            local target
            if reference then
                target = reference.index + (options.before and 0 or 1)
                if current.index < reference.index then target = target - 1 end
            else
                -- If the anchor closed while dragging, safely append.
                target = current.index
                for _, other in ipairs(hl.get_workspace_windows(window.workspace)) do
                    local other_column = valid(other) and column(other) or nil
                    if other_column then target = math.max(target, other_column.index) end
                end
            end
            if target == current.index then break end
            dispatch(hl.dsp.layout("swapcol " .. (target < current.index and "l" or "r")))
        end
    end)

    -- Release every inhibitor even after a failed placement. Keep the original
    -- workspace frozen until its old focus has been restored, including a focus
    -- which was only partly visible before the overview opened.
    local restore_error
    local function cleanup(action)
        local restored, reason = pcall(action)
        if not restored and not restore_error then restore_error = reason end
    end
    block_preparation_focus(true)
    for id, workspace in pairs(inhibited) do
        if (not original_workspace or id ~= original_workspace.id)
            and (not original_special or id ~= original_special.id) then
            cleanup(function()
                if not workspace.id then return end
                select(workspace.monitor, workspace)
                dispatch(hl.dsp.layout("inhibit_scroll 0"))
            end)
        end
    end
    for _, context in ipairs(contexts) do
        if not original_monitor or context.monitor.name ~= original_monitor.name then
            cleanup(function()
                select(context.monitor, context.workspace)
                if context.special then select(context.monitor, context.special) end
            end)
        end
    end
    block_preparation_focus(false)
    -- The original camera is still frozen, so native workspace/monitor focus
    -- can safely select its replacement window if the old focus was moved away.
    cleanup(function() select(original_monitor, original_workspace) end)
    cleanup(function()
        if valid(original_window) and original_workspace and original_window.workspace.id == original_workspace.id then
            focus(original_window)
        end
    end)
    if original_workspace and inhibited[original_workspace.id] then
        cleanup(function() dispatch(hl.dsp.layout("inhibit_scroll 0")) end)
    end
    if original_special and original_special.id then
        -- An exclusive overview can leave its old normal window focused while
        -- Scratch is open. Preserve that state instead of focusing a new client.
        local special_focused = valid(original_window) and original_window.workspace.id == original_special.id
        block_preparation_focus(not special_focused)
        cleanup(function() select(original_monitor, original_special) end)
        if special_focused then cleanup(function() focus(original_window) end) end
        if inhibited[original_special.id] then
            cleanup(function() dispatch(hl.dsp.layout("inhibit_scroll 0")) end)
        end
    end
    block_preparation_focus(false)
    for _, animation in pairs(workspace_animations) do cleanup(function() hl.animation(animation) end) end
    hl.config({ cursor = { no_warps = no_warps } })
    hl.dispatch(hl.dsp.event("ii:layoutChanged"))
    if not ok then error(message) end
    if restore_error then error(restore_error) end
end

-- Hyprland's dispatch IPC evaluates a dispatcher factory.
function M.insert(options)
    return function() M.place(options) end
end

return M
