-- Tree pane: the tracker/folder hierarchy with an add/delete toolbar. Scope lives
-- in the tree, not in a toggle: an expanded tracker reveals its "Load conditions"
-- row (aura-wide) followed by one row per phase and a "+ add phase" row. Selecting
-- the tracker or its Load row shows the aura-wide Load panel; selecting a phase row
-- shows that phase's Appearance / Behavior / Conditions tabs.
--
-- Only one tracker is expanded at a time (auto-expand-selected): selecting a tracker
-- expands it and collapses any other. Rows are rebuilt wholesale from the def tree
-- whenever it changes, which is fine for the expected node counts.

local WM = GetWindowManager()
local TOOLBAR_H, ROW_H, INDENT = 30, 36, 16

local idCounter = 0
local function newId(prefix)
	idCounter = idCounter + 1
	return prefix .. GetTimeStamp() .. "_" .. idCounter
end

-- Depth-first remove of a def by id from the tree. Returns true if removed.
local function removeById(defs, id)
	for i, def in ipairs(defs) do
		if def.id == id then
			table.remove(defs, i)
			return true
		end
		if def.children and removeById(def.children, id) then
			return true
		end
	end
	return false
end

-- Depth-first find of a def by id.
local function findNode(defs, id)
	for _, def in ipairs(defs) do
		if def.id == id then
			return def
		end
		if def.children then
			local found = findNode(def.children, id)
			if found then
				return found
			end
		end
	end
	return nil
end

-- The list (and index) that directly contains id, so a node can be inserted next
-- to it as a sibling.
local function findParentList(defs, id)
	for i, def in ipairs(defs) do
		if def.id == id then
			return defs, i
		end
		if def.children then
			local list, idx = findParentList(def.children, id)
			if list then
				return list, idx
			end
		end
	end
	return nil
end

-- True if id is within node's subtree (so we never drop a folder into itself).
local function isInSubtree(node, id)
	if node.id == id then
		return true
	end
	for _, c in ipairs(node.children or {}) do
		if isInSubtree(c, id) then
			return true
		end
	end
	return false
end

-- Absolute screen anchor of the group directly containing `id` (0,0 if top-level).
-- A node's stored position is relative to this, so reparenting must re-base it.
local function parentAnchorOf(id)
	local function walk(defs, ax, ay)
		for _, def in ipairs(defs or {}) do
			if def.id == id then
				return ax, ay, true
			end
			if def.kind == "folder" then
				local p = def.pos or { x = 0, y = 0 }
				local rx, ry, found = walk(def.children, ax + (p.x or 0), ay + (p.y or 0))
				if found then
					return rx, ry, true
				end
			end
		end
		return ax, ay, false
	end
	local x, y = walk(QAT.sv.trackers, 0, 0)
	return x or 0, y or 0
end

-- Snapshot a node's absolute screen position before a reparent.
local function absPosOf(node, id)
	local ax, ay = parentAnchorOf(id)
	local p = node.pos or { x = 0, y = 0 }
	return ax + (p.x or 0), ay + (p.y or 0)
end

-- After a reparent, rewrite the node's relative position so it stays on screen exactly
-- where it was (its new parent anchor may differ from the old one).
local function rebaseAfterReparent(node, id, absx, absy)
	local nax, nay = parentAnchorOf(id)
	node.pos = node.pos or {}
	node.pos.x = absx - nax
	node.pos.y = absy - nay
end

-- Move a node by drag-drop: onto a folder nests it inside; onto a tracker makes it
-- a sibling next to it; onto empty space moves it to the top level.
local function dropNode(dragId, targetDef)
	if not dragId or (targetDef and dragId == targetDef.id) then
		return
	end
	local dragged = findNode(QAT.sv.trackers, dragId)
	if not dragged then
		return
	end
	if targetDef and isInSubtree(dragged, targetDef.id) then
		return -- can't move a group into its own descendant
	end
	-- Preserve the node's on-screen position across the reparent (its position is
	-- relative to its parent group's anchor, which is about to change).
	local absx, absy = absPosOf(dragged, dragId)
	removeById(QAT.sv.trackers, dragId)
	if targetDef and targetDef.kind == "folder" then
		targetDef.children = targetDef.children or {}
		table.insert(targetDef.children, dragged)
	elseif targetDef then
		local list, idx = findParentList(QAT.sv.trackers, targetDef.id)
		if list then
			table.insert(list, idx + 1, dragged)
		else
			table.insert(QAT.sv.trackers, dragged)
		end
	else
		table.insert(QAT.sv.trackers, dragged) -- dropped on empty space
	end
	rebaseAfterReparent(dragged, dragId, absx, absy)
	QAT.CanonicalizeTree(QAT.sv.trackers)
	QAT.widgets.NotifyTrackerChanged() -- load chain changed; rebuild runtime + views
	QAT.Editor_Tree_Build()
end

-- ===== Scope selection (drives the inspector; the tree owns the child rows) =====

-- Select a folder or the aura-wide Load scope of a tracker. Selecting a tracker
-- also expands it (and collapses any other expanded tracker).
local function selectNode(id)
	QAT.log.editor:Debug("select node '%s'", tostring(id))
	local def = findNode(QAT.sv.trackers, id)
	QAT.editor.selectedId = id
	QAT.editor.selectedScope = "load"
	if def and def.kind ~= "folder" then
		QAT.editor.expandedTracker = id
	end
	QAT.Editor_Tree_Build()
	if QAT.Editor_Inspector_Show then
		QAT.Editor_Inspector_Show(id)
	end
end
QAT.Editor_SelectNode = selectNode

-- Select the aura-wide Load scope (the tracker's "Load conditions" row).
function QAT.Editor_SelectLoad(id)
	QAT.editor.selectedId = id
	QAT.editor.selectedScope = "load"
	QAT.editor.expandedTracker = id
	QAT.Editor_Tree_Build()
	if QAT.Editor_Inspector_Show then
		QAT.Editor_Inspector_Show(id)
	end
end

-- Select a layer of a tracker (layer scope) — shows the Layer settings card.
function QAT.Editor_SelectLayer(id, layer)
	QAT.editor.selectedId = id
	QAT.editor.selectedScope = "layer"
	QAT.editor.selectedLayer = layer
	QAT.editor.expandedTracker = id
	QAT.Editor_Tree_Build()
	if QAT.Editor_Inspector_Show then
		QAT.Editor_Inspector_Show(id)
	end
end

-- Select a group's grid-layout scope (folders with grid enabled) — shows the table
-- builder card.
function QAT.Editor_SelectGrid(id)
	QAT.editor.selectedId = id
	QAT.editor.selectedScope = "grid"
	QAT.Editor_Tree_Build()
	if QAT.Editor_Inspector_Show then
		QAT.Editor_Inspector_Show(id)
	end
end

-- Select a phase of a tracker (phase scope).
function QAT.Editor_SelectPhase(id, phaseId)
	QAT.editor.selectedId = id
	QAT.editor.selectedScope = "phase"
	QAT.editor.selectedPhaseId = phaseId
	QAT.editor.expandedTracker = id
	QAT.Editor_Tree_Build()
	if QAT.Editor_Inspector_Show then
		QAT.Editor_Inspector_Show(id)
	end
end

-- A complete single-phase tracker the inspector can render immediately: a flat
-- default run through CanonicalizeDef.
local function newTrackerDef()
	return QAT.CanonicalizeDef({
		id = newId("tracker_"),
		kind = "tracker",
		display = "bar",
		name = "New Tracker",
		abilityIds = {},
		unit = "player",
		x = math.floor(GuiRoot:GetWidth() / 2 - 110), -- centred (top-left origin, 220x30)
		y = math.floor(GuiRoot:GetHeight() / 2 - 15),
		enabled = true,
	})
end

local function addTracker()
	local def = newTrackerDef()
	table.insert(QAT.sv.trackers, def)
	QAT.log.editor:Debug("added tracker '%s'", def.id)
	selectNode(def.id)
	if QAT.Editor_ShowAddTrackerHint then
		QAT.Editor_ShowAddTrackerHint()
	end
end

local function addGroup()
	local def = { id = newId("group_"), kind = "folder", name = "New Group", children = {}, enabled = true }
	table.insert(QAT.sv.trackers, def)
	QAT.log.editor:Debug("added group '%s'", def.id)
	selectNode(def.id)
end

-- Add a dynamic tracker: a top-level entry whose own phases are stamped once per live
-- target emitted by a source (e.g. taunt). Pre-seeded with idle + active phases wired
-- to the source.
local function addDynamicTracker()
	local source = (QAT.Targeting and QAT.Targeting.SourceNames() or {})[1]
	local cx = math.floor(GuiRoot:GetWidth() / 2 - 110)
	local def = QAT.CanonicalizeDef({
		id = newId("dyn_"),
		kind = "dynamic",
		name = "Dynamic Tracker",
		enabled = true,
		source = source,
		columns = 2,
		fill = { axis = "rows", from = "left" },
		pos = { x = cx, y = 300, width = 220, height = 30 },
		initial = "idle",
		phases = {
			{
				id = "idle",
				layer = 0,
				look = { display = "none" },
				duration = { type = "none" },
				transitions = { { when = { kind = "source", result = "gained" }, to = "active" } },
			},
			{
				id = "active",
				layer = 0,
				look = { display = "bar", showTime = true },
				duration = { type = "source" },
				transitions = {},
			},
		},
	})
	QAT.CanonicalizeDynamicDef(def)
	table.insert(QAT.sv.trackers, def)
	QAT.log.editor:Debug("added dynamic tracker '%s' (source=%s)", def.id, tostring(source))
	QAT.widgets.NotifyTrackerChanged()
	selectNode(def.id)
end

-- Add a fresh tracker straight into a group and land on it. Called by the group's
-- "+ add tracker" tree row and its Members card button.
function QAT.Editor_AddTrackerToGroup(groupId)
	local g = findNode(QAT.sv.trackers, groupId)
	if not g or g.kind ~= "folder" then
		return
	end
	g.children = g.children or {}
	local def = newTrackerDef()
	-- newTrackerDef centres on screen in absolute coords; re-base to the group anchor so
	-- it lands centred rather than offset by the group's position.
	local absx, absy = (def.pos and def.pos.x) or 0, (def.pos and def.pos.y) or 0
	table.insert(g.children, def)
	rebaseAfterReparent(def, def.id, absx, absy)
	QAT.editor.collapsed[groupId] = nil -- keep the group open so the new row shows
	QAT.log.editor:Debug("added tracker '%s' to group '%s'", def.id, groupId)
	QAT.CanonicalizeTree(QAT.sv.trackers)
	QAT.widgets.NotifyTrackerChanged() -- load chain changed; rebuild runtime + views
	selectNode(def.id)
end

-- Remove a tracker from its group, keeping it as a top-level tracker (non-
-- destructive; the tracker and its phases are preserved). Called by the Members
-- card's remove button.
function QAT.Editor_UnparentTracker(trackerId)
	local dragged = findNode(QAT.sv.trackers, trackerId)
	if not dragged then
		return
	end
	-- Keep it where it is on screen: its absolute position becomes its new top-level
	-- position (top-level anchor is the origin).
	local absx, absy = absPosOf(dragged, trackerId)
	removeById(QAT.sv.trackers, trackerId)
	table.insert(QAT.sv.trackers, dragged)
	rebaseAfterReparent(dragged, trackerId, absx, absy)
	QAT.log.editor:Debug("unparented tracker '%s' to top level", trackerId)
	QAT.CanonicalizeTree(QAT.sv.trackers)
	QAT.widgets.NotifyTrackerChanged() -- load chain changed; rebuild runtime + views
	QAT.Editor_Tree_Build()
end

local function performDelete(id)
	if removeById(QAT.sv.trackers, id) then
		QAT.log.editor:Debug("deleted node '%s'", tostring(id))
		QAT.editor.selectedId = nil
		if QAT.editor.expandedTracker == id then
			QAT.editor.expandedTracker = nil
		end
		QAT.Editor_Tree_Build()
		if QAT.Editor_Inspector_Show then
			QAT.Editor_Inspector_Show(nil)
		end
		QAT.widgets.NotifyTrackerChanged() -- rebuild the HUD so the deleted tracker vanishes
	end
end

local function deleteSelected()
	local id = QAT.editor.selectedId
	if not id then
		return
	end
	local def = QAT.Editor_FindDef and QAT.Editor_FindDef(QAT.sv.trackers, id)
	local name = (def and (def.name or def.id)) or "this tracker"
	if QAT.Editor_ConfirmDelete then
		QAT.Editor_ConfirmDelete(name, function()
			performDelete(id)
		end)
	else
		performDelete(id)
	end
end

local rows = {}
local ICON_SIZE = 18
local CHECK_ON = "EsoUI/Art/Buttons/checkbox_checked.dds"
local CHECK_OFF = "EsoUI/Art/Buttons/checkbox_unchecked.dds"
local ARROW_OPEN = "EsoUI/Art/Buttons/tree_open_up.dds"
local ARROW_CLOSED = "EsoUI/Art/Buttons/tree_closed_up.dds"
local ICON_MISSING = "/esoui/art/icons/icon_missing.dds"

local BG_FULL = { 0.21, 0.40, 0.72, 0.55 } -- the exact selected target
local BG_SUBTLE = { 0.21, 0.40, 0.72, 0.22 } -- the ancestor tracker of the selection
local BG_NONE = { 0, 0, 0, 0 }

-- Per-folder collapse state (editor-session only, not persisted). Trackers use the
-- single-slot expandedTracker instead (auto-expand-selected).
QAT.editor.collapsed = QAT.editor.collapsed or {}

-- Best icon to represent a tracker in the tree: the resolved icon of the first
-- phase that has one (falling back to source icon for dynamic defs), else a
-- placeholder.
local function trackerIcon(def)
	if def.kind == "dynamic" and def.source then
		local srcIcon = QAT.Targeting and QAT.Targeting.GetIcon(def.source)
		if srcIcon then
			return srcIcon
		end
	end
	for _, p in ipairs(def.phases or {}) do
		local ic = QAT.util.PhaseIcon(p, def)
		if ic then
			return ic
		end
	end
	return ICON_MISSING
end

-- Count the trackers ("auras") in a group, including any nested in sub-groups.
local function countAuras(def)
	local n = 0
	for _, c in ipairs(def.children or {}) do
		if c.kind == "folder" then
			n = n + countAuras(c)
		else
			n = n + 1
		end
	end
	return n
end

-- A small bordered badge (AURA, INITIAL) cached on its owning row.
local function ensureBadge(row, name, r, g, b)
	local badge = row.badge
	if not badge then
		badge = WM:CreateControl(name, row, CT_BACKDROP)
		badge:SetCenterColor(0.16, 0.22, 0.34, 1)
		badge:SetEdgeColor(0.30, 0.40, 0.58, 1)
		badge:SetEdgeTexture("", 1, 1, 1)
		local l = QAT.widgets.Label(badge, name .. "_L", "", "$(BOLD_FONT)|10|soft-shadow-thin")
		l:SetAnchor(CENTER, badge, CENTER, 0, 0)
		badge:SetHeight(14)
		badge.label = l
		function badge:SetText(s)
			self.label:SetText(s)
			self:SetWidth(self.label:GetTextWidth() + 10)
		end
		row.badge = badge
	end
	badge.label:SetColor(r, g, b, 1)
	return badge
end

-- A small status square cached on its owning row.
local function ensureDot(row, name)
	local dot = row.dot
	if not dot then
		dot = WM:CreateControl(name, row, CT_BACKDROP)
		dot:SetDimensions(8, 8)
		dot:SetEdgeColor(0, 0, 0, 0)
		row.dot = dot
	end
	return dot
end

-- A small phase-icon texture cached on its owning row, shown on the right edge.
local function ensurePhaseIcon(row, name)
	local ic = row.phaseIcon
	if not ic then
		ic = WM:CreateControl(name, row, CT_TEXTURE)
		ic:SetDimensions(16, 16)
		row.phaseIcon = ic
	end
	return ic
end

-- Row width, tracking the scroll viewport (set each build). Rows are fixed-width
-- and left-anchored so the scroll child can resize-to-fit vertically without a
-- circular width dependency.
local treeRowW = 280

-- Shared row shell: a pooled Clickable at y, sized to the viewport width.
local function baseRow(parent, name, y)
	local row = rows[name] or QAT.widgets.Clickable(parent, name, BG_NONE)
	rows[name] = row
	row:SetHidden(false)
	row.dropLayer = nil -- cleared each build; only layer/phase/add rows set it
	row:ClearAnchors()
	row:SetAnchor(TOPLEFT, parent, TOPLEFT, 0, y)
	row:SetDimensions(treeRowW, ROW_H)
	return row
end

local function setBg(row, bg)
	row.bg:SetCenterColor(unpack(bg))
end

-- The tracker/folder def a drop at screen-Y should target, or nil for empty space.
-- Top-level rows carry defId; virtual child rows carry dropId pointing at their
-- owning tracker/group, so dropping over a phase or member row still resolves to a
-- sensible node.
local function rowAt(my)
	if not my then
		return nil
	end
	for _, row in pairs(rows) do
		local id = row.dropId or row.defId
		if not row:IsHidden() and id and my >= row:GetTop() and my <= row:GetBottom() then
			return findNode(QAT.sv.trackers, id)
		end
	end
	return nil
end

-- The owning tracker id + layer number a drop at screen-Y targets, for phase drags.
-- Layer/phase/add rows carry dropId (tracker) + dropLayer; others leave dropLayer nil.
local function rowLayerAt(my)
	if not my then
		return nil
	end
	for _, row in pairs(rows) do
		if
			not row:IsHidden()
			and row.dropId
			and row.dropLayer ~= nil
			and my >= row:GetTop()
			and my <= row:GetBottom()
		then
			return row.dropId, row.dropLayer
		end
	end
	return nil
end

-- A shared mouse-up for tree rows: complete an in-progress drag (drop onto the row
-- under the cursor) or, if it was a plain click, run the row's own action. ESO has
-- no implicit mouse capture, so the release may land on a different row than the
-- press; both ends read the shared drag state, so either row can finish the drop.
local function rowMouseUp(clickAction)
	return function(_, button, upInside)
		if button ~= MOUSE_BUTTON_INDEX_LEFT then
			return
		end
		local _, my = GetUIMousePosition()
		local moved = math.abs((my or 0) - (QAT.editor.treeDragY or 0)) > 8

		-- A phase being dragged between layers takes precedence over node reparenting.
		local pd = QAT.editor.treePhaseDrag
		if pd then
			QAT.editor.treePhaseDrag = nil
			if moved then
				local dropId, dropLayer = rowLayerAt(my)
				if dropId == pd.id and dropLayer ~= nil and QAT.Editor_MovePhaseToLayer then
					local d = findNode(QAT.sv.trackers, pd.id)
					if d then
						QAT.Editor_MovePhaseToLayer(d, pd.phaseId, dropLayer)
					end
				end
			elseif upInside and clickAction then
				clickAction()
			end
			QAT.editor.treeDragId = nil
			return
		end

		local dragging = QAT.editor.treeDragId ~= nil
		if dragging and moved then
			dropNode(QAT.editor.treeDragId, rowAt(my))
		elseif upInside and clickAction then
			clickAction()
		end
		QAT.editor.treeDragId = nil
	end
end

-- A top-level tracker or folder row. Trackers get a disclosure arrow + icon and,
-- when expanded, are followed by their virtual child rows. Folders keep the
-- collapse arrow. Drag-drop reparenting lives here.
local function makeRow(parent, def, depth, y)
	local name = "QAT_TreeRow_" .. def.id
	local isFolder = def.kind == "folder"
	local isDynamic = def.kind == "dynamic"
	local enabled = def.enabled ~= false

	local row = baseRow(parent, name, y)
	row.defId = def.id
	row.dropId = nil
	local selected = QAT.editor.selectedId == def.id
	if isFolder then
		setBg(row, selected and BG_FULL or BG_NONE)
	else
		setBg(row, selected and BG_SUBTLE or BG_NONE)
	end

	-- Click selects; a vertical drag onto another row reparents (drag-drop nesting).
	row:SetHandler("OnMouseDown", function()
		QAT.editor.treeDragId = def.id
		local _, my = GetUIMousePosition()
		QAT.editor.treeDragY = my
	end)
	row:SetHandler(
		"OnMouseUp",
		rowMouseUp(function()
			selectNode(def.id)
		end)
	)

	-- Left glyph: disclosure arrow (folders toggle collapse; trackers toggle the
	-- single-slot expansion) plus, for trackers, the resolved phase icon.
	local arrow = row.arrow
	if not arrow then
		arrow = QAT.widgets.IconButton(row, name .. "_Arrow", nil, ICON_SIZE)
		row.arrow = arrow
	end
	arrow:ClearAnchors()
	arrow:SetAnchor(LEFT, row, LEFT, 6 + depth * INDENT, 0)
	arrow:SetHidden(false)

	local iconTex = row.iconTex
	if not iconTex then
		iconTex = WM:CreateControl(name .. "_Icon", row, CT_TEXTURE)
		iconTex:SetDimensions(ICON_SIZE, ICON_SIZE)
		row.iconTex = iconTex
	end

	local leftGlyph
	if isFolder or isDynamic then
		arrow:SetTexture(QAT.editor.collapsed[def.id] and ARROW_CLOSED or ARROW_OPEN)
		arrow.onClick = function()
			QAT.editor.collapsed[def.id] = not QAT.editor.collapsed[def.id]
			QAT.Editor_Tree_Build()
		end
		iconTex:SetHidden(not isDynamic)
		if isDynamic then
			iconTex:SetTexture(trackerIcon(def))
			iconTex:SetColor(1, 1, 1, enabled and 1 or 0.35)
			iconTex:ClearAnchors()
			iconTex:SetAnchor(LEFT, arrow, RIGHT, 4, 0)
		end
		leftGlyph = isDynamic and iconTex or arrow
	else
		local expanded = QAT.editor.expandedTracker == def.id
		arrow:SetTexture(expanded and ARROW_OPEN or ARROW_CLOSED)
		arrow.onClick = function()
			if QAT.editor.expandedTracker == def.id then
				QAT.editor.expandedTracker = nil
				QAT.Editor_Tree_Build()
			else
				selectNode(def.id)
			end
		end
		iconTex:SetHidden(false)
		iconTex:SetTexture(trackerIcon(def))
		iconTex:SetColor(1, 1, 1, enabled and 1 or 0.35)
		iconTex:ClearAnchors()
		iconTex:SetAnchor(LEFT, arrow, RIGHT, 4, 0)
		leftGlyph = iconTex
	end

	-- Enable checkbox on the right edge (defined first so badge/label can anchor to it).
	local check = row.check
	if not check then
		check = QAT.widgets.IconButton(row, name .. "_Check", nil, ICON_SIZE)
		row.check = check
	end
	check:ClearAnchors()
	check:SetAnchor(RIGHT, row, RIGHT, -6, 0)
	check:SetTexture(enabled and CHECK_ON or CHECK_OFF)
	check.onClick = function()
		def.enabled = not (def.enabled ~= false)
		QAT.widgets.NotifyTrackerChanged(def.id)
		QAT.Editor_Tree_Build()
	end

	-- Name (dimmed when disabled).
	local label = row.label or QAT.widgets.Label(row, name .. "_Label", "")
	row.label = label
	label:SetText(def.name or def.id)
	label:SetColor(0.9, 0.92, 0.95, enabled and 1 or 0.4)
	label:ClearAnchors()
	label:SetAnchor(LEFT, leftGlyph, RIGHT, 6, 0)

	-- Groups carry an aura-count badge; dynamic/tracker stretch the name to the check.
	if isFolder then
		local aur = countAuras(def)
		local badge = ensureBadge(row, name .. "_Badge", 0.62, 0.72, 0.90)
		badge:SetText(string.format("%d AURA%s", aur, aur == 1 and "" or "S"))
		badge:SetHidden(false)
		badge:ClearAnchors()
		badge:SetAnchor(LEFT, label, RIGHT, 8, 0)
	elseif isDynamic then
		local badge = ensureBadge(row, name .. "_Badge", 0.62, 0.72, 0.90)
		badge:SetText("DYNAMIC")
		badge:SetHidden(false)
		badge:ClearAnchors()
		badge:SetAnchor(LEFT, iconTex, RIGHT, 4, 0)
		label:ClearAnchors()
		label:SetAnchor(LEFT, badge, RIGHT, 6, 0)
		label:SetAnchor(RIGHT, check, LEFT, -8, 0)
	else
		label:SetAnchor(RIGHT, row, RIGHT, -28, 0)
		if row.badge then
			row.badge:SetHidden(true)
		end
	end

	return ROW_H
end

-- The aura-wide (or group-wide) "Load conditions" row shown first under an
-- expanded tracker or group.
local function makeLoadRow(parent, def, depth, y)
	local name = "QAT_TreeLoad_" .. def.id
	local isFolder = def.kind == "folder"
	local isDynamic = def.kind == "dynamic"
	local row = baseRow(parent, name, y)
	row.defId = nil
	row.dropId = def.id
	local selected = QAT.editor.selectedId == def.id and (QAT.editor.selectedScope or "load") ~= "phase"
	setBg(row, selected and BG_FULL or BG_NONE)
	row:SetHandler("OnMouseDown", nil)
	row:SetHandler(
		"OnMouseUp",
		rowMouseUp(function()
			QAT.Editor_SelectLoad(def.id)
		end)
	)

	local label = row.label or QAT.widgets.Label(row, name .. "_Label", "")
	row.label = label
	label:SetText("Load conditions")
	label:SetColor(0.85, 0.88, 0.93, 1)
	label:ClearAnchors()
	label:SetAnchor(LEFT, row, LEFT, 8 + depth * INDENT, 0)

	local badge = ensureBadge(row, name .. "_Badge", 0.62, 0.72, 0.90)
	if isDynamic then
		badge:SetText("DYNAMIC")
	elseif isFolder then
		badge:SetText("GROUP")
	else
		badge:SetText("AURA")
	end
	badge:SetHidden(false)
	badge:ClearAnchors()
	badge:SetAnchor(LEFT, label, RIGHT, 8, 0)

	return ROW_H
end

-- The "Grid layout" row shown under a group whose grid is enabled — selects the
-- table-builder scope, with a C×R badge summarising the current dimensions.
local function makeGridRow(parent, def, depth, y)
	local name = "QAT_TreeGrid_" .. def.id
	local row = baseRow(parent, name, y)
	row.defId = nil
	row.dropId = nil
	local selected = QAT.editor.selectedId == def.id and QAT.editor.selectedScope == "grid"
	setBg(row, selected and BG_FULL or BG_NONE)
	row:SetHandler("OnMouseDown", nil)
	row:SetHandler(
		"OnMouseUp",
		rowMouseUp(function()
			QAT.Editor_SelectGrid(def.id)
		end)
	)

	local label = row.label or QAT.widgets.Label(row, name .. "_Label", "")
	row.label = label
	label:SetText("Grid layout")
	label:SetColor(0.85, 0.88, 0.93, 1)
	label:ClearAnchors()
	label:SetAnchor(LEFT, row, LEFT, 8 + depth * INDENT, 0)

	local g = def.grid or {}
	local count = row.count or QAT.widgets.Label(row, name .. "_Cnt", "", "$(MEDIUM_FONT)|13|soft-shadow-thin")
	row.count = count
	count:SetText(string.format("%d×%d", g.cols or 2, g.rows or 2))
	count:SetColor(0.45, 0.52, 0.63, 1)
	count:ClearAnchors()
	count:SetAnchor(RIGHT, row, RIGHT, -10, 0)

	return ROW_H
end

-- One row per phase (idle included, per "show idle"). The initial phase carries a
-- green dot and an INITIAL badge; hidden (display=none) phases read dimmed.
local function makePhaseRow(parent, def, phase, depth, y)
	local name = "QAT_TreePhase_" .. def.id .. "_" .. phase.id
	local row = baseRow(parent, name, y)
	row.defId = nil
	row.dropId = def.id
	local isInitial = QAT.Editor_IsInitialPhase(def, phase.id)
	local selected = QAT.editor.selectedId == def.id
		and QAT.editor.selectedScope == "phase"
		and QAT.editor.selectedPhaseId == phase.id
	setBg(row, selected and BG_FULL or BG_NONE)
	row.dropLayer = phase.layer or 0 -- drop target: this phase's layer
	-- Press starts a phase drag; a plain click (no move) selects. Dropping over another
	-- layer's row (or its + add phase / header) moves the phase into that layer.
	row:SetHandler("OnMouseDown", function(_, button)
		if button == MOUSE_BUTTON_INDEX_LEFT then
			QAT.editor.treePhaseDrag = { id = def.id, phaseId = phase.id }
			local _, my = GetUIMousePosition()
			QAT.editor.treeDragY = my
		end
	end)
	row:SetHandler(
		"OnMouseUp",
		rowMouseUp(function()
			QAT.Editor_SelectPhase(def.id, phase.id)
		end)
	)

	local hidden = (phase.look and phase.look.display) == "none"
	local dot = ensureDot(row, name .. "_Dot")
	if isInitial then
		dot:SetCenterColor(0.35, 0.78, 0.42, 1)
	elseif hidden then
		dot:SetCenterColor(0.35, 0.40, 0.50, 1)
	else
		dot:SetCenterColor(0.55, 0.62, 0.75, 1)
	end
	dot:ClearAnchors()
	dot:SetAnchor(LEFT, row, LEFT, 10 + depth * INDENT, 0)

	local label = row.label or QAT.widgets.Label(row, name .. "_Label", "")
	row.label = label
	label:SetText(phase.name or phase.id)
	label:SetColor(0.9, 0.92, 0.95, hidden and 0.55 or 1)
	label:ClearAnchors()
	label:SetAnchor(LEFT, dot, RIGHT, 8, 0)

	local badge = ensureBadge(row, name .. "_Badge", 0.55, 0.82, 0.55)
	if isInitial then
		badge:SetText("INITIAL")
		badge:SetHidden(false)
		badge:ClearAnchors()
		badge:SetAnchor(LEFT, label, RIGHT, 8, 0)
	else
		badge:SetHidden(true)
	end

	-- The phase's resolved icon on the right edge (auto from the tracked ability, or an
	-- override); hidden when the phase has no icon to show.
	local pic = ensurePhaseIcon(row, name .. "_Icon")
	local tex = QAT.util.PhaseIcon(phase, def)
	pic:SetHidden(tex == nil)
	if tex then
		pic:SetTexture(tex)
		pic:SetDesaturation(hidden and 1 or 0)
		pic:ClearAnchors()
		pic:SetAnchor(RIGHT, row, RIGHT, -10, 0)
	end

	return ROW_H
end

-- The "+ add phase" affordance closing out a layer's phase list. `layer` targets
-- which parallel layer the new phase joins.
local function makeAddRow(parent, def, depth, y, layer)
	local name = "QAT_TreeAdd_" .. def.id .. "_L" .. (layer or 0)
	local row = baseRow(parent, name, y)
	row.defId = nil
	row.dropId = def.id
	row.dropLayer = layer or 0 -- dropping a dragged phase here also targets this layer
	setBg(row, BG_NONE)
	row:SetHandler("OnMouseDown", nil)
	row:SetHandler(
		"OnMouseUp",
		rowMouseUp(function()
			if QAT.Editor_AddPhase then
				local d = findNode(QAT.sv.trackers, def.id)
				if d then
					QAT.Editor_AddPhase(d, layer or 0)
				end
			end
		end)
	)

	local label = row.label or QAT.widgets.Label(row, name .. "_Label", "")
	row.label = label
	label:SetText("+ add phase")
	label:SetColor(0.55, 0.62, 0.74, 1)
	label:ClearAnchors()
	label:SetAnchor(LEFT, row, LEFT, 10 + depth * INDENT, 0)

	return ROW_H
end

-- A selectable "Layer n" section row heading its phases. Selecting it opens the Layer
-- settings card. `posLabel` marks the draw extremes ("back" = behind, "front" = in
-- front); `phaseCount` shows on the right.
local function makeLayerHeaderRow(parent, def, layer, posLabel, phaseCount, depth, y)
	local name = "QAT_TreeLayer_" .. def.id .. "_L" .. layer
	local row = baseRow(parent, name, y)
	row.defId = nil
	row.dropId = def.id
	row.dropLayer = layer -- drop a dragged phase here to move it into this layer
	local selected = QAT.editor.selectedId == def.id
		and QAT.editor.selectedScope == "layer"
		and QAT.editor.selectedLayer == layer
	setBg(row, selected and BG_FULL or BG_NONE)
	row:SetHandler("OnMouseDown", nil)
	row:SetHandler(
		"OnMouseUp",
		rowMouseUp(function()
			QAT.Editor_SelectLayer(def.id, layer)
		end)
	)

	local label = row.label or QAT.widgets.Label(row, name .. "_Label", "", "$(BOLD_FONT)|15|soft-shadow-thin")
	row.label = label
	label:SetText("Layer " .. (layer + 1)) -- 1-based, matches the breadcrumb
	label:SetColor(0.72, 0.78, 0.88, 1)
	label:ClearAnchors()
	label:SetAnchor(LEFT, row, LEFT, 10 + depth * INDENT, 0)

	local badge = ensureBadge(row, name .. "_Badge", 0.78, 0.66, 0.42)
	badge:SetText(posLabel or "")
	badge:SetHidden(not posLabel)
	badge:ClearAnchors()
	badge:SetAnchor(LEFT, label, RIGHT, 8, 0)

	local count = row.count or QAT.widgets.Label(row, name .. "_Cnt", "", "$(MEDIUM_FONT)|13|soft-shadow-thin")
	row.count = count
	count:SetText(phaseCount .. (phaseCount == 1 and " phase" or " phases"))
	count:SetColor(0.45, 0.52, 0.63, 1)
	count:ClearAnchors()
	count:SetAnchor(RIGHT, row, RIGHT, -10, 0)

	return ROW_H
end

-- The "+ add layer" affordance closing out an expanded tracker: starts a new
-- parallel layer that draws in front of the others.
local function makeAddLayerRow(parent, def, depth, y)
	local name = "QAT_TreeAddLayer_" .. def.id
	local row = baseRow(parent, name, y)
	row.defId = nil
	row.dropId = def.id
	setBg(row, BG_NONE)
	row:SetHandler("OnMouseDown", nil)
	row:SetHandler(
		"OnMouseUp",
		rowMouseUp(function()
			if QAT.Editor_AddLayer then
				local d = findNode(QAT.sv.trackers, def.id)
				if d then
					QAT.Editor_AddLayer(d)
				end
			end
		end)
	)

	local label = row.label or QAT.widgets.Label(row, name .. "_Label", "")
	row.label = label
	label:SetText("+ add layer")
	label:SetColor(0.45, 0.52, 0.64, 1)
	label:ClearAnchors()
	label:SetAnchor(LEFT, row, LEFT, 10 + depth * INDENT, 0)

	return ROW_H
end

-- The "+ add tracker" affordance closing out an expanded group's members.
local function makeAddTrackerRow(parent, def, depth, y)
	local name = "QAT_TreeAddTracker_" .. def.id
	local row = baseRow(parent, name, y)
	row.defId = nil
	row.dropId = def.id
	setBg(row, BG_NONE)
	row:SetHandler("OnMouseDown", nil)
	row:SetHandler(
		"OnMouseUp",
		rowMouseUp(function()
			if QAT.Editor_AddTrackerToGroup then
				QAT.Editor_AddTrackerToGroup(def.id)
			end
		end)
	)

	local label = row.label or QAT.widgets.Label(row, name .. "_Label", "")
	row.label = label
	label:SetText("+ add tracker")
	label:SetColor(0.55, 0.62, 0.74, 1)
	label:ClearAnchors()
	label:SetAnchor(LEFT, row, LEFT, 10 + depth * INDENT, 0)

	return ROW_H
end

local function buildRows(parent, defs, depth, y)
	for _, def in ipairs(defs or {}) do
		y = y + makeRow(parent, def, depth, y)
		if def.kind == "folder" then
			if not QAT.editor.collapsed[def.id] then
				y = y + makeLoadRow(parent, def, depth + 1, y)
				if def.grid and def.grid.enabled then
					y = y + makeGridRow(parent, def, depth + 1, y)
				end
				y = buildRows(parent, def.children, depth + 1, y)
				y = y + makeAddTrackerRow(parent, def, depth + 1, y)
			end
		elseif def.kind == "dynamic" then
			if not QAT.editor.collapsed[def.id] then
				y = y + makeLoadRow(parent, def, depth + 1, y)
				local order, byLayer = {}, {}
				for _, p in ipairs(def.phases or {}) do
					local L = p.layer or 0
					if not byLayer[L] then
						byLayer[L] = {}
						order[#order + 1] = L
					end
					table.insert(byLayer[L], p)
				end
				table.sort(order)
				local multi = #order > 1
				for li, L in ipairs(order) do
					local phaseDepth = depth + 1
					if multi then
						local pos = (li == 1 and "back") or (li == #order and "front") or nil
						y = y + makeLayerHeaderRow(parent, def, L, pos, #byLayer[L], depth + 1, y)
						phaseDepth = depth + 2
					end
					for _, p in ipairs(byLayer[L]) do
						y = y + makePhaseRow(parent, def, p, phaseDepth, y)
					end
					y = y + makeAddRow(parent, def, phaseDepth, y, L)
				end
				y = y + makeAddLayerRow(parent, def, depth + 1, y)
			end
		else
			if QAT.editor.expandedTracker == def.id then
				y = y + makeLoadRow(parent, def, depth + 1, y)
				local order, byLayer = {}, {}
				for _, p in ipairs(def.phases or {}) do
					local L = p.layer or 0
					if not byLayer[L] then
						byLayer[L] = {}
						order[#order + 1] = L
					end
					table.insert(byLayer[L], p)
				end
				table.sort(order)
				local multi = #order > 1
				for li, L in ipairs(order) do
					local phaseDepth = depth + 1
					if multi then
						local pos = (li == 1 and "back") or (li == #order and "front") or nil
						y = y + makeLayerHeaderRow(parent, def, L, pos, #byLayer[L], depth + 1, y)
						phaseDepth = depth + 2
					end
					for _, p in ipairs(byLayer[L]) do
						y = y + makePhaseRow(parent, def, p, phaseDepth, y)
					end
					y = y + makeAddRow(parent, def, phaseDepth, y, L)
				end
				y = y + makeAddLayerRow(parent, def, depth + 1, y)
			end
		end
	end
	return y
end

function QAT.Editor_Tree_Build(pane)
	pane = pane or QAT.editor.treePane
	QAT.editor.treePane = pane

	if not QAT.editor.treeToolbar then
		local tb = WM:CreateControl("QAT_Tree_Toolbar", pane, CT_CONTROL)
		tb:SetAnchor(TOPLEFT, pane, TOPLEFT, 0, 0)
		tb:SetAnchor(TOPRIGHT, pane, TOPRIGHT, 0, 0)
		tb:SetHeight(TOOLBAR_H)
		QAT.editor.treeToolbar = tb

		-- Toolbar actions. Delete pins to the right edge; the three add buttons sit
		-- left-to-right, with addD right-anchored to delBtn so it fills whatever space
		-- is available and never overlaps.
		local GAP = 8
		local delBtn = QAT.widgets.TextButton(tb, "QAT_Tree_Btn_Delete", "Delete", deleteSelected)
		delBtn:SetHeight(TOOLBAR_H - 6)
		delBtn:SetAnchor(RIGHT, tb, RIGHT, -GAP, 0)
		QAT.widgets.Tooltip(delBtn, "Delete the selected tracker or group.")
		local addT = QAT.widgets.TextButton(tb, "QAT_Tree_Btn_AddTracker", "+ Tracker", addTracker)
		addT:SetHeight(TOOLBAR_H - 6)
		addT:SetAnchor(LEFT, tb, LEFT, GAP, 0)
		QAT.widgets.Tooltip(addT, "Add a new tracker.")
		local addG = QAT.widgets.TextButton(tb, "QAT_Tree_Btn_AddGroup", "+ Group", addGroup)
		addG:SetHeight(TOOLBAR_H - 6)
		addG:SetAnchor(LEFT, addT, RIGHT, GAP, 0)
		QAT.widgets.Tooltip(addG, "Add a group (folder). Its Load conditions cascade to the trackers inside it.")
		local addD = QAT.widgets.TextButton(tb, "QAT_Tree_Btn_AddDynamic", "+ Dynamic", addDynamicTracker)
		addD:SetHeight(TOOLBAR_H - 6)
		addD:SetAnchor(LEFT, addG, RIGHT, GAP, 0)
		addD:SetAnchor(RIGHT, delBtn, LEFT, -GAP, 0)
		QAT.widgets.Tooltip(addD, "Add a dynamic tracker: stamps its phases once per live target (e.g. taunts).")

		-- Scroll viewport filling the pane below the toolbar: a ZO_ScrollContainer so
		-- rows clip to the pane and scroll with a scrollbar / mouse-wheel (no manual
		-- offsetting, which let rows draw outside the window). Rows render into its
		-- ScrollChild, which resizes to fit their height.
		local sc = WM:CreateControlFromVirtual("QAT_Tree_Scroll", pane, "ZO_ScrollContainer")
		sc:SetAnchor(TOPLEFT, pane, TOPLEFT, 0, TOOLBAR_H)
		sc:SetAnchor(BOTTOMRIGHT, pane, BOTTOMRIGHT, 0, 0)
		local content = GetControl(sc, "ScrollChild")
		content:SetResizeToFitDescendents(true)
		content:SetResizeToFitPadding(0, 8)
		QAT.editor.treeScrollC = sc
		QAT.editor.treeContent = content
	end

	-- Track the viewport width (leave room for the scrollbar), hide old rows, rebuild.
	treeRowW = math.max(200, QAT.editor.treeScrollC:GetWidth() - 16)
	for _, row in pairs(rows) do
		row:SetHidden(true)
	end
	buildRows(QAT.editor.treeContent, QAT.sv.trackers, 0, 0)
end

function QAT.Editor_Tree_Relayout()
	-- Rebuild so rows pick up the new viewport width after a pane/splitter resize.
	if QAT.editor.treeScrollC then
		QAT.Editor_Tree_Build()
	end
end

-- Rebuild the tree whenever a tracker def changes elsewhere.
CALLBACK_MANAGER:RegisterCallback("QAT_TrackerChanged", function()
	if QAT.editor.frame then
		QAT.Editor_Tree_Build()
	end
end)
