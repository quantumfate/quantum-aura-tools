-- Small UI widget helpers for the editor (plain ESO controls; no DOM here).

QAT.widgets = {}

local WM = GetWindowManager()
local FONT = "$(MEDIUM_FONT)|18|soft-shadow-thin"

-- Filled backdrop panel.
function QAT.widgets.Panel(parent, name, center, edge)
	local c = WM:CreateControl(name, parent, CT_BACKDROP)
	c:SetCenterColor(unpack(center or { 0.07, 0.08, 0.10, 0.95 }))
	c:SetEdgeColor(unpack(edge or { 0, 0, 0, 1 }))
	c:SetEdgeTexture("", 1, 1, 1)
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

-- A text button: backdrop + label, fires onClick on left mouse-up inside.
function QAT.widgets.TextButton(parent, name, text, onClick)
	local b = QAT.widgets.Panel(parent, name, { 0.16, 0.18, 0.22, 1 })
	b:SetMouseEnabled(true)
	local label = QAT.widgets.Label(b, name .. "_Label", text)
	label:SetAnchor(CENTER)
	label:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
	b.label = label
	b:SetHandler("OnMouseEnter", function(self)
		self:SetCenterColor(0.22, 0.25, 0.30, 1)
	end)
	b:SetHandler("OnMouseExit", function(self)
		self:SetCenterColor(0.16, 0.18, 0.22, 1)
	end)
	-- Consume the press so a movable parent window does not capture it as a drag.
	b:SetHandler("OnMouseDown", function() end)
	b:SetHandler("OnMouseUp", function(_, button, upInside)
		if QAT.log then
			QAT.log.editor:Debug(
				"button '%s' OnMouseUp button=%s upInside=%s",
				name,
				tostring(button),
				tostring(upInside)
			)
		end
		if upInside and button == MOUSE_BUTTON_INDEX_LEFT and onClick then
			onClick()
		end
	end)
	return b
end

-- A labeled checkbox; onToggle(checked) on click.
function QAT.widgets.Checkbox(parent, name, checked, onToggle)
	local box = QAT.widgets.Panel(parent, name, { 0.10, 0.11, 0.13, 1 })
	box:SetDimensions(18, 18)
	box:SetMouseEnabled(true)
	local tick = QAT.widgets.Label(box, name .. "_Tick", checked and "x" or "")
	tick:SetAnchor(CENTER)
	tick:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
	box.checked = checked
	function box:SetChecked(v)
		self.checked = v
		tick:SetText(v and "x" or "")
	end
	box:SetHandler("OnMouseDown", function() end)
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
