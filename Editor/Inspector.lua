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

	local GAP, h = 8, QAT.editor.PHASESEL_H - 12
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

	-- ===== Header (tracker scope) =====
	-- Row 1:  Name [____]   Size [w] x [h]   X [slider]   Y [slider]
	-- (divider) -- gap -- Row 2:  Center  Pop out ............ Phases  Load  (end divider)
	local header = QAT.widgets.Panel(pane, "QAT_Insp_Header", { 0.10, 0.11, 0.14, 1 })
	header:SetAnchor(TOPLEFT, pane, TOPLEFT, 0, 0)
	header:SetAnchor(TOPRIGHT, pane, TOPRIGHT, 0, 0)
	header:SetHeight(QAT.editor.HEADER_H)
	insp.header = header
	local ROW1_Y, DIV1_Y, ROW2_Y = 12, 44, 70

	local function curDef()
		return insp.currentId and findDef(QAT.sv.trackers, insp.currentId)
	end
	-- Live position update from the sliders / Center: write the def and move the live
	-- controls, without a full inspector refresh (so sliders don't reset mid-drag).
	local function setPos(field, v)
		local def = curDef()
		if def then
			def.pos = def.pos or {}
			def.pos[field] = v
			if QAT.Runtime_RepositionTracker then
				QAT.Runtime_RepositionTracker(def.id, def.pos.x or 0, def.pos.y or 0)
			end
		end
	end

	-- Name.
	insp.nameCaption = QAT.widgets.Label(header, "QAT_Insp_NameCaption", "Name")
	insp.nameCaption:SetAnchor(TOPLEFT, header, TOPLEFT, 12, ROW1_Y + 3)
	insp.nameBox = QAT.widgets.EditBox(header, "QAT_Insp_NameBox", 170, 22)
	insp.nameBox:SetAnchor(LEFT, insp.nameCaption, RIGHT, 8, 0)
	insp.nameBox.onChange = function(text)
		local def = curDef()
		text = zo_strtrim(text or "")
		if def and text ~= "" then
			def.name = text
			QAT.widgets.NotifyTrackerChanged(def.id)
		end
	end

	-- Size + position, right-aligned and built right-to-left so they read
	-- "Size w x h   X [slider]   Y [slider]".
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
	insp.posYSlider = QAT.widgets.Slider(header, "QAT_Insp_PosY", 96, function(v)
		setPos("y", zo_round(v))
	end)
	insp.posYSlider:SetAnchor(TOPRIGHT, header, TOPRIGHT, -12, ROW1_Y + 2)
	insp.posYCap = QAT.widgets.Label(header, "QAT_Insp_PosYCap", "Y")
	insp.posYCap:SetAnchor(RIGHT, insp.posYSlider, LEFT, -6, 0)
	insp.posXSlider = QAT.widgets.Slider(header, "QAT_Insp_PosX", 96, function(v)
		setPos("x", zo_round(v))
	end)
	insp.posXSlider:SetAnchor(RIGHT, insp.posYCap, LEFT, -14, 0)
	insp.posXCap = QAT.widgets.Label(header, "QAT_Insp_PosXCap", "X")
	insp.posXCap:SetAnchor(RIGHT, insp.posXSlider, LEFT, -6, 0)
	insp.heightBox = QAT.widgets.EditBox(header, "QAT_Insp_HeightBox", 46, 22)
	insp.heightBox:SetAnchor(RIGHT, insp.posXCap, LEFT, -16, 0)
	insp.heightBox.onChange = dimChange("height")
	insp.sizeX = QAT.widgets.Label(header, "QAT_Insp_SizeX", "x")
	insp.sizeX:SetAnchor(RIGHT, insp.heightBox, LEFT, -5, 0)
	insp.widthBox = QAT.widgets.EditBox(header, "QAT_Insp_WidthBox", 46, 22)
	insp.widthBox:SetAnchor(RIGHT, insp.sizeX, LEFT, -5, 0)
	insp.widthBox.onChange = dimChange("width")
	insp.sizeCaption = QAT.widgets.Label(header, "QAT_Insp_SizeCaption", "Size")
	insp.sizeCaption:SetAnchor(RIGHT, insp.widthBox, LEFT, -6, 0)
	QAT.widgets.Tooltip(
		insp.posXCap,
		"Horizontal position (offset from screen centre). Drag the tracker on the HUD for fine control."
	)
	QAT.widgets.Tooltip(insp.posYCap, "Vertical position (offset from screen centre).")

	-- Divider between row 1 and the action row.
	insp.headerDiv1 = QAT.widgets.Divider(header, "QAT_Insp_HeaderDiv1")
	insp.headerDiv1:SetAnchor(TOPLEFT, header, TOPLEFT, 0, DIV1_Y)
	insp.headerDiv1:SetAnchor(TOPRIGHT, header, TOPRIGHT, 0, DIV1_Y)

	-- Row 2: actions (left) and the Phases/Load mode switch (right).
	insp.move = QAT.widgets.TextButton(header, "QAT_Insp_Move", "Center", function()
		setPos("x", 0)
		setPos("y", 0)
		refreshBody() -- update the sliders
	end)
	insp.move:SetHeight(24)
	insp.move:SetAnchor(TOPLEFT, header, TOPLEFT, 12, ROW2_Y)
	QAT.widgets.Tooltip(insp.move, "Recentre this tracker on screen (position 0, 0).")

	insp.popout = QAT.widgets.TextButton(header, "QAT_Insp_Popout", "Pop out", function()
		d(QAT.displayName .. ": detachable inspector is not yet available.")
	end)
	insp.popout:SetHeight(24)
	insp.popout:SetAnchor(LEFT, insp.move, RIGHT, 8, 0)
	QAT.widgets.Tooltip(insp.popout, "Detach this inspector into its own window. (Not yet available.)")

	insp.loadBtn = QAT.widgets.TextButton(header, "QAT_Insp_LoadBtn", "Load", function()
		QAT.editor.loadMode = true
		refreshBody()
	end)
	insp.loadBtn:SetHeight(24)
	insp.loadBtn:SetMinWidth(76)
	insp.loadBtn:SetAnchor(TOPRIGHT, header, TOPRIGHT, -12, ROW2_Y)
	QAT.widgets.Tooltip(
		insp.loadBtn,
		"When this tracker is active: class, role, combat, zone, boss and set conditions."
	)

	insp.phasesBtn = QAT.widgets.TextButton(header, "QAT_Insp_PhasesBtn", "Phases", function()
		QAT.editor.loadMode = false
		refreshBody()
	end)
	insp.phasesBtn:SetHeight(24)
	insp.phasesBtn:SetMinWidth(76)
	insp.phasesBtn:SetAnchor(RIGHT, insp.loadBtn, LEFT, -8, 0)
	QAT.widgets.Tooltip(insp.phasesBtn, "Edit this tracker's phases — appearance, behavior and runtime conditions.")

	-- End-of-header divider.
	local headerDiv = QAT.widgets.Divider(pane, "QAT_Insp_HeaderDiv")
	headerDiv:SetAnchor(BOTTOMLEFT, header, BOTTOMLEFT, 0, 0)
	headerDiv:SetAnchor(BOTTOMRIGHT, header, BOTTOMRIGHT, 0, 0)

	-- Shared phase-selector strip, set below the header by the content gap.
	local selTop = QAT.editor.HEADER_H + QAT.editor.HEADER_GAP
	local sel = WM:CreateControl("QAT_Insp_PhaseSel", pane, CT_CONTROL)
	sel:SetAnchor(TOPLEFT, pane, TOPLEFT, 12, selTop)
	sel:SetAnchor(TOPRIGHT, pane, TOPRIGHT, -12, selTop)
	sel:SetHeight(QAT.editor.PHASESEL_H)
	insp.phaseSel = sel
	insp.phaseSelPool = QAT.widgets.NewPool()

	-- Body host (below the tab bar).
	local bodyTop = QAT.editor.HEADER_H + QAT.editor.HEADER_GAP + QAT.editor.PHASESEL_H + QAT.editor.TAB_H
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
		-- In Load mode the phase strip and tabs are hidden; the header Phases button
		-- is the way back.
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
		insp.posXCap,
		insp.posXSlider,
		insp.posYCap,
		insp.posYSlider,
	}) do
		c:SetHidden(not showTracker)
	end

	if def then
		insp.nameBox:SetText(def.name or def.id)
		if showTracker then
			local pos = def.pos or {}
			insp.widthBox:SetText(tostring(pos.width or 220))
			insp.heightBox:SetText(tostring(pos.height or 30))
			-- Slider range spans the screen, centred on 0.
			local halfW, halfH = GuiRoot:GetWidth() / 2, GuiRoot:GetHeight() / 2
			insp.posXSlider:SetMinMax(-halfW, halfW)
			insp.posYSlider:SetMinMax(-halfH, halfH)
			insp.posXSlider:SetValue(pos.x or 0)
			insp.posYSlider:SetValue(pos.y or 0)
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
