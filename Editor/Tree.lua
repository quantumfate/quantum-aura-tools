-- Tree pane: the tracker/folder hierarchy with an add/delete toolbar. Rows are
-- rebuilt from the def tree whenever it changes. Rows are anchored inside a
-- scroll container and rebuilt wholesale rather than virtualized, which is fine
-- for the expected node counts.

local WM = GetWindowManager()
local TOOLBAR_H, ROW_H, INDENT = 28, 24, 16

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

local function selectNode(id)
	QAT.log.editor:Debug("select node '%s'", tostring(id))
	QAT.editor.selectedId = id
	QAT.Editor_Tree_Build()
	if QAT.Editor_Inspector_Show then
		QAT.Editor_Inspector_Show(id)
	end
end
QAT.Editor_SelectNode = selectNode

local function addTracker()
	-- Build a flat default and canonicalize it so the stored def is a complete
	-- single-phase tracker the inspector can render immediately.
	local def = QAT.CanonicalizeDef({
		id = newId("tracker_"),
		kind = "tracker",
		display = "bar",
		name = "New Tracker",
		abilityIds = {},
		unit = "player",
		point = CENTER,
		x = 0,
		y = 0,
		enabled = true,
	})
	table.insert(QAT.sv.trackers, def)
	QAT.log.editor:Debug("added tracker '%s'", def.id)
	-- Land on the visible "active" phase, not the empty hidden "idle" one.
	QAT.editor.selectedPhaseId = "active"
	selectNode(def.id)
	-- First-run hint: a new tracker is hidden until its effect triggers.
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

local function performDelete(id)
	if removeById(QAT.sv.trackers, id) then
		QAT.log.editor:Debug("deleted node '%s'", tostring(id))
		QAT.editor.selectedId = nil
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

-- Per-folder collapse state (editor-session only, not persisted).
QAT.editor.collapsed = QAT.editor.collapsed or {}

-- Best icon to represent a tracker in the tree: the resolved icon of the first
-- phase that has one, else a placeholder.
local function trackerIcon(def)
	for _, p in ipairs(def.phases or {}) do
		local ic = QAT.util.PhaseIcon(p)
		if ic then
			return ic
		end
	end
	return ICON_MISSING
end

local function makeRow(parent, def, depth, y)
	local name = "QAT_TreeRow_" .. def.id
	local isFolder = def.kind == "folder"
	local enabled = def.enabled ~= false

	local row = rows[name] or QAT.widgets.Clickable(parent, name, { 0, 0, 0, 0 })
	rows[name] = row
	row:SetHidden(false)
	row:ClearAnchors()
	row:SetAnchor(TOPLEFT, parent, TOPLEFT, 0, y)
	row:SetAnchor(TOPRIGHT, parent, TOPRIGHT, 0, y)
	row:SetHeight(ROW_H)

	local selected = QAT.editor.selectedId == def.id
	row.bg:SetCenterColor(unpack(selected and { 0.20, 0.28, 0.40, 1 } or { 0, 0, 0, 0 }))
	row:SetHandler("OnMouseUp", function(_, button, upInside)
		if upInside and button == MOUSE_BUTTON_INDEX_LEFT then
			selectNode(def.id)
		end
	end)

	-- Left glyph: a folder's expand arrow (clickable, toggles collapse) or a
	-- tracker's icon (non-interactive; clicks fall through to the row).
	local arrow = row.arrow
	if not arrow then
		arrow = QAT.widgets.IconButton(row, name .. "_Arrow", nil, ICON_SIZE)
		row.arrow = arrow
	end
	arrow:ClearAnchors()
	arrow:SetAnchor(LEFT, row, LEFT, 6 + depth * INDENT, 0)

	local iconTex = row.iconTex
	if not iconTex then
		iconTex = WM:CreateControl(name .. "_Icon", row, CT_TEXTURE)
		row.iconTex = iconTex
	end
	iconTex:SetDimensions(ICON_SIZE, ICON_SIZE)
	iconTex:ClearAnchors()
	iconTex:SetAnchor(LEFT, row, LEFT, 6 + depth * INDENT, 0)

	local leftGlyph
	if isFolder then
		arrow:SetHidden(false)
		arrow:SetTexture(QAT.editor.collapsed[def.id] and ARROW_CLOSED or ARROW_OPEN)
		arrow.onClick = function()
			QAT.editor.collapsed[def.id] = not QAT.editor.collapsed[def.id]
			QAT.Editor_Tree_Build()
		end
		iconTex:SetHidden(true)
		leftGlyph = arrow
	else
		arrow:SetHidden(true)
		iconTex:SetHidden(false)
		iconTex:SetTexture(trackerIcon(def))
		iconTex:SetColor(1, 1, 1, enabled and 1 or 0.35)
		leftGlyph = iconTex
	end

	-- Name (dimmed when disabled).
	local label = row.label or QAT.widgets.Label(row, name .. "_Label", "")
	row.label = label
	label:SetText(def.name or def.id)
	label:SetColor(0.9, 0.92, 0.95, enabled and 1 or 0.4)
	label:ClearAnchors()
	label:SetAnchor(LEFT, leftGlyph, RIGHT, 6, 0)
	label:SetAnchor(RIGHT, row, RIGHT, -28, 0)

	-- Enable checkbox on the right edge.
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

	return ROW_H
end

local function buildRows(parent, defs, depth, y)
	for _, def in ipairs(defs or {}) do
		y = y + makeRow(parent, def, depth, y)
		if def.kind == "folder" and not QAT.editor.collapsed[def.id] then
			y = buildRows(parent, def.children, depth + 1, y)
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

		-- Create actions on the left; the destructive Delete is pushed to the right
		-- edge so it reads as a separate concern from the add buttons.
		local x = 4
		for _, b in ipairs({ { "+ Tracker", addTracker, 86 }, { "+ Group", addGroup, 78 } }) do
			local btn = QAT.widgets.TextButton(tb, "QAT_Tree_Btn_" .. b[1], b[1], b[2])
			btn:SetDimensions(b[3], TOOLBAR_H - 6)
			btn:SetAnchor(LEFT, tb, LEFT, x, 0)
			x = x + b[3] + 6
		end
		local delBtn = QAT.widgets.TextButton(tb, "QAT_Tree_Btn_Delete", "Delete", deleteSelected)
		delBtn:SetDimensions(64, TOOLBAR_H - 6)
		delBtn:SetAnchor(RIGHT, tb, RIGHT, -4, 0)

		-- Fixed viewport filling the pane below the toolbar. It needs a real rect
		-- (top + bottom anchored) so its child rows are hit-testable; scrolling is
		-- done by offsetting the rows' y, not by moving this container.
		local content = WM:CreateControl("QAT_Tree_Content", pane, CT_CONTROL)
		content:SetAnchor(TOPLEFT, pane, TOPLEFT, 0, TOOLBAR_H)
		content:SetAnchor(BOTTOMRIGHT, pane, BOTTOMRIGHT, 0, 0)
		content:SetMouseEnabled(true)
		QAT.editor.treeScroll = 0
		content:SetHandler("OnMouseWheel", function(_, delta)
			QAT.editor.treeScroll = zo_min(0, QAT.editor.treeScroll + delta * 30)
			QAT.Editor_Tree_Build()
		end)
		QAT.editor.treeContent = content
	end

	-- Hide old rows, then (re)build from the scroll offset.
	for _, row in pairs(rows) do
		row:SetHidden(true)
	end
	buildRows(QAT.editor.treeContent, QAT.sv.trackers, 0, QAT.editor.treeScroll or 0)
end

function QAT.Editor_Tree_Relayout()
	-- Rows anchor to the content/pane width automatically; nothing extra yet.
end

-- Rebuild the tree whenever a tracker def changes elsewhere.
CALLBACK_MANAGER:RegisterCallback("QAT_TrackerChanged", function()
	if QAT.editor.frame then
		QAT.Editor_Tree_Build()
	end
end)
