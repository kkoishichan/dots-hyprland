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

print("column-swipe: slow placement, flick paging, tape ends and mixed widths passed")
