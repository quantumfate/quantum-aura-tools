-- Effect Aggregator window — the harvest/learning surface over the capture engine.
--
-- A sibling top-level window to the Editor, built from the same QAT.widgets kit and
-- visual language. This module is the VIEW: it reads QAT.capture.* and drives the
-- engine's start/stop/freeze/clear/pin/ignore. Capture itself is decoupled and runs
-- without this window (Engine/Capture.lua).
--
-- Layout (top -> bottom): title bar · capture control bar · filter bar · two-pane
-- body (grouped list | inspector). This file builds the shell and the two bars; the
-- list and inspector renderers are layered on in later steps and called from
-- QAT.Aggregator_Refresh.

QAT.aggregator = QAT.aggregator or {}

local WM = GetWindowManager()
local W = QAT.widgets

local TITLE_H, CTRL_H, FILTER_H = 28, 50, 78
local INSPECTOR_W = 468
local PANE_GAP = 6

-- Relationship buckets shown as the primary segmented filter (value -> label + accent).
local RELATIONSHIPS = {
	{ value = "all", label = "All" },
	{ value = "bs", label = "Boss→Self" },
	{ value = "sb", label = "Self→Boss" },
	{ value = "xb", label = "Other→Boss" },
	{ value = "gs", label = "Group→Self" },
	{ value = "ss", label = "Self→Self" },
}

-- Semantic colors from the design spec (0..1 floats).
local COL = {
	bs = { 0.851, 0.541, 0.416 },
	sb = { 0.310, 0.690, 0.627 },
	gs = { 0.435, 0.604, 0.816 },
	ss = { 0.490, 0.557, 0.627 },
	live = { 0.486, 0.753, 0.416 },
	frozen = { 0.784, 0.694, 0.518 },
	rec = { 1.0, 0.416, 0.353 },
}

-- Default filter state: show the interesting buckets, hide Self→Self passive noise.
local function defaultFilter()
	return {
		relationship = "all",
		revealPassives = false,
		search = "",
		effect = "any", -- any | buff | debuff
		timing = "any", -- any | timed | passive
		seenMin = 0,
		hasStacks = false,
		pinnedOnly = false,
		zoneId = nil, -- nil = all zones
		sort = "lastSeen", -- lastSeen | seen | name
	}
end

-- ---------------------------------------------------------------------------
-- Filtering (shared by the count badges and, later, the list renderer)
-- ---------------------------------------------------------------------------

-- Does a row pass everything EXCEPT the relationship segment? (Counts per bucket are
-- computed with the rest of the filter applied, so the segment labels stay honest.)
local function passesNonRelationship(row, fq)
	if fq.pinnedOnly and not row.pinned then
		return false
	end
	if fq.zoneId and row.zoneId ~= fq.zoneId then
		return false
	end
	if fq.hasStacks and (row.maxStacks or 0) <= 0 then
		return false
	end
	if (row.seenCount or 0) < (fq.seenMin or 0) then
		return false
	end
	if fq.effect == "buff" and row.effectType ~= BUFF_EFFECT_TYPE_BUFF then
		return false
	end
	if fq.effect == "debuff" and row.effectType ~= BUFF_EFFECT_TYPE_DEBUFF then
		return false
	end
	if fq.timing == "timed" and not row.timed then
		return false
	end
	if fq.timing == "passive" and row.timed then
		return false
	end
	if fq.search ~= "" then
		local q = fq.search:lower()
		local name = (row.name or ""):lower()
		if not name:find(q, 1, true) and not tostring(row.abilityId):find(q, 1, true) then
			return false
		end
	end
	return true
end

-- The full predicate (relationship segment included). Self→Self is hidden unless the
-- segment explicitly selects it or Reveal Self-passives is on.
function QAT.Aggregator_RowPasses(row, fq)
	if not passesNonRelationship(row, fq) then
		return false
	end
	if fq.relationship == "all" then
		if row.bucket == "ss" and not fq.revealPassives then
			return false
		end
		return true
	end
	return row.bucket == fq.relationship
end

-- Per-bucket counts (respecting the rest of the filter) for the segment labels.
local function bucketCounts(fq)
	local counts = { all = 0, bs = 0, sb = 0, xb = 0, gs = 0, ss = 0 }
	for _, row in ipairs(QAT.capture.list) do
		if passesNonRelationship(row, fq) then
			if counts[row.bucket] ~= nil then
				counts[row.bucket] = counts[row.bucket] + 1
			end
			-- "All" excludes Self→Self unless passives are revealed.
			if row.bucket ~= "ss" or fq.revealPassives then
				counts.all = counts.all + 1
			end
		end
	end
	return counts
end

-- ---------------------------------------------------------------------------
-- Geometry
-- ---------------------------------------------------------------------------

local function saveGeometry()
	local f = QAT.aggregator.frame
	if not f then
		return
	end
	local g = QAT.sv.capture.window
	g.x, g.y = f:GetLeft(), f:GetTop()
	g.width, g.height = f:GetDimensions()
end

function QAT.Aggregator_Relayout()
	local f = QAT.aggregator.frame
	if not f then
		return
	end
	local w, h = f:GetDimensions()
	local bodyY = TITLE_H + CTRL_H + FILTER_H
	local bodyH = h - bodyY

	local listW = w - INSPECTOR_W - PANE_GAP
	QAT.aggregator.listPane:ClearAnchors()
	QAT.aggregator.listPane:SetAnchor(TOPLEFT, f, TOPLEFT, 0, bodyY)
	QAT.aggregator.listPane:SetDimensions(listW, bodyH)

	QAT.aggregator.inspectorPane:ClearAnchors()
	QAT.aggregator.inspectorPane:SetAnchor(TOPLEFT, f, TOPLEFT, listW + PANE_GAP, bodyY)
	QAT.aggregator.inspectorPane:SetDimensions(INSPECTOR_W, bodyH)

	if QAT.Aggregator_List_Relayout then
		QAT.Aggregator_List_Relayout()
	end
end

-- ---------------------------------------------------------------------------
-- Title bar
-- ---------------------------------------------------------------------------

local function buildTitleBar(f)
	local bar = W.Panel(f, "QAT_Agg_Title", { 0.065, 0.08, 0.11, 1 })
	bar:SetAnchor(TOPLEFT, f, TOPLEFT, 0, 0)
	bar:SetAnchor(TOPRIGHT, f, TOPRIGHT, 0, 0)
	bar:SetHeight(TITLE_H)
	bar:SetMouseEnabled(true)
	bar:SetHandler("OnMouseDown", function()
		f:StartMoving()
	end)
	bar:SetHandler("OnMouseUp", function()
		f:StopMovingOrResizing()
		saveGeometry()
	end)

	local title = W.Label(bar, "QAT_Agg_TitleText", QAT.displayName .. "  —  Effect Aggregator")
	title:SetAnchor(LEFT, bar, LEFT, 10, 0)

	local close = W.TextButton(bar, "QAT_Agg_Close", "X", function()
		QAT.Aggregator_Toggle()
	end)
	close:SetDimensions(TITLE_H - 6, TITLE_H - 6)
	close:SetAnchor(RIGHT, bar, RIGHT, -4, 0)
end

-- ---------------------------------------------------------------------------
-- Capture control bar
-- ---------------------------------------------------------------------------

local function buildControlBar(f)
	local bar = W.Panel(f, "QAT_Agg_Ctrl", { 0.05, 0.062, 0.088, 1 })
	bar:SetAnchor(TOPLEFT, f, TOPLEFT, 0, TITLE_H)
	bar:SetAnchor(TOPRIGHT, f, TOPRIGHT, 0, TITLE_H)
	bar:SetHeight(CTRL_H)
	QAT.aggregator.ctrlBar = bar

	-- On/Off toggle (whole pill). Color + label reflect running state.
	local toggle = W.TextButton(bar, "QAT_Agg_Toggle", "Capture off", function()
		QAT.Capture_Toggle()
	end)
	toggle:SetMinWidth(120)
	toggle:SetHeight(28)
	toggle:SetAnchor(LEFT, bar, LEFT, 10, 0)
	QAT.aggregator.toggleBtn = toggle

	-- State tag (LIVE / FROZEN / STOPPED).
	local tag = W.Badge(bar, "QAT_Agg_StateTag", "STOPPED", COL.ss)
	tag:SetAnchor(LEFT, toggle, RIGHT, 10, 0)
	QAT.aggregator.stateTag = tag

	-- Status line (capturing in <zone> · N effects).
	local status = W.Label(bar, "QAT_Agg_Status", "", "$(MEDIUM_FONT)|15|soft-shadow-thin")
	status:SetColor(0.6, 0.68, 0.78, 1)
	status:SetAnchor(LEFT, tag, RIGHT, 10, 0)
	QAT.aggregator.statusLabel = status

	-- Clear catch (right).
	local clear = W.TextButton(bar, "QAT_Agg_Clear", "Clear catch", function()
		QAT.Capture_Clear()
	end)
	clear:SetAnchor(RIGHT, bar, RIGHT, -10, 0)
	QAT.aggregator.clearBtn = clear

	-- Freeze view (view pause only; capture keeps running).
	local freeze = W.TextButton(bar, "QAT_Agg_Freeze", "Freeze view", function()
		QAT.Capture_SetFrozen(not QAT.capture.frozen)
	end)
	freeze:SetAnchor(RIGHT, clear, LEFT, 8, 0)
	QAT.aggregator.freezeBtn = freeze

	-- Zone selector (scopes the aggregated view; distinct from the live-capture zone).
	local zone = W.Dropdown(bar, "QAT_Agg_Zone", 150, { { label = "All zones", value = nil } }, nil, function(v)
		QAT.aggregator.filter.zoneId = v
		QAT.Aggregator_Refresh()
	end)
	zone:SetAnchor(RIGHT, freeze, LEFT, 8, 0)
	QAT.aggregator.zoneDd = zone
end

-- ---------------------------------------------------------------------------
-- Filter bar
-- ---------------------------------------------------------------------------

-- A single-select segmented control: a row of joined TextButtons sharing one value.
-- onSelect(value) fires on change. Returns { setValue, setCount } helpers.
local function segmented(parent, name, options, current, onSelect)
	local group = { buttons = {} }
	local prev
	for _, opt in ipairs(options) do
		local btn = W.TextButton(parent, name .. "_" .. opt.value, opt.label, function()
			group:setValue(opt.value) -- move the highlight to the clicked segment
			onSelect(opt.value)
		end)
		btn:SetHeight(26)
		btn.optValue = opt.value
		btn.optLabel = opt.label
		if prev then
			btn:SetAnchor(LEFT, prev, RIGHT, -1, 0) -- shared border, joined pills
		else
			btn:SetAnchor(LEFT, parent, LEFT, 0, 0)
		end
		btn:SetSelected(opt.value == current)
		group.buttons[opt.value] = btn
		prev = btn
	end
	function group:setValue(v)
		for val, btn in pairs(self.buttons) do
			btn:SetSelected(val == v)
		end
	end
	-- Append a live count to a segment's label.
	function group:setCount(v, n)
		local btn = self.buttons[v]
		if btn then
			btn:SetText(btn.optLabel .. "  " .. n)
		end
	end
	group.first = options[1] and group.buttons[options[1].value]
	return group
end

local function buildFilterBar(f)
	local bar = W.Panel(f, "QAT_Agg_Filter", { 0.045, 0.055, 0.078, 1 })
	bar:SetAnchor(TOPLEFT, f, TOPLEFT, 0, TITLE_H + CTRL_H)
	bar:SetAnchor(TOPRIGHT, f, TOPRIGHT, 0, TITLE_H + CTRL_H)
	bar:SetHeight(FILTER_H)
	QAT.aggregator.filterBar = bar

	-- Row 1: relationship segmented + reveal-passives toggle.
	local rel = segmented(bar, "QAT_Agg_Rel", RELATIONSHIPS, QAT.aggregator.filter.relationship, function(v)
		QAT.aggregator.filter.relationship = v
		QAT.Aggregator_Refresh()
	end)
	rel.first:ClearAnchors()
	rel.first:SetAnchor(TOPLEFT, bar, TOPLEFT, 10, 8)
	QAT.aggregator.relSeg = rel

	local reveal = W.TextButton(bar, "QAT_Agg_Reveal", "Reveal Self-passives", function()
		local on = not QAT.aggregator.filter.revealPassives
		QAT.aggregator.filter.revealPassives = on
		QAT.aggregator.revealBtn:SetSelected(on)
		QAT.Aggregator_Refresh()
	end)
	reveal:SetHeight(26)
	reveal:SetAnchor(TOPRIGHT, bar, TOPRIGHT, -10, 8)
	QAT.aggregator.revealBtn = reveal

	-- Row 2: search · buffs/debuffs · timed/passive · seen>= · has-stacks · pinned.
	local row2Y = 44
	local search = W.EditBox(bar, "QAT_Agg_Search", 200, 24, "", function(t)
		QAT.aggregator.filter.search = t or ""
		QAT.Aggregator_Refresh()
	end)
	search:SetAnchor(TOPLEFT, bar, TOPLEFT, 10, row2Y)
	QAT.aggregator.searchBox = search

	local eff = segmented(
		bar,
		"QAT_Agg_Eff",
		{
			{ value = "any", label = "Any" },
			{ value = "buff", label = "Buffs" },
			{ value = "debuff", label = "Debuffs" },
		},
		"any",
		function(v)
			QAT.aggregator.filter.effect = v
			QAT.Aggregator_Refresh()
		end
	)
	eff.first:ClearAnchors()
	eff.first:SetAnchor(LEFT, search, RIGHT, 12, 0)

	local timing = segmented(
		bar,
		"QAT_Agg_Tim",
		{
			{ value = "any", label = "Any" },
			{ value = "timed", label = "Timed" },
			{ value = "passive", label = "Passive" },
		},
		"any",
		function(v)
			QAT.aggregator.filter.timing = v
			QAT.Aggregator_Refresh()
		end
	)
	timing.first:ClearAnchors()
	timing.first:SetAnchor(LEFT, eff.buttons["debuff"], RIGHT, 12, 0)

	local pinned = W.TextButton(bar, "QAT_Agg_Pinned", "Pinned only", function()
		local on = not QAT.aggregator.filter.pinnedOnly
		QAT.aggregator.filter.pinnedOnly = on
		QAT.aggregator.pinnedBtn:SetSelected(on)
		QAT.Aggregator_Refresh()
	end)
	pinned:SetHeight(26)
	pinned:SetAnchor(TOPRIGHT, bar, TOPRIGHT, -10, row2Y)
	QAT.aggregator.pinnedBtn = pinned
end

-- ---------------------------------------------------------------------------
-- Refresh (status + counts + list) — throttled off QAT_CaptureChanged
-- ---------------------------------------------------------------------------

-- Build the zone dropdown options from the current catch (per-zone counts + total).
local function refreshZoneOptions()
	local perZone, order = {}, {}
	for _, row in ipairs(QAT.capture.list) do
		local z = row.zoneId or 0
		if not perZone[z] then
			perZone[z] = 0
			table.insert(order, z)
		end
		perZone[z] = perZone[z] + 1
	end
	local opts = { { label = "All zones", value = nil } }
	for _, z in ipairs(order) do
		table.insert(opts, { label = GetZoneNameById(z) .. " · " .. perZone[z], value = z })
	end
	QAT.aggregator.zoneDd:SetOptions(opts)
	QAT.aggregator.zoneDd:SetValue(QAT.aggregator.filter.zoneId)
end

function QAT.Aggregator_Refresh()
	local a = QAT.aggregator
	if not a.frame or a.frame:IsHidden() then
		return
	end
	local cap = QAT.capture

	-- Control bar state.
	if cap.running then
		a.toggleBtn:SetText("Capturing")
		a.toggleBtn:SetSelected(true)
		if cap.frozen then
			a.stateTag:SetText("FROZEN")
			a.stateTag:SetColorRGB(COL.frozen)
		else
			a.stateTag:SetText("LIVE")
			a.stateTag:SetColorRGB(COL.live)
		end
		a.statusLabel:SetText(
			string.format("Capturing in %s · %d effects", GetZoneNameById(cap.currentZoneId), #cap.list)
		)
	else
		a.toggleBtn:SetText("Capture off")
		a.toggleBtn:SetSelected(false)
		a.stateTag:SetText("STOPPED")
		a.stateTag:SetColorRGB(COL.ss)
		a.statusLabel:SetText(cap.everCaptured and "Capture off — showing frozen catch" or "Capture is off")
	end
	a.freezeBtn:SetSelected(cap.frozen)

	-- Segment counts.
	local counts = bucketCounts(a.filter)
	for _, r in ipairs(RELATIONSHIPS) do
		a.relSeg:setCount(r.value, counts[r.value] or 0)
	end

	refreshZoneOptions()

	-- Freeze holds the LIST still for reading; the control bar keeps updating so the
	-- FROZEN state is visible and capture is clearly still running.
	if QAT.Aggregator_List_Render and not cap.frozen then
		QAT.Aggregator_List_Render()
	end

	-- Keep the inspector in sync with the (possibly live-updating) selected row.
	if QAT.Aggregator_Inspector_Render then
		local sel = a.selectedKey and QAT.capture.store[a.selectedKey]
		QAT.Aggregator_Inspector_Render(sel or nil)
	end
end

-- ---------------------------------------------------------------------------
-- Init / toggle
-- ---------------------------------------------------------------------------

function QAT.Aggregator_Init()
	-- Lazy-default the window geometry (no migration needed; nested under capture SV).
	QAT.sv.capture.window = QAT.sv.capture.window or { x = 240, y = 140, width = 1120, height = 620 }
	local g = QAT.sv.capture.window
	QAT.aggregator.filter = defaultFilter()

	local f = WM:CreateTopLevelWindow("QAT_Aggregator")
	f:SetDimensions(g.width, g.height)
	f:SetClampedToScreen(true)
	f:SetMouseEnabled(true)
	f:SetMovable(true)
	f:SetResizeHandleSize(6)
	f:SetDimensionConstraints(760, 420, 0, 0)
	f:SetHidden(true)
	f:ClearAnchors()
	f:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, g.x, g.y)
	f:SetHandler("OnMoveStop", saveGeometry)
	f:SetHandler("OnResizeStop", function()
		saveGeometry()
		QAT.Aggregator_Relayout()
	end)
	W.Panel(f, "QAT_Agg_Bg", { 0.043, 0.075, 0.098, 0.98 }):SetAnchorFill()
	QAT.aggregator.frame = f

	buildTitleBar(f)
	buildControlBar(f)
	buildFilterBar(f)

	-- Body panes (list | inspector). Renderers are layered on in later steps.
	QAT.aggregator.listPane = W.Panel(f, "QAT_Agg_ListPane", { 0.04, 0.05, 0.07, 1 })
	QAT.aggregator.inspectorPane = W.Panel(f, "QAT_Agg_InspectorPane", { 0.04, 0.058, 0.078, 1 })
	if QAT.Aggregator_List_Build then
		QAT.Aggregator_List_Build(QAT.aggregator.listPane)
	end
	if QAT.Aggregator_Inspector_Build then
		QAT.Aggregator_Inspector_Build(QAT.aggregator.inspectorPane)
	end

	QAT.Aggregator_Relayout()

	-- Live refresh: the engine coalesces the callback, so this is already throttled.
	-- Refresh always runs; Refresh itself holds the list when frozen (view pause),
	-- while still updating the control bar so FROZEN + capture status stay live.
	CALLBACK_MANAGER:RegisterCallback("QAT_CaptureChanged", function()
		QAT.Aggregator_Refresh()
	end)

	QAT.log.capture:Info("aggregator window ready")
end

-- Build Tracker: seed a minimal single-effect tracker from a row and hand off to
-- the Editor. Deliberately thin — the Editor owns real authoring (phases, load).
local buildCounter = 0
function QAT.Aggregator_BuildTracker(row)
	if not row then
		return
	end
	buildCounter = buildCounter + 1
	local def = QAT.CanonicalizeDef({
		id = "tracker_agg_" .. GetTimeStamp() .. "_" .. buildCounter,
		kind = "tracker",
		display = "icon",
		name = row.name or ("#" .. row.abilityId),
		icon = row.icon,
		abilityIds = { row.abilityId },
		-- Self→me watches the player; anything on the boss defaults to the target.
		unit = (row.targetRole == "me") and "player" or "reticleover",
		x = math.floor(GuiRoot:GetWidth() / 2 - 32),
		y = math.floor(GuiRoot:GetHeight() / 2 - 32),
		enabled = true,
	})

	-- Passive effect (no duration) -> track by presence, no timer chrome.
	if not row.timed then
		for _, phase in ipairs(def.phases) do
			if phase.id == "active" then
				phase.duration = { type = "none" }
				phase.look.showTime = false
			end
		end
	end

	table.insert(QAT.sv.trackers, def)
	QAT.log.capture:Info("build-tracker: '%s' from #%d", def.id, row.abilityId)
	if QAT.widgets.NotifyTrackerChanged then
		QAT.widgets.NotifyTrackerChanged()
	end

	-- Open the Editor (if hidden) and land on the new tracker.
	if QAT.editor and QAT.editor.frame and QAT.editor.frame:IsHidden() and QAT.Editor_Toggle then
		QAT.Editor_Toggle()
	end
	if QAT.Editor_SelectNode then
		QAT.Editor_SelectNode(def.id)
	end
	d(
		string.format(
			"%s: built tracker for %s (#%d) — opened in the Editor.",
			QAT.displayName,
			def.name,
			row.abilityId
		)
	)
end

function QAT.Aggregator_Toggle()
	local f = QAT.aggregator.frame
	if not f then
		QAT.log.capture:Warning("Aggregator_Toggle before init")
		return
	end
	local show = f:IsHidden()
	f:SetHidden(not show)
	if show then
		QAT.Aggregator_Refresh()
	end
end
