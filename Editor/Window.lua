-- The editor's main window: a user-resizable two-pane frame (tree | inspector)
-- with a draggable splitter. Window geometry and the splitter position are
-- persisted in sv.editor and restored on open.

QAT.editor = QAT.editor or {}

local WM = GetWindowManager()
-- Per-phase tabs (Load is a tracker-wide panel reached from the header, not a tab).
local TABS = { "Appearance", "Behavior", "Conditions" }
-- The header is two rows (identity/geometry + the phase strip); the tab bar sits a
-- gap below it.
local TITLE_H, TAB_H, SPLITTER_W, HEADER_H, PHASESEL_H = 28, 28, 6, 74, 36
local HEADER_GAP = 30 -- breathing space between the header and the tab content
QAT.editor.HEADER_H, QAT.editor.TAB_H, QAT.editor.PHASESEL_H = HEADER_H, TAB_H, PHASESEL_H
QAT.editor.HEADER_GAP = HEADER_GAP
local MIN_TREE, MIN_INSPECTOR = 410, 320

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
	local bar = QAT.widgets.Panel(f, "QAT_Editor_Title", { 0.065, 0.08, 0.11, 1 })
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

local TAB_GAP, TAB_MIN_W = 6, 96

local function selectTab(name)
	QAT.editor.activeTab = name
	for _, tabName in ipairs(TABS) do
		QAT.editor.tabButtons[tabName]:SetSelected(tabName == name)
	end
	if QAT.Editor_Inspector_SetTab then
		QAT.Editor_Inspector_SetTab(name)
	end
end
QAT.Editor_SelectTab = selectTab

local TAB_TIPS = {
	Appearance = "How the selected phase looks (kind, colours, readouts).",
	Behavior = "The selected phase's timer and its transitions to other phases.",
	Conditions = "Reactive look changes for the selected phase (e.g. turn red under 3s).",
}

local function buildTabBar(pane)
	QAT.editor.tabButtons = {}
	local prev
	for _, name in ipairs(TABS) do
		local btn = QAT.widgets.TextButton(pane, "QAT_Editor_Tab_" .. name, name, function()
			selectTab(name)
		end)
		btn:SetHeight(TAB_H)
		btn:SetMinWidth(TAB_MIN_W) -- uniform-ish tabs that still grow for long labels
		QAT.widgets.Tooltip(btn, TAB_TIPS[name])
		if prev then
			btn:SetAnchor(LEFT, prev, RIGHT, TAB_GAP, 0)
		else
			btn:SetAnchor(TOPLEFT, pane, TOPLEFT, 0, 0)
		end
		QAT.editor.tabButtons[name] = btn
		prev = btn
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
	f:SetDimensionConstraints(660, 360, 0, 0)
	f:SetHidden(true)
	f:ClearAnchors()
	f:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, sv.x, sv.y)
	f:SetHandler("OnMoveStop", saveGeometry)
	f:SetHandler("OnResizeStop", function()
		saveGeometry()
		QAT.Editor_Relayout()
	end)
	QAT.widgets.Panel(f, "QAT_Editor_Bg", { 0.045, 0.055, 0.078, 0.98 }):SetAnchorFill()
	QAT.editor.frame = f

	buildTitleBar(f)

	QAT.editor.treePane = QAT.widgets.Panel(f, "QAT_Editor_TreePane", { 0.05, 0.062, 0.088, 1 })

	-- Draggable splitter: dragging changes the tree-pane width.
	local splitter = QAT.widgets.Panel(f, "QAT_Editor_Splitter", { 0.10, 0.12, 0.16, 1 })
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

	QAT.editor.inspectorPane = QAT.widgets.Panel(f, "QAT_Editor_InspectorPane", { 0.045, 0.055, 0.078, 1 })

	-- The tab bar sits a gap below the header (the phase strip now lives in the header).
	local tabY = HEADER_H + HEADER_GAP
	local tabBar = WM:CreateControl("QAT_Editor_TabBar", QAT.editor.inspectorPane, CT_CONTROL)
	tabBar:SetAnchor(TOPLEFT, QAT.editor.inspectorPane, TOPLEFT, 12, tabY)
	tabBar:SetAnchor(TOPRIGHT, QAT.editor.inspectorPane, TOPRIGHT, -12, tabY)
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
	selectTab("Appearance")
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
	-- Trackers are only draggable on the HUD while the editor is open.
	if QAT.Runtime_SetTrackersMovable then
		QAT.Runtime_SetTrackersMovable(show)
	end
	QAT.log.editor:Debug("editor %s", show and "shown" or "hidden")
end
