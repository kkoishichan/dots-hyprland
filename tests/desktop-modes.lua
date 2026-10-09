-- Load the real base + custom configuration in fresh contexts, as Hyprland does
-- on reload. Check both modes and a return to scrolling for stale overrides.
package.path = "dots/.config/hypr/?.lua;dots/.config/hypr/?/init.lua;" .. package.path
local mode = require("custom.desktop_mode")
local path = os.tmpname()
for _, case in ipairs({ { "{}", "scrolling" }, { '{"desktopLayout":"classic"}', "classic" },
    { '{"desktopLayout": "scrolling"}', "scrolling" }, { '{"desktopLayout":"unknown"}', "scrolling" } }) do
    local file = assert(io.open(path, "w")); file:write(case[1]); file:close()
    assert(mode.read(path) == case[2])
end
os.remove(path)
assert(mode.read(path) == "scrolling")

local function dispatcher(name)
    return setmetatable({}, {
        __index = function(_, key) return dispatcher(name .. "." .. key) end,
        __call = function(_, value) return { kind = name, value = value } end,
    })
end
for _, scrolling in ipairs({ true, false, true }) do
    local bindings, gestures, animations, config, watching = {}, {}, {}, {}, false
    hl = {
        dsp = dispatcher("dsp"), env = function() end, monitor = function() end,
        curve = function() end, device = function() end,
        define_submap = function() end,
        bind = function(key, action, opts) bindings[key] = { action = action, options = opts } end,
        unbind = function(key) bindings[key] = nil end,
        gesture = function(value) gestures[value.fingers .. ":" .. value.direction] = value end,
        animation = function(value) animations[value.leaf] = value end,
        config = function(value)
            for group, values in pairs(value) do
                config[group] = config[group] or {}
                for key, v in pairs(values) do config[group][key] = v end
            end
        end,
    }
    package.loaded["hyprland.lib"] = nil
    package.loaded["hyprland.variables"] = nil
    package.loaded["custom.variables"] = nil
    package.loaded["custom.desktop_mode"] = { scrolling = scrolling }
    package.loaded["custom.overview_drop"] = {
        configure_workspace_animation = hl.animation,
        watch_overview = function() watching = true end,
    }
    package.loaded["custom.column_swipe"] = { start = function() end, update = function() end, finish = function() end }
    dofile("dots/.config/hypr/hyprland/general.lua")
    dofile("dots/.config/hypr/hyprland/keybinds.lua")
    dofile("dots/.config/hypr/custom/general.lua")
    dofile("dots/.config/hypr/custom/keybinds.lua")
    assert(config.general.layout == (scrolling and "scrolling" or "dwindle"))
    assert(watching == scrolling)
    assert(bindings["SUPER + Return"], "Terminal must remain available in both modes")
    for _, key in ipairs({ "XF86Back", "XF86Forward" }) do
        for _, mods in ipairs({ "SUPER", "CTRL + SUPER", "SUPER + SHIFT", "SUPER + ALT" }) do
            assert(bindings[mods .. " + " .. key], "Legacy browser key missing")
        end
    end
    if scrolling then
        assert(not bindings["SUPER + Tab"])
        assert(not bindings["SUPER + 1"])
        assert(bindings["SUPER + R"])
        assert(type(bindings["SUPER + SHIFT + Right"].action) == "function")
        assert(bindings["SUPER + Semicolon"].options.repeating)
        assert(gestures["3:horizontal"] and gestures["3:up"])
        assert(gestures["4:horizontal"].action == "unset")
        assert(animations.workspaces.style == "slidevert")
    else
        assert(bindings["SUPER + Tab"])
        assert(bindings["SUPER + 1"])
        assert(not bindings["SUPER + R"], "No scrolling preset in classic mode")
        assert(bindings["SUPER + SHIFT + Right"].action.kind == "dsp.window.move")
        assert(bindings["SUPER + Semicolon"].action.value == "splitratio -0.1")
        assert(bindings["SUPER + XF86Back"].action.value.workspace == "r-1")
        assert(not gestures["3:horizontal"])
        assert(gestures["3:swipe"].action == "move")
        assert(gestures["4:horizontal"].action == "workspace")
        assert(animations.workspaces.style ~= "slidevert")
        assert(workspace_in_group(2) == 2)
    end
end
print("desktop-modes: persisted enum, both native profiles and legacy shortcuts passed")
