-- Inspector: an aura-scoped identity header (name, size, position, move, pop-out)
-- and a breadcrumb that reflects what the tree has selected. Scope is encoded in the
-- tree, not in a toggle: selecting a tracker (or its "Load conditions" row) shows the
-- aura-wide Load panel; selecting a phase row shows that phase's Appearance / Behavior
-- / Conditions tabs. Everything renders from the bound def and refreshes on
-- "QAT_TrackerChanged".

local WM = GetWindowManager()
local PHASE_TABS = { "Appearance", "Behavior", "Conditions" }

-- Forward declaration so header/breadcrumb callbacks can call it.
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

local function phaseById(def, id)
	for _, p in ipairs(def.phases or {}) do
		if p.id == id then
			return p
		end
	end
	return nil
end

local function ensureSelectedPhase(def)
	if phaseById(def, QAT.editor.selectedPhaseId) then
		return
	end
	QAT.editor.selectedPhaseId = def.phases and def.phases[1] and def.phases[1].id
end

-- ===== Phase mutations (shared with the tree, which owns the phase rows) =====

function QAT.Editor_AddPhase(def)
	local n = #def.phases + 1
	local id = "phase" .. n
	while phaseById(def, id) do
		n = n + 1
		id = "phase" .. n
	end
	table.insert(def.phases, { id = id, look = { display = "bar" }, duration = { type = "none" }, transitions = {} })
	QAT.editor.selectedPhaseId = id
	QAT.editor.selectedScope = "phase"
	QAT.CanonicalizeDef(def)
	QAT.widgets.NotifyTrackerChanged(def.id)
end

function QAT.Editor_SetInitialPhase(def, phaseId)
	def.initial = phaseId
	QAT.CanonicalizeDef(def)
	QAT.widgets.NotifyTrackerChanged(def.id)
end

function QAT.Editor_DeletePhase(def, phaseId)
	if #def.phases <= 1 then
		return -- a tracker must keep at least one phase
	end
	local function remove()
		for i, p in ipairs(def.phases) do
			if p.id == phaseId then
				table.remove(def.phases, i)
				break
			end
		end
		QAT.editor.selectedPhaseId = def.phases[1].id
		QAT.CanonicalizeDef(def)
		QAT.widgets.NotifyTrackerChanged(def.id)
	end
	if QAT.Editor_ConfirmDelete then
		QAT.Editor_ConfirmDelete("phase " .. tostring(phaseId), remove)
	else
		remove()
	end
end

-- A small bordered badge (e.g. AURA, INITIAL).
local function makeBadge(parent, name)
	local b = WM:CreateControl(name, parent, CT_BACKDROP)
	b:SetCenterColor(0.16, 0.22, 0.34, 1)
	b:SetEdgeColor(0.30, 0.40, 0.58, 1)
	b:SetEdgeTexture("", 1, 1, 1)
	local l = QAT.widgets.Label(b, name .. "_L", "", "$(BOLD_FONT)|11|soft-shadow-thin")
	l:SetColor(0.62, 0.72, 0.90, 1)
	l:SetAnchor(CENTER, b, CENTER, 0, 0)
	b.label = l
	function b:SetText(s)
		l:SetText(s)
		b:SetWidth(l:GetTextWidth() + 12)
	end
	b:SetHeight(16)
	return b
end

function QAT.Editor_Inspector_Build(pane)
	local insp = QAT.editor.inspector or {}
	QAT.editor.inspector = insp

	-- ===== Header (aura scope) =====
	-- Row 1:  Name | Size | Position (left)                       Center  Pop out (right)
	-- Row 2:  breadcrumb  Tracker > Load|phase [INITIAL]          [Set initial  Delete phase]
	local header = QAT.widgets.Panel(pane, "QAT_Insp_Header", { 0.06, 0.075, 0.105, 1 })
	header:SetAnchor(TOPLEFT, pane, TOPLEFT, 0, 0)
	header:SetAnchor(TOPRIGHT, pane, TOPRIGHT, 0, 0)
	header:SetHeight(QAT.editor.HEADER_H)
	insp.header = header
	local ROW1_Y, BAR_Y = 8, 44

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

	-- Group note: a group has no geometry of its own (positions live on its member
	-- auras), so in place of Size/Position it explains that.
	insp.groupNote = QAT.widgets.Label(row1, "QAT_Insp_GroupNote", "")
	insp.groupNote:SetColor(0.5, 0.56, 0.66, 1)
	insp.groupNote:SetAnchor(LEFT, insp.nameBox, RIGHT, 18, 0)
	insp.groupNote:SetHidden(true)

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
	insp.widthBox = QAT.widgets.EditBox(row1, "QAT_Insp_WidthBox", 54, 22)
	insp.widthBox:SetAnchor(LEFT, insp.sizeCaption, RIGHT, 6, 0)
	insp.widthBox.onChange = dimChange("width")
	insp.sizeX = QAT.widgets.Label(row1, "QAT_Insp_SizeX", "x")
	insp.sizeX:SetAnchor(LEFT, insp.widthBox, RIGHT, 4, 0)
	insp.heightBox = QAT.widgets.EditBox(row1, "QAT_Insp_HeightBox", 54, 22)
	insp.heightBox:SetAnchor(LEFT, insp.sizeX, RIGHT, 4, 0)
	insp.heightBox.onChange = dimChange("height")

	-- Position (chained after Size). Top-left origin: 0,0 is the screen's top-left
	-- corner, x grows right and y grows down; clamped to the screen. Moves live.
	local function posChange(field, box)
		return function(text)
			local n = tonumber(text)
			local def = curDef()
			if def and n then
				local pos = def.pos or {}
				local maxv = (field == "x") and (GuiRoot:GetWidth() - (pos.width or 220))
					or (GuiRoot:GetHeight() - (pos.height or 30))
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
	insp.posXBox = QAT.widgets.EditBox(row1, "QAT_Insp_PosXBox", 54, 22)
	insp.posXBox:SetAnchor(LEFT, insp.posCaption, RIGHT, 6, 0)
	insp.posXBox.onChange = posChange("x", insp.posXBox)
	insp.posX = QAT.widgets.Label(row1, "QAT_Insp_PosX", "x")
	insp.posX:SetAnchor(LEFT, insp.posXBox, RIGHT, 4, 0)
	insp.posYBox = QAT.widgets.EditBox(row1, "QAT_Insp_PosYBox", 54, 22)
	insp.posYBox:SetAnchor(LEFT, insp.posX, RIGHT, 4, 0)
	insp.posYBox.onChange = posChange("y", insp.posYBox)
	QAT.widgets.Tooltip(
		insp.posCaption,
		"Position of the top-left corner from the screen's top-left (x right, y down), clamped to the screen. Drag the tracker on the HUD for fine control."
	)

	-- Row 1 right group: Center, Pop out (chained right-to-left).
	insp.popout = QAT.widgets.TextButton(row1, "QAT_Insp_Popout", "Pop out", function()
		d(QAT.displayName .. ": detachable inspector is not yet available.")
	end)
	insp.popout:SetHeight(22)
	insp.popout:SetAnchor(RIGHT, row1, RIGHT, 0, 0)
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

	-- Row 2: breadcrumb (left) + phase actions (right). A plain row on the header so
	-- it reads as the current location, not a second navigation surface.
	local crumb = WM:CreateControl("QAT_Insp_Crumb", header, CT_CONTROL)
	crumb:SetAnchor(TOPLEFT, header, TOPLEFT, 12, BAR_Y)
	crumb:SetAnchor(TOPRIGHT, header, TOPRIGHT, -12, BAR_Y)
	crumb:SetHeight(22)
	insp.crumb = crumb

	insp.crumbRoot = QAT.widgets.Label(crumb, "QAT_Insp_CrumbRoot", "")
	insp.crumbRoot:SetColor(0.55, 0.62, 0.74, 1)
	insp.crumbRoot:SetAnchor(LEFT, crumb, LEFT, 0, 0)
	insp.crumbRoot:SetMouseEnabled(true)
	insp.crumbRoot:SetHandler("OnMouseUp", function(_, button, upInside)
		if upInside and button == MOUSE_BUTTON_INDEX_LEFT and insp.currentId then
			if QAT.Editor_SelectLoad then
				QAT.Editor_SelectLoad(insp.currentId) -- click the aura name -> Load scope
			end
		end
	end)

	insp.crumbSep = QAT.widgets.Label(crumb, "QAT_Insp_CrumbSep", "›")
	insp.crumbSep:SetColor(0.40, 0.46, 0.56, 1)
	insp.crumbSep:SetAnchor(LEFT, insp.crumbRoot, RIGHT, 8, 0)

	insp.crumbLeaf = QAT.widgets.Label(crumb, "QAT_Insp_CrumbLeaf", "", "$(BOLD_FONT)|18|soft-shadow-thin")
	insp.crumbLeaf:SetColor(0.92, 0.94, 0.97, 1)
	insp.crumbLeaf:SetAnchor(LEFT, insp.crumbSep, RIGHT, 8, 0)

	insp.crumbBadge = makeBadge(crumb, "QAT_Insp_CrumbBadge")
	insp.crumbBadge:SetAnchor(LEFT, insp.crumbLeaf, RIGHT, 8, 0)

	-- Phase actions (right, phase scope only).
	insp.delPhaseBtn = QAT.widgets.TextButton(crumb, "QAT_Insp_DelPhase", "Delete phase", function()
		local def = curDef()
		if def then
			QAT.Editor_DeletePhase(def, QAT.editor.selectedPhaseId)
		end
	end)
	insp.delPhaseBtn:SetHeight(22)
	insp.delPhaseBtn:SetAnchor(RIGHT, crumb, RIGHT, 0, 0)
	QAT.widgets.Tooltip(insp.delPhaseBtn, "Delete the selected phase.")

	insp.setInitBtn = QAT.widgets.TextButton(crumb, "QAT_Insp_SetInit", "Set initial", function()
		local def = curDef()
		if def then
			QAT.Editor_SetInitialPhase(def, QAT.editor.selectedPhaseId)
		end
	end)
	insp.setInitBtn:SetHeight(22)
	insp.setInitBtn:SetAnchor(RIGHT, insp.delPhaseBtn, LEFT, 8, 0)
	QAT.widgets.Tooltip(insp.setInitBtn, "Make the selected phase the tracker's starting phase.")

	-- Body host (below the tab bar). The phase tab bar lives in Window.lua and is
	-- shown only in phase scope.
	local bodyTop = QAT.editor.HEADER_H + QAT.editor.HEADER_GAP + QAT.editor.TAB_H
	local body = QAT.widgets.Panel(pane, "QAT_Insp_Body", { 0.045, 0.055, 0.078, 1 })
	body:SetAnchor(TOPLEFT, pane, TOPLEFT, 0, bodyTop)
	body:SetAnchor(BOTTOMRIGHT, pane, BOTTOMRIGHT, 0, 0)
	insp.body = body

	local placeholder = QAT.widgets.Label(body, "QAT_Insp_Placeholder", "")
	placeholder:SetAnchor(TOPLEFT, body, TOPLEFT, 12, 12)
	placeholder:SetAnchor(TOPRIGHT, body, TOPRIGHT, -12, 12)
	placeholder:SetVerticalAlignment(TEXT_ALIGN_TOP)
	insp.placeholder = placeholder

	-- One container per per-phase tab, plus an aura-wide Load container; the body
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

-- Update the breadcrumb + phase-action buttons for the current selection.
local function renderCrumb(def)
	local insp = QAT.editor.inspector
	local isFolder = def.kind == "folder"
	local scope = QAT.editor.selectedScope or "load"
	insp.crumbRoot:SetText(def.name or def.id)
	if scope == "phase" and not isFolder then
		insp.crumbLeaf:SetText(QAT.editor.selectedPhaseId or "")
		local isInitial = QAT.editor.selectedPhaseId == def.initial
		insp.crumbBadge:SetText("INITIAL")
		insp.crumbBadge:SetHidden(not isInitial)
		insp.setInitBtn:SetHidden(false)
		insp.setInitBtn:SetSelected(isInitial)
		insp.delPhaseBtn:SetHidden(false)
	else
		insp.crumbLeaf:SetText("Load")
		insp.crumbBadge:SetText(isFolder and "GROUP" or "AURA")
		insp.crumbBadge:SetHidden(false)
		insp.setInitBtn:SetHidden(true)
		insp.delPhaseBtn:SetHidden(true)
	end
end

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
	-- Any rebuild invalidates the layout an open dropdown list is anchored to, so
	-- close it rather than let it linger on the popup layer intercepting clicks.
	if QAT.widgets.CloseDropdowns then
		QAT.widgets.CloseDropdowns()
	end

	local def = insp.currentId and findDef(QAT.sv.trackers, insp.currentId)

	for _, c in pairs(insp.tabContainers or {}) do
		c:SetHidden(true)
	end
	insp.loadContainer:SetHidden(true)

	if not def then
		insp.placeholder:SetHidden(false)
		insp.placeholder:SetText("Select a tracker in the tree, or add one with + Tracker.")
		insp.crumb:SetHidden(true)
		if QAT.editor.tabBar then
			QAT.editor.tabBar:SetHidden(true)
		end
	else
		insp.placeholder:SetHidden(true)
		insp.crumb:SetHidden(false)

		-- Folders have no phases, so they are always Load scope.
		local isFolder = def.kind == "folder"
		local scope = (isFolder and "load") or (QAT.editor.selectedScope or "load")
		QAT.editor.selectedScope = scope
		renderCrumb(def)

		if scope == "phase" then
			ensureSelectedPhase(def)
			renderCrumb(def) -- selectedPhaseId may have changed
			if QAT.editor.tabBar then
				QAT.editor.tabBar:SetHidden(false)
			end
			if QAT.editor.tabButtons then
				for _, n in ipairs(PHASE_TABS) do
					QAT.editor.tabButtons[n]:SetSelected(QAT.editor.activeTab == n)
				end
			end
			local tab = QAT.editor.activeTab or "Appearance"
			local container = insp.tabContainers[tab]
			local renderer = QAT.editor.tabRenderers[tab]
			if container and renderer then
				container:SetHidden(false)
				QAT.Safe("tab " .. tab, function()
					renderer(container, def)
				end)
			end
		else
			if QAT.editor.tabBar then
				QAT.editor.tabBar:SetHidden(true)
			end
			local renderer = QAT.editor.tabRenderers["Load"]
			if renderer then
				insp.loadContainer:SetHidden(false)
				QAT.Safe("tab Load", function()
					renderer(insp.loadContainer, def)
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

	insp.nameCaption:SetHidden(not def)
	insp.nameBox:SetHidden(not def)
	insp.move:SetHidden(not def)
	insp.popout:SetHidden(not def)
	-- Size + position apply to a drawn tracker; folders have neither.
	local isFolder = def ~= nil and def.kind == "folder"
	local showTracker = def ~= nil and not isFolder
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
	insp.groupNote:SetHidden(not isFolder)
	if isFolder then
		insp.groupNote:SetText("Group container · positions are set per member aura")
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

-- Live update while a tracker is being dragged on the HUD: persist the top-left
-- position and reflect it in the X/Y boxes, without a full inspector rebuild.
function QAT.Editor_SetTrackerPosLive(id, x, y)
	local def = findDef(QAT.sv.trackers, id)
	if not def then
		return
	end
	def.pos = def.pos or {}
	def.pos.x, def.pos.y = x, y
	local insp = QAT.editor.inspector
	if insp and insp.currentId == id and insp.posXBox then
		insp.posXBox:SetText(tostring(x))
		insp.posYBox:SetText(tostring(y))
	end
end

-- Called by Display when a drag ends: persist the final top-left position and
-- refresh the inspector so its X/Y boxes track the drag.
function QAT.Editor_OnTrackerDragged(id, x, y)
	local def = findDef(QAT.sv.trackers, id)
	if not def then
		return
	end
	def.pos = def.pos or {}
	def.pos.x, def.pos.y = x, y
	if QAT.Runtime_RepositionTracker then
		QAT.Runtime_RepositionTracker(id, x, y) -- re-anchor all phases cleanly
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
	-- Header / breadcrumb / body all anchor to the pane; nothing extra yet.
end

CALLBACK_MANAGER:RegisterCallback("QAT_TrackerChanged", function(id)
	local insp = QAT.editor.inspector
	if insp and insp.currentId == id then
		QAT.Editor_Inspector_Show(id)
	end
end)
