-- Regression: global dispatchers request a key-release callback in Hyprland.
-- A layout action followed by one must not execute the layout again on release.
local bindings, calls, current = {}, {}, nil
local function action(kind)
    return function(value) return { kind = kind, value = value } end
end
local workspace = { id = 1 }
local monitor = { name = "test", width = 1200, height = 800, scale = 1,
    transform = 0, x = 0, reserved = { left = 0, right = 0 } }
local windows = {}
for i = 1, 2 do
    windows[i] = { stable_id = i, mapped = true, fullscreen = 0,
        workspace = workspace, monitor = monitor,
        at = { x = (i - 1) * 600 }, size = { x = 600 },
        layout = { name = "scrolling", column = { index = i - 1, width = 0.5 } } }
end
hl = {
    dsp = { layout = action("layout"), global = action("global"),
        event = action("event"), exec_cmd = action("exec"), focus = action("focus"),
        window = { move = action("move") } },
    unbind = function(key) bindings[key] = nil end,
    bind = function(key, callback, options)
        bindings[key] = { callback = callback, options = options }
    end,
    get_active_window = function() return windows[1] end,
    get_workspace_windows = function() return windows end,
    get_config = function() return false end,
    config = function() end,
    dispatch = function(dispatcher)
        calls[#calls + 1] = dispatcher
        if dispatcher.kind == "global" and current then current.releasePending = true end
        return true
    end,
}
package.path = "dots/.config/hypr/?.lua;" .. package.path
package.loaded["custom.desktop_mode"] = { scrolling = true }
dofile("dots/.config/hypr/custom/keybinds.lua")

local function tap(key)
    calls = {}
    local bind = assert(bindings[key], key)
    current = bind
    bind.releasePending = false
    bind.callback()
    if bind.releasePending or bind.options.release then bind.callback() end
    current = nil
    return calls
end

for _, entry in ipairs({
    { "SUPER + SHIFT + Left", "swapcol l" },
    { "SUPER + SHIFT + Right", "swapcol r" },
    { "SUPER + ALT + Left", "consume_or_expel prev" },
    { "SUPER + ALT + Right", "consume_or_expel next" },
    { "SUPER + Semicolon", "colresize -conf" },
    { "SUPER + Apostrophe", "colresize +conf" },
    { "SUPER + CTRL + C", "center" },
}) do
    local count = 0
    for _, call in ipairs(tap(entry[1])) do
        if call.kind == "layout" and call.value == entry[2] then count = count + 1 end
    end
    assert(count == 1, entry[1] .. " must act once per press/release, got " .. count)
end
local resized = 0
for _, call in ipairs(tap("SUPER + R")) do
    if call.kind == "layout" and call.value:match("^colresize ") then resized = resized + 1 end
end
assert(resized == 2, "Win+R must adjust the pair once, got " .. resized .. " resizes")
assert(bindings["SUPER + Semicolon"].options.repeating)
assert(bindings["SUPER + Apostrophe"].options.repeating)
assert(not bindings["SUPER + SHIFT + Left"].options.repeating)
assert(not bindings["SUPER + SHIFT + Right"].options.repeating)
print("layout-keybinds: one action per press/release, paired layouts and width repeat passed")
