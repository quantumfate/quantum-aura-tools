-- Inspector: a persistent header (name, enable, move, pop-out) plus the tab body
-- host (Phases / Conditions / Load). It is bound to a tracker id and renders
-- entirely from that def, refreshing on the "QAT_TrackerChanged" callback, so any
-- number of inspector instances on the same tracker stay in sync.

local WM = GetWindowManager()

local function findDef(defs, id)
	for _, def in ipairs(defs or {}) do
		if def.id == id then
			return def
		end
		if def.children then
			local found = findDef(def.children, id)
			if found then
				return found
			end
		end
	end
	return nil
end
QAT.Editor_FindDef = findDef

function QAT.Editor_Inspector_Build(pane)
	local insp = QAT.editor.inspector or {}
	QAT.editor.inspector = insp

	-- Persistent header (top strip, above the tab bar).
	local header = QAT.widgets.Panel(pane, "QAT_Insp_Header", { 0.10, 0.11, 0.14, 1 })
	header:SetAnchor(TOPLEFT, pane, TOPLEFT, 0, 0)
	header:SetAnchor(TOPRIGHT, pane, TOPRIGHT, 0, 0)
	header:SetHeight(QAT.editor.HEADER_H)
	insp.header = header

	local nameLabel = QAT.widgets.Label(header, "QAT_Insp_Name", "(no tracker selected)")
	nameLabel:SetAnchor(TOPLEFT, header, TOPLEFT, 10, 6)
	insp.nameLabel = nameLabel

	insp.enable = QAT.widgets.TextButton(header, "QAT_Insp_Enable", "Enabled", function()
		local def = insp.currentId and findDef(QAT.sv.trackers, insp.currentId)
		if def then
			def.enabled = not (def.enabled ~= false)
			QAT.widgets.NotifyTrackerChanged(def.id)
			QAT.Editor_Inspector_Show(def.id)
		end
	end)
	insp.enable:SetDimensions(80, 22)
	insp.enable:SetAnchor(BOTTOMLEFT, header, BOTTOMLEFT, 10, -6)

	insp.move = QAT.widgets.TextButton(header, "QAT_Insp_Move", "Move on screen", function()
		if QAT.Editor_MoveTracker and insp.currentId then
			QAT.Editor_MoveTracker(insp.currentId)
		end
	end)
	insp.move:SetDimensions(120, 22)
	insp.move:SetAnchor(LEFT, insp.enable, RIGHT, 6, 0)

	insp.popout = QAT.widgets.TextButton(header, "QAT_Insp_Popout", "Pop out", function()
		d(QAT.displayName .. ": detachable inspector is not yet available.")
	end)
	insp.popout:SetDimensions(70, 22)
	insp.popout:SetAnchor(LEFT, insp.move, RIGHT, 6, 0)

	-- Tab body host (below the tab bar).
	local body = QAT.widgets.Panel(pane, "QAT_Insp_Body", { 0.06, 0.07, 0.09, 1 })
	body:SetAnchor(TOPLEFT, pane, TOPLEFT, 0, QAT.editor.HEADER_H + QAT.editor.TAB_H)
	body:SetAnchor(BOTTOMRIGHT, pane, BOTTOMRIGHT, 0, 0)
	insp.body = body

	local placeholder = QAT.widgets.Label(body, "QAT_Insp_Placeholder", "")
	placeholder:SetAnchor(TOPLEFT, body, TOPLEFT, 12, 12)
	placeholder:SetAnchor(TOPRIGHT, body, TOPRIGHT, -12, 12)
	placeholder:SetVerticalAlignment(TEXT_ALIGN_TOP)
	insp.placeholder = placeholder

	-- One container per tab, each filling the body; only the active one is shown.
	insp.tabContainers = {}
	for _, tabName in ipairs({ "Phases", "Conditions", "Load" }) do
		local c = WM:CreateControl("QAT_Insp_Tab_" .. tabName, body, CT_CONTROL)
		c:SetAnchor(TOPLEFT, body, TOPLEFT, 0, 0)
		c:SetAnchor(BOTTOMRIGHT, body, BOTTOMRIGHT, 0, 0)
		c:SetHidden(true)
		insp.tabContainers[tabName] = c
	end

	-- Start with nothing selected: hide the per-tracker actions and tabs.
	QAT.Editor_Inspector_Show(nil)
end

-- Tab modules register their renderer here: QAT.editor.tabRenderers[name](container, def).
QAT.editor.tabRenderers = QAT.editor.tabRenderers or {}

local function refreshBody()
	local insp = QAT.editor.inspector
	if not insp then
		return
	end
	local tab = QAT.editor.activeTab or "Phases"
	local def = insp.currentId and findDef(QAT.sv.trackers, insp.currentId)

	for _, container in pairs(insp.tabContainers or {}) do
		container:SetHidden(true)
	end

	if not def then
		insp.placeholder:SetHidden(false)
		insp.placeholder:SetText("Select a tracker in the tree, or add one with + Tracker.")
		return
	end
	insp.placeholder:SetHidden(true)

	local container = insp.tabContainers and insp.tabContainers[tab]
	local renderer = QAT.editor.tabRenderers[tab]
	if container and renderer then
		container:SetHidden(false)
		QAT.Safe("tab " .. tab, function()
			renderer(container, def)
		end)
	end
end
QAT.Editor_Inspector_Refresh = refreshBody

function QAT.Editor_Inspector_Show(id)
	local insp = QAT.editor.inspector
	if not insp then
		return
	end
	insp.currentId = id
	local def = id and findDef(QAT.sv.trackers, id)

	-- The per-tracker actions and tabs are meaningless with nothing selected.
	insp.enable:SetHidden(not def)
	insp.move:SetHidden(not def)
	insp.popout:SetHidden(not def)
	if QAT.editor.tabBar then
		QAT.editor.tabBar:SetHidden(not def)
	end

	insp.nameLabel:SetText(def and (def.name or def.id) or "(no tracker selected)")
	if def then
		insp.enable.label:SetText(def.enabled ~= false and "Enabled" or "Disabled")
	end
	refreshBody()
end

function QAT.Editor_Inspector_SetTab(_)
	refreshBody()
end

function QAT.Editor_Inspector_Relayout()
	-- Header/body anchor to the pane; nothing extra yet.
end

CALLBACK_MANAGER:RegisterCallback("QAT_TrackerChanged", function(id)
	local insp = QAT.editor.inspector
	if insp and insp.currentId == id then
		QAT.Editor_Inspector_Show(id)
	end
end)
