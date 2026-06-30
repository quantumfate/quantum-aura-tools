--- Display control factory.
---
--- Builds (or reuses) a screen-anchored control for a phase. The runtime feeds the
--- returned control (remaining, duration, stacks) each render tick via :SetState.
---
--- Controls are reused by name across rebuilds (ESO controls cannot be destroyed),
--- so live editing can rebuild a tracker without leaking or name-colliding. Every
--- control owns all sub-elements (background, icon, bar, and the name/time/stacks
--- labels); the display kind and the live data decide which are shown.
---
--- Readouts are data-driven: the bar/icon animation is always the remaining time;
--- the time number shows whenever a timer is running; the stacks number shows when
--- the phase declares `showStacks` and the effect actually reports stacks. A buff
--- with no real duration (a passive) shows a full static bar / lit icon.

QAT.display = {}

local WM = GetWindowManager()

local DEFAULTS = {
	width = 220,
	height = 30,
	point = CENTER,
	x = 0,
	y = -200,
}

-- Per-readout label fonts: a shared face/style with an author-settable size.
local FONT_FACE, FONT_STYLE = "$(BOLD_FONT)", "soft-shadow-thick"
local DEFAULT_FONT_SIZE = { label = 20, time = 20, stacks = 16 }
local function fontFor(sizes, key)
	local size = (sizes and sizes[key]) or DEFAULT_FONT_SIZE[key]
	return FONT_FACE .. "|" .. size .. "|" .. FONT_STYLE
end

-- Per-element fallback colors, used when the phase's look leaves one unset.
local DEFAULT_COLORS = {
	background = { 0, 0, 0, 0.55 },
	bar = { 0.20, 0.80, 0.35, 1 },
	border = { 0, 0, 0, 1 },
	stacks = { 1, 0.82, 0.20, 1 },
	text = { 1, 1, 1, 1 },
	timer = { 1, 1, 1, 1 },
	cooldown = { 0.5, 0.5, 0.5, 1 },
}

local function value(def, key)
	local v = def[key]
	if v == nil then
		return DEFAULTS[key]
	end
	return v
end

local function colorOf(colors, key)
	return (colors and colors[key]) or DEFAULT_COLORS[key]
end

-- Return an existing control by name, or create it via factory. ESO errors when
-- creating a control whose name already exists, so reuse must be explicit.
local function reuse(name, factory)
	return WM:GetControlByName(name, "") or factory()
end

--- Build or reuse a display control for a phase.
---@param def table display def: display kind, name, icon, font, decimals,
---  showStacks, colors (per-element), and position (point, x, y, width, height)
---@return table control exposing :SetState(active, remaining, duration, stacks),
---  :SetHidden(hidden) and :SetElementColor(element, rgba)
function QAT.display.Create(def)
	local kind = def.display or "bar"
	local name = "QAT_Tracker_" .. tostring(def.id)
	local w, h = value(def, "width"), value(def, "height")
	-- An icon is square: it uses the height for both dimensions so it does not
	-- inherit the bar's width (phases each own their control, so an icon phase and a
	-- bar phase in the same tracker can be sized independently).
	if kind == "icon" then
		w = h
	end
	local colors = def.colors
	local fontSizes = def.fontSizes
	local showLeftIcon = (kind == "bar") and def.icon ~= nil and def.icon ~= ""

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
	bg:SetCenterColor(unpack(colorOf(colors, "background")))
	bg:SetEdgeColor(unpack(colorOf(colors, "border")))
	bg:SetEdgeTexture("", 1, 1, 1)

	local showIcon = (kind == "icon") or showLeftIcon
	local icon = reuse(name .. "_Icon", function()
		return WM:CreateControl(name .. "_Icon", tlw, CT_TEXTURE)
	end)
	icon:ClearAnchors()
	if kind == "icon" then
		icon:SetAnchorFill() -- the icon IS the display
	else
		icon:SetDimensions(h, h)
		icon:SetAnchor(LEFT, tlw, LEFT, 0, 0)
	end
	icon:SetTexture(def.icon or "/esoui/art/icons/icon_missing.dds")
	icon:SetColor(1, 1, 1, 1)
	icon:SetHidden(not showIcon)

	local bar = reuse(name .. "_Bar", function()
		return WM:CreateControl(name .. "_Bar", tlw, CT_STATUSBAR)
	end)
	bar:ClearAnchors()
	bar:SetAnchor(TOPLEFT, tlw, TOPLEFT, showLeftIcon and h or 0, 0)
	bar:SetAnchor(BOTTOMRIGHT, tlw, BOTTOMRIGHT, 0, 0)
	bar:SetColor(unpack(colorOf(colors, "bar")))
	bar:SetMinMax(0, 1)
	bar:SetValue(1)
	bar:SetHidden(kind ~= "bar")

	-- Three independent labels so each can carry its own color (text / timer / stacks).
	local nameLabel = reuse(name .. "_Name", function()
		return WM:CreateControl(name .. "_Name", tlw, CT_LABEL)
	end)
	local timeLabel = reuse(name .. "_Time", function()
		return WM:CreateControl(name .. "_Time", tlw, CT_LABEL)
	end)
	local stacksLabel = reuse(name .. "_Stacks", function()
		return WM:CreateControl(name .. "_Stacks", tlw, CT_LABEL)
	end)
	nameLabel:SetFont(fontFor(fontSizes, "label"))
	timeLabel:SetFont(fontFor(fontSizes, "time"))
	stacksLabel:SetFont(fontFor(fontSizes, "stacks"))
	for _, l in ipairs({ nameLabel, timeLabel, stacksLabel }) do
		l:SetVerticalAlignment(TEXT_ALIGN_CENTER)
		l:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
	end

	-- Static label anchors per kind (icon-kind number anchors are set live in
	-- SetState since they depend on how many numbers are showing).
	nameLabel:ClearAnchors()
	timeLabel:ClearAnchors()
	stacksLabel:ClearAnchors()
	if kind == "icon" then
		nameLabel:SetHidden(true)
	else
		nameLabel:SetHidden(false)
		nameLabel:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
		nameLabel:SetAnchor(LEFT, tlw, LEFT, showIcon and (h + 6) or 6, 0)
		timeLabel:SetAnchor(RIGHT, tlw, RIGHT, -6, 0)
		stacksLabel:SetAnchor(RIGHT, timeLabel, LEFT, -8, 0)
	end

	local control = {
		tlw = tlw,
		kind = kind,
		bg = bg,
		bar = (kind == "bar") and bar or nil,
		icon = showIcon and icon or nil,
		nameLabel = nameLabel,
		timeLabel = timeLabel,
		stacksLabel = stacksLabel,
		colors = colors,
		name = def.name or tostring(def.id),
		decimals = def.decimals or 1,
		showStacks = def.showStacks or false,
		showTime = def.showTime ~= false,
	}

	function control:SetHidden(hidden)
		self.tlw:SetHidden(hidden)
	end

	-- Reset every element to its authored base color. SetState calls this first so a
	-- runtime-condition override (SetElementColor) only lasts while its condition holds.
	function control:resetColors()
		self.bg:SetCenterColor(unpack(colorOf(self.colors, "background")))
		self.bg:SetEdgeColor(unpack(colorOf(self.colors, "border")))
		if self.bar then
			self.bar:SetColor(unpack(colorOf(self.colors, "bar")))
		end
		self.nameLabel:SetColor(unpack(colorOf(self.colors, "text")))
		self.timeLabel:SetColor(unpack(colorOf(self.colors, "timer")))
		self.stacksLabel:SetColor(unpack(colorOf(self.colors, "stacks")))
	end

	-- Ephemeral per-element recolor from a runtime condition. Never persisted.
	function control:SetElementColor(element, c)
		if not c then
			return
		end
		if element == "background" then
			self.bg:SetCenterColor(unpack(c))
		elseif element == "border" then
			self.bg:SetEdgeColor(unpack(c))
		elseif element == "bar" and self.bar then
			self.bar:SetColor(unpack(c))
		elseif element == "text" then
			self.nameLabel:SetColor(unpack(c))
		elseif element == "timer" then
			self.timeLabel:SetColor(unpack(c))
		elseif element == "stacks" then
			self.stacksLabel:SetColor(unpack(c))
		end
	end

	-- Position the icon-kind number overlays: one number centers; two split to
	-- stacks-top / time-bottom.
	function control:placeIconNumbers(showTime, showStacks)
		self.timeLabel:ClearAnchors()
		self.stacksLabel:ClearAnchors()
		if showTime and showStacks then
			self.stacksLabel:SetAnchor(TOP, self.tlw, TOP, 0, 2)
			self.timeLabel:SetAnchor(BOTTOM, self.tlw, BOTTOM, 0, -2)
		else
			self.timeLabel:SetAnchor(CENTER, self.tlw, CENTER, 0, 0)
			self.stacksLabel:SetAnchor(CENTER, self.tlw, CENTER, 0, 0)
		end
	end

	function control:SetState(active, remaining, duration, stacks)
		if not active or self.kind == "none" or self.kind == "audio" then
			self.tlw:SetHidden(true) -- non-visual kinds; an audio cue fires on enter
			return
		end
		self.tlw:SetHidden(false)
		stacks = stacks or 0

		local hasTimer = duration ~= nil and duration > 0
		local showTime = hasTimer and self.showTime
		local showStacks = self.showStacks and stacks > 0

		self:resetColors()

		if self.bar then
			self.bar:SetValue(hasTimer and zo_clamp(remaining / duration, 0, 1) or 1)
		end

		self.nameLabel:SetText(self.name)
		self.timeLabel:SetText(showTime and string.format("%." .. self.decimals .. "f", remaining or 0) or "")
		self.stacksLabel:SetText(showStacks and tostring(stacks) or "")
		self.timeLabel:SetHidden(not showTime)
		self.stacksLabel:SetHidden(not showStacks)

		if self.kind == "icon" then
			self:placeIconNumbers(showTime, showStacks)
		end

		-- Cooldown tint: desaturate the icon once a timed phase has run out (a
		-- lockout still showing) — keeps the at-a-glance "not ready" read.
		if self.icon then
			local onCooldown = hasTimer and remaining and remaining <= 0
			self.icon:SetDesaturation(onCooldown and 1 or 0)
		end
	end

	return control
end
