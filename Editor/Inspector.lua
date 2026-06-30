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

	local GAP, h = 8, 20 -- slim chips to fit the thinner phase bar
	local cap = get("cap", function()
		return QAT.widgets.Label(sel, "QAT_PhaseSel_Cap", "Phase:")
	end)
	cap:ClearAnchors()
	cap:SetAnchor(LEFT, sel, LEFT, 12, 0)

	local prev = cap
	for i, p in ipairs(def.phases) do
		local pid = p.id
		local chip = get("chip" .. i, function()
			return QAT.widgets.TextButton(sel, "QAT_PhaseSel_Chip" .. i, "", nil)
		end)
		chip:SetSelected(pid == QAT.editor.selectedPhaseId)
		chip:SetText(pid) -- auto-fits width to the phase name
		chip:SetHeight(h)
		chip:ClearAnchors()
		chip:SetAnchor(LEFT, prev, RIGHT, GAP, 0)
		QAT.widgets.Tooltip(chip, "Edit phase '" .. pid .. "'.")
		chip.onClick = function()
			QAT.editor.selectedPhaseId = pid
			refreshBody()
		end
		prev = chip
	end

	local addBtn = get("add", function()
		return QAT.widgets.TextButton(sel, "QAT_PhaseSel_Add", "+ Phase", nil)
	end)
	addBtn:SetHeight(h)
	addBtn:ClearAnchors()
	addBtn:SetAnchor(LEFT, prev, RIGHT, GAP, 0)
	QAT.widgets.Tooltip(addBtn, "Add a new phase to this tracker.")
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

	-- Phase actions for the SELECTED phase, right-aligned so they read against the
	-- highlighted chip ("delete the active phase").
	local selId = QAT.editor.selectedPhaseId

	local delBtn = get("delPhase", function()
		return QAT.widgets.TextButton(sel, "QAT_PhaseSel_Del", "Delete phase", nil)
	end)
	delBtn:SetHeight(h)
	delBtn:ClearAnchors()
	delBtn:SetAnchor(RIGHT, sel, RIGHT, -12, 0)
	QAT.widgets.Tooltip(delBtn, "Delete the selected phase '" .. tostring(selId) .. "'.")
	local function removeSelectedPhase()
		if #def.phases <= 1 then
			return
		end
		for i, p in ipairs(def.phases) do
			if p.id == selId then
				table.remove(def.phases, i)
				break
			end
		end
		QAT.editor.selectedPhaseId = def.phases[1].id
		QAT.CanonicalizeDef(def)
		QAT.widgets.NotifyTrackerChanged(def.id)
	end
	delBtn.onClick = function()
		if #def.phases <= 1 then
			return -- a tracker must keep at least one phase
		end
		if QAT.Editor_ConfirmDelete then
			QAT.Editor_ConfirmDelete("phase " .. tostring(selId), removeSelectedPhase)
		else
			removeSelectedPhase()
		end
	end

	local initBtn = get("initPhase", function()
		return QAT.widgets.TextButton(sel, "QAT_PhaseSel_Init", "Set initial", nil)
	end)
	initBtn:SetHeight(h)
	initBtn:ClearAnchors()
	initBtn:SetAnchor(RIGHT, delBtn, LEFT, GAP, 0)
	initBtn:SetSelected(selId == def.initial) -- lit when the selected phase is the initial one
	QAT.widgets.Tooltip(initBtn, "Make the selected phase the tracker's starting phase.")
	initBtn.onClick = function()
		def.initial = selId
		QAT.CanonicalizeDef(def)
		QAT.widgets.NotifyTrackerChanged(def.id)
	end

	QAT.widgets.PoolEnd(pool)
end

function QAT.Editor_Inspector_Build(pane)
	local insp = QAT.editor.inspector or {}
	QAT.editor.inspector = insp

	-- ===== Header (tracker scope), two rows =====
	-- Row 1:  Name | Size | Position (left)            Center  Pop out   Phases  Load (right)
	-- Row 2:  the phase strip (Phase: chips +Phase ............ Set initial  Delete phase)
	local header = QAT.widgets.Panel(pane, "QAT_Insp_Header", { 0.12, 0.13, 0.17, 1 })
	header:SetAnchor(TOPLEFT, pane, TOPLEFT, 0, 0)
	header:SetAnchor(TOPRIGHT, pane, TOPRIGHT, 0, 0)
	header:SetHeight(QAT.editor.HEADER_H)
	insp.header = header
	local ROW1_Y, BAR_Y, BAR_H = 8, 44, 28

	local function curDef()
		return insp.currentId and findDef(QAT.sv.trackers, insp.currentId)
	end

	-- Row 1 lives in a fixed-height container so the mixed labels / boxes / buttons
	-- all centre on one line.
	local row1 = WM:CreateControl("QAT_Insp_Row1", header, CT_CONTROL)
	row1:SetAnchor(TOPLEFT, header, TOPLEFT, 12, ROW1_Y)
	row1:SetAnchor(TOPRIGHT, header, TOPRIGHT, -12, ROW1_Y)
	row1:SetHeight(24)

	-- Name (left).
	insp.nameCaption = QAT.widgets.Label(row1, "QAT_Insp_NameCaption", "Name")
	insp.nameCaption:SetAnchor(LEFT, row1, LEFT, 0, 0)
	insp.nameBox = QAT.widgets.EditBox(row1, "QAT_Insp_NameBox", 150, 22)
	insp.nameBox:SetAnchor(LEFT, insp.nameCaption, RIGHT, 8, 0)
	insp.nameBox.onChange = function(text)
		local def = curDef()
		text = zo_strtrim(text or "")
		if def and text ~= "" then
			def.name = text
			QAT.widgets.NotifyTrackerChanged(def.id)
		end
	end

	-- Size (chained after Name). Whole-number pixels.
	local function dimChange(field)
		return function(text)
			local n = tonumber(text)
			local def = curDef()
			if def and n and n > 0 then
				def.pos = def.pos or {}
				def.pos[field] = n
				QAT.widgets.NotifyTrackerChanged(def.id)
			end
		end
	end
	insp.sizeCaption = QAT.widgets.Label(row1, "QAT_Insp_SizeCaption", "Size")
	insp.sizeCaption:SetAnchor(LEFT, insp.nameBox, RIGHT, 18, 0)
	insp.widthBox = QAT.widgets.EditBox(row1, "QAT_Insp_WidthBox", 44, 22)
	insp.widthBox:SetAnchor(LEFT, insp.sizeCaption, RIGHT, 6, 0)
	insp.widthBox.onChange = dimChange("width")
	insp.sizeX = QAT.widgets.Label(row1, "QAT_Insp_SizeX", "x")
	insp.sizeX:SetAnchor(LEFT, insp.widthBox, RIGHT, 4, 0)
	insp.heightBox = QAT.widgets.EditBox(row1, "QAT_Insp_HeightBox", 44, 22)
	insp.heightBox:SetAnchor(LEFT, insp.sizeX, RIGHT, 4, 0)
	insp.heightBox.onChange = dimChange("height")

	-- Position (chained after Size). Top-left origin: 0,0 is the screen's top-left
	-- corner, x grows right and y grows down; clamped to the screen. Moves live.
	local function posChange(field, box)
		return function(text)
			local n = tonumber(text)
			local def = curDef()
			if def and n then
				local maxv = (field == "x") and GuiRoot:GetWidth() or GuiRoot:GetHeight()
				n = zo_clamp(zo_round(n), 0, maxv)
				def.pos = def.pos or {}
				def.pos[field] = n
				box:SetText(tostring(n)) -- reflect the clamped value
				if QAT.Runtime_RepositionTracker then
					QAT.Runtime_RepositionTracker(def.id, def.pos.x or 0, def.pos.y or 0)
				end
			end
		end
	end
	insp.posCaption = QAT.widgets.Label(row1, "QAT_Insp_PosCaption", "Position")
	insp.posCaption:SetAnchor(LEFT, insp.heightBox, RIGHT, 18, 0)
	insp.posXBox = QAT.widgets.EditBox(row1, "QAT_Insp_PosXBox", 44, 22)
	insp.posXBox:SetAnchor(LEFT, insp.posCaption, RIGHT, 6, 0)
	insp.posXBox.onChange = posChange("x", insp.posXBox)
	insp.posX = QAT.widgets.Label(row1, "QAT_Insp_PosX", "x")
	insp.posX:SetAnchor(LEFT, insp.posXBox, RIGHT, 4, 0)
	insp.posYBox = QAT.widgets.EditBox(row1, "QAT_Insp_PosYBox", 44, 22)
	insp.posYBox:SetAnchor(LEFT, insp.posX, RIGHT, 4, 0)
	insp.posYBox.onChange = posChange("y", insp.posYBox)
	QAT.widgets.Tooltip(
		insp.posCaption,
		"Position of the top-left corner from the screen's top-left (x right, y down), clamped to the screen. Drag the tracker on the HUD for fine control."
	)

	-- Row 1 right group: Center, Pop out, then the Phases/Load mode switch. Chained
	-- right-to-left so they read Center | Pop out  ...  Phases | Load.
	insp.loadBtn = QAT.widgets.TextButton(row1, "QAT_Insp_LoadBtn", "Load", function()
		QAT.editor.loadMode = true
		refreshBody()
	end)
	insp.loadBtn:SetHeight(22)
	insp.loadBtn:SetMinWidth(70)
	insp.loadBtn:SetAnchor(RIGHT, row1, RIGHT, 0, 0)
	QAT.widgets.Tooltip(
		insp.loadBtn,
		"When this tracker is active: class, role, combat, zone, boss and set conditions."
	)

	insp.phasesBtn = QAT.widgets.TextButton(row1, "QAT_Insp_PhasesBtn", "Phases", function()
		QAT.editor.loadMode = false
		refreshBody()
	end)
	insp.phasesBtn:SetHeight(22)
	insp.phasesBtn:SetMinWidth(70)
	insp.phasesBtn:SetAnchor(RIGHT, insp.loadBtn, LEFT, -8, 0)
	QAT.widgets.Tooltip(insp.phasesBtn, "Edit this tracker's phases — appearance, behavior and runtime conditions.")

	insp.popout = QAT.widgets.TextButton(row1, "QAT_Insp_Popout", "Pop out", function()
		d(QAT.displayName .. ": detachable inspector is not yet available.")
	end)
	insp.popout:SetHeight(22)
	insp.popout:SetAnchor(RIGHT, insp.phasesBtn, LEFT, -18, 0)
	QAT.widgets.Tooltip(insp.popout, "Detach this inspector into its own window. (Not yet available.)")

	insp.move = QAT.widgets.TextButton(row1, "QAT_Insp_Move", "Center", function()
		local def = curDef()
		if def then
			local pos = def.pos or {}
			def.pos = pos
			pos.x = zo_round(GuiRoot:GetWidth() / 2 - (pos.width or 220) / 2)
			pos.y = zo_round(GuiRoot:GetHeight() / 2 - (pos.height or 30) / 2)
			if QAT.Runtime_RepositionTracker then
				QAT.Runtime_RepositionTracker(def.id, pos.x, pos.y)
			end
			QAT.Editor_Inspector_Show(insp.currentId) -- refresh the X/Y boxes
		end
	end)
	insp.move:SetHeight(22)
	insp.move:SetAnchor(RIGHT, insp.popout, LEFT, -8, 0)
	QAT.widgets.Tooltip(insp.move, "Recentre this tracker on screen.")

	-- Row 2: the phase "config-nav" bar — a distinct, thinner coloured band so it
	-- reads as navigation rather than part of the identity header.
	insp.phaseBar = QAT.widgets.Panel(header, "QAT_Insp_PhaseBar", { 0.10, 0.12, 0.18, 1 }, { 0.18, 0.22, 0.30, 1 })
	insp.phaseBar:SetAnchor(TOPLEFT, header, TOPLEFT, 0, BAR_Y)
	insp.phaseBar:SetAnchor(TOPRIGHT, header, TOPRIGHT, 0, BAR_Y)
	insp.phaseBar:SetHeight(BAR_H)

	local sel = WM:CreateControl("QAT_Insp_PhaseSel", insp.phaseBar, CT_CONTROL)
	sel:SetAnchor(TOPLEFT, insp.phaseBar, TOPLEFT, 12, 0)
	sel:SetAnchor(BOTTOMRIGHT, insp.phaseBar, BOTTOMRIGHT, -12, 0)
	insp.phaseSel = sel
	insp.phaseSelPool = QAT.widgets.NewPool()

	-- Body host (below the tab bar; the phase strip is in the header now).
	local bodyTop = QAT.editor.HEADER_H + QAT.editor.HEADER_GAP + QAT.editor.TAB_H
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
	-- Re-entrancy guard: hiding a container that holds a focused EditBox fires its
	-- OnFocusLost (a commit), which can call back into refreshBody. Coalesce any such
	-- nested call into a single re-render after the current one finishes.
	if insp.refreshing then
		insp.refreshPending = true
		return
	end
	insp.refreshing = true

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
		insp.phasesBtn:SetHidden(true)
	else
		insp.placeholder:SetHidden(true)
		insp.loadBtn:SetHidden(false)

		-- Folders have no phases, so they only ever show the Load panel.
		local isFolder = def.kind == "folder"
		local showLoad = QAT.editor.loadMode or isFolder

		insp.phasesBtn:SetHidden(isFolder) -- a folder has only Load
		insp.phasesBtn:SetSelected(not showLoad)
		insp.loadBtn:SetSelected(showLoad)
		if QAT.editor.tabButtons then
			for _, n in ipairs(PHASE_TABS) do
				QAT.editor.tabButtons[n]:SetSelected(not showLoad and QAT.editor.activeTab == n)
			end
		end
		-- In Load mode the phase bar and tabs are hidden; the header Phases button
		-- is the way back.
		insp.phaseBar:SetHidden(showLoad)
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
		else
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
	end

	insp.refreshing = false
	if insp.refreshPending then
		insp.refreshPending = false
		refreshBody()
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
	insp.phasesBtn:SetHidden(not def)
	-- Size + position apply to a drawn tracker; folders have neither.
	local showTracker = def ~= nil and def.kind ~= "folder"
	for _, c in ipairs({
		insp.sizeCaption,
		insp.widthBox,
		insp.sizeX,
		insp.heightBox,
		insp.posCaption,
		insp.posXBox,
		insp.posX,
		insp.posYBox,
	}) do
		c:SetHidden(not showTracker)
	end

	if def then
		insp.nameBox:SetText(def.name or def.id)
		if showTracker then
			local pos = def.pos or {}
			insp.widthBox:SetText(tostring(pos.width or 220))
			insp.heightBox:SetText(tostring(pos.height or 30))
			insp.posXBox:SetText(tostring(pos.x or 0))
			insp.posYBox:SetText(tostring(pos.y or 0))
		end
	end
	refreshBody()
end

-- Called by Display when a tracker is dragged on the HUD: persist the new offset
-- and refresh the inspector so its position sliders track the drag.
function QAT.Editor_OnTrackerDragged(id, x, y)
	local def = findDef(QAT.sv.trackers, id)
	if not def then
		return
	end
	def.pos = def.pos or {}
	def.pos.x, def.pos.y = x, y
	if QAT.Runtime_RepositionTracker then
		QAT.Runtime_RepositionTracker(id, x, y) -- re-anchor cleanly (centre + offset)
	end
	local insp = QAT.editor.inspector
	if insp and insp.currentId == id then
		QAT.Editor_Inspector_Show(id)
	end
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
