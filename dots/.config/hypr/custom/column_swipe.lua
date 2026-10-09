-- Three-finger horizontal scrolling with predictable stops, replacing scroll_move's
-- release snap, which mixes centered and edge stops a quarter screen apart and lets
-- release velocity pick between them.
-- A slow release settles at the nearest stop in view (centered or edge-aligned);
-- a flick pages through edge-aligned stops in its direction.
local M = {}

-- Releases at or above this speed (screens per second) page by edges. Check the
-- last release with: hyprctl repl 'print(require("custom.column_swipe").describe())'
M.flick_speed = 1.0
-- Fingers resting this long (ms) before lifting count as a slow release.
M.rest_ms = 80

local PROJECTION_DECAY = 4.0 -- Hyprland's scroll_move momentum projection
local MAX_PROJECTION = 2.0
local SMOOTHING = 0.35
local SAME_STOP = 12 -- px; window boxes omit gaps, so the current stop is a few px away
local OVERSHOOT = 16 -- px past an edge so fit_into_view aligns it exactly

M.last_release = nil

-- columns: { x, right } window boxes sorted by column; viewport: { left, right }.
-- speed: screens per second, positive when content moves right.
function M.plan(columns, viewport, speed)
    if #columns == 0 then return nil end
    local width = viewport.right - viewport.left
    local first, last = columns[1], columns[#columns]
    -- Window boxes omit the outer gaps; two half columns exactly fill the screen.
    local fills = last.right - first.x >= width - 2 * SAME_STOP
    local flick = math.abs(speed) >= M.flick_speed

    -- No stop exposes space beyond either end of a tape wider than the screen;
    -- Ctrl+Win+C can still center an end column explicitly.
    local function blank(shift)
        return fills and (first.x + shift > viewport.left + SAME_STOP
            or last.right + shift < viewport.right - SAME_STOP)
    end

    local candidates = {}
    for index, column in ipairs(columns) do
        local stops = {
            { kind = "left", shift = viewport.left - column.x },
            { kind = "right", shift = viewport.right - column.right },
        }
        if not flick then
            stops[3] = { kind = "center", shift = (viewport.left + viewport.right - column.x - column.right) / 2 }
        end
        for _, stop in ipairs(stops) do
            if not blank(stop.shift) then
                candidates[#candidates + 1] = { index = index, kind = stop.kind, shift = stop.shift }
            end
        end
    end

    local function nearest(target, ahead)
        local best, best_distance
        for _, candidate in ipairs(candidates) do
            if ahead(candidate.shift) then
                local distance = math.abs(candidate.shift - target)
                if not best or distance < best_distance - 0.5 then
                    best, best_distance = candidate, distance
                end
            end
        end
        return best
    end

    local any = function() return true end
    if not flick then return nearest(0, any) end
    local projected = math.max(-MAX_PROJECTION, math.min(MAX_PROJECTION, speed / PROJECTION_DECAY)) * width
    return nearest(projected, function(shift)
        return speed > 0 and shift > SAME_STOP or speed < 0 and shift < -SAME_STOP
    end) or nearest(0, any) -- At the end of the tape, settle where the flick started.
end

function M.describe()
    local release = M.last_release
    if not release then return "no three-finger release yet" end
    return string.format("last release %.2f screens/s, %s (flick_speed %.2f)",
        release.speed, release.flick and "flick" or "slow", M.flick_speed)
end

local function dispatch(action)
    local result, message = hl.dispatch(action)
    if type(result) == "table" and result.ok == false then
        error(result.error or "column swipe dispatch failed")
    elseif result == false then
        error(message or "column swipe dispatch failed")
    end
end

local function viewport_of(monitor)
    local width = monitor.transform % 2 == 1 and monitor.height or monitor.width
    return { left = monitor.x + monitor.reserved.left,
        right = monitor.x + width / monitor.scale - monitor.reserved.right }
end

local function snapshot(workspace)
    local by_index = {}
    for _, window in ipairs(hl.get_workspace_windows(workspace)) do
        local layout = window.layout
        if window.mapped and not window.hidden and not window.floating
            and layout and layout.name == "scrolling" and layout.column then
            local index = layout.column.index
            local column = by_index[index]
            if not column then
                column = { index = index, x = window.at.x, right = window.at.x + window.size.x, window = window }
                by_index[index] = column
            end
            column.x = math.min(column.x, window.at.x)
            column.right = math.max(column.right, window.at.x + window.size.x)
        end
    end
    local columns = {}
    for _, column in pairs(by_index) do columns[#columns + 1] = column end
    table.sort(columns, function(a, b) return a.index < b.index end)
    return columns
end

-- Numeric layout moves also focus the column at the viewport center. That hard
-- focus fits it back into view even with follow_focus disabled; a full-width
-- column then resists every small delta. Keep focus until release, as native
-- scroll_move does, without changing normal focus-follow or overriding window
-- properties. The rule is enabled only for the lifetime of a horizontal swipe.
local drag_focus_rule = nil
local function set_drag_focus(blocked)
    if blocked and not drag_focus_rule then
        drag_focus_rule = hl.window_rule({ name = "scrolling-swipe-focus",
            enabled = false, match = { float = false }, no_focus = true })
    end
    if drag_focus_rule and drag_focus_rule:is_enabled() ~= blocked then
        drag_focus_rule:set_enabled(blocked)
    end
end

local function move(shift)
    if shift == 0 then return end
    dispatch(hl.dsp.layout(string.format("move %.3f", shift)))
end

local gesture = nil

function M.start(event)
    set_drag_focus(false) -- Clean up an interrupted gesture before starting another.
    gesture = nil
    local active = hl.get_active_window()
    -- Win+D maximized columns can scroll; Win+F true fullscreen cannot.
    if active and (active.fullscreen == 2 or active.floating and active.fullscreen ~= 0) then return end
    local workspace = hl.get_active_workspace()
    local monitor = hl.get_active_monitor()
    if not workspace or not monitor then return end
    local columns = snapshot(workspace)
    if #columns == 0 then return end
    gesture = { workspace = workspace, monitor = monitor,
        original = active, velocity = 0, time = nil }
    set_drag_focus(true)
end

function M.update(event)
    if not gesture or not event.delta then return end
    local delta = event.delta.x
    if delta == 0 then return end
    local ok, message = pcall(move, delta)
    if not ok then
        gesture = nil
        set_drag_focus(false)
        error(message)
    end
    if gesture.time and event.time_ms > gesture.time then
        local instant = delta / ((event.time_ms - gesture.time) / 1000)
        gesture.velocity = gesture.velocity * (1 - SMOOTHING) + instant * SMOOTHING
    end
    gesture.time = event.time_ms
end

local function fully_visible(window, viewport)
    return window.at.x >= viewport.left - 1 and window.at.x + window.size.x <= viewport.right + 1
end

local function settle(current)
    local viewport = viewport_of(current.monitor)
    local columns = snapshot(current.workspace)
    local resting = not current.time or current.finished - current.time > M.rest_ms
    local speed = (current.cancelled or resting) and 0
        or current.velocity / (viewport.right - viewport.left)
    M.last_release = { speed = speed, flick = math.abs(speed) >= M.flick_speed }
    local plan = M.plan(columns, viewport, speed)
    if not plan then return end

    local column = columns[plan.index]
    local overshoot = plan.kind == "left" and -OVERSHOOT or plan.kind == "right" and OVERSHOOT or 0
    move(plan.shift + overshoot)
    set_drag_focus(false)
    -- Exact alignment comes from the layout itself, never from rounded window boxes.
    dispatch(hl.dsp.focus({ window = column.window }))
    dispatch(hl.dsp.layout(plan.kind == "center" and "center" or "fit_into_view"))

    -- Keep the original focus while it remains fully on screen.
    local original = current.original
    if original and original.mapped and not original.floating
        and original.workspace and original.workspace.id == current.workspace.id
        and fully_visible(original, viewport) then
        dispatch(hl.dsp.focus({ window = original }))
    end
    -- Layout moves emit no IPC event; refresh Quickshell's window positions.
    hl.dispatch(hl.dsp.event("ii:layoutChanged"))
end

function M.finish(event)
    local current = gesture
    gesture = nil
    if not current then return end
    current.cancelled = event.cancelled
    current.finished = event.time_ms
    -- A scroll gesture leaves the cursor where it is.
    local no_warps = hl.get_config("cursor:no_warps")
    hl.config({ cursor = { no_warps = true } })
    local ok, message = pcall(settle, current)
    set_drag_focus(false)
    hl.config({ cursor = { no_warps = no_warps } })
    if not ok then error(message) end
end

return M
