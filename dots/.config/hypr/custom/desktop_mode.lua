-- Shared with Quickshell's Settings > Interface > Desktop layout.
-- Read on every configuration load, including a TTY-started session.
local M = {}

function M.read(path)
    local file = io.open(path, "r")
    if not file then return "scrolling" end
    local text = file:read("*a")
    file:close()
    -- This is a flat enum written by JsonAdapter, never executable Lua.
    return text:match('"desktopLayout"%s*:%s*"([%a]+)"') == "classic" and "classic" or "scrolling"
end

local config_home = os.getenv("XDG_CONFIG_HOME")
if not config_home or config_home == "" then config_home = os.getenv("HOME") .. "/.config" end
M.mode = M.read(config_home .. "/illogical-impulse/config.json")
M.scrolling = M.mode == "scrolling"
return M
