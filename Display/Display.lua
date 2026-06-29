--- Display control factory.
---
--- Builds a screen-anchored control of one display kind ("icon", "bar", "text")
--- for a phase. The runtime feeds the returned control (remaining, duration,
--- stacks) each render tick via :SetState.

QAT.display = {}

local WM = GetWindowManager()

local DEFAULTS = {
	width = 220,
	height = 30,
	font = "$(BOLD_FONT)|22|soft-shadow-thick",
	color = { 0.20, 0.80, 0.35, 1 },
	bgColor = { 0, 0, 0, 0.55 },
	point = CENTER,
	x = 0,
	y = -200,
}

---@return any
local function value(def, key)
	local v = def[key]
	if v == nil then
		return DEFAULTS[key]
	end
	return v
end

--- Build a display control for a phase.
---@param def table display def: display kind, name, color, icon, font, decimals,
---  and position (point, x, y, width, height)
---@return table control exposing :SetState(active, remaining, duration, stacks),
---  :SetHidden(hidden) and :SetBarColor(rgba)
function QAT.display.Create(def)
	local kind = def.display or "bar"

	-- A "none" phase has no on-screen element (cue-only). Return a no-op control
	-- so the tracker state machine can drive it uniformly.
	if kind == "none" then
		return {
			kind = "none",
			SetHidden = function() end,
			SetBarColor = function() end,
			SetState = function() end,
		}
	end

	local name = "QAT_Tracker_" .. tostring(def.id)
	local w, h = value(def, "width"), value(def, "height")

	local tlw = WM:CreateTopLevelWindow(name)
	tlw:SetDimensions(w, h)
	tlw:SetMovable(true)
	tlw:SetMouseEnabled(true)
	tlw:SetClampedToScreen(true)
	tlw:SetHidden(true)
	tlw:ClearAnchors()
	tlw:SetAnchor(value(def, "point"), GuiRoot, value(def, "point"), value(def, "x"), value(def, "y"))

	local bg = WM:CreateControl(name .. "_Bg", tlw, CT_BACKDROP)
	bg:SetAnchorFill()
	bg:SetCenterColor(unpack(value(def, "bgColor")))
	bg:SetEdgeColor(0, 0, 0, 1)
	bg:SetEdgeTexture("", 1, 1, 1)

	local icon
	if kind == "icon" or def.icon then
		icon = WM:CreateControl(name .. "_Icon", tlw, CT_TEXTURE)
		icon:SetDimensions(h, h)
		icon:SetAnchor(LEFT, tlw, LEFT, 0, 0)
		if def.icon then
			icon:SetTexture(def.icon)
		end
	end

	local bar
	if kind == "bar" then
		bar = WM:CreateControl(name .. "_Bar", tlw, CT_STATUSBAR)
		bar:SetAnchorFill()
		bar:SetColor(unpack(value(def, "color")))
		bar:SetMinMax(0, 1)
		bar:SetValue(1)
	end

	local label = WM:CreateControl(name .. "_Label", tlw, CT_LABEL)
	label:SetFont(value(def, "font"))
	label:SetAnchor(LEFT, icon or tlw, icon and RIGHT or LEFT, 6, 0)
	label:SetVerticalAlignment(TEXT_ALIGN_CENTER)
	label:SetColor(1, 1, 1, 1)

	local control = {
		tlw = tlw,
		kind = kind,
		bar = bar,
		icon = icon,
		label = label,
		name = def.name or tostring(def.id),
		decimals = def.decimals or 1,
		baseColor = value(def, "color"),
	}

	function control:SetHidden(hidden)
		self.tlw:SetHidden(hidden)
	end

	-- Override the bar color (used by runtime conditions). SetState resets to the
	-- phase's base color first, so an override only lasts while its condition holds.
	function control:SetBarColor(c)
		if self.bar and c then
			self.bar:SetColor(unpack(c))
		end
	end

	-- remaining/duration may be nil for a timer-less phase (e.g. "Ready"):
	-- then the bar shows full and the label shows just the name.
	function control:SetState(active, remaining, duration, stacks)
		if not active then
			self.tlw:SetHidden(true)
			return
		end
		self.tlw:SetHidden(false)

		local hasTimer = duration ~= nil and duration > 0
		if self.bar then
			self.bar:SetValue(hasTimer and zo_clamp(remaining / duration, 0, 1) or 1)
			self.bar:SetColor(unpack(self.baseColor)) -- reset; runtime conds re-apply after
		end

		local text = self.name
		if hasTimer then
			text = text .. "  " .. string.format("%." .. self.decimals .. "f", remaining or 0)
		end
		if stacks and stacks > 1 then
			text = text .. " (" .. stacks .. ")"
		end
		self.label:SetText(text)

		if self.icon then
			self.icon:SetDesaturation((hasTimer and remaining <= 0) and 1 or 0)
		end
	end

	return control
end
