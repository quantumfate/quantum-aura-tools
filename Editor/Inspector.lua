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

	-- Editable tracker name (organizational; distinct from a phase's drawn label).
	local nameLabelCaption = QAT.widgets.Label(header, "QAT_Insp_NameCaption", "Name")
	nameLabelCaption:SetAnchor(TOPLEFT, header, TOPLEFT, 10, 6)
	insp.nameCaption = nameLabelCaption

	insp.nameBox = QAT.widgets.EditBox(header, "QAT_Insp_NameBox", 220, 22)
	insp.nameBox:SetAnchor(LEFT, nameLabelCaption, RIGHT, 8, 0)
	insp.nameBox.onChange = function(text)
		local def = insp.currentId and findDef(QAT.sv.trackers, insp.currentId)
		text = zo_strtrim(text or "")
		if def and text ~= "" then
			def.name = text
			QAT.widgets.NotifyTrackerChanged(def.id)
		end
	end

	insp.move = QAT.widgets.TextButton(header, "QAT_Insp_Move", "Move on screen", function()
		if QAT.Editor_MoveTracker and insp.currentId then
			QAT.Editor_MoveTracker(insp.currentId)
		end
	end)
	insp.move:SetDimensions(120, 22)
	insp.move:SetAnchor(BOTTOMLEFT, header, BOTTOMLEFT, 10, -6)

	insp.popout = QAT.widgets.TextButton(header, "QAT_Insp_Popout", "Pop out", function()
		d(QAT.displayName .. ": detachable inspector is not yet available.")
	end)
	insp.popout:SetDimensions(70, 22)
	insp.popout:SetAnchor(LEFT, insp.move, RIGHT, 10, 0)

	-- Tracker dimensions (W x H). Bars use both; icons are square and use H only.
	local function dimChange(field)
		return function(text)
			local def = insp.currentId and findDef(QAT.sv.trackers, insp.currentId)
			local n = tonumber(text)
			if def and n and n > 0 then
				def.pos = def.pos or {}
				def.pos[field] = n
				QAT.widgets.NotifyTrackerChanged(def.id)
			end
		end
	end
	insp.sizeCaption = QAT.widgets.Label(header, "QAT_Insp_SizeCaption", "Size")
	insp.sizeCaption:SetAnchor(LEFT, insp.popout, RIGHT, 16, 0)
	insp.widthBox = QAT.widgets.EditBox(header, "QAT_Insp_WidthBox", 46, 22)
	insp.widthBox:SetAnchor(LEFT, insp.sizeCaption, RIGHT, 6, 0)
	insp.widthBox.onChange = dimChange("width")
	insp.sizeX = QAT.widgets.Label(header, "QAT_Insp_SizeX", "x")
	insp.sizeX:SetAnchor(LEFT, insp.widthBox, RIGHT, 4, 0)
	insp.heightBox = QAT.widgets.EditBox(header, "QAT_Insp_HeightBox", 46, 22)
	insp.heightBox:SetAnchor(LEFT, insp.sizeX, RIGHT, 4, 0)
	insp.heightBox.onChange = dimChange("height")

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
	insp.nameCaption:SetHidden(not def)
	insp.nameBox:SetHidden(not def)
	insp.move:SetHidden(not def)
	insp.popout:SetHidden(not def)
	-- Size fields apply to a tracker's drawn dimensions; folders have none.
	local showSize = def ~= nil and def.kind ~= "folder"
	insp.sizeCaption:SetHidden(not showSize)
	insp.widthBox:SetHidden(not showSize)
	insp.sizeX:SetHidden(not showSize)
	insp.heightBox:SetHidden(not showSize)
	if QAT.editor.tabBar then
		QAT.editor.tabBar:SetHidden(not def)
	end
	-- Folders only have a Load tab (no phases / runtime conditions).
	if def and QAT.Editor_SetAvailableTabs then
		QAT.Editor_SetAvailableTabs(def.kind == "folder")
	end

	if def then
		insp.nameBox:SetText(def.name or def.id)
		if def.kind ~= "folder" then
			local pos = def.pos or {}
			insp.widthBox:SetText(tostring(pos.width or 220))
			insp.heightBox:SetText(tostring(pos.height or 30))
		end
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
