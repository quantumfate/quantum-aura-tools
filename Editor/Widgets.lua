-- Small UI widget helpers for the editor (plain ESO controls; no DOM here).

QAT.widgets = {}

local WM = GetWindowManager()
local FONT = "$(MEDIUM_FONT)|18|soft-shadow-thin"

-- Optional global UI font (LibMediaProvider, chosen in the settings panel). When set,
-- its face replaces the face token in every kit-built label's font string, so all
-- window chrome adopts it. HUD tracker readouts are untouched — they don't use this
-- kit and carry their own per-phase font. Applied at label creation, so a change
-- takes effect on /reloadui.
local function applyFace(fontString)
	local face = QAT.sv and QAT.util and QAT.util.FontFace(QAT.sv.account.uiFont)
	if not face then
		return fontString
	end
	return face .. (fontString:match("|.*$") or "|18|soft-shadow-thin")
end
QAT.widgets.ApplyUIFace = applyFace

-- Shared palette so inputs, dropdowns and buttons read as one toolkit and stand
-- apart from the panel background.
-- A dark-navy, minimal palette with a blue accent. Shared so the whole editor
-- reads as one modern toolkit.
local C = {
	bodyBg = { 0.045, 0.055, 0.078, 1 }, -- panes / window background
	cardBg = { 0.075, 0.09, 0.125, 1 }, -- grouped "card" sections
	cardEdge = { 0.15, 0.18, 0.25, 1 },
	headerText = { 0.42, 0.50, 0.63, 1 }, -- muted uppercase section labels
	fieldBg = { 0.03, 0.04, 0.06, 1 }, -- text inputs (inset)
	fieldEdge = { 0.21, 0.26, 0.35, 1 }, -- subtle input border
	ddBg = { 0.07, 0.085, 0.12, 1 }, -- dropdowns
	btnBg = { 0.11, 0.13, 0.18, 1 },
	btnEdge = { 0.20, 0.25, 0.34, 1 },
	selBg = { 0.21, 0.40, 0.72, 1 }, -- active tab / chip / selected (blue accent)
}
QAT.widgets.palette = C
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
	l:SetFont(applyFace(font or FONT))
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
			self.onClick(self)
		end
	end)
	return b
end

-- A checkbox (CT_CONTROL base + backdrop visual). The toggle callback is read from
-- box.onToggle at fire time (rebindable per render, so a pooled box can be reused).
function QAT.widgets.Checkbox(parent, name, checked, onToggle)
	local box = QAT.widgets.Clickable(parent, name, checked and C.selBg or C.fieldBg)
	box.bg:SetEdgeColor(unpack(C.fieldEdge)) -- visible border so an empty box still reads
	box:SetDimensions(20, 20)
	box.onToggle = onToggle
	-- Filled blue when checked (not a tiny "x") so the state is legible at a glance.
	local tick = QAT.widgets.Label(box, name .. "_Tick", checked and "x" or "", "$(BOLD_FONT)|18|soft-shadow-thin")
	tick:SetAnchor(CENTER, box, CENTER, 0, -1)
	tick:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
	box.checked = checked
	function box:SetChecked(v)
		self.checked = v
		tick:SetText(v and "x" or "")
		self.bg:SetCenterColor(unpack(v and C.selBg or C.fieldBg))
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
			self.onClick(self)
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

-- Attach a native item tooltip (shows set bonuses on hover) driven by an item link.
-- The link is read at hover time via control.qatItemLink, so it can be rebound.
function QAT.widgets.ItemTooltip(control, link)
	control.qatItemLink = link
	if not control.qatItemTipBound then
		control.qatItemTipBound = true
		control:SetMouseEnabled(true)
		control:SetHandler("OnMouseEnter", function(self)
			if self.qatItemLink and self.qatItemLink ~= "" then
				InitializeTooltip(ItemTooltip, self, RIGHT, -8, 0, LEFT)
				ItemTooltip:SetLink(self.qatItemLink)
			end
		end)
		control:SetHandler("OnMouseExit", function()
			ClearTooltip(ItemTooltip)
		end)
	end
	return control
end

-- A small bordered "pill" chip for tags (e.g. equipment slots). Sizes to its text.
local CHIP_EDGE = { 0.13, 0.19, 0.24, 1 }
function QAT.widgets.Chip(parent, name, text)
	local c = QAT.widgets.Panel(parent, name, { 0.055, 0.106, 0.145, 1 }, CHIP_EDGE)
	local l = QAT.widgets.Label(c, name .. "_L", "", "$(MEDIUM_FONT)|14|soft-shadow-thin")
	l:SetColor(0.66, 0.73, 0.83, 1)
	l:SetAnchor(LEFT, c, LEFT, 6, -1)
	c.label = l
	function c:SetText(t)
		l:SetText(t or "")
		c:SetDimensions(math.ceil(l:GetTextWidth()) + 12, 18)
		-- Re-assert the edge: a CT_BACKDROP border can fail to redraw after a pooled
		-- chip is resized to a new width, so some chips rendered borderless.
		c:SetEdgeColor(unpack(CHIP_EDGE))
		c:SetEdgeTexture("", 1, 1, 1)
	end
	c:SetText(text)
	return c
end

-- A read-only "ability" chip: a small icon tile, the ability's name, and a faint
-- #id, all resolved from an ability id (see QAT.util.AbilityInfo). Sizes to its
-- content and hovers its name. Use anywhere the user would otherwise face a raw id.
function QAT.widgets.AbilityChip(parent, name)
	local c = QAT.widgets.Panel(parent, name, { 0.055, 0.106, 0.145, 1 }, CHIP_EDGE)
	c:SetHeight(24)
	local ic = WM:CreateControl(name .. "_Ic", c, CT_TEXTURE)
	ic:SetDimensions(18, 18)
	ic:SetAnchor(LEFT, c, LEFT, 4, 0)
	local l = QAT.widgets.Label(c, name .. "_L", "", "$(MEDIUM_FONT)|15|soft-shadow-thin")
	l:SetColor(0.80, 0.86, 0.94, 1)
	l:SetAnchor(LEFT, ic, RIGHT, 6, -1)
	c.icon, c.label = ic, l
	QAT.widgets.Tooltip(c, "")
	-- Optional remove affordance: a trailing × that calls onRemove. Created lazily.
	function c:SetRemovable(onRemove)
		self.onRemove = onRemove
		if not self.xb then
			local xb = QAT.widgets.Label(self, name .. "_X", "×", "$(BOLD_FONT)|17|soft-shadow-thin")
			xb:SetMouseEnabled(true)
			xb:SetColor(0.55, 0.62, 0.72, 1)
			xb:SetHandler("OnMouseEnter", function()
				xb:SetColor(0.95, 0.55, 0.55, 1)
			end)
			xb:SetHandler("OnMouseExit", function()
				xb:SetColor(0.55, 0.62, 0.72, 1)
			end)
			xb:SetHandler("OnMouseUp", function(_, b, inside)
				if inside and b == MOUSE_BUTTON_INDEX_LEFT and self.onRemove then
					self.onRemove()
				end
			end)
			self.xb = xb
		end
		self.xb:SetHidden(onRemove == nil)
	end
	-- Set the chip's ability. A 0/nil id shows the "(none)" fallback dimmed.
	function c:SetAbility(id)
		local nm, tex = QAT.util.AbilityInfo(id)
		ic:SetTexture(tex)
		local idText = (id and id ~= 0) and (" |c556070#" .. id .. "|r") or ""
		l:SetText(nm .. idText)
		l:SetColor(0.80, 0.86, 0.94, (id and id ~= 0) and 1 or 0.5)
		self.tooltipText = (id and id ~= 0) and nm or "No ability set"
		local extra = (self.xb and not self.xb:IsHidden()) and 20 or 0
		self:SetWidth(4 + 18 + 6 + math.ceil(l:GetTextWidth()) + 8 + extra)
		if self.xb then
			self.xb:ClearAnchors()
			self.xb:SetAnchor(RIGHT, self, RIGHT, -6, -1)
		end
		-- Re-assert the edge: a CT_BACKDROP border can drop after a pooled resize.
		self:SetEdgeColor(unpack(CHIP_EDGE))
		self:SetEdgeTexture("", 1, 1, 1)
	end
	return c
end

-- A small colored badge (bar mode, INITIAL, ...): a dark bordered box with centered
-- text tinted by rgb. Sizes to its text via :SetText.
function QAT.widgets.Badge(parent, name, text, rgb)
	rgb = rgb or { 0.62, 0.72, 0.90 }
	local b = WM:CreateControl(name, parent, CT_BACKDROP)
	b:SetCenterColor(0.10, 0.13, 0.17, 1)
	b:SetEdgeColor(rgb[1] * 0.6, rgb[2] * 0.6, rgb[3] * 0.6, 1)
	b:SetEdgeTexture("", 1, 1, 1)
	b:SetHeight(16)
	local l = QAT.widgets.Label(b, name .. "_L", "", "$(BOLD_FONT)|14|soft-shadow-thin")
	l:SetColor(rgb[1], rgb[2], rgb[3], 1)
	l:SetAnchor(CENTER, b, CENTER, 0, 0)
	b.label = l
	function b:SetText(t)
		l:SetText(t or "")
		b:SetWidth(math.ceil(l:GetTextWidth()) + 12)
	end
	function b:SetColorRGB(c)
		l:SetColor(c[1], c[2], c[3], 1)
		b:SetEdgeColor(c[1] * 0.6, c[2] * 0.6, c[3] * 0.6, 1)
	end
	b:SetText(text)
	return b
end

-- A bordered close button ("×") that turns red on hover. onClick read at fire time.
function QAT.widgets.CloseButton(parent, name, onClick)
	local b = QAT.widgets.Clickable(parent, name, C.btnBg)
	b.bg:SetEdgeColor(unpack(C.btnEdge))
	b.onClick = onClick
	local l = QAT.widgets.Label(b, name .. "_L", "×", "$(BOLD_FONT)|22|soft-shadow-thin")
	l:SetAnchor(CENTER, b, CENTER, 0, -2)
	l:SetColor(0.75, 0.80, 0.88, 1)
	b:SetHandler("OnMouseEnter", function(self)
		self.bg:SetCenterColor(0.42, 0.13, 0.13, 1)
		l:SetColor(1, 0.85, 0.85, 1)
	end)
	b:SetHandler("OnMouseExit", function(self)
		self.bg:SetCenterColor(unpack(C.btnBg))
		l:SetColor(0.75, 0.80, 0.88, 1)
	end)
	b:SetHandler("OnMouseUp", function(self, button, upInside)
		if upInside and button == MOUSE_BUTTON_INDEX_LEFT and self.onClick then
			self.onClick(self)
		end
	end)
	return b
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

-- A grouped "card" panel: a subtly-bordered box with a muted uppercase title.
-- Content should be anchored inside with padding (card.padX / card.contentY give
-- sensible insets). Reuse-friendly: SetTitle re-labels a pooled card.
function QAT.widgets.Card(parent, name, title)
	local card = WM:CreateControl(name, parent, CT_BACKDROP)
	card:SetCenterColor(unpack(C.cardBg))
	card:SetEdgeColor(unpack(C.cardEdge))
	card:SetEdgeTexture("", 1, 1, 1)
	card.padX, card.contentY = 16, 34
	local t = QAT.widgets.Label(card, name .. "_Title", "", "$(BOLD_FONT)|15|soft-shadow-thin")
	t:SetColor(unpack(C.headerText))
	t:SetAnchor(TOPLEFT, card, TOPLEFT, 16, 11)
	card.titleLabel = t
	function card:SetTitle(s)
		t:SetText(string.upper(s or ""))
	end
	card:SetTitle(title)
	return card
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
	edit:SetFont(applyFace("$(MEDIUM_FONT)|18|soft-shadow-thin"))
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
-- A shared, full-screen top-level layer that hosts open dropdown lists. Because it
-- is its own top-level at DT_HIGH, its rows hit-test above every field in the editor
-- window (a same-window overlay draw tier is not enough to beat an EditBox drawn in
-- another branch, which is why options overlapping a field below were unclickable).
-- The layer itself is mouse-transparent; only the visible list rows capture clicks.
-- Exactly one dropdown list may be open at a time. It is parented to a full-screen
-- "eater" top-level so the list (and its options) hit-test above every field, while a
-- click anywhere outside the list lands on the eater and closes it. A list can never
-- linger and swallow clicks in its region after the dropdown lost focus.
local openList, eater
local function closeDropdowns()
	if openList then
		openList:SetHidden(true)
		openList = nil
	end
	if eater then
		eater:SetHidden(true)
	end
end
QAT.widgets.CloseDropdowns = closeDropdowns

-- The eater must be its own full-screen top-level: as a child of a zero-size control
-- its hit area collapses to nothing, so it never catches the outside click that
-- should close the list. A DT_HIGH top-level hit-tests full-screen above the editor.
local function getEater()
	if not eater then
		eater = WM:CreateTopLevelWindow("QAT_Widgets_DropdownLayer")
		eater:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, 0, 0)
		eater:SetDimensions(GuiRoot:GetWidth(), GuiRoot:GetHeight())
		eater:SetMouseEnabled(true)
		eater:SetDrawTier(DT_HIGH)
		eater:SetHidden(true)
		-- Close on outside click. Defer the hide to the next frame for the same reason
		-- as options: hiding the eater inside its own mouse dispatch would strand the
		-- capture on the hidden eater and swallow later clicks.
		eater:SetHandler("OnMouseDown", function()
			zo_callLater(closeDropdowns, 0)
		end)
	end
	return eater
end

local function openDropdownList(list)
	if openList == list then
		closeDropdowns() -- clicking the open dropdown again closes it
		return
	end
	closeDropdowns() -- only one open at a time
	getEater():SetHidden(false)
	list:SetHidden(false)
	openList = list
end

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

	-- Host the open list on the eater (a full-screen catcher under a DT_HIGH top-level),
	-- anchored to the dropdown. This puts the option rows above every field in the
	-- editor window, so an option overlapping a field below still captures the click,
	-- while a click outside the list hits the eater and closes it.
	local list = WM:CreateControl(name .. "_List", getEater(), CT_CONTROL)
	list:SetAnchor(TOPLEFT, dd, BOTTOMLEFT, 0, 2)
	list:SetDrawTier(DT_HIGH)
	list:SetDrawLayer(DL_OVERLAY)
	list:SetDrawLevel(5)
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
				-- Optional per-option thumbnail, shown when the option carries `.icon`.
				opt.icon = WM:CreateControl(name .. "_Opt" .. i .. "_I", opt, CT_TEXTURE)
				opt.icon:SetDimensions(18, 18)
				opt.icon:SetAnchor(LEFT, opt, LEFT, 6, 0)
				opt.label = QAT.widgets.Label(opt, name .. "_Opt" .. i .. "_L", "")
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
						-- Hiding this option inside its own mouse-up strands ESO's mouse capture
						-- on a now-hidden control and swallows every later click. Defer the close
						-- + rebuild to the next frame, after this dispatch releases the capture.
						local v = self2.optValue
						zo_callLater(function()
							closeDropdowns()
							if dd.onSelect then
								dd.onSelect(v)
							end
						end, 0)
					end
				end)
				optControls[i] = opt
			end
			opt.optValue = o.value
			opt.label:SetText(o.label)
			if o.icon then
				opt.icon:SetTexture(o.icon)
				opt.icon:SetHidden(false)
				opt.label:ClearAnchors()
				opt.label:SetAnchor(LEFT, opt.icon, RIGHT, 6, 0)
				opt.label:SetAnchor(RIGHT, opt, RIGHT, -6, 0)
			else
				opt.icon:SetHidden(true)
				opt.label:ClearAnchors()
				opt.label:SetAnchor(LEFT, opt, LEFT, 8, 0)
				opt.label:SetAnchor(RIGHT, opt, RIGHT, -6, 0)
			end
			opt:SetHidden(false)
		end
		for i = #self.options + 1, #optControls do
			optControls[i]:SetHidden(true)
		end
	end

	dd:SetHandler("OnMouseUp", function(_, button, upInside)
		if upInside and button == MOUSE_BUTTON_INDEX_LEFT then
			openDropdownList(list) -- toggles this list open/closed (single-open + eater)
		end
	end)
	function dd:SetValue(v)
		dd.value = v
		label:SetText(labelFor(v))
	end

	-- Cascade hides to the list: when a pooled dropdown is hidden (or the panel
	-- rebuilds), its list must not linger on the popup layer intercepting clicks.
	local nativeSetHidden = dd.SetHidden
	function dd:SetHidden(h)
		nativeSetHidden(self, h)
		if h and openList == list then
			closeDropdowns()
		end
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
