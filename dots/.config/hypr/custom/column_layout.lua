-- Coordinate a screenful of native scrolling columns without a shell process.
local M = {}
local states = {}
local patterns = {
    { 1 / 2, 1 / 2 },
    { 2 / 3, 1 / 3 },
    { 1 / 3, 2 / 3 },
    { 1 / 3, 1 / 3, 1 / 3 },
}

local function matches(columns, first, widths)
    for offset, width in ipairs(widths) do
        local column = columns[first + offset - 1]
        if not column or math.abs(column.width - width) > 0.0001 then
            return false
        end
    end
    return true
end

local function coverage(columns, first, count, viewport)
    local total = 0
    for i = first, first + count - 1 do
        local column = columns[i]
        total = total + math.max(0, math.min(column.right, viewport.right)
            - math.max(column.x, viewport.left))
    end
    return total
end

local function choose_start(columns, focus, count, viewport, preferred)
    local low = math.max(1, focus - count + 1)
    local high = math.min(focus, #columns - count + 1)
    if preferred then
        return math.max(low, math.min(high, preferred))
    end
    local best, best_coverage = low, -1
    for first = low, high do
        local score = coverage(columns, first, count, viewport)
        if score > best_coverage then
            best, best_coverage = first, score
        end
    end
    return best
end

-- Pure planning also makes selection and cycling testable without a desktop.
function M.plan(columns, focus, viewport, previous)
    if #columns < 2 or not focus then return nil end
    local limit = #columns >= 3 and 4 or 3
    local mode, anchor = 0, nil

    -- Keep the same group while cycling or focusing another window within it.
    -- Native column membership detects closing, merging, splitting or reordering.
    if previous and previous.mode <= limit then
        for first = 1, #columns - #previous.ids + 1 do
            local same = focus >= first and focus < first + #previous.ids
            for offset, id in ipairs(previous.ids) do
                same = same and columns[first + offset - 1].id == id
            end
            if same and matches(columns, first, patterns[previous.mode]) then
                mode, anchor = previous.mode, first
                break
            end
        end
    end

    -- Infer an existing preset after reload; normalize custom widths to halves.
    if mode == 0 then
        local best_coverage = -1
        for candidate = 1, limit do
            local widths = patterns[candidate]
            local first = choose_start(columns, focus, #widths, viewport)
            local score = coverage(columns, first, #widths, viewport)
            if matches(columns, first, widths) and score > best_coverage then
                mode, anchor, best_coverage = candidate, first, score
            end
        end
    end

    local next_mode = mode % limit + 1
    local widths = patterns[next_mode]
    local first = choose_start(columns, focus, #widths, viewport, anchor)
    local ids = {}
    for i = first, first + #widths - 1 do ids[#ids + 1] = columns[i].id end
    return { mode = next_mode, first = first, widths = widths, ids = ids }
end

local function snapshot(active)
    local by_index = {}
    local active_index = active.layout.column.index
    for _, window in ipairs(hl.get_workspace_windows(active.workspace)) do
        local layout = window.layout
        if window.mapped and not window.hidden and not window.floating
            and layout and layout.name == "scrolling" and layout.column then
            local native = layout.column
            local column = by_index[native.index]
            if not column then
                column = { index = native.index, width = native.width, window = window,
                    members = {}, x = window.at.x, right = window.at.x + window.size.x }
                by_index[native.index] = column
            end
            column.members[#column.members + 1] = tostring(window.stable_id)
            column.x = math.min(column.x, window.at.x)
            column.right = math.max(column.right, window.at.x + window.size.x)
            if window.stable_id == active.stable_id then column.window = window end
        end
    end
    local columns = {}
    for _, column in pairs(by_index) do
        table.sort(column.members)
        column.id = table.concat(column.members, ",")
        columns[#columns + 1] = column
    end
    table.sort(columns, function(a, b) return a.index < b.index end)
    local focused
    for i, column in ipairs(columns) do
        if column.index == active_index then focused = i end
    end
    return columns, focused
end

local function dispatch(action)
    local ok, message = hl.dispatch(action)
    if ok == false then error(message or "column layout dispatch failed") end
end

function M.cycle()
    local active = hl.get_active_window()
    if not active or not active.mapped or active.floating or active.fullscreen ~= 0
        or not active.workspace or not active.monitor then return end
    local layout = active.layout
    if not layout or layout.name ~= "scrolling" or not layout.column then return end

    local columns, focused = snapshot(active)
    local monitor = active.monitor
    local pixel_width = monitor.transform % 2 == 1 and monitor.height or monitor.width
    local reserved = monitor.reserved
    local viewport = { left = monitor.x + reserved.left,
        right = monitor.x + pixel_width / monitor.scale - reserved.right }
    local key = monitor.name .. ":" .. tostring(active.workspace.id)
    local plan = M.plan(columns, focused, viewport, states[key])
    if not plan then return end

    -- colresize targets the focused column. Do the short transaction in one
    -- compositor callback, suppress cursor warps, then restore the original focus.
    local no_warps = hl.get_config("cursor:no_warps")
    hl.config({ cursor = { no_warps = true } })
    local function focus(window)
        dispatch(hl.dsp.focus({ window = window }))
    end
    local ok, message = pcall(function()
        for offset, width in ipairs(plan.widths) do
            focus(columns[plan.first + offset - 1].window)
            dispatch(hl.dsp.layout("colresize " .. string.format("%.9f", width)))
        end
        -- Fit both ends so the whole selected group fills the viewport, even
        -- when the original camera was between columns. Their widths sum to 1.
        dispatch(hl.dsp.layout("fit_into_view"))
        focus(columns[plan.first].window)
        dispatch(hl.dsp.layout("fit_into_view"))
    end)
    local restored, restore_error = pcall(function() focus(active) end)
    hl.config({ cursor = { no_warps = no_warps } })
    if not ok then error(message) end
    if not restored then error(restore_error) end
    states[key] = { mode = plan.mode, ids = plan.ids }
    -- A global shortcut would request key-release replay of this entire cycle.
    hl.dispatch(hl.dsp.event("ii:layoutChanged"))
end

return M
