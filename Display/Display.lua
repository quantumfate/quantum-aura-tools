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

-- Per-readout label fonts: an author-settable face (via LibMediaProvider) and size,
-- with a shared style. `face` is a resolved font path or the default $(BOLD_FONT).
local FONT_FACE, FONT_STYLE = "$(BOLD_FONT)", "soft-shadow-thick"
local DEFAULT_FONT_SIZE = { label = 20, time = 20, stacks = 16 }
local function fontFor(sizes, key, face)
	local size = (sizes and sizes[key]) or DEFAULT_FONT_SIZE[key]
	return (face or FONT_FACE) .. "|" .. size .. "|" .. FONT_STYLE
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
	if kind == "icon" or kind == "border" or kind == "gradient" then
		w = h
	end
	local colors = def.colors
	local fontSizes = def.fontSizes
	-- The bar kind carries an optional square icon on the left. When shown, the bar
	-- shares the row with it (starts after it) rather than sitting behind it.
	local showLeftIcon = (kind == "bar") and def.showIcon ~= false and def.icon ~= nil and def.icon ~= ""
	-- The border kind is a frame-only overlay: transparent background, with the icon
	-- shown behind the draining frame when the unified "show icon" gate is on.
	local iconBehind = (kind == "border") and def.showIcon ~= false and def.icon ~= nil and def.icon ~= ""

	-- Top-left origin: pos.x/pos.y are the control's top-left corner from the screen's
	-- top-left (x right, y down), matching the editor's Position fields.
	local point, posX, posY = TOPLEFT, value(def, "x"), value(def, "y")
	local tlw = reuse(name, function()
		return WM:CreateTopLevelWindow(name)
	end)
	tlw:SetDimensions(w, h)
	tlw:SetHidden(true)
	-- Layer order: a higher-layer phase (e.g. a transparent cooldown frame) draws
	-- above a lower one (e.g. the duration icon) sharing the tracker's position.
	tlw:SetDrawLevel(def.drawLevel or 0)
	tlw.qatTrackerId = def.trackerId
	-- Custom drag (only while the editor is open AND this is the selected node):
	-- ESO's SetMovable rewrites the anchor mid-drag, so GetLeft/GetTop read back
	-- garbage. Instead we drive the anchor ourselves from the mouse, keeping the
	-- whole control in one coordinate space (UI mouse pos == anchor offset == the
	-- editor's clamp), so positions are exact top-left pixels. Mouse arming is owned
	-- by QAT.Runtime_ApplyDragSelection (only the selected tracker is grabbable), so a
	-- freshly (re)built control starts disabled.
	tlw:SetMouseEnabled(false)
	tlw:SetHandler("OnMouseDown", function(self, button)
		if button ~= MOUSE_BUTTON_INDEX_LEFT or not QAT.trackersMovable then
			return
		end
		local mx, my = GetUIMousePosition()
		self.qatGrabX, self.qatGrabY = mx - self:GetLeft(), my - self:GetTop()
		self.qatDragging = true
	end)
	tlw:SetHandler("OnMouseUp", function(self)
		if self.qatDragging then
			self.qatDragging = false
			-- Finalize from the last computed offset (GetLeft can be a frame stale).
			if QAT.Editor_OnTrackerDragged and self.qatTrackerId then
				QAT.Editor_OnTrackerDragged(self.qatTrackerId, self.qatLastX or 0, self.qatLastY or 0)
			end
		end
	end)
	tlw:SetHandler("OnUpdate", function(self)
		if not self.qatDragging then
			return
		end
		local mx, my = GetUIMousePosition()
		local x = zo_clamp(mx - self.qatGrabX, 0, GuiRoot:GetWidth() - self:GetWidth())
		local y = zo_clamp(my - self.qatGrabY, 0, GuiRoot:GetHeight() - self:GetHeight())
		self:ClearAnchors()
		self:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, x, y)
		self.qatLastX, self.qatLastY = zo_round(x), zo_round(y)
		if QAT.Editor_SetTrackerPosLive and self.qatTrackerId then
			QAT.Editor_SetTrackerPosLive(self.qatTrackerId, self.qatLastX, self.qatLastY)
		end
	end)
	tlw:ClearAnchors()
	tlw:SetAnchor(point, GuiRoot, point, posX, posY)

	local bg = reuse(name .. "_Bg", function()
		return WM:CreateControl(name .. "_Bg", tlw, CT_BACKDROP)
	end)
	-- Backdrop edge dimensions must be powers of two; snap anything else to 1.
	local VALID_BORDER = { [1] = true, [2] = true, [4] = true, [8] = true, [16] = true }
	local borderT = def.borderThickness
	if not VALID_BORDER[borderT] then
		borderT = 1
	end
	bg:SetAnchorFill()
	if kind == "border" then
		-- Frame-only: the CT_BACKDROP draws nothing (our own segments are the frame),
		-- keeping the background fully transparent so it can overlay another phase.
		bg:SetCenterColor(0, 0, 0, 0)
		bg:SetEdgeColor(0, 0, 0, 0)
		bg:SetEdgeTexture("", 1, 1, 1)
	else
		bg:SetCenterColor(unpack(colorOf(colors, "background")))
		bg:SetEdgeColor(unpack(colorOf(colors, "border")))
		bg:SetEdgeTexture("", borderT, borderT, borderT) -- empty texture => solid colour edge of this thickness
	end

	-- The gradient icon honours the same unified gate; the graphic kind is itself a
	-- full-fill texture (its image is chosen live in SetState from def.graphic).
	local gradientIcon = (kind == "gradient") and def.showIcon ~= false
	local fullIcon = (kind == "icon") or (kind == "graphic") or gradientIcon or iconBehind
	local showIcon = fullIcon or showLeftIcon
	local graphicSpec = (kind == "graphic") and def.graphic or nil
	local icon = reuse(name .. "_Icon", function()
		return WM:CreateControl(name .. "_Icon", tlw, CT_TEXTURE)
	end)
	icon:ClearAnchors()
	if kind == "graphic" then
		-- Keep the texture's 1:1 ratio: a square sized to the shorter side (no stretch on
		-- a wide/short tracker), placed left / center / right.
		local side = math.min(w, h)
		icon:SetDimensions(side, side)
		local align = graphicSpec and graphicSpec.align or "center"
		if align == "left" then
			icon:SetAnchor(LEFT, tlw, LEFT, 0, 0)
		elseif align == "right" then
			icon:SetAnchor(RIGHT, tlw, RIGHT, 0, 0)
		else
			icon:SetAnchor(CENTER, tlw, CENTER, 0, 0)
		end
	elseif fullIcon then
		icon:SetAnchorFill() -- the icon IS the display (border kind: it sits behind the frame)
	else
		icon:SetDimensions(h, h)
		icon:SetAnchor(LEFT, tlw, LEFT, 0, 0)
	end
	local baseTexture = (graphicSpec and graphicSpec.default) or def.icon or "/esoui/art/icons/icon_missing.dds"
	icon:SetTexture(baseTexture)
	icon:SetColor(1, 1, 1, 1)
	icon:SetHidden(not showIcon)

	local bar = reuse(name .. "_Bar", function()
		return WM:CreateControl(name .. "_Bar", tlw, CT_STATUSBAR)
	end)
	bar:ClearAnchors()
	if kind == "bar" then
		-- Bar of the chosen height, anchored top/middle/bottom. When an icon shows the
		-- bar starts after it (small gap) so the two never overlap; otherwise it fills
		-- the full width. Full height + no icon reproduces the classic bar.
		local BESIDE_GAP = showLeftIcon and 4 or 0
		local bh = (def.barHeight == "thin" and 6) or (def.barHeight == "half" and math.floor(h / 2)) or h
		local yoff = (def.barAnchor == "top" and 0)
			or (def.barAnchor == "bottom" and (h - bh))
			or math.floor((h - bh) / 2)
		local xstart = (showLeftIcon and h or 0) + BESIDE_GAP
		bar:SetAnchor(TOPLEFT, tlw, TOPLEFT, xstart, yoff)
		bar:SetDimensions(w - xstart, bh)
	else
		bar:SetAnchor(TOPLEFT, tlw, TOPLEFT, 0, 0)
		bar:SetAnchor(BOTTOMRIGHT, tlw, BOTTOMRIGHT, 0, 0)
	end
	bar:SetColor(unpack(colorOf(colors, "bar")))
	bar:SetMinMax(0, 1)
	bar:SetValue(1)
	bar:SetHidden(kind ~= "bar")

	-- Border-kind drain frame: four solid edge textures (top, right, bottom, left)
	-- laid clockwise from the top-left corner. Each is resized every frame so the
	-- combined visible length equals the remaining fraction of the perimeter — the
	-- frame shrinks clockwise as time runs out. Hidden entirely for other kinds.
	local edgeNames = { "_ETop", "_ERight", "_EBottom", "_ELeft" }
	local edges = {}
	for _, suffix in ipairs(edgeNames) do
		local e = reuse(name .. suffix, function()
			return WM:CreateControl(name .. suffix, tlw, CT_TEXTURE)
		end)
		e:ClearAnchors()
		e:SetTexture("") -- solid colour, no image
		e:SetDrawLevel(2) -- above icon (0) and proc (1), below labels (5)
		e:SetHidden(kind ~= "border")
		edges[#edges + 1] = e
	end

	-- Gradient-kind sweep: a translucent progress bar overlaid on the fully-lit icon —
	-- the same fill animation as the Bar kind but see-through, so the icon shows behind
	-- it. "reveal" maps the fill to remaining time; "shine" loops the fill for a pulse.
	local sweep = reuse(name .. "_Sweep", function()
		return WM:CreateControl(name .. "_Sweep", tlw, CT_STATUSBAR)
	end)
	sweep:ClearAnchors()
	sweep:SetAnchorFill()
	sweep:SetMinMax(0, 1)
	sweep:SetValue(1)
	sweep:SetDrawLevel(2) -- above the icon (0), below the readout labels (5)
	-- Fill direction: horizontal for ltr/rtl, vertical for ttb/btt; the reverse
	-- alignment fills from the far edge (right / bottom).
	local dir = def.sweepDir or "rtl"
	local horiz = (dir == "ltr" or dir == "rtl")
	sweep:SetOrientation(horiz and ORIENTATION_HORIZONTAL or ORIENTATION_VERTICAL)
	sweep:SetBarAlignment((dir == "rtl" or dir == "ttb") and BAR_ALIGNMENT_REVERSE or BAR_ALIGNMENT_NORMAL)
	sweep:SetHidden(kind ~= "gradient")

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
	local face = QAT.util.FontFace(def.font)
	nameLabel:SetFont(fontFor(fontSizes, "label", face))
	timeLabel:SetFont(fontFor(fontSizes, "time", face))
	stacksLabel:SetFont(fontFor(fontSizes, "stacks", face))
	for _, l in ipairs({ nameLabel, timeLabel, stacksLabel }) do
		l:SetVerticalAlignment(TEXT_ALIGN_CENTER)
		l:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
		l:SetDrawLevel(5) -- readouts stay legible above the proc glow
	end

	-- Static label anchors per kind (icon-kind number anchors are set live in
	-- SetState since they depend on how many numbers are showing).
	nameLabel:ClearAnchors()
	timeLabel:ClearAnchors()
	stacksLabel:ClearAnchors()
	if kind == "icon" or kind == "border" or kind == "gradient" or kind == "graphic" then
		nameLabel:SetHidden(true)
	else
		nameLabel:SetHidden(false)
		nameLabel:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
		nameLabel:SetAnchor(LEFT, tlw, LEFT, showIcon and (h + 6) or 6, 0)
		timeLabel:SetAnchor(RIGHT, tlw, RIGHT, -6, 0)
		if kind == "bar" and showLeftIcon then
			stacksLabel:SetAnchor(CENTER, icon, CENTER, 0, 0) -- stacks sit on the bar's left icon
		else
			stacksLabel:SetAnchor(RIGHT, timeLabel, LEFT, -8, 0)
		end
	end

	-- Proc glow: the game's looping ability-proc swirl, overlaid on the icon (or the
	-- whole control) and shown while a Show-Proc condition holds.
	local proc = reuse(name .. "_Proc", function()
		return WM:CreateControl(name .. "_Proc", tlw, CT_TEXTURE)
	end)
	proc:SetTexture("EsoUI/Art/ActionBar/abilityHighlightAnimation.dds")
	proc:SetBlendMode(TEX_BLEND_MODE_ADD) -- additive: the texture's black is transparent
	proc:SetDrawLevel(1) -- above icon/bar (0), below the readout labels (5)
	-- Fill the icon exactly (or the whole control if there's no icon) so the glow
	-- matches the icon's dimensions.
	local procTarget = showIcon and icon or tlw
	proc:ClearAnchors()
	proc:SetAnchor(TOPLEFT, procTarget, TOPLEFT, 0, 0)
	proc:SetAnchor(BOTTOMRIGHT, procTarget, BOTTOMRIGHT, 0, 0)
	proc:SetHidden(true)

	local control = {
		tlw = tlw,
		kind = kind,
		bg = bg,
		bar = (kind == "bar") and bar or nil,
		edges = (kind == "border") and edges or nil,
		borderStyle = def.borderStyle or "drain",
		sweep = (kind == "gradient") and sweep or nil,
		sweepColor = def.sweepColor,
		borderT = borderT,
		lowThreshold = def.lowThreshold,
		lowColor = def.lowColor,
		lowPulse = def.lowPulse or false,
		icon = showIcon and icon or nil,
		graphic = graphicSpec, -- graphic kind: { default, rules } for live texture swaps
		graphicBase = baseTexture,
		nameLabel = nameLabel,
		timeLabel = timeLabel,
		stacksLabel = stacksLabel,
		proc = proc,
		colors = colors,
		name = def.name or tostring(def.id),
		decimals = def.decimals or 1,
		forceHidden = def.forceHidden or false,
		showStacks = def.showStacks or false,
		showTime = def.showTime ~= false,
	}

	-- Show/hide the looping proc swirl. The flipbook animation is created lazily and
	-- only (re)started on the hidden->shown edge.
	function control:SetProc(on)
		local p = self.proc
		if on then
			if not p.qatAnim then
				local a = CreateSimpleAnimation(ANIMATION_TEXTURE, p)
				a:SetImageData(64, 1)
				a:SetFramerate(30)
				a:GetTimeline():SetPlaybackType(ANIMATION_PLAYBACK_LOOP, LOOP_INDEFINITELY)
				p.qatAnim = a
			end
			if p:IsHidden() then
				p:SetHidden(false)
				p.qatAnim:GetTimeline():PlayFromStart()
			end
		elseif not p:IsHidden() then
			p:SetHidden(true)
			if p.qatAnim then
				p.qatAnim:GetTimeline():Stop()
			end
		end
	end

	function control:SetHidden(hidden)
		self.tlw:SetHidden(hidden)
		if hidden then
			self:SetProc(false)
		end
	end

	-- Move the control to a new top-left position (live, without a rebuild).
	function control:Reposition(x, y)
		self.tlw:ClearAnchors()
		self.tlw:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, x, y)
	end

	-- Resolve the graphic-kind texture for the current state: the first rule whose
	-- threshold holds wins, else the default. Rule stats mirror the transition
	-- vocabulary (remaining seconds, stack count).
	local function ruleHolds(op, a, b)
		if op == "<=" then
			return a <= b
		elseif op == "<" then
			return a < b
		elseif op == ">=" then
			return a >= b
		elseif op == ">" then
			return a > b
		elseif op == "==" then
			return a == b
		end
		return false
	end
	function control:graphicTexture(remaining, stacks)
		local g = self.graphic
		for _, r in ipairs(g.rules or {}) do
			local cur = (r.stat == "stacks") and (stacks or 0) or (remaining or 0)
			if ruleHolds(r.op or "<=", cur, r.value or 0) then
				return r.texture
			end
		end
		return self.graphicBase
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
			if self.edges then
				for _, e in ipairs(self.edges) do
					if not e:IsHidden() then
						e:SetColor(c[1], c[2], c[3], c[4] or 1)
					end
				end
			end
		elseif element == "bar" and self.bar then
			self.bar:SetColor(unpack(c))
		elseif element == "text" then
			self.nameLabel:SetColor(unpack(c))
		elseif element == "timer" then
			self.timeLabel:SetColor(unpack(c))
		elseif element == "stacks" then
			self.stacksLabel:SetColor(unpack(c))
		elseif element == "sweep" and self.sweep then
			self.sweep:SetColor(unpack(c)) -- gradient-kind translucent fill (ephemeral override)
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

	-- Lay the four drain edges clockwise from the top-left so the visible border
	-- length equals `frac` of the perimeter. `remaining` drives the optional low-time
	-- recolor/pulse. Segments shorter than the corner thickness are hidden.
	function control:setBorderFraction(frac, remaining)
		local es = self.edges
		if not es then
			return
		end
		local tw, th = self.tlw:GetWidth(), self.tlw:GetHeight()
		local t = self.borderT
		local P = 2 * (tw + th)
		local want = zo_clamp(frac or 0, 0, 1) * P
		local tl = zo_min(want, tw)
		want = want - tl
		local rl = zo_min(want, th)
		want = want - rl
		local bl = zo_min(want, tw)
		want = want - bl
		local ll = zo_min(want, th)

		-- Colour: the frame reads as the progress fill; drop to the low colour (and
		-- optionally pulse alpha) once under the author's threshold.
		local c = colorOf(self.colors, "bar")
		if self.lowThreshold and remaining and remaining > 0 and remaining <= self.lowThreshold then
			c = self.lowColor or { 0.90, 0.20, 0.20, 1 }
			if self.lowPulse then
				local a = 0.55 + 0.45 * (0.5 + 0.5 * math.sin(GetFrameTimeSeconds() * 6))
				c = { c[1], c[2], c[3], (c[4] or 1) * a }
			end
		end

		local top, right, bottom, left = es[1], es[2], es[3], es[4]
		top:ClearAnchors()
		top:SetAnchor(TOPLEFT, self.tlw, TOPLEFT, 0, 0)
		right:ClearAnchors()
		right:SetAnchor(TOPRIGHT, self.tlw, TOPRIGHT, 0, 0)
		bottom:ClearAnchors()
		bottom:SetAnchor(BOTTOMRIGHT, self.tlw, BOTTOMRIGHT, 0, 0)
		left:ClearAnchors()
		left:SetAnchor(BOTTOMLEFT, self.tlw, BOTTOMLEFT, 0, 0)
		local function seg(e, len, horiz)
			if len < t then
				e:SetHidden(true)
				return
			end
			e:SetHidden(false)
			e:SetColor(c[1], c[2], c[3], c[4] or 1)
			if horiz then
				e:SetDimensions(len, t)
			else
				e:SetDimensions(t, len)
			end
		end
		seg(top, tl, true)
		seg(right, rl, false)
		seg(bottom, bl, true)
		seg(left, ll, false)
	end

	-- Drive the gradient sweep. `frac` is remaining/duration (1 for a passive). "shine"
	-- loops a band across the icon, faster as time runs low; "reveal" dims the expired
	-- portion with a moving boundary whose leading edge is the coloured band.
	function control:setGradient(frac, remaining, hasTimer)
		local sw = self.sweep
		if not sw then
			return
		end
		-- Translucent fill so the icon reads through it; default a soft blue at ~45%.
		-- The fill always maps to remaining time (a reveal); its direction is fixed at
		-- creation from sweepDir.
		local c = self.sweepColor or { 0.30, 0.65, 1.0, 0.45 }
		sw:SetColor(c[1], c[2], c[3], c[4] or 0.45)
		sw:SetValue(hasTimer and frac or 1)
	end

	function control:SetState(active, remaining, duration, stacks)
		if self.forceHidden then
			self.tlw:SetHidden(true) -- layer toggled invisible
			self:SetProc(false)
			return
		end
		if not active or self.kind == "none" or self.kind == "audio" then
			self.tlw:SetHidden(true) -- non-visual kinds; an audio cue fires on enter
			self:SetProc(false)
			return
		end
		self.tlw:SetHidden(false)
		stacks = stacks or 0

		local hasTimer = duration ~= nil and duration > 0
		local showTime = hasTimer and self.showTime
		local showStacks = self.showStacks and stacks > 0 and self.kind ~= "text" -- text has no stacks

		self:resetColors()

		local frac = hasTimer and zo_clamp(remaining / duration, 0, 1) or 1

		if self.bar then
			self.bar:SetValue(frac)
			-- Low-time recolor/pulse for the beside bar (matches the border kind).
			if self.lowThreshold and remaining and remaining > 0.05 and remaining <= self.lowThreshold then
				local lc = self.lowColor or { 0.90, 0.20, 0.20, 1 }
				if self.lowPulse then
					local pulse = 0.65 + 0.35 * math.sin(GetFrameTimeSeconds() * 6)
					lc = { lc[1] * pulse, lc[2] * pulse, lc[3] * pulse, lc[4] or 1 }
				end
				self.bar:SetColor(lc[1], lc[2], lc[3], lc[4] or 1)
			end
		end

		if self.kind == "border" then
			-- "fill" grows the frame as the timer progresses (inverse of the drain).
			local bf = (self.borderStyle == "fill") and (1 - frac) or frac
			self:setBorderFraction(bf, remaining)
		elseif self.kind == "gradient" then
			self:setGradient(frac, remaining, hasTimer)
		end

		self.nameLabel:SetText(self.name)
		self.timeLabel:SetText(showTime and string.format("%." .. self.decimals .. "f", remaining or 0) or "")
		self.stacksLabel:SetText(showStacks and tostring(stacks) or "")
		self.timeLabel:SetHidden(not showTime)
		self.stacksLabel:SetHidden(not showStacks)

		if self.kind == "icon" or self.kind == "border" or self.kind == "gradient" or self.kind == "graphic" then
			self:placeIconNumbers(showTime, showStacks)
		end

		-- Cooldown tint: desaturate the icon once a timed phase has run out (a
		-- lockout still showing) — keeps the at-a-glance "not ready" read.
		if self.icon then
			local onCooldown = hasTimer and remaining and remaining <= 0
			self.icon:SetDesaturation(onCooldown and 1 or 0)
		end

		-- Graphic kind: pick the texture live — the first rule whose stat threshold
		-- holds against the current remaining time / stacks, else the default.
		if self.graphic and self.icon then
			self.icon:SetTexture(self:graphicTexture(remaining, stacks))
		end
	end

	return control
end
