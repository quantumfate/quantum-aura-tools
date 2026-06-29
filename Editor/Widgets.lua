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
	b:SetHandler("OnMouseUp", function(_, button, upInside)
		if upInside and button == MOUSE_BUTTON_INDEX_LEFT and onClick then
			onClick()
		end
	end)
	return b
end

-- A labeled checkbox (CT_CONTROL base + backdrop visual); onToggle(checked) on click.
function QAT.widgets.Checkbox(parent, name, checked, onToggle)
	local box = QAT.widgets.Clickable(parent, name, { 0.10, 0.11, 0.13, 1 })
	box.bg:SetEdgeColor(0, 0, 0, 1)
	box:SetDimensions(18, 18)
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
			if onToggle then
				onToggle(self.checked)
			end
		end
	end)
	return box
end

-- A bold section header label.
function QAT.widgets.SectionHeader(parent, name, text)
	local l = QAT.widgets.Label(parent, name, text, "$(BOLD_FONT)|18|soft-shadow-thin")
	l:SetColor(0.55, 0.72, 0.95, 1)
	return l
end

-- A single-line text entry (backdrop + ZO_DefaultEditForBackdrop edit box).
-- onChange(text) fires when the field commits (focus lost or Enter).
function QAT.widgets.EditBox(parent, name, width, height, initial, onChange)
	local frame = QAT.widgets.Panel(parent, name, { 0.03, 0.04, 0.05, 1 })
	frame:SetDimensions(width, height or 24)
	local edit = CreateControlFromVirtual(name .. "_Edit", frame, "ZO_DefaultEditForBackdrop")
	edit:SetAnchor(TOPLEFT, frame, TOPLEFT, 4, 0)
	edit:SetAnchor(BOTTOMRIGHT, frame, BOTTOMRIGHT, -4, 0)
	edit:SetText(initial or "")
	edit:SetHandler("OnEnter", function(self)
		self:LoseFocus()
	end)
	edit:SetHandler("OnFocusLost", function(self)
		if onChange then
			onChange(self:GetText())
		end
	end)
	frame.edit = edit
	function frame:SetText(t)
		edit:SetText(t or "")
	end
	function frame:GetText()
		return edit:GetText()
	end
	return frame
end

-- A dropdown (CT_CONTROL base). options = { { label=, value= }, ... }.
-- onSelect(value) fires on choice. The option list draws above siblings (DT_HIGH).
function QAT.widgets.Dropdown(parent, name, width, options, current, onSelect)
	local dd = QAT.widgets.Clickable(parent, name, { 0.12, 0.13, 0.16, 1 })
	dd.bg:SetEdgeColor(0, 0, 0, 1)
	dd:SetDimensions(width, 24)

	local label = QAT.widgets.Label(dd, name .. "_Label", "")
	label:SetAnchor(LEFT, dd, LEFT, 6, 0)
	label:SetAnchor(RIGHT, dd, RIGHT, -6, 0)

	local function labelFor(val)
		for _, o in ipairs(options) do
			if o.value == val then
				return o.label
			end
		end
		return tostring(val)
	end
	dd.value = current
	label:SetText(labelFor(current))

	local list = WM:CreateControl(name .. "_List", dd, CT_CONTROL)
	list:SetAnchor(TOPLEFT, dd, BOTTOMLEFT, 0, 2)
	list:SetDimensions(width, #options * 24)
	list:SetDrawTier(DT_HIGH)
	list:SetHidden(true)
	local listBg = QAT.widgets.Panel(list, name .. "_ListBg", { 0.10, 0.11, 0.13, 1 })
	listBg:SetAnchorFill()

	for i, o in ipairs(options) do
		local opt = QAT.widgets.Clickable(list, name .. "_Opt" .. i, { 0, 0, 0, 0 })
		opt:SetDimensions(width, 24)
		opt:SetAnchor(TOPLEFT, list, TOPLEFT, 0, (i - 1) * 24)
		local ol = QAT.widgets.Label(opt, name .. "_Opt" .. i .. "_L", o.label)
		ol:SetAnchor(LEFT, opt, LEFT, 6, 0)
		opt:SetHandler("OnMouseEnter", function(self)
			self.bg:SetCenterColor(0.22, 0.25, 0.30, 1)
		end)
		opt:SetHandler("OnMouseExit", function(self)
			self.bg:SetCenterColor(0, 0, 0, 0)
		end)
		opt:SetHandler("OnMouseUp", function(_, button, upInside)
			if upInside and button == MOUSE_BUTTON_INDEX_LEFT then
				dd.value = o.value
				label:SetText(o.label)
				list:SetHidden(true)
				if onSelect then
					onSelect(o.value)
				end
			end
		end)
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
	return dd
end

-- A color swatch button that opens the native color picker. onChange({r,g,b,a}).
function QAT.widgets.ColorSwatch(parent, name, size, color, onChange)
	local sw = QAT.widgets.Clickable(parent, name)
	sw:SetDimensions(size, size)
	sw.color = color or { 1, 1, 1, 1 }
	sw.bg:SetCenterColor(unpack(sw.color))
	sw.bg:SetEdgeColor(0, 0, 0, 1)
	sw:SetHandler("OnMouseUp", function(_, button, upInside)
		if upInside and button == MOUSE_BUTTON_INDEX_LEFT then
			local c = sw.color
			COLOR_PICKER:Show(function(r, g, b, a)
				sw.color = { r, g, b, a }
				sw.bg:SetCenterColor(r, g, b, a)
				if onChange then
					onChange(sw.color)
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
