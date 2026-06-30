--- Display control factory.
---
--- Builds (or reuses) a screen-anchored control for a phase. The runtime feeds the
--- returned control (remaining, duration, stacks) each render tick via :SetState.
---
--- Controls are reused by name across rebuilds (ESO controls cannot be destroyed),
--- so live editing can rebuild a tracker without leaking or name-colliding. Every
--- control owns all sub-elements (background, icon, bar, label); the display kind
--- only decides which are shown.

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

-- Return an existing control by name, or create it via factory. ESO errors when
-- creating a control whose name already exists, so reuse must be explicit.
local function reuse(name, factory)
	return WM:GetControlByName(name, "") or factory()
end

--- Build or reuse a display control for a phase.
---@param def table display def: display kind, name, color, icon, font, decimals,
---  and position (point, x, y, width, height)
---@return table control exposing :SetState(active, remaining, duration, stacks),
---  :SetHidden(hidden) and :SetBarColor(rgba)
function QAT.display.Create(def)
	local kind = def.display or "bar"
	local name = "QAT_Tracker_" .. tostring(def.id)
	local w, h = value(def, "width"), value(def, "height")

	local tlw = reuse(name, function()
		return WM:CreateTopLevelWindow(name)
	end)
	tlw:SetDimensions(w, h)
	tlw:SetMovable(true)
	tlw:SetMouseEnabled(true)
	tlw:SetClampedToScreen(true)
	tlw:SetHidden(true)
	tlw:ClearAnchors()
	tlw:SetAnchor(value(def, "point"), GuiRoot, value(def, "point"), value(def, "x"), value(def, "y"))

	local bg = reuse(name .. "_Bg", function()
		return WM:CreateControl(name .. "_Bg", tlw, CT_BACKDROP)
	end)
	bg:SetAnchorFill()
	bg:SetCenterColor(unpack(value(def, "bgColor")))
	bg:SetEdgeColor(0, 0, 0, 1)
	bg:SetEdgeTexture("", 1, 1, 1)

	local showIcon = (kind == "icon") or (def.icon ~= nil)
	local icon = reuse(name .. "_Icon", function()
		return WM:CreateControl(name .. "_Icon", tlw, CT_TEXTURE)
	end)
	icon:SetDimensions(h, h)
	icon:ClearAnchors()
	icon:SetAnchor(LEFT, tlw, LEFT, 0, 0)
	icon:SetTexture(def.icon or "/esoui/art/icons/icon_missing.dds")
	icon:SetHidden(not showIcon)

	local bar = reuse(name .. "_Bar", function()
		return WM:CreateControl(name .. "_Bar", tlw, CT_STATUSBAR)
	end)
	bar:SetAnchorFill()
	bar:SetColor(unpack(value(def, "color")))
	bar:SetMinMax(0, 1)
	bar:SetValue(1)
	bar:SetHidden(kind ~= "bar")

	local label = reuse(name .. "_Label", function()
		return WM:CreateControl(name .. "_Label", tlw, CT_LABEL)
	end)
	label:SetFont(value(def, "font"))
	label:ClearAnchors()
	label:SetAnchor(LEFT, showIcon and icon or tlw, showIcon and RIGHT or LEFT, 6, 0)
	label:SetVerticalAlignment(TEXT_ALIGN_CENTER)
	label:SetColor(1, 1, 1, 1)

	local control = {
		tlw = tlw,
		kind = kind,
		bar = (kind == "bar") and bar or nil,
		icon = showIcon and icon or nil,
		label = label,
		name = def.name or tostring(def.id),
		decimals = def.decimals or 1,
		valueSource = def.value or "time",
		showStacks = def.showStacks or false,
		maxStacks = def.maxStacks,
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

	-- The bar fill and the numeric readout come from the phase's value source:
	--   "time"   - remaining / duration (a countdown bar)
	--   "stacks" - stacks / maxStacks   (a stack meter; full if no maxStacks set)
	--   "none"   - static full bar, name only
	-- remaining/duration may be nil for a timer-less phase (e.g. "Ready"): a time
	-- source then shows full and the label is just the name.
	function control:SetState(active, remaining, duration, stacks)
		if not active then
			self.tlw:SetHidden(true)
			return
		end
		self.tlw:SetHidden(false)
		stacks = stacks or 0

		local hasTimer = duration ~= nil and duration > 0
		local src = self.valueSource
		local fill = 1
		if src == "time" and hasTimer then
			fill = zo_clamp(remaining / duration, 0, 1)
		elseif src == "stacks" then
			fill = (self.maxStacks and self.maxStacks > 0) and zo_clamp(stacks / self.maxStacks, 0, 1) or 1
		end
		if self.bar then
			self.bar:SetValue(fill)
			self.bar:SetColor(unpack(self.baseColor)) -- reset; runtime conds re-apply after
		end

		local text = self.name
		if src == "time" and hasTimer then
			text = text .. "  " .. string.format("%." .. self.decimals .. "f", remaining or 0)
		elseif src == "stacks" then
			text = text .. "  " .. stacks
		end
		-- Optional stacks badge, when the readout isn't already the stack count.
		if self.showStacks and src ~= "stacks" and stacks > 1 then
			text = text .. " (" .. stacks .. ")"
		end
		self.label:SetText(text)

		if self.icon then
			self.icon:SetDesaturation((hasTimer and remaining and remaining <= 0) and 1 or 0)
		end
	end

	return control
end
