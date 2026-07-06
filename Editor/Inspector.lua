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

function QAT.Editor_AddPhase(def, layer)
	local n = #def.phases + 1
	local id = "phase" .. n
	while phaseById(def, id) do
		n = n + 1
		id = "phase" .. n
	end
	table.insert(
		def.phases,
		{ id = id, layer = layer or 0, look = { display = "bar" }, duration = { type = "none" }, transitions = {} }
	)
	QAT.editor.selectedPhaseId = id
	QAT.editor.selectedScope = "phase"
	QAT.CanonicalizeDef(def)
	QAT.widgets.NotifyTrackerChanged(def.id)
end

-- Sorted list of the layer numbers a tracker currently uses.
function QAT.Editor_LayerList(def)
	local seen, out = {}, {}
	for _, p in ipairs(def.phases or {}) do
		local L = p.layer or 0
		if not seen[L] then
			seen[L] = true
			out[#out + 1] = L
		end
	end
	table.sort(out)
	return out
end

-- Move a phase into another layer (via a tree drag). No-op if it's already there.
-- Keeps the phase selected so the editor stays put.
function QAT.Editor_MovePhaseToLayer(def, phaseId, targetLayer)
	local moved = false
	for _, p in ipairs(def.phases) do
		if p.id == phaseId and (p.layer or 0) ~= targetLayer then
			p.layer = targetLayer
			moved = true
			break
		end
	end
	if not moved then
		return
	end
	QAT.CanonicalizeDef(def)
	if QAT.Editor_SelectPhase then
		QAT.Editor_SelectPhase(def.id, phaseId)
	end
	QAT.widgets.NotifyTrackerChanged(def.id)
end

-- Set one per-layer display setting (align | visible).
function QAT.Editor_SetLayerSetting(def, layer, key, value)
	def.layerSettings = def.layerSettings or {}
	def.layerSettings[layer] = def.layerSettings[layer] or {}
	def.layerSettings[layer][key] = value
	QAT.CanonicalizeDef(def)
	QAT.widgets.NotifyTrackerChanged(def.id)
end

-- Move a layer forward (toward the front / higher number) or back in the stack by
-- swapping it with its neighbour: every phase's layer, plus the two layers' settings
-- and initial phases, are exchanged. Returns the layer's new number (for reselection).
function QAT.Editor_MoveLayer(def, layer, dir)
	local layers = QAT.Editor_LayerList(def)
	local idx
	for i, L in ipairs(layers) do
		if L == layer then
			idx = i
			break
		end
	end
	if not idx then
		return layer
	end
	local other = dir == "forward" and layers[idx + 1] or layers[idx - 1]
	if not other then
		return layer -- already at an end
	end
	-- Swap the two layer numbers across all phases (via a temporary sentinel).
	local TMP = -999
	for _, p in ipairs(def.phases) do
		if (p.layer or 0) == layer then
			p.layer = TMP
		end
	end
	for _, p in ipairs(def.phases) do
		if (p.layer or 0) == other then
			p.layer = layer
		end
	end
	for _, p in ipairs(def.phases) do
		if p.layer == TMP then
			p.layer = other
		end
	end
	def.layerSettings = def.layerSettings or {}
	def.layerSettings[layer], def.layerSettings[other] = def.layerSettings[other], def.layerSettings[layer]
	def.layerInitial = def.layerInitial or {}
	def.layerInitial[layer], def.layerInitial[other] = def.layerInitial[other], def.layerInitial[layer]
	if layer == 0 or other == 0 then
		def.initial = def.layerInitial[0]
	end
	QAT.CanonicalizeDef(def)
	QAT.widgets.NotifyTrackerChanged(def.id)
	return other
end

-- Add a new parallel layer: a fresh phase on the next unused layer, which becomes
-- that layer's initial (via canonicalize). Layers run concurrently and draw in
-- ascending order (lowest = back, highest = front).
function QAT.Editor_AddLayer(def)
	local maxLayer = 0
	for _, p in ipairs(def.phases) do
		if (p.layer or 0) > maxLayer then
			maxLayer = p.layer or 0
		end
	end
	QAT.Editor_AddPhase(def, maxLayer + 1)
end

-- Transplant another tracker def's phases into `target` as a brand-new parallel layer
-- (one layer above the current maximum). Phase ids are made unique and their in-layer
-- transitions remapped, so the incoming state machine keeps working alongside the
-- existing layers. The source's starting phase becomes the new layer's initial. Used by
-- the aggregator's "add to existing tracker" action. Returns the new layer index.
function QAT.Editor_AddDefAsLayer(target, sourceDef)
	if not target or not sourceDef or not sourceDef.phases or #sourceDef.phases == 0 then
		return
	end
	local newLayer = 0
	for _, p in ipairs(target.phases) do
		newLayer = math.max(newLayer, p.layer or 0)
	end
	newLayer = newLayer + 1

	-- Keep the incoming phase ids as-is where they don't clash with the target's; a
	-- clash just gets a "_2"/"_3" suffix (never a layer-number suffix, which leaked the
	-- internal mechanism into user-facing names).
	local used = {}
	for _, p in ipairs(target.phases) do
		used[p.id] = true
	end
	local remap = {}
	for _, p in ipairs(sourceDef.phases) do
		remap[p.id] = QAT.util.UniqueSlug(p.id, "phase", used)
	end
	for _, p in ipairs(sourceDef.phases) do
		local np = QAT.util.DeepCopy(p)
		np.id = remap[p.id]
		np.layer = newLayer
		for _, tr in ipairs(np.transitions or {}) do
			if tr.to and remap[tr.to] then
				tr.to = remap[tr.to]
			end
		end
		target.phases[#target.phases + 1] = np
	end

	local srcInit = (sourceDef.layerInitial and sourceDef.layerInitial[0])
		or sourceDef.initial
		or sourceDef.phases[1].id
	target.layerInitial = target.layerInitial or {}
	target.layerInitial[newLayer] = remap[srcInit] or remap[sourceDef.phases[1].id]

	QAT.CanonicalizeDef(target)
	QAT.widgets.NotifyTrackerChanged(target.id)
	return newLayer
end

function QAT.Editor_SetInitialPhase(def, phaseId)
	-- "Initial" is per layer: set this phase as its layer's start. Layer 0 also drives
	-- def.initial (the canonical layer-0 start).
	local layer = 0
	for _, p in ipairs(def.phases) do
		if p.id == phaseId then
			layer = p.layer or 0
			break
		end
	end
	def.layerInitial = def.layerInitial or {}
	def.layerInitial[layer] = phaseId
	if layer == 0 then
		def.initial = phaseId
	end
	QAT.CanonicalizeDef(def)
	QAT.widgets.NotifyTrackerChanged(def.id)
end

-- Is this phase its layer's starting phase? (Layer-aware INITIAL badge.)
function QAT.Editor_IsInitialPhase(def, phaseId)
	for _, p in ipairs(def.phases) do
		if p.id == phaseId then
			local li = def.layerInitial and def.layerInitial[p.layer or 0]
			return li == phaseId or ((p.layer or 0) == 0 and def.initial == phaseId)
		end
	end
	return false
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
	local l = QAT.widgets.Label(b, name .. "_L", "", "$(BOLD_FONT)|13|soft-shadow-thin")
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
	-- The size box is Width × Height for the whole tracker. Bars fill it with a square
	-- icon on the left (Height × Height); Icon and Border phases are square and use
	-- Height for both, so Width doesn't affect them. Captions + tooltips make that clear.
	local SIZE_TIP = "Tracker box in pixels: Width × Height.\n"
		.. "• Bar: fills the box; the left icon is square (Height × Height).\n"
		.. "• Icon / Border: square — uses Height for both, so Width is ignored."
	insp.sizeCaption = QAT.widgets.Label(row1, "QAT_Insp_SizeCaption", "Size (W×H)")
	insp.sizeCaption:SetAnchor(LEFT, insp.nameBox, RIGHT, 18, 0)
	QAT.widgets.Tooltip(insp.sizeCaption, SIZE_TIP)
	insp.widthBox = QAT.widgets.EditBox(row1, "QAT_Insp_WidthBox", 54, 22)
	insp.widthBox:SetAnchor(LEFT, insp.sizeCaption, RIGHT, 6, 0)
	insp.widthBox.onChange = dimChange("width")
	QAT.widgets.Tooltip(insp.widthBox, "Width (px). Used by Bar phases; ignored by square Icon/Border phases.")
	insp.sizeX = QAT.widgets.Label(row1, "QAT_Insp_SizeX", "x")
	insp.sizeX:SetAnchor(LEFT, insp.widthBox, RIGHT, 4, 0)
	insp.heightBox = QAT.widgets.EditBox(row1, "QAT_Insp_HeightBox", 54, 22)
	insp.heightBox:SetAnchor(LEFT, insp.sizeX, RIGHT, 4, 0)
	insp.heightBox.onChange = dimChange("height")
	QAT.widgets.Tooltip(
		insp.heightBox,
		"Height (px). The bar height, and the square size of Icon/Border phases and the bar's left icon."
	)

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

	-- Row 1 right group: Center (recentre the tracker on screen).
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
	insp.move:SetAnchor(RIGHT, row1, RIGHT, 0, 0)
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

	-- One scroll viewport per per-phase tab, plus an aura-wide Load viewport; the
	-- body shows exactly one at a time. Each is a ZO_ScrollContainer that clips and
	-- scrolls its content; renderers draw into its ScrollChild (the "container"),
	-- which resizes to fit so the scrollbar/mouse-wheel track the content height.
	local function makeViewport(name)
		local sc = WM:CreateControlFromVirtual(name, body, "ZO_ScrollContainer")
		sc:SetAnchor(TOPLEFT, body, TOPLEFT, 0, 0)
		sc:SetAnchor(BOTTOMRIGHT, body, BOTTOMRIGHT, 0, 0)
		sc:SetHidden(true)
		local child = GetControl(sc, "ScrollChild")
		child:SetResizeToFitDescendents(true)
		child:SetResizeToFitPadding(0, 16)
		return sc, child
	end

	insp.tabScrolls = {}
	insp.tabContainers = {}
	for _, tabName in ipairs(PHASE_TABS) do
		local sc, child = makeViewport("QAT_Insp_Tab_" .. tabName)
		insp.tabScrolls[tabName] = sc
		insp.tabContainers[tabName] = child
	end
	insp.loadScroll, insp.loadContainer = makeViewport("QAT_Insp_LoadContainer")

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
		local isInitial = QAT.Editor_IsInitialPhase(def, QAT.editor.selectedPhaseId)
		insp.crumbBadge:SetText("INITIAL")
		insp.crumbBadge:SetHidden(not isInitial)
		insp.setInitBtn:SetHidden(false)
		insp.setInitBtn:SetSelected(isInitial)
		insp.delPhaseBtn:SetHidden(false)
	elseif scope == "layer" and not isFolder then
		insp.crumbLeaf:SetText("Layer " .. ((QAT.editor.selectedLayer or 0) + 1))
		insp.crumbBadge:SetHidden(true)
		insp.setInitBtn:SetHidden(true)
		insp.delPhaseBtn:SetHidden(true)
	elseif scope == "grid" and isFolder then
		insp.crumbLeaf:SetText("Grid layout")
		insp.crumbBadge:SetText("GROUP")
		insp.crumbBadge:SetHidden(false)
		insp.setInitBtn:SetHidden(true)
		insp.delPhaseBtn:SetHidden(true)
	else
		insp.crumbLeaf:SetText("Load")
		insp.crumbBadge:SetText(isFolder and "GROUP" or "AURA")
		insp.crumbBadge:SetHidden(false)
		insp.setInitBtn:SetHidden(true)
		insp.delPhaseBtn:SetHidden(true)
	end
end

-- The Layer settings card (layer scope): stack order, x/y offset from the tracker
-- origin, and a visibility toggle. Rendered into the shared load scroll container.
function QAT.Editor_RenderLayerCard(container, def)
	local pool = container.pool or QAT.widgets.NewPool()
	container.pool = pool
	QAT.widgets.PoolBegin(pool)
	local function get(k, f)
		return QAT.widgets.PoolGet(pool, k, f)
	end

	QAT.CanonicalizeDef(def)
	local layer = QAT.editor.selectedLayer or 0
	local layers = QAT.Editor_LayerList(def)
	local idx = 1
	for i, L in ipairs(layers) do
		if L == layer then
			idx = i
		end
	end
	local posLabel = (idx == 1 and "back") or (idx == #layers and "front") or nil
	def.layerSettings = def.layerSettings or {}
	local s = def.layerSettings[layer] or { align = "topleft", visible = true }

	local cw = container.qatViewportW or container:GetWidth()
	if cw < 240 then
		cw = 900
	end
	local OUT, ROW = 14, 34
	local card = get("card", function()
		return QAT.widgets.Card(container, "QAT_Layer_Card", "Layer")
	end)
	card:SetTitle("Layer " .. (layer + 1) .. (posLabel and ("  ·  " .. posLabel) or ""))
	card:ClearAnchors()
	card:SetAnchor(TOPLEFT, container, TOPLEFT, OUT, OUT)
	local PAD = OUT + card.padX
	local LX = PAD + 120
	local y = OUT + card.contentY

	local sub = get("sub", function()
		return QAT.widgets.Label(container, "QAT_Layer_Sub", "")
	end)
	sub:SetText("Controls this layer of the parallel stack. Drag a phase in the tree to move it between layers.")
	sub:SetColor(0.55, 0.6, 0.7, 1)
	sub:ClearAnchors()
	sub:SetAnchor(TOPLEFT, container, TOPLEFT, PAD, y)
	y = y + 30

	local function rowLabel(key, text)
		local l = get("L" .. key, function()
			return QAT.widgets.Label(container, "QAT_Layer_L" .. key, "")
		end)
		l:SetText(text)
		l:ClearAnchors()
		l:SetAnchor(TOPLEFT, container, TOPLEFT, PAD, y + 4)
	end

	-- Stack order: Forward (toward front) / Back (toward behind).
	rowLabel("Order", "Stack order")
	local fwd = get("fwd", function()
		return QAT.widgets.TextButton(container, "QAT_Layer_Fwd", "Forward", nil)
	end)
	fwd:SetHeight(26)
	fwd:ClearAnchors()
	fwd:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y)
	fwd.onClick = function()
		QAT.Editor_SelectLayer(def.id, QAT.Editor_MoveLayer(def, layer, "forward"))
	end
	local back = get("back", function()
		return QAT.widgets.TextButton(container, "QAT_Layer_Back", "Back", nil)
	end)
	back:SetHeight(26)
	back:ClearAnchors()
	back:SetAnchor(LEFT, fwd, RIGHT, 8, 0)
	back.onClick = function()
		QAT.Editor_SelectLayer(def.id, QAT.Editor_MoveLayer(def, layer, "back"))
	end
	y = y + ROW + 4

	-- Alignment: where this layer sits within the tracker's box. Only matters when the
	-- layer is narrower than the box (e.g. a square icon over a wide bar) — layers stack
	-- at the shared origin, there is no free x/y offset.
	rowLabel("Align", "Alignment")
	local alignOpts = {
		{ label = "Top left", value = "topleft" },
		{ label = "Top", value = "top" },
		{ label = "Top right", value = "topright" },
		{ label = "Left", value = "left" },
		{ label = "Center", value = "center" },
		{ label = "Right", value = "right" },
		{ label = "Bottom left", value = "bottomleft" },
		{ label = "Bottom", value = "bottom" },
		{ label = "Bottom right", value = "bottomright" },
	}
	local align = get("align", function()
		return QAT.widgets.Dropdown(container, "QAT_Layer_Align", 160, alignOpts, "topleft", nil)
	end)
	align:SetOptions(alignOpts)
	align:SetValue(s.align or "topleft")
	align:ClearAnchors()
	align:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y)
	align.onSelect = function(v)
		QAT.Editor_SetLayerSetting(def, layer, "align", v)
	end
	y = y + ROW + 4

	-- Visibility.
	rowLabel("Vis", "Layer visible")
	local chk = get("vis", function()
		return QAT.widgets.Checkbox(container, "QAT_Layer_Vis", true)
	end)
	chk:SetChecked(s.visible ~= false)
	chk:ClearAnchors()
	chk:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y)
	local visLbl = get("visLbl", function()
		return QAT.widgets.Label(container, "QAT_Layer_VisLbl", "")
	end)
	visLbl:SetText(s.visible ~= false and "shown" or "hidden")
	visLbl:ClearAnchors()
	visLbl:SetAnchor(LEFT, chk, RIGHT, 10, 0)
	chk.onToggle = function(v)
		visLbl:SetText(v and "shown" or "hidden")
		QAT.Editor_SetLayerSetting(def, layer, "visible", v)
	end
	y = y + ROW + 4

	card:SetDimensions(cw - OUT * 2, (y - OUT) + 10)
	QAT.widgets.PoolEnd(pool)
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

	for _, sc in pairs(insp.tabScrolls or {}) do
		sc:SetHidden(true)
	end
	insp.loadScroll:SetHidden(true)
	-- The viewport width renderers should lay out against (the scroll child fits its
	-- content, so its own width can't be read for this). Leave room for the scrollbar.
	local viewportW = insp.body:GetWidth() - 16

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

		-- Folders have no phases: they are Load scope, or Grid scope when arranged as a
		-- table (a grid-enabled group selected on its "Grid layout" row).
		local isFolder = def.kind == "folder"
		local scope = QAT.editor.selectedScope or "load"
		if isFolder then
			local gridScope = scope == "grid" and def.grid and def.grid.enabled
			scope = gridScope and "grid" or "load"
		end
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
				insp.tabScrolls[tab]:SetHidden(false)
				container.qatViewportW = viewportW
				QAT.Safe("tab " .. tab, function()
					renderer(container, def)
				end)
			end
		elseif scope == "layer" then
			if QAT.editor.tabBar then
				QAT.editor.tabBar:SetHidden(true)
			end
			insp.loadScroll:SetHidden(false)
			insp.loadContainer.qatViewportW = viewportW
			QAT.Safe("tab Layer", function()
				QAT.Editor_RenderLayerCard(insp.loadContainer, def)
			end)
		elseif scope == "grid" then
			if QAT.editor.tabBar then
				QAT.editor.tabBar:SetHidden(true)
			end
			insp.loadScroll:SetHidden(false)
			insp.loadContainer.qatViewportW = viewportW
			QAT.Safe("tab Grid", function()
				QAT.Editor_RenderGridCard(insp.loadContainer, def)
			end)
		else
			if QAT.editor.tabBar then
				QAT.editor.tabBar:SetHidden(true)
			end
			local renderer = QAT.editor.tabRenderers["Load"]
			if renderer then
				insp.loadScroll:SetHidden(false)
				insp.loadContainer.qatViewportW = viewportW
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
	-- Header / breadcrumb / body anchor to the pane automatically; re-render the
	-- active tab so its fixed-width cards pick up the new viewport width.
	if QAT.editor.inspector and QAT.editor.inspector.currentId then
		refreshBody()
	end
end

CALLBACK_MANAGER:RegisterCallback("QAT_TrackerChanged", function(id)
	local insp = QAT.editor.inspector
	if insp and insp.currentId == id then
		QAT.Editor_Inspector_Show(id)
	end
end)

-- Keep the "current loadout" card live: when worn slots change (equip/unequip),
-- re-render the Load scope. Trailing-debounced via RegisterForUpdate so a mass gear
-- swap (e.g. Wizard's Wardrobe changing every slot at once) settles into a single
-- rebuild ~150ms after the last change, rather than one per slot.
local WORN_EVT = QAT.name .. "_WornChanged"
local WORN_TICK = QAT.name .. "_WornRefresh"
local function scheduleLoadoutRefresh()
	local insp = QAT.editor.inspector
	if not (QAT.editor.frame and not QAT.editor.frame:IsHidden() and insp and insp.currentId) then
		return
	end
	if (QAT.editor.selectedScope or "load") ~= "load" then
		return -- the loadout card only shows in Load scope
	end
	EVENT_MANAGER:UnregisterForUpdate(WORN_TICK) -- reset the timer on each change
	EVENT_MANAGER:RegisterForUpdate(WORN_TICK, 150, function()
		EVENT_MANAGER:UnregisterForUpdate(WORN_TICK) -- one-shot
		if QAT.Editor_Inspector_Refresh then
			QAT.Editor_Inspector_Refresh()
		end
	end)
end
EVENT_MANAGER:RegisterForEvent(WORN_EVT, EVENT_INVENTORY_SINGLE_SLOT_UPDATE, scheduleLoadoutRefresh)
EVENT_MANAGER:AddFilterForEvent(WORN_EVT, EVENT_INVENTORY_SINGLE_SLOT_UPDATE, REGISTER_FILTER_BAG_ID, BAG_WORN)
