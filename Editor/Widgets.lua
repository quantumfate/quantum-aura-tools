-- Small UI widget helpers for the editor (plain ESO controls; no DOM here).

QAT.widgets = {}

local WM = GetWindowManager()
local FONT = "$(MEDIUM_FONT)|18|soft-shadow-thin"

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
local IDLE_COLOR = { 0.16, 0.18, 0.22, 1 }
local SELECTED_COLOR = { 0.20, 0.30, 0.45, 1 }

function QAT.widgets.TextButton(parent, name, text, onClick)
	local b = QAT.widgets.Clickable(parent, name, IDLE_COLOR)
	b.bg:SetEdgeColor(0, 0, 0, 1)
	b.baseColor = IDLE_COLOR
	b.onClick = onClick -- read at fire time, so a pooled button can be rebound
	local label = QAT.widgets.Label(b, name .. "_Label", text)
	label:SetAnchor(CENTER)
	label:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
	b.label = label

	function b:SetSelected(sel)
		self.baseColor = sel and SELECTED_COLOR or IDLE_COLOR
		self.bg:SetCenterColor(unpack(self.baseColor))
	end

	b:SetHandler("OnMouseEnter", function(self)
		local c = self.baseColor
		self.bg:SetCenterColor(c[1] + 0.06, c[2] + 0.07, c[3] + 0.08, 1)
	end)
	b:SetHandler("OnMouseExit", function(self)
		self.bg:SetCenterColor(unpack(self.baseColor))
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

-- Attach a hover tooltip to a control. Enables mouse on the control and installs
-- enter/exit handlers, so use it on passive controls (labels) rather than on
-- interactive widgets that already own OnMouseEnter/Exit (buttons, dropdowns).
-- The text is read from control.tooltipText at hover time, so it can be re-set on
-- a pooled control each render.
function QAT.widgets.Tooltip(control, text)
	control.tooltipText = text
	if control.qatTooltipBound then
		return control
	end
	control.qatTooltipBound = true
	control:SetMouseEnabled(true)
	control:SetHandler("OnMouseEnter", function(self)
		if self.tooltipText and self.tooltipText ~= "" then
			InitializeTooltip(InformationTooltip, self, TOPLEFT, 0, 4, BOTTOMLEFT)
			SetTooltipText(InformationTooltip, self.tooltipText)
		end
	end)
	control:SetHandler("OnMouseExit", function()
		ClearTooltip(InformationTooltip)
	end)
	return control
end

-- A bold section header label.
function QAT.widgets.SectionHeader(parent, name, text)
	local l = QAT.widgets.Label(parent, name, text, "$(BOLD_FONT)|18|soft-shadow-thin")
	l:SetColor(0.55, 0.72, 0.95, 1)
	return l
end

-- A single-line text entry (backdrop + ZO_DefaultEditForBackdrop edit box).
-- The commit callback is read from frame.onChange at fire time (not captured), so
-- a pooled box can be rebound to the current target on each render. Commits on
-- focus loss or Enter, but ONLY when the text actually changed since it was last
-- set/committed — otherwise hiding a focused box (which fires OnFocusLost) would
-- spuriously re-commit and, if onChange re-renders, recurse.
function QAT.widgets.EditBox(parent, name, width, height, initial, onChange)
	local frame = QAT.widgets.Panel(parent, name, { 0.03, 0.04, 0.05, 1 })
	frame:SetDimensions(width, height or 24)
	frame.onChange = onChange
	frame._committed = initial or ""
	local edit = CreateControlFromVirtual(name .. "_Edit", frame, "ZO_DefaultEditForBackdrop")
	edit:SetAnchor(TOPLEFT, frame, TOPLEFT, 4, 0)
	edit:SetAnchor(BOTTOMRIGHT, frame, BOTTOMRIGHT, -4, 0)
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
	local dd = QAT.widgets.Clickable(parent, name, { 0.12, 0.13, 0.16, 1 })
	dd.bg:SetEdgeColor(0, 0, 0, 1)
	dd:SetDimensions(width, 24)
	dd.onSelect = onSelect
	dd.options = options or {}

	local label = QAT.widgets.Label(dd, name .. "_Label", "")
	label:SetAnchor(LEFT, dd, LEFT, 6, 0)
	label:SetAnchor(RIGHT, dd, RIGHT, -6, 0)

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
	local listBg = QAT.widgets.Panel(list, name .. "_ListBg", { 0.10, 0.11, 0.13, 1 })
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
				opt.label:SetAnchor(LEFT, opt, LEFT, 6, 0)
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
	sw.bg:SetEdgeColor(0, 0, 0, 1)
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
