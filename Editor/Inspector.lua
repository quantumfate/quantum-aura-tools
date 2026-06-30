-- Inspector: a tracker-scoped header (name, move, pop-out, size, Load) plus a
-- phase-scoped area below it — a shared phase-selector strip and the per-phase
-- tabs (Appearance / Behavior / Conditions). "Load" in the header swaps the body
-- to the tracker-wide Load panel and hides the phase strip + tabs, so it is never
-- mistaken for a per-phase setting. Everything renders from the bound def and
-- refreshes on "QAT_TrackerChanged".

local WM = GetWindowManager()
local PHASE_TABS = { "Appearance", "Behavior", "Conditions" }

-- Forward declaration so header/phase-strip callbacks can call it.
local refreshBody

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

local function ensureSelectedPhase(def)
	for _, p in ipairs(def.phases or {}) do
		if p.id == QAT.editor.selectedPhaseId then
			return
		end
	end
	QAT.editor.selectedPhaseId = def.phases and def.phases[1] and def.phases[1].id
end

-- Render the shared phase strip: "Phase: [chips] (+ Phase)".
local function renderPhaseSel(def)
	local insp = QAT.editor.inspector
	local sel = insp.phaseSel
	local pool = insp.phaseSelPool
	QAT.widgets.PoolBegin(pool)
	local function get(key, factory)
		return QAT.widgets.PoolGet(pool, key, factory)
	end

	local cap = get("cap", function()
		return QAT.widgets.Label(sel, "QAT_PhaseSel_Cap", "Phase:")
	end)
	cap:ClearAnchors()
	cap:SetAnchor(LEFT, sel, LEFT, 10, 0)

	local x = 58
	for i, p in ipairs(def.phases) do
		local pid = p.id
		local chip = get("chip" .. i, function()
			return QAT.widgets.TextButton(sel, "QAT_PhaseSel_Chip" .. i, "", nil)
		end)
		chip:SetSelected(pid == QAT.editor.selectedPhaseId)
		chip.label:SetText(pid)
		chip:SetDimensions(84, QAT.editor.PHASESEL_H - 8)
		chip:ClearAnchors()
		chip:SetAnchor(LEFT, sel, LEFT, x, 0)
		chip.onClick = function()
			QAT.editor.selectedPhaseId = pid
			refreshBody()
		end
		x = x + 88
	end

	local addBtn = get("add", function()
		return QAT.widgets.TextButton(sel, "QAT_PhaseSel_Add", "+ Phase", nil)
	end)
	addBtn:SetDimensions(76, QAT.editor.PHASESEL_H - 8)
	addBtn:ClearAnchors()
	addBtn:SetAnchor(LEFT, sel, LEFT, x, 0)
	addBtn.onClick = function()
		local n = #def.phases + 1
		table.insert(
			def.phases,
			{ id = "phase" .. n, look = { display = "bar" }, duration = { type = "none" }, transitions = {} }
		)
		QAT.editor.selectedPhaseId = "phase" .. n
		QAT.CanonicalizeDef(def)
		QAT.widgets.NotifyTrackerChanged(def.id)
	end

	QAT.widgets.PoolEnd(pool)
end

function QAT.Editor_Inspector_Build(pane)
	local insp = QAT.editor.inspector or {}
	QAT.editor.inspector = insp

	-- Header (tracker scope): name, move, pop out, size, and the Load toggle.
	local header = QAT.widgets.Panel(pane, "QAT_Insp_Header", { 0.10, 0.11, 0.14, 1 })
	header:SetAnchor(TOPLEFT, pane, TOPLEFT, 0, 0)
	header:SetAnchor(TOPRIGHT, pane, TOPRIGHT, 0, 0)
	header:SetHeight(QAT.editor.HEADER_H)
	insp.header = header

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

	-- Load toggle (tracker scope), set off on the header's right edge.
	insp.loadBtn = QAT.widgets.TextButton(header, "QAT_Insp_LoadBtn", "Load", function()
		QAT.editor.loadMode = true
		refreshBody()
	end)
	insp.loadBtn:SetDimensions(76, 22)
	insp.loadBtn:SetAnchor(BOTTOMRIGHT, header, BOTTOMRIGHT, -10, -6)

	-- Shared phase-selector strip (between the header and the tab bar).
	local sel = WM:CreateControl("QAT_Insp_PhaseSel", pane, CT_CONTROL)
	sel:SetAnchor(TOPLEFT, pane, TOPLEFT, 0, QAT.editor.HEADER_H)
	sel:SetAnchor(TOPRIGHT, pane, TOPRIGHT, 0, QAT.editor.HEADER_H)
	sel:SetHeight(QAT.editor.PHASESEL_H)
	insp.phaseSel = sel
	insp.phaseSelPool = QAT.widgets.NewPool()

	-- Body host (below the tab bar).
	local bodyTop = QAT.editor.HEADER_H + QAT.editor.PHASESEL_H + QAT.editor.TAB_H
	local body = QAT.widgets.Panel(pane, "QAT_Insp_Body", { 0.06, 0.07, 0.09, 1 })
	body:SetAnchor(TOPLEFT, pane, TOPLEFT, 0, bodyTop)
	body:SetAnchor(BOTTOMRIGHT, pane, BOTTOMRIGHT, 0, 0)
	insp.body = body

	local placeholder = QAT.widgets.Label(body, "QAT_Insp_Placeholder", "")
	placeholder:SetAnchor(TOPLEFT, body, TOPLEFT, 12, 12)
	placeholder:SetAnchor(TOPRIGHT, body, TOPRIGHT, -12, 12)
	placeholder:SetVerticalAlignment(TEXT_ALIGN_TOP)
	insp.placeholder = placeholder

	-- One container per per-phase tab, plus a tracker-wide Load container; the body
	-- shows exactly one at a time.
	insp.tabContainers = {}
	for _, tabName in ipairs(PHASE_TABS) do
		local c = WM:CreateControl("QAT_Insp_Tab_" .. tabName, body, CT_CONTROL)
		c:SetAnchor(TOPLEFT, body, TOPLEFT, 0, 0)
		c:SetAnchor(BOTTOMRIGHT, body, BOTTOMRIGHT, 0, 0)
		c:SetHidden(true)
		insp.tabContainers[tabName] = c
	end
	local loadC = WM:CreateControl("QAT_Insp_LoadContainer", body, CT_CONTROL)
	loadC:SetAnchor(TOPLEFT, body, TOPLEFT, 0, 0)
	loadC:SetAnchor(BOTTOMRIGHT, body, BOTTOMRIGHT, 0, 0)
	loadC:SetHidden(true)
	insp.loadContainer = loadC

	QAT.Editor_Inspector_Show(nil)
end

QAT.editor.tabRenderers = QAT.editor.tabRenderers or {}

refreshBody = function()
	local insp = QAT.editor.inspector
	if not insp then
		return
	end
	local def = insp.currentId and findDef(QAT.sv.trackers, insp.currentId)

	for _, c in pairs(insp.tabContainers or {}) do
		c:SetHidden(true)
	end
	insp.loadContainer:SetHidden(true)

	if not def then
		insp.placeholder:SetHidden(false)
		insp.placeholder:SetText("Select a tracker in the tree, or add one with + Tracker.")
		insp.phaseSel:SetHidden(true)
		if QAT.editor.tabBar then
			QAT.editor.tabBar:SetHidden(true)
		end
		insp.loadBtn:SetHidden(true)
		return
	end
	insp.placeholder:SetHidden(true)
	insp.loadBtn:SetHidden(false)

	-- Folders have no phases, so they only ever show the Load panel.
	local isFolder = def.kind == "folder"
	local showLoad = QAT.editor.loadMode or isFolder

	insp.loadBtn:SetSelected(showLoad)
	if QAT.editor.tabButtons then
		for _, n in ipairs(PHASE_TABS) do
			QAT.editor.tabButtons[n]:SetSelected(not showLoad and QAT.editor.activeTab == n)
		end
	end
	insp.phaseSel:SetHidden(showLoad)
	if QAT.editor.tabBar then
		QAT.editor.tabBar:SetHidden(showLoad)
	end

	if showLoad then
		local renderer = QAT.editor.tabRenderers["Load"]
		if renderer then
			insp.loadContainer:SetHidden(false)
			QAT.Safe("tab Load", function()
				renderer(insp.loadContainer, def)
			end)
		end
		return
	end

	ensureSelectedPhase(def)
	renderPhaseSel(def)

	local tab = QAT.editor.activeTab or "Appearance"
	local container = insp.tabContainers[tab]
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
	QAT.editor.loadMode = false -- (re)selecting a tracker lands on a per-phase tab

	insp.nameCaption:SetHidden(not def)
	insp.nameBox:SetHidden(not def)
	insp.move:SetHidden(not def)
	insp.popout:SetHidden(not def)
	insp.loadBtn:SetHidden(not def)
	local showSize = def ~= nil and def.kind ~= "folder"
	insp.sizeCaption:SetHidden(not showSize)
	insp.widthBox:SetHidden(not showSize)
	insp.sizeX:SetHidden(not showSize)
	insp.heightBox:SetHidden(not showSize)

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
	-- Header / phase strip / body all anchor to the pane; nothing extra yet.
end

CALLBACK_MANAGER:RegisterCallback("QAT_TrackerChanged", function(id)
	local insp = QAT.editor.inspector
	if insp and insp.currentId == id then
		QAT.Editor_Inspector_Show(id)
	end
end)
