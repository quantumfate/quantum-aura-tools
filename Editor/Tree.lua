-- Tree pane: the tracker/folder hierarchy with a toolbar. Rows are rebuilt from
-- the def tree on change. (Virtualized ZO_ScrollList is a later optimization;
-- this rebuilds anchored rows inside a scroll container.)

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
	local def = {
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
	}
	table.insert(QAT.sv.trackers, def)
	QAT.log.editor:Debug("added tracker '%s'", def.id)
	selectNode(def.id)
end

local function addGroup()
	local def = { id = newId("group_"), kind = "folder", name = "New Group", children = {}, enabled = true }
	table.insert(QAT.sv.trackers, def)
	QAT.log.editor:Debug("added group '%s'", def.id)
	selectNode(def.id)
end

local function deleteSelected()
	if QAT.editor.selectedId and removeById(QAT.sv.trackers, QAT.editor.selectedId) then
		QAT.log.editor:Debug("deleted node '%s'", tostring(QAT.editor.selectedId))
		QAT.editor.selectedId = nil
		QAT.Editor_Tree_Build()
		if QAT.Editor_Inspector_Show then
			QAT.Editor_Inspector_Show(nil)
		end
	end
end

local rows = {}

local function makeRow(parent, def, depth, y)
	local name = "QAT_TreeRow_" .. def.id
	local row = rows[name] or QAT.widgets.Panel(parent, name, { 0, 0, 0, 0 })
	rows[name] = row
	row:SetHidden(false)
	row:SetMouseEnabled(true)
	row:ClearAnchors()
	row:SetAnchor(TOPLEFT, parent, TOPLEFT, 0, y)
	row:SetAnchor(TOPRIGHT, parent, TOPRIGHT, 0, y)
	row:SetHeight(ROW_H)

	local selected = QAT.editor.selectedId == def.id
	row:SetCenterColor(unpack(selected and { 0.20, 0.28, 0.40, 1 } or { 0, 0, 0, 0 }))

	local check = row.check or QAT.widgets.Checkbox(row, name .. "_En", def.enabled ~= false, nil)
	row.check = check
	check:SetChecked(def.enabled ~= false)
	check:ClearAnchors()
	check:SetAnchor(LEFT, row, LEFT, 4 + depth * INDENT, 0)
	check:SetHandler("OnMouseUp", function(self, button, upInside)
		if upInside and button == MOUSE_BUTTON_INDEX_LEFT then
			def.enabled = not (def.enabled ~= false)
			self:SetChecked(def.enabled)
			QAT.widgets.NotifyTrackerChanged(def.id)
		end
	end)

	local prefix = def.kind == "folder" and "[+] " or "- "
	local label = row.label or QAT.widgets.Label(row, name .. "_Label", "")
	row.label = label
	label:SetText(prefix .. (def.name or def.id))
	label:ClearAnchors()
	label:SetAnchor(LEFT, check, RIGHT, 6, 0)
	label:SetAnchor(RIGHT, row, RIGHT, -4, 0)

	row:SetHandler("OnMouseUp", function(_, button, upInside)
		if upInside and button == MOUSE_BUTTON_INDEX_LEFT then
			selectNode(def.id)
		end
	end)

	return ROW_H
end

local function buildRows(parent, defs, depth, y)
	for _, def in ipairs(defs or {}) do
		y = y + makeRow(parent, def, depth, y)
		if def.kind == "folder" then
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

		local x = 2
		local defsBtns = {
			{ "+ Tracker", addTracker, 78 },
			{ "+ Group", addGroup, 70 },
			{ "Delete", deleteSelected, 60 },
		}
		for _, b in ipairs(defsBtns) do
			local btn = QAT.widgets.TextButton(tb, "QAT_Tree_Btn_" .. b[1], b[1], b[2])
			btn:SetDimensions(b[3], TOOLBAR_H - 6)
			btn:SetAnchor(LEFT, tb, LEFT, x, 0)
			x = x + b[3] + 2
		end

		local content = WM:CreateControl("QAT_Tree_Content", pane, CT_CONTROL)
		content:SetAnchor(TOPLEFT, pane, TOPLEFT, 0, TOOLBAR_H)
		content:SetAnchor(TOPRIGHT, pane, TOPRIGHT, 0, TOOLBAR_H)
		content:SetMouseEnabled(true)
		QAT.editor.treeScroll = 0
		content:SetHandler("OnMouseWheel", function(self, delta)
			QAT.editor.treeScroll = zo_min(0, QAT.editor.treeScroll + delta * 30)
			self:ClearAnchors()
			self:SetAnchor(TOPLEFT, pane, TOPLEFT, 0, TOOLBAR_H + QAT.editor.treeScroll)
			self:SetAnchor(TOPRIGHT, pane, TOPRIGHT, 0, TOOLBAR_H + QAT.editor.treeScroll)
		end)
		QAT.editor.treeContent = content
	end

	-- Hide old rows, then (re)build.
	for _, row in pairs(rows) do
		row:SetHidden(true)
	end
	buildRows(QAT.editor.treeContent, QAT.sv.trackers, 0, 0)
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
