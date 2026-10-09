local swipe = dofile("dots/.config/hypr/custom/column_swipe.lua")

local viewport = { left = 0, right = 1920 }

-- Window boxes for columns of the given screen fractions, scrolled by offset px.
-- Boxes sit 4 px inside their strips, as with the configured gaps.
local function columns(fractions, offset)
    local result, x = {}, -offset
    for i, fraction in ipairs(fractions) do
        local width = fraction * 1920
        result[i] = { x = x + 4, right = x + width - 4 }
        x = x + width
    end
    return result
end

local function halves(count, offset)
    local fractions = {}
    for i = 1, count do fractions[i] = 0.5 end
    return columns(fractions, offset)
end

local function check(plan, index, kind, shift, message)
    assert(plan, message .. ": no stop")
    assert(index == nil or plan.index == index, message .. ": column " .. plan.index)
    assert(kind == nil or plan.kind == kind, message .. ": kind " .. plan.kind)
    assert(math.abs(plan.shift - shift) <= 12, message .. ": shift " .. plan.shift)
end

-- Slow releases settle at the nearest stop in view. Half columns stop every quarter
-- screen: aligned pairs at offsets 0, 960, ... and centered columns at 480, 1440, ...
check(swipe.plan(halves(5, 0), viewport, 0), nil, nil, 0, "aligned pair stays")
check(swipe.plan(halves(5, 100), viewport, 0), nil, nil, 100, "short drag returns")
check(swipe.plan(halves(5, 640), viewport, 0), 2, "center", 160, "drag a third: center the column in view")
check(swipe.plan(halves(5, 960), viewport, 0), nil, nil, 0, "drag a half: next aligned pair")
check(swipe.plan(halves(5, 840), viewport, 0), nil, nil, -120, "past the midpoint: aligned pair")
check(swipe.plan(halves(5, 600), viewport, 0), 2, "center", 120, "before the midpoint: centered")
check(swipe.plan(halves(5, 640), viewport, swipe.flick_speed - 0.01), 2, "center", 160, "below flick speed is slow")

-- Flicks page through edge-aligned stops in their direction.
check(swipe.plan(halves(5, 0), viewport, -1.5), nil, nil, -960, "flick pages one pair")
check(swipe.plan(halves(5, 640), viewport, -1.5), nil, nil, -320, "flick from a centered view aligns ahead")
check(swipe.plan(halves(9, 0), viewport, -6), nil, nil, -2880, "a fast flick projects a quarter of its speed")
check(swipe.plan(halves(9, 0), viewport, -12), nil, nil, -3840, "projection stops at two screens")
check(swipe.plan(halves(5, 1920), viewport, 1.5), nil, nil, 960, "flick right pages back")
local plan = swipe.plan(halves(5, 640), viewport, -1.5)
assert(plan.kind ~= "center", "flicks never center")

-- Neither end of a tape wider than the screen exposes blank space.
check(swipe.plan(halves(3, 960), viewport, -2), nil, nil, 0, "flick at the end stays")
check(swipe.plan(halves(3, 0), viewport, 2), nil, nil, 0, "flick at the start stays")
check(swipe.plan(halves(3, -300), viewport, 0), nil, nil, -300, "overscroll at the start bounces back")
assert(swipe.plan(halves(3, -300), viewport, 0).kind ~= "center", "the bounce does not center the first column")
check(swipe.plan(halves(3, 1260), viewport, 0), nil, nil, 300, "overscroll at the end bounces back")

-- Mixed widths and narrow tapes.
check(swipe.plan(columns({ 2 / 3, 1 / 3, 0.5, 0.5 }, 100), viewport, 0), nil, nil, 100, "mixed widths return")
check(swipe.plan(columns({ 2 / 3, 1 / 3, 0.5, 0.5 }, 0), viewport, -1.5), nil, nil, -960, "mixed widths page")
check(swipe.plan(halves(2, 480), viewport, 0), nil, nil, 480, "a screen-filling pair never centers")
check(swipe.plan(halves(2, -480), viewport, 0), nil, nil, -480, "a screen-filling pair returns from either side")
check(swipe.plan(halves(1, 0), viewport, 0), 1, nil, 0, "a single half column stays")
assert(swipe.plan({}, viewport, 0) == nil)

-- Exercise the actual gesture lifecycle and native numeric-move focus fit: a
-- full-width column must not be snapped back during small finger movements.
local function gesture_case(mode, floating, cancelled, failure, empty_end)
    local workspace = { id = 1 }
    local monitor = { x = 0, width = 1920, height = 1080, scale = 1,
        transform = 0, reserved = { left = 0, right = 0 } }
    local windows = {}
    for i, box in ipairs(columns({ 1, 0.5, 0.5 }, 0)) do
        windows[i] = { stable_id = i, mapped = true, hidden = false,
            floating = i == 1 and floating, fullscreen = i == 1 and mode or 0,
            workspace = workspace, at = { x = box.x }, size = { x = box.right - box.x },
            layout = { name = "scrolling", column = { index = i - 1 } } }
    end
    local original, active = windows[1], windows[1]
    local moved, refreshed, no_warps, focus_blocked = 0, 0, false, false
    local failure_pending = failure
    hl = {
        get_active_window = function() return active end,
        get_active_workspace = function() return workspace end,
        get_active_monitor = function() return monitor end,
        get_workspace_windows = function() return windows end,
        get_config = function() return no_warps end,
        config = function(value) no_warps = value.cursor.no_warps end,
        window_rule = function(spec)
            assert(spec.match.float == false and spec.no_focus and not spec.enabled)
            return {
                is_enabled = function() return focus_blocked end,
                set_enabled = function(_, enabled) focus_blocked = enabled end,
            }
        end,
        dsp = {
            layout = function(command) return { command = command } end,
            focus = function(value) return { focus = value.window } end,
            event = function(value) return { event = value } end,
        },
        dispatch = function(action)
            if action.command then
                local shift = tonumber(action.command:match("^move (.+)$"))
                if shift then
                    if failure_pending then
                        failure_pending = false
                        return { ok = false, error = "test move failure" }
                    end
                    moved = moved + 1
                    for _, window in ipairs(windows) do window.at.x = window.at.x + shift end
                    if not focus_blocked then
                        -- Native layoutmsg move hard-focuses the center column,
                        -- even if already focused, and fits it fully into view.
                        for _, window in ipairs(windows) do
                            if window.at.x <= 960 and window.at.x + window.size.x > 960 then
                                active = window
                                local fit = window.at.x < 4 and 4 - window.at.x
                                    or window.at.x + window.size.x > 1916 and 1916 - window.at.x - window.size.x or 0
                                for _, v in ipairs(windows) do v.at.x = v.at.x + fit end
                                break
                            end
                        end
                    end
                end
            elseif action.focus then
                active = action.focus
            elseif action.event == "ii:layoutChanged" then
                refreshed = refreshed + 1
            end
            return { ok = true }
        end,
    }
    local gesture_swipe = dofile("dots/.config/hypr/custom/column_swipe.lua")
    local blocked = floating or mode == 2
    gesture_swipe.start({ time_ms = 0 })
    local ok, message = pcall(gesture_swipe.update, { delta = { x = -16 }, time_ms = 16 })
    if blocked then
        assert(moved == 0, "true fullscreen or floating maximized windows must not scroll")
        assert(not focus_blocked, "a rejected swipe must not block focus")
    elseif failure then
        assert(not ok and message:find("test move failure", 1, true), "move failure was swallowed")
        assert(not focus_blocked, "failed update did not restore focus")
    else
        assert(ok, message)
        assert(original.at.x == -12, "full-width column resisted a small delta")
        assert(moved == 1, "a small delta should move once, without compensation")
        assert(active == original, "dragging changed focus")
        for i = 1, 10 do gesture_swipe.update({ delta = { x = -0.1 }, time_ms = 16 + i }) end
        assert(math.abs(original.at.x + 13) < 0.001, "subpixel movements were discarded")
    end
    if empty_end then windows = {} end -- Every window closed while fingers were down.
    gesture_swipe.finish({ time_ms = 200, cancelled = cancelled })
    assert(original.fullscreen == mode, "scrolling must preserve fullscreen state")
    assert(not no_warps, "gesture did not restore the cursor setting")
    assert(not focus_blocked, "gesture did not restore normal focus")
    assert(refreshed == ((blocked or failure or empty_end) and 0 or 1), "wrong layout refresh count")
    if not blocked and not failure and not empty_end then
        -- A fresh start must release the previous gesture's focus rule, including
        -- when it is rejected because the window has entered true fullscreen.
        gesture_swipe.start({ time_ms = 300 })
        original.fullscreen = 2
        active = original
        gesture_swipe.start({ time_ms = 320 })
        assert(not focus_blocked, "an interrupted swipe left focus blocked")
        original.fullscreen = mode
    end
end
for _, mode in ipairs({ 0, 1, 2 }) do gesture_case(mode, false, false) end
gesture_case(1, false, true)
gesture_case(1, true, false)
gesture_case(2, true, false)
gesture_case(1, false, false, true)
gesture_case(1, false, false, false, true)

print("column-swipe: stops, flick paging, tape ends, mixed widths, fullscreen guard and focus restoration passed")
