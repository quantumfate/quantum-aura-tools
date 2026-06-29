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
-- mouse-up inside.
function QAT.widgets.TextButton(parent, name, text, onClick)
	local b = QAT.widgets.Clickable(parent, name, { 0.16, 0.18, 0.22, 1 })
	b.bg:SetEdgeColor(0, 0, 0, 1)
	local label = QAT.widgets.Label(b, name .. "_Label", text)
	label:SetAnchor(CENTER)
	label:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
	b.label = label
	b:SetHandler("OnMouseEnter", function(self)
		self.bg:SetCenterColor(0.22, 0.25, 0.30, 1)
	end)
	b:SetHandler("OnMouseExit", function(self)
		self.bg:SetCenterColor(0.16, 0.18, 0.22, 1)
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

-- Notify all views that a tracker's def changed (inspector, tree, graph refresh).
function QAT.widgets.NotifyTrackerChanged(id)
	CALLBACK_MANAGER:FireCallbacks("QAT_TrackerChanged", id)
end
