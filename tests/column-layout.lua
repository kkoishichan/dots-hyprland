local layout = dofile("dots/.config/hypr/custom/column_layout.lua")

local function columns(widths, offset)
    local result, x = {}, -(offset or 0)
    for i, width in ipairs(widths) do
        result[i] = { id = tostring(i), width = width, x = x, right = x + width * 1200 }
        x = result[i].right
    end
    return result
end

local viewport = { left = 0, right = 1200 }
local function apply(cols, plan)
    local x = 0
    for i, width in ipairs(plan.widths) do cols[plan.first + i - 1].width = width end
    for i = 1, plan.first - 1 do x = x - cols[i].width * 1200 end
    for _, column in ipairs(cols) do
        column.x, column.right = x, x + column.width * 1200
        x = column.right
    end
    return { mode = plan.mode, ids = plan.ids }
end

local function check_plan(plan, mode, first, focus)
    assert(plan and plan.mode == mode, "wrong cycle mode")
    assert(plan.first == first, "wrong starting column")
    assert(focus >= first and focus < first + #plan.widths, "focused column was excluded")
    local sum = 0
    for _, width in ipairs(plan.widths) do sum = sum + width end
    assert(math.abs(sum - 1) < 0.000001, "group does not fill one viewport")
end

-- Normal two/three-column cycle, including entering from the right viewport edge.
for focus = 1, 3 do
    local cols = columns({ .5, .5, .5 }, focus == 3 and 600 or 0)
    local state
    for _, mode in ipairs({ 2, 3, 4, 1, 2, 3, 4, 1 }) do
        local plan = layout.plan(cols, focus, viewport, state)
        check_plan(plan, mode, mode == 4 and 1 or (focus == 3 and 2 or 1), focus)
        state = apply(cols, plan)
    end
end

-- Only the selected group changes; offscreen columns keep independent widths.
local cols = columns({ .8, .5, .5, .75, .4 }, 960)
local plan = layout.plan(cols, 3, viewport)
check_plan(plan, 2, 2, 3)
local state = apply(cols, plan)
assert(cols[1].width == .8 and cols[4].width == .75 and cols[5].width == .4)
plan = layout.plan(cols, 2, viewport, state)
check_plan(plan, 3, 2, 2)
state = apply(cols, plan)
plan = layout.plan(cols, 2, viewport, state)
check_plan(plan, 4, 2, 2)

-- Two available columns never get an empty third slot.
cols, state = columns({ .5, .5 }), nil
for _, mode in ipairs({ 2, 3, 1, 2 }) do
    plan = layout.plan(cols, 2, viewport, state)
    check_plan(plan, mode, 1, 2)
    state = apply(cols, plan)
end
assert(layout.plan({}, nil, viewport) == nil)
assert(layout.plan(columns({ .5 }), 1, viewport) == nil)

-- Reload infers existing proportions; arbitrary mouse resizing first normalizes.
check_plan(layout.plan(columns({ 2 / 3, 1 / 3, .5 }), 1, viewport), 3, 1, 1)
check_plan(layout.plan(columns({ 1 / 3, 1 / 3, 1 / 3 }), 3, viewport), 1, 2, 3)
check_plan(layout.plan(columns({ .45, .55, .5 }), 1, viewport), 1, 1, 1)

-- A split/merge/close invalidates the old group; new windows do not inherit stale state.
cols = columns({ .5, .5, .5 })
state = { mode = 3, ids = { "closed", "merged" } }
check_plan(layout.plan(cols, 1, viewport, state), 2, 1, 1)

-- Moving focus to a third column and then returning to pairs retains that window.
cols = columns({ 1 / 3, 1 / 3, 1 / 3, .5 })
state = { mode = 4, ids = { "1", "2", "3" } }
check_plan(layout.plan(cols, 3, viewport, state), 1, 2, 3)

-- The group follows the viewport after focusing outside its previous members.
cols = columns({ 2 / 3, 1 / 3, .5, .5 }, 1200)
state = { mode = 2, ids = { "1", "2" } }
check_plan(layout.plan(cols, 4, viewport, state), 2, 3, 4)

print("column-layout: cycling, focus retention, viewport selection and stale groups passed")
