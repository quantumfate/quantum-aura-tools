-- The editor's main window: a user-resizable two-pane frame (tree | inspector)
-- with a draggable splitter. Window geometry and the splitter position are
-- persisted in sv.editor and restored on open.

QAT.editor = QAT.editor or {}

local WM = GetWindowManager()
local TABS = { "Phases", "Conditions", "Load" }
local TITLE_H, TAB_H, SPLITTER_W, HEADER_H = 28, 26, 6, 56
QAT.editor.HEADER_H, QAT.editor.TAB_H = HEADER_H, TAB_H
local MIN_TREE, MIN_INSPECTOR = 160, 320

local function saveGeometry()
	local f = QAT.editor.frame
	if not f then
		return
	end
	local sv = QAT.sv.editor
	sv.x, sv.y = f:GetLeft(), f:GetTop()
	sv.width, sv.height = f:GetDimensions()
end

-- Position the panes for the current frame size + tree-pane width.
function QAT.Editor_Relayout()
	local f = QAT.editor.frame
	if not f then
		return
	end
	local w, h = f:GetDimensions()
	local treeW = zo_clamp(QAT.sv.editor.treeWidth, MIN_TREE, w - SPLITTER_W - MIN_INSPECTOR)
	QAT.sv.editor.treeWidth = treeW

	local body = h - TITLE_H

	QAT.editor.treePane:ClearAnchors()
	QAT.editor.treePane:SetAnchor(TOPLEFT, f, TOPLEFT, 0, TITLE_H)
	QAT.editor.treePane:SetDimensions(treeW, body)

	QAT.editor.splitter:ClearAnchors()
	QAT.editor.splitter:SetAnchor(TOPLEFT, f, TOPLEFT, treeW, TITLE_H)
	QAT.editor.splitter:SetDimensions(SPLITTER_W, body)

	local inspX = treeW + SPLITTER_W
	QAT.editor.inspectorPane:ClearAnchors()
	QAT.editor.inspectorPane:SetAnchor(TOPLEFT, f, TOPLEFT, inspX, TITLE_H)
	QAT.editor.inspectorPane:SetDimensions(w - inspX, body)

	if QAT.Editor_Tree_Relayout then
		QAT.Editor_Tree_Relayout()
	end
	if QAT.Editor_Inspector_Relayout then
		QAT.Editor_Inspector_Relayout()
	end
end

local function buildTitleBar(f)
	local bar = QAT.widgets.Panel(f, "QAT_Editor_Title", { 0.12, 0.13, 0.16, 1 })
	bar:SetAnchor(TOPLEFT, f, TOPLEFT, 0, 0)
	bar:SetAnchor(TOPRIGHT, f, TOPRIGHT, 0, 0)
	bar:SetHeight(TITLE_H)

	-- Dragging the title bar moves the window. The frame is left non-movable
	-- otherwise; a permanently movable window captures all mouse-down across its
	-- area and starves child controls of clicks. Movability is enabled only for
	-- the duration of a title-bar drag.
	bar:SetMouseEnabled(true)
	bar:SetHandler("OnMouseDown", function()
		f:StartMoving()
	end)
	bar:SetHandler("OnMouseUp", function()
		f:StopMovingOrResizing()
		saveGeometry()
	end)

	local title = QAT.widgets.Label(bar, "QAT_Editor_TitleText", QAT.displayName .. "  —  Editor")
	title:SetAnchor(LEFT, bar, LEFT, 10, 0)

	local close = QAT.widgets.TextButton(bar, "QAT_Editor_Close", "X", function()
		QAT.Editor_Toggle()
	end)
	close:SetDimensions(TITLE_H - 6, TITLE_H - 6)
	close:SetAnchor(RIGHT, bar, RIGHT, -4, 0)
end

local function selectTab(name)
	QAT.editor.activeTab = name
	for _, tabName in ipairs(TABS) do
		local btn = QAT.editor.tabButtons[tabName]
		btn:SetCenterColor(unpack(tabName == name and { 0.22, 0.25, 0.30, 1 } or { 0.13, 0.14, 0.17, 1 }))
	end
	if QAT.Editor_Inspector_SetTab then
		QAT.Editor_Inspector_SetTab(name)
	end
end
QAT.Editor_SelectTab = selectTab

local function buildTabBar(pane)
	QAT.editor.tabButtons = {}
	local x = 0
	local tabW = 110
	for _, name in ipairs(TABS) do
		local btn = QAT.widgets.TextButton(pane, "QAT_Editor_Tab_" .. name, name, function()
			selectTab(name)
		end)
		btn:SetDimensions(tabW, TAB_H)
		btn:SetAnchor(TOPLEFT, pane, TOPLEFT, x, 0)
		QAT.editor.tabButtons[name] = btn
		x = x + tabW + 2
	end
end

function QAT.Editor_Init()
	local sv = QAT.sv.editor
	QAT.log.editor:Debug(
		"Editor_Init: restoring geometry %dx%d @ (%d,%d), treeWidth=%d",
		sv.width,
		sv.height,
		sv.x,
		sv.y,
		sv.treeWidth
	)

	local f = WM:CreateTopLevelWindow("QAT_Editor")
	f:SetDimensions(sv.width, sv.height)
	f:SetClampedToScreen(true)
	f:SetMouseEnabled(true)
	f:SetMovable(true)
	f:SetResizeHandleSize(SPLITTER_W)
	f:SetDimensionConstraints(600, 360, 0, 0)
	f:SetHidden(true)
	f:ClearAnchors()
	f:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, sv.x, sv.y)
	f:SetHandler("OnMoveStop", saveGeometry)
	f:SetHandler("OnResizeStop", function()
		saveGeometry()
		QAT.Editor_Relayout()
	end)
	QAT.widgets.Panel(f, "QAT_Editor_Bg", { 0.05, 0.06, 0.08, 0.96 }):SetAnchorFill()
	QAT.editor.frame = f

	buildTitleBar(f)

	QAT.editor.treePane = QAT.widgets.Panel(f, "QAT_Editor_TreePane", { 0.08, 0.09, 0.11, 1 })

	-- Draggable splitter: dragging changes the tree-pane width.
	local splitter = QAT.widgets.Panel(f, "QAT_Editor_Splitter", { 0.20, 0.22, 0.26, 1 })
	splitter:SetMouseEnabled(true)
	splitter:SetHandler("OnMouseDown", function()
		QAT.editor.dragSplit = true
	end)
	splitter:SetHandler("OnMouseUp", function()
		QAT.editor.dragSplit = false
	end)
	splitter:SetHandler("OnUpdate", function()
		if not QAT.editor.dragSplit then
			return
		end
		local mx = GetUIMousePosition()
		QAT.sv.editor.treeWidth = mx - QAT.editor.frame:GetLeft()
		QAT.Editor_Relayout()
	end)
	QAT.editor.splitter = splitter

	QAT.editor.inspectorPane = QAT.widgets.Panel(f, "QAT_Editor_InspectorPane", { 0.06, 0.07, 0.09, 1 })

	local tabBar = WM:CreateControl("QAT_Editor_TabBar", QAT.editor.inspectorPane, CT_CONTROL)
	tabBar:SetAnchor(TOPLEFT, QAT.editor.inspectorPane, TOPLEFT, 0, HEADER_H)
	tabBar:SetAnchor(TOPRIGHT, QAT.editor.inspectorPane, TOPRIGHT, 0, HEADER_H)
	tabBar:SetHeight(TAB_H)
	QAT.editor.tabBar = tabBar
	buildTabBar(tabBar)

	if QAT.Editor_Tree_Build then
		QAT.Editor_Tree_Build(QAT.editor.treePane)
	end
	if QAT.Editor_Inspector_Build then
		QAT.Editor_Inspector_Build(QAT.editor.inspectorPane)
	end

	QAT.Editor_Relayout()
	selectTab("Phases")
	QAT.log.editor:Info("Editor_Init complete")
end

function QAT.Editor_Toggle()
	local f = QAT.editor.frame
	if not f then
		QAT.log.editor:Warning("Editor_Toggle before Editor_Init")
		return
	end
	local show = f:IsHidden()
	f:SetHidden(not show)
	QAT.log.editor:Debug("editor %s", show and "shown" or "hidden")
end
