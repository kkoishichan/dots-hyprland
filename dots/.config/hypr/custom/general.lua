local desktop_mode = require("custom.desktop_mode")

hl.device({
	name = "tpps/2-elan-trackpoint",
	accel_profile = "flat",
	sensitivity = 0.2,
	scroll_factor = 0.5,
})

local function get_generated_color(name, fallback)
	local colors_file = io.open(HOME .. "/.local/state/quickshell/user/generated/colors.json", "r")
	if colors_file == nil then
		return fallback
	end

	local colors = colors_file:read("*a")
	colors_file:close()
	return colors:match('"' .. name .. '"%s*:%s*"#([%x]+)"') or fallback
end

-- Theme and input devices are shared; layout geometry and behaviour are not.
hl.config({ general = { col = {
    active_border = "rgba(" .. get_generated_color("primary", "ffb5a1") .. "FF)",
} } })
require("custom.layouts." .. desktop_mode.mode)
