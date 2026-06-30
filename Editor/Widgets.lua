-- Small UI widget helpers for the editor (plain ESO controls; no DOM here).

QAT.widgets = {}

local WM = GetWindowManager()
local FONT = "$(MEDIUM_FONT)|18|soft-shadow-thin"

-- Shared palette so inputs, dropdowns and buttons read as one toolkit and stand
-- apart from the panel background.
local C = {
	fieldBg = { 0.03, 0.04, 0.06, 1 }, -- text inputs: near-black inset so they pop
	fieldEdge = { 0.36, 0.42, 0.52, 1 }, -- brighter border for clear separation
	ddBg = { 0.11, 0.13, 0.17, 1 }, -- dropdowns: a touch raised vs inputs
	btnBg = { 0.18, 0.20, 0.26, 1 },
	btnEdge = { 0.38, 0.43, 0.53, 1 },
	selBg = { 0.20, 0.34, 0.52, 1 }, -- active tab / chip / selected
}
local DROPDOWN_ARROW = "EsoUI/Art/Buttons/scrollbox_downArrow_up.dds"

-- Shared hover-tooltip show/hide (used by both the Tooltip helper and widgets that
-- already own mouse handlers, like buttons).
local function ShowTip(owner, text)
	if text and text ~= "" then
		InitializeTooltip(InformationTooltip, owner, TOPLEFT, 0, 4, BOTTOMLEFT)
		SetTooltipText(InformationTooltip, text)
	end
end
local function HideTip()
	ClearTooltip(InformationTooltip)
end

-- Filled backdrop panel. Backdrops are for VISUALS only — they do not reliably
-- receive mouse input, so anything clickable must be built on a CT_CONTROL base
-- (see Clickable) with a backdrop as a child.
function QAT.widgets.Panel(parent, name, center, edge)
	local c = WM:CreateControl(name, parent, CT_BACKDROP)
	c:SetCenterColor(unpack(center or { 0.07, 0.08, 0.10, 0.95 }))
	c:SetEdgeColor(unpack(edge or { 0, 0, 0, 1 }))
	c:SetEdgeTexture("", 1, 1, 1)
	return c
end

-- A mouse-enabled CT_CONTROL with a fill backdrop child for its background.
-- Returns the control; its backdrop is at control.bg (use control.bg:SetCenterColor).
function QAT.widgets.Clickable(parent, name, center)
	local c = WM:CreateControl(name, parent, CT_CONTROL)
	c:SetMouseEnabled(true)
	local bg = WM:CreateControl(name .. "_Bg", c, CT_BACKDROP)
	bg:SetAnchorFill()
	bg:SetCenterColor(unpack(center or { 0, 0, 0, 0 }))
	bg:SetEdgeColor(0, 0, 0, 0)
	bg:SetEdgeTexture("", 1, 1, 1)
	c.bg = bg
	return c
end

function QAT.widgets.Label(parent, name, text, font)
	local l = WM:CreateControl(name, parent, CT_LABEL)
	l:SetFont(font or FONT)
	l:SetColor(0.9, 0.92, 0.95, 1)
	l:SetVerticalAlignment(TEXT_ALIGN_CENTER)
	l:SetText(text or "")
	return l
end

-- A text button (CT_CONTROL base + backdrop visual), fires onClick on left
-- mouse-up inside. Supports a persistent selected state (button:SetSelected(bool))
-- that survives hover, for tab/chip-style toggles.
local IDLE_COLOR = C.btnBg
local SELECTED_COLOR = C.selBg

local BTN_H = 24 -- default button height
local BTN_PAD = 14 -- horizontal padding around a button's text

function QAT.widgets.TextButton(parent, name, text, onClick)
	local b = QAT.widgets.Clickable(parent, name, IDLE_COLOR)
	b.bg:SetEdgeColor(unpack(C.btnEdge))
	b.baseColor = IDLE_COLOR
	b.onClick = onClick -- read at fire time, so a pooled button can be rebound
	b.minWidth = 0
	local label = QAT.widgets.Label(b, name .. "_Label", text)
	label:SetAnchor(CENTER)
	label:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
	label:SetMaxLineCount(1) -- never wrap; keep button text on one line
	b.label = label
	b:SetHeight(BTN_H)

	-- Buttons size to their text (+ padding) so labels never clip and rows can be
	-- laid out by chaining widths with a single gap. SetText refits.
	function b:FitWidth()
		local w = math.ceil(self.label:GetTextWidth()) + BTN_PAD * 2
		self:SetWidth(math.max(self.minWidth or 0, w))
		return self
	end
	function b:SetText(t)
		self.label:SetText(t or "")
		self:FitWidth()
	end
	function b:SetMinWidth(w)
		self.minWidth = w or 0
		self:FitWidth()
	end
	b:FitWidth()

	function b:SetSelected(sel)
		self.baseColor = sel and SELECTED_COLOR or IDLE_COLOR
		self.bg:SetCenterColor(unpack(self.baseColor))
	end

	-- Tooltip text is read at hover time, so a pooled button can be re-described.
	function b:SetTooltip(text)
		self.tooltipText = text
	end

	b:SetHandler("OnMouseEnter", function(self)
		local c = self.baseColor
		self.bg:SetCenterColor(c[1] + 0.06, c[2] + 0.07, c[3] + 0.08, 1)
		ShowTip(self, self.tooltipText)
	end)
	b:SetHandler("OnMouseExit", function(self)
		self.bg:SetCenterColor(unpack(self.baseColor))
		HideTip()
	end)
	b:SetHandler("OnMouseUp", function(self, button, upInside)
		if upInside and button == MOUSE_BUTTON_INDEX_LEFT and self.onClick then
			self.onClick()
		end
	end)
	return b
end

-- A checkbox (CT_CONTROL base + backdrop visual). The toggle callback is read from
-- box.onToggle at fire time (rebindable per render, so a pooled box can be reused).
function QAT.widgets.Checkbox(parent, name, checked, onToggle)
	local box = QAT.widgets.Clickable(parent, name, { 0.10, 0.11, 0.13, 1 })
	box.bg:SetEdgeColor(0, 0, 0, 1)
	box:SetDimensions(18, 18)
	box.onToggle = onToggle
	local tick = QAT.widgets.Label(box, name .. "_Tick", checked and "x" or "")
	tick:SetAnchor(CENTER)
	tick:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
	box.checked = checked
	function box:SetChecked(v)
		self.checked = v
		tick:SetText(v and "x" or "")
	end
	box:SetHandler("OnMouseUp", function(self, button, upInside)
		if upInside and button == MOUSE_BUTTON_INDEX_LEFT then
			self:SetChecked(not self.checked)
			if self.onToggle then
				self.onToggle(self.checked)
			end
		end
	end)
	return box
end

-- A clickable icon: a mouse-enabled CT_CONTROL with a CT_TEXTURE child (a bare
-- texture, like a bare backdrop, does not reliably receive mouse input). The
-- click callback is read from button.onClick at fire time (rebindable per render).
function QAT.widgets.IconButton(parent, name, texture, size, onClick)
	local b = WM:CreateControl(name, parent, CT_CONTROL)
	b:SetMouseEnabled(true)
	b:SetDimensions(size, size)
	b.onClick = onClick
	local tex = WM:CreateControl(name .. "_Tex", b, CT_TEXTURE)
	tex:SetAnchorFill()
	if texture then
		tex:SetTexture(texture)
	end
	b.tex = tex
	function b:SetTexture(t)
		tex:SetTexture(t)
	end
	function b:SetTextureColor(...)
		tex:SetColor(...)
	end
	b:SetHandler("OnMouseUp", function(self, button, upInside)
		if upInside and button == MOUSE_BUTTON_INDEX_LEFT and self.onClick then
			self.onClick()
		end
	end)
	return b
end

-- A framed icon "well": a bordered backdrop with the texture inset inside it, so a
-- display icon reads as a deliberate slot rather than a floating texture. Exposes
-- :SetTexture(t) and :SetTextureColor(...).
function QAT.widgets.IconWell(parent, name, size)
	local frame = QAT.widgets.Panel(parent, name, { 0.05, 0.06, 0.08, 1 }, C.fieldEdge)
	frame:SetDimensions(size, size)
	local tex = WM:CreateControl(name .. "_Tex", frame, CT_TEXTURE)
	tex:SetAnchor(TOPLEFT, frame, TOPLEFT, 1, 1)
	tex:SetAnchor(BOTTOMRIGHT, frame, BOTTOMRIGHT, -1, -1)
	frame.tex = tex
	function frame:SetTexture(t)
		tex:SetTexture(t)
	end
	function frame:SetTextureColor(...)
		tex:SetColor(...)
	end
	return frame
end

-- Attach a hover tooltip to a control. A TextButton routes through its own
-- handler-aware SetTooltip (so its hover colouring survives); other controls get
-- enter/exit handlers installed here (use on passive controls like labels). Text
-- is read at hover time, so a pooled control can be re-described each render.
function QAT.widgets.Tooltip(control, text)
	if control.SetTooltip then -- TextButton: keeps its existing hover handlers
		control:SetTooltip(text)
		return control
	end
	control.tooltipText = text
	if control.qatTooltipBound then
		return control
	end
	control.qatTooltipBound = true
	control:SetMouseEnabled(true)
	control:SetHandler("OnMouseEnter", function(self)
		ShowTip(self, self.tooltipText)
	end)
	control:SetHandler("OnMouseExit", HideTip)
	return control
end

-- A 1px horizontal rule for separating sections. Anchor it yourself (left/right).
function QAT.widgets.Divider(parent, name)
	local d = WM:CreateControl(name, parent, CT_BACKDROP)
	d:SetHeight(1)
	d:SetCenterColor(0.30, 0.34, 0.42, 0.7)
	d:SetEdgeColor(0, 0, 0, 0)
	d:SetEdgeTexture("", 1, 1, 1)
	return d
end

-- A bold section header label.
function QAT.widgets.SectionHeader(parent, name, text)
	local l = QAT.widgets.Label(parent, name, text, "$(BOLD_FONT)|18|soft-shadow-thin")
	l:SetColor(0.55, 0.72, 0.95, 1)
	return l
end

-- A horizontal slider (custom: a track + a draggable thumb). onChange(value) fires
-- while dragging. Use :SetMinMax(min, max) and :SetValue(v). Integer-ish values are
-- the caller's concern (floor in onChange).
local SLIDER_THUMB_W = 12
function QAT.widgets.Slider(parent, name, width, onChange)
	local s = WM:CreateControl(name, parent, CT_CONTROL)
	s:SetDimensions(width, 18)
	s:SetMouseEnabled(true)
	s.min, s.max, s.value, s.width = 0, 1, 0, width
	s.onChange = onChange

	local track = QAT.widgets.Panel(s, name .. "_Track", { 0.05, 0.06, 0.08, 1 }, C.fieldEdge)
	track:SetHeight(6)
	track:SetAnchor(LEFT, s, LEFT, 0, 0)
	track:SetAnchor(RIGHT, s, RIGHT, 0, 0)

	local thumb = QAT.widgets.Panel(s, name .. "_Thumb", { 0.42, 0.52, 0.68, 1 }, C.btnEdge)
	thumb:SetDimensions(SLIDER_THUMB_W, 16)
	s.thumb = thumb

	local function fraction(v)
		if s.max <= s.min then
			return 0
		end
		return zo_clamp((v - s.min) / (s.max - s.min), 0, 1)
	end
	local function placeThumb(frac)
		thumb:ClearAnchors()
		thumb:SetAnchor(LEFT, s, LEFT, frac * (s.width - SLIDER_THUMB_W), 0)
	end

	function s:SetMinMax(mn, mx)
		self.min, self.max = mn, mx
		placeThumb(fraction(self.value))
	end
	function s:SetValue(v)
		self.value = v
		placeThumb(fraction(v))
	end

	local function updateFromMouse()
		local mx = GetUIMousePosition()
		local frac = zo_clamp((mx - s:GetLeft() - SLIDER_THUMB_W / 2) / (s.width - SLIDER_THUMB_W), 0, 1)
		s.value = s.min + frac * (s.max - s.min)
		placeThumb(frac)
		if s.onChange then
			s.onChange(s.value)
		end
	end
	s:SetHandler("OnMouseDown", function()
		s.dragging = true
		updateFromMouse()
	end)
	s:SetHandler("OnMouseUp", function()
		s.dragging = false
	end)
	s:SetHandler("OnUpdate", function()
		if s.dragging then
			updateFromMouse()
		end
	end)
	return s
end

-- A single-line text entry (backdrop + ZO_DefaultEditForBackdrop edit box).
-- The commit callback is read from frame.onChange at fire time (not captured), so
-- a pooled box can be rebound to the current target on each render. Commits on
-- focus loss or Enter, but ONLY when the text actually changed since it was last
-- set/committed — otherwise hiding a focused box (which fires OnFocusLost) would
-- spuriously re-commit and, if onChange re-renders, recurse.
function QAT.widgets.EditBox(parent, name, width, height, initial, onChange)
	local frame = QAT.widgets.Panel(parent, name, C.fieldBg, C.fieldEdge)
	frame:SetDimensions(width, height or 24)
	frame.onChange = onChange
	frame._committed = initial or ""
	local edit = CreateControlFromVirtual(name .. "_Edit", frame, "ZO_DefaultEditForBackdrop")
	edit:SetAnchor(TOPLEFT, frame, TOPLEFT, 6, 0)
	edit:SetAnchor(BOTTOMRIGHT, frame, BOTTOMRIGHT, -6, 0)
	edit:SetText(initial or "")
	edit:SetHandler("OnEnter", function(self)
		self:LoseFocus()
	end)
	edit:SetHandler("OnFocusLost", function(self)
		local t = self:GetText()
		if t == frame._committed then
			return -- unchanged; don't re-fire (prevents SetHidden -> commit loops)
		end
		frame._committed = t
		if frame.onChange then
			frame.onChange(t)
		end
	end)
	frame.edit = edit
	function frame:SetText(t)
		t = t or ""
		self._committed = t -- programmatic set is the new baseline, not a user edit
		edit:SetText(t)
	end
	function frame:GetText()
		return edit:GetText()
	end
	return frame
end

-- A dropdown (CT_CONTROL base). options = { { label=, value= }, ... }.
-- The select callback is read from dd.onSelect at fire time (rebindable per
-- render). Options can be replaced with dd:SetOptions(options). The option list
-- draws above siblings (DT_HIGH).
function QAT.widgets.Dropdown(parent, name, width, options, current, onSelect)
	local dd = QAT.widgets.Clickable(parent, name, C.ddBg)
	dd.bg:SetEdgeColor(unpack(C.fieldEdge))
	dd:SetDimensions(width, 24)
	dd.onSelect = onSelect
	dd.options = options or {}

	-- Down-arrow on the right marks this as a dropdown (vs a plain box).
	local arrow = WM:CreateControl(name .. "_Arrow", dd, CT_TEXTURE)
	arrow:SetTexture(DROPDOWN_ARROW)
	arrow:SetColor(0.75, 0.80, 0.88, 1)
	arrow:SetDimensions(14, 14)
	arrow:SetAnchor(RIGHT, dd, RIGHT, -6, 0)

	local label = QAT.widgets.Label(dd, name .. "_Label", "")
	label:SetAnchor(LEFT, dd, LEFT, 8, 0)
	label:SetAnchor(RIGHT, arrow, LEFT, -4, 0)
	label:SetMaxLineCount(1) -- truncate rather than wrap (e.g. "Set Background Color")

	local function labelFor(val)
		for _, o in ipairs(dd.options) do
			if o.value == val then
				return o.label
			end
		end
		return val == nil and "" or tostring(val)
	end

	local list = WM:CreateControl(name .. "_List", dd, CT_CONTROL)
	list:SetAnchor(TOPLEFT, dd, BOTTOMLEFT, 0, 2)
	list:SetDrawTier(DT_HIGH)
	list:SetHidden(true)
	local listBg = QAT.widgets.Panel(list, name .. "_ListBg", { 0.11, 0.12, 0.15, 1 }, C.fieldEdge)
	listBg:SetAnchorFill()
	local optControls = {}

	-- (Re)build the option rows. Option controls are pooled by index since ESO
	-- controls cannot be destroyed.
	function dd:SetOptions(opts)
		self.options = opts or {}
		list:SetDimensions(width, math.max(1, #self.options) * 24)
		for i, o in ipairs(self.options) do
			local opt = optControls[i]
			if not opt then
				opt = QAT.widgets.Clickable(list, name .. "_Opt" .. i, { 0, 0, 0, 0 })
				opt:SetDimensions(width, 24)
				opt:SetAnchor(TOPLEFT, list, TOPLEFT, 0, (i - 1) * 24)
				opt.label = QAT.widgets.Label(opt, name .. "_Opt" .. i .. "_L", "")
				opt.label:SetAnchor(LEFT, opt, LEFT, 8, 0)
				opt.label:SetAnchor(RIGHT, opt, RIGHT, -6, 0)
				opt.label:SetMaxLineCount(1)
				opt:SetHandler("OnMouseEnter", function(self2)
					self2.bg:SetCenterColor(0.22, 0.25, 0.30, 1)
				end)
				opt:SetHandler("OnMouseExit", function(self2)
					self2.bg:SetCenterColor(0, 0, 0, 0)
				end)
				opt:SetHandler("OnMouseUp", function(self2, button, upInside)
					if upInside and button == MOUSE_BUTTON_INDEX_LEFT then
						dd.value = self2.optValue
						label:SetText(labelFor(self2.optValue))
						list:SetHidden(true)
						if dd.onSelect then
							dd.onSelect(self2.optValue)
						end
					end
				end)
				optControls[i] = opt
			end
			opt.optValue = o.value
			opt.label:SetText(o.label)
			opt:SetHidden(false)
		end
		for i = #self.options + 1, #optControls do
			optControls[i]:SetHidden(true)
		end
	end

	dd:SetHandler("OnMouseUp", function(_, button, upInside)
		if upInside and button == MOUSE_BUTTON_INDEX_LEFT then
			list:SetHidden(not list:IsHidden())
		end
	end)
	function dd:SetValue(v)
		dd.value = v
		label:SetText(labelFor(v))
	end

	dd:SetOptions(dd.options)
	dd:SetValue(current)
	return dd
end

-- A color swatch button that opens the native color picker. The change callback
-- is read from sw.onChange at fire time (rebindable per render). onChange({r,g,b,a}).
function QAT.widgets.ColorSwatch(parent, name, size, color, onChange)
	local sw = QAT.widgets.Clickable(parent, name)
	sw:SetDimensions(size, size)
	sw.color = color or { 1, 1, 1, 1 }
	sw.onChange = onChange
	sw.bg:SetCenterColor(unpack(sw.color))
	sw.bg:SetEdgeColor(unpack(C.fieldEdge)) -- light frame so a black swatch is still visible
	sw:SetHandler("OnMouseUp", function(_, button, upInside)
		if upInside and button == MOUSE_BUTTON_INDEX_LEFT then
			local c = sw.color
			COLOR_PICKER:Show(function(r, g, b, a)
				sw.color = { r, g, b, a }
				sw.bg:SetCenterColor(r, g, b, a)
				if sw.onChange then
					sw.onChange(sw.color)
				end
			end, c[1], c[2], c[3], c[4] or 1)
		end
	end)
	function sw:SetColor(c)
		sw.color = c
		sw.bg:SetCenterColor(unpack(c))
	end
	return sw
end

-- A control pool keyed by name. ESO controls cannot be destroyed, so dynamic
-- content reuses controls across rebuilds: call Begin, then Get each control you
-- need (created once, reused and unhidden thereafter), then End to hide any that
-- were not used this pass.
function QAT.widgets.NewPool()
	return { cache = {}, used = {} }
end

function QAT.widgets.PoolBegin(pool)
	pool.used = {}
end

-- factory() must create and return a control; it runs only the first time a given
-- name is requested.
function QAT.widgets.PoolGet(pool, name, factory)
	local c = pool.cache[name]
	if not c then
		c = factory()
		pool.cache[name] = c
	end
	pool.used[name] = true
	c:SetHidden(false)
	return c
end

function QAT.widgets.PoolEnd(pool)
	for name, c in pairs(pool.cache) do
		if not pool.used[name] then
			c:SetHidden(true)
		end
	end
end

-- Notify all views that a tracker's def changed (inspector, tree, graph refresh).
function QAT.widgets.NotifyTrackerChanged(id)
	CALLBACK_MANAGER:FireCallbacks("QAT_TrackerChanged", id)
end
