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
    local ok, message = hl.dispatch(action)
    if ok == false then error(message or "column swipe dispatch failed") end
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

-- layoutmsg move focuses the column at the center, whose follow-focus fit can pan
-- further; undo any such extra pan against a tiled reference window.
local function position(window)
    local ok, x = pcall(function() return window.at.x end)
    return ok and x or nil
end

local function move(shift, reference)
    if math.abs(shift) < 0.5 then return end
    local before = position(reference)
    dispatch(hl.dsp.layout(string.format("move %.3f", shift)))
    local after = before and position(reference)
    if not after then return end -- The reference closed mid-gesture.
    local drift = before + shift - after
    if math.abs(drift) > 1.5 then
        dispatch(hl.dsp.layout(string.format("move %.3f", drift)))
    end
end

local gesture = nil

function M.start(event)
    gesture = nil
    local active = hl.get_active_window()
    if active and active.fullscreen ~= 0 then return end
    local workspace = hl.get_active_workspace()
    local monitor = hl.get_active_monitor()
    if not workspace or not monitor then return end
    local columns = snapshot(workspace)
    if #columns == 0 then return end
    gesture = { workspace = workspace, monitor = monitor, reference = columns[1].window,
        original = active, velocity = 0, time = nil }
end

function M.update(event)
    if not gesture or not event.delta then return end
    local delta = event.delta.x
    if delta == 0 then return end
    move(delta, gesture.reference)
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
    move(plan.shift + overshoot, current.reference)
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
    hl.config({ cursor = { no_warps = no_warps } })
    if not ok then error(message) end
end

return M
