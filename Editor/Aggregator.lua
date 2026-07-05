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

local TITLE_H, CTRL_H, FILTER_H = 28, 54, 86
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
		search = "",
		effect = "any", -- any | buff | debuff
		timing = "any", -- any | timed | passive
		seenMin = 0,
		hasStacks = false,
		favouritesOnly = false,
		prioritiseMine = false, -- float effects the character can produce to the top
		zoneId = nil, -- nil = all zones
		sort = "lastSeen", -- lastSeen | seen | name
	}
end

-- "Mine" lookup: ability ids the character has access to — every ability slotted on
-- either bar plus every scribable grimoire's cast id. Loadout-dependent, so it is
-- recomputed on demand (window open / toggle), never stored. `scribed` maps a
-- grimoire cast id to its name for the "comes from" readout.
function QAT.Aggregator_RefreshMine()
	local set, scribed = {}, {}
	for _, e in ipairs(QAT.conditions.ScanSlottedAbilities()) do
		set[e.abilityId] = true
	end
	for _, g in ipairs(QAT.conditions.ScribedGrimoires()) do
		if g.abilityId and g.abilityId > 0 then
			set[g.abilityId] = true
			scribed[g.abilityId] = { name = g.name, icon = g.icon }
		end
	end
	QAT.aggregator.mine = { set = set, scribed = scribed }
end

-- Does this effect come from something the player can produce? True when its ability
-- is slotted/scribable, or it was self-cast (a buff/passive the player put up).
function QAT.Aggregator_RowIsMine(row)
	local m = QAT.aggregator.mine
	if m and m.set[row.abilityId] then
		return true
	end
	return row.castByPlayer and row.bucket == "ss" or false
end

-- Grimoire name this effect's ability is the cast id of, or nil. Only the grimoire
-- cast ability itself is attributable — the sub-buffs it grants have their own ids
-- with no API link back, so we never guess.
function QAT.Aggregator_RowScribedFrom(row)
	local m = QAT.aggregator.mine
	local e = m and m.scribed[row.abilityId]
	return e and e.name or nil
end

-- The grimoire's icon for a scribed-attributable row, or nil.
function QAT.Aggregator_RowScribedIcon(row)
	local m = QAT.aggregator.mine
	local e = m and m.scribed[row.abilityId]
	return e and e.icon or nil
end

-- ---------------------------------------------------------------------------
-- Filtering (shared by the count badges and, later, the list renderer)
-- ---------------------------------------------------------------------------

-- Does a row pass everything EXCEPT the relationship segment? (Counts per bucket are
-- computed with the rest of the filter applied, so the segment labels stay honest.)
local function passesNonRelationship(row, fq)
	if fq.favouritesOnly and not row.favourited then
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
		return true -- Self→Self passives are always shown (their section is pinned open)
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
			counts.all = counts.all + 1 -- every bucket (incl. Self→Self) counts toward All
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
	toggle:SetHeight(30)
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

	-- A hairline divider setting the view controls (zone/freeze/clear) apart from the
	-- live-capture status on the left.
	local vrule = W.Panel(bar, "QAT_Agg_CtrlRule", { 0.16, 0.20, 0.27, 1 })
	vrule:SetDimensions(1, 22)
	vrule:SetAnchor(RIGHT, zone, LEFT, -12, 0)
end

-- ---------------------------------------------------------------------------
-- Filter bar
-- ---------------------------------------------------------------------------

-- A single-select segmented control: a row of joined TextButtons sharing one value.
-- onSelect(value) fires on change. Returns { setValue, setCount } helpers.
local function segmented(parent, name, options, current, onSelect)
	local group = { buttons = {} }
	-- A recessed inset track sits behind the pills (created first so it draws under
	-- them), auto-sized by anchoring to the first and last button. Reads as one control
	-- surface instead of loose bordered buttons.
	local track = W.Panel(parent, name .. "_Track", { 0.018, 0.028, 0.042, 1 }, { 0.10, 0.13, 0.18, 1 })
	group.track = track
	local prev, first, last
	for _, opt in ipairs(options) do
		local btn = W.TextButton(parent, name .. "_" .. opt.value, opt.label, function()
			group:setValue(opt.value) -- move the highlight to the clicked segment
			onSelect(opt.value)
		end)
		btn:SetHeight(28)
		btn.optValue = opt.value
		btn.optLabel = opt.label
		if prev then
			btn:SetAnchor(LEFT, prev, RIGHT, 2, 0) -- small gap so each reads as a pill
		end
		btn:SetSelected(opt.value == current)
		group.buttons[opt.value] = btn
		prev = btn
		first = first or btn
		last = btn
	end
	-- Wrap the track around the pills with a little padding; it follows their widths
	-- (which change as counts are appended).
	local P = 4
	track:ClearAnchors()
	track:SetAnchor(TOPLEFT, first, TOPLEFT, -P, -P)
	track:SetAnchor(BOTTOMRIGHT, last, BOTTOMRIGHT, P, P)
	function group:setValue(v)
		for val, btn in pairs(self.buttons) do
			btn:SetSelected(val == v)
		end
	end
	-- Append a live count to a segment's label; a zero is dimmed so only meaningful
	-- numbers stand out.
	function group:setCount(v, n)
		local btn = self.buttons[v]
		if btn then
			local col = (n == 0) and "|c46505f" or "|c9fb0c6"
			btn:SetText(btn.optLabel .. "  " .. col .. n .. "|r")
		end
	end
	-- The first pill is the anchor surface (caller positions it); the track follows.
	group.first = first
	return group
end

-- ---------------------------------------------------------------------------
-- Ignored-abilities popup (a small list with an X to un-ignore each)
-- ---------------------------------------------------------------------------

local IGN_POPW = 320
local ignoredPool

local function makeIgnoredRow(parent, name)
	local p = W.Panel(parent, name, { 0.06, 0.09, 0.13, 1 }, { 0.12, 0.17, 0.22, 1 })
	p:SetHeight(26)
	local icon = WM:CreateControl(name .. "_Ic", p, CT_TEXTURE)
	icon:SetDimensions(18, 18)
	icon:SetAnchor(LEFT, p, LEFT, 6, 0)
	local nm = W.Label(p, name .. "_Nm", "", "$(MEDIUM_FONT)|15|soft-shadow-thin")
	nm:SetAnchor(LEFT, icon, RIGHT, 8, 0)
	local del = W.CloseButton(p, name .. "_X", nil)
	del:SetDimensions(22, 22)
	del:SetAnchor(RIGHT, p, RIGHT, -3, 0)
	function p:Bind(id, onRemove)
		local n, ic = QAT.util.AbilityInfo(id)
		icon:SetTexture(ic)
		nm:SetText(n .. "  |c556070#" .. id .. "|r")
		del.onClick = onRemove
		self:SetHidden(false)
	end
	return p
end

local function refreshIgnoredPopup()
	local p = QAT.aggregator.ignoredPopup
	if not p or p:IsHidden() then
		return
	end
	ignoredPool = ignoredPool or W.NewPool()
	W.PoolBegin(ignoredPool)
	local ids = {}
	for id in pairs(QAT.sv.capture.ignored or {}) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	local y = 32
	if #ids == 0 then
		local e = W.PoolGet(ignoredPool, "empty", function()
			return W.Label(p, "QAT_Agg_IgEmpty", "", "$(MEDIUM_FONT)|15|soft-shadow-thin")
		end)
		e:SetHidden(false)
		e:SetColor(0.5, 0.55, 0.62, 1)
		e:SetText("No ignored abilities.")
		e:ClearAnchors()
		e:SetAnchor(TOPLEFT, p, TOPLEFT, 12, y)
		y = y + 28
	else
		for i, id in ipairs(ids) do
			local row = W.PoolGet(ignoredPool, "row" .. i, function()
				return makeIgnoredRow(p, "QAT_Agg_IgRow" .. i)
			end)
			row:ClearAnchors()
			row:SetAnchor(TOPLEFT, p, TOPLEFT, 8, y)
			row:SetWidth(IGN_POPW - 16)
			row:Bind(id, function()
				QAT.Capture_Unignore(id)
				refreshIgnoredPopup()
				if QAT.Aggregator_List_Render then
					QAT.Aggregator_List_Render()
				end
			end)
			y = y + 30
		end
	end
	W.PoolEnd(ignoredPool)
	p:SetHeight(y + 8)
end

local function buildIgnoredPopup(f)
	local p = W.Panel(f, "QAT_Agg_Ignored", { 0.055, 0.075, 0.10, 0.985 }, { 0.18, 0.24, 0.32, 1 })
	p:SetWidth(IGN_POPW)
	p:SetHidden(true)
	p:SetDrawTier(DT_HIGH) -- float above the list/inspector
	local title = W.Label(p, "QAT_Agg_IgTitle", "Ignored abilities", "$(BOLD_FONT)|15|soft-shadow-thin")
	title:SetColor(0.72, 0.79, 0.88, 1)
	title:SetAnchor(TOPLEFT, p, TOPLEFT, 12, 9)
	QAT.aggregator.ignoredPopup = p
end

-- Toggle the ignored-abilities popup (anchored under its filter-bar button).
function QAT.Aggregator_ToggleIgnored()
	local p = QAT.aggregator.ignoredPopup
	if not p then
		return
	end
	local show = p:IsHidden()
	p:SetHidden(not show)
	if show then
		p:ClearAnchors()
		p:SetAnchor(TOPRIGHT, QAT.aggregator.ignoredBtn, BOTTOMRIGHT, 0, 6)
		refreshIgnoredPopup()
	end
end

local function buildFilterBar(f)
	local bar = W.Panel(f, "QAT_Agg_Filter", { 0.045, 0.055, 0.078, 1 })
	bar:SetAnchor(TOPLEFT, f, TOPLEFT, 0, TITLE_H + CTRL_H)
	bar:SetAnchor(TOPRIGHT, f, TOPRIGHT, 0, TITLE_H + CTRL_H)
	bar:SetHeight(FILTER_H)
	QAT.aggregator.filterBar = bar

	-- Separate the filter bar from the capture chrome above it with a hairline rule.
	local topRule = W.Divider(bar, "QAT_Agg_FilterRule")
	topRule:SetAnchor(TOPLEFT, bar, TOPLEFT, 0, 0)
	topRule:SetAnchor(TOPRIGHT, bar, TOPRIGHT, 0, 0)

	-- Row 1: relationship segmented (left) + Favourites / Focus Scribing / Ignored
	-- toggles (right, in that order).
	local rel = segmented(bar, "QAT_Agg_Rel", RELATIONSHIPS, QAT.aggregator.filter.relationship, function(v)
		QAT.aggregator.filter.relationship = v
		QAT.Aggregator_Refresh()
	end)
	rel.first:ClearAnchors()
	rel.first:SetAnchor(TOPLEFT, bar, TOPLEFT, 10, 8)
	QAT.aggregator.relSeg = rel

	local ignoredBtn = W.TextButton(bar, "QAT_Agg_IgnoredBtn", "Ignored", function()
		QAT.Aggregator_ToggleIgnored()
	end)
	ignoredBtn:SetHeight(30)
	ignoredBtn:SetAnchor(TOPRIGHT, bar, TOPRIGHT, -10, 8)
	QAT.widgets.Tooltip(ignoredBtn, "Abilities you've ignored — click the × on one to un-ignore it.")
	QAT.aggregator.ignoredBtn = ignoredBtn

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

	-- Focus Scribing: float effects the character can produce (slotted or scribable) to
	-- the top, so a same-named buff's own-source id sorts above copies from others.
	local mine = W.TextButton(bar, "QAT_Agg_Mine", "Focus Scribing ability", function()
		local on = not QAT.aggregator.filter.prioritiseMine
		QAT.aggregator.filter.prioritiseMine = on
		if on then
			QAT.Aggregator_RefreshMine() -- pick up the current loadout
		end
		QAT.aggregator.mineBtn:SetSelected(on)
		QAT.Aggregator_Refresh()
	end)
	mine:SetHeight(30)
	mine:SetSelected(QAT.aggregator.filter.prioritiseMine)
	mine:SetAnchor(RIGHT, ignoredBtn, LEFT, -8, 0)
	QAT.widgets.Tooltip(
		mine,
		"Float effects from your scribable grimoires (and your slotted skills) to the top, so a scribed variant of a shared buff sorts above copies from other sources."
	)
	QAT.aggregator.mineBtn = mine

	local fav = W.TextButton(bar, "QAT_Agg_Fav", "Favourites only", function()
		local on = not QAT.aggregator.filter.favouritesOnly
		QAT.aggregator.filter.favouritesOnly = on
		QAT.aggregator.favBtn:SetSelected(on)
		QAT.Aggregator_Refresh()
	end)
	fav:SetHeight(30)
	fav:SetAnchor(RIGHT, mine, LEFT, -8, 0)
	QAT.widgets.Tooltip(fav, "Show only favourited effects. Favourites always float to the top of each section.")
	QAT.aggregator.favBtn = fav
	-- Gold star as a texture (the ★ glyph boxes out in the default font).
	local favStar = WM:CreateControl("QAT_Agg_FavStar", bar, CT_TEXTURE)
	favStar:SetTexture("EsoUI/Art/Collections/Favorite_StarOnly.dds")
	favStar:SetColor(0.921, 0.784, 0.353, 1)
	favStar:SetDimensions(14, 14)
	favStar:SetAnchor(RIGHT, fav, LEFT, -4, 0)
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

	-- Keep the ignored popup live while it's open (ignoring/un-ignoring updates it).
	if a.ignoredPopup and not a.ignoredPopup:IsHidden() then
		refreshIgnoredPopup()
	end

	-- Keep the inspector in sync: the Tracker builder while selecting, otherwise the
	-- single-row detail (following the live-updating selected row).
	if a.selecting then
		if QAT.Aggregator_Inspector_RenderBuilder then
			QAT.Aggregator_Inspector_RenderBuilder()
		end
	elseif QAT.Aggregator_Inspector_Render then
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

	-- Build-selection state (session only; distinct from favourites). `selecting`
	-- turns on row checkboxes and swaps the inspector for the Tracker builder;
	-- `selected` is the ordered list of chosen row keys, `selectedSet` its lookup.
	QAT.aggregator.selecting = false
	QAT.aggregator.selected = {}
	QAT.aggregator.selectedSet = {}
	QAT.aggregator.builderManual = false -- switch tracker: auto-mesh (false) vs wire-your-own

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
	buildIgnoredPopup(f)

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

-- ---------------------------------------------------------------------------
-- Build selection (multi-select -> one tracker)
-- ---------------------------------------------------------------------------

-- Toggle whether a row (by key) is in the build selection, preserving pick order.
function QAT.Aggregator_ToggleSelected(key)
	local a = QAT.aggregator
	if not key then
		return
	end
	if a.selectedSet[key] then
		a.selectedSet[key] = nil
		for i, k in ipairs(a.selected) do
			if k == key then
				table.remove(a.selected, i)
				break
			end
		end
	else
		a.selectedSet[key] = true
		a.selected[#a.selected + 1] = key
	end
	if QAT.Aggregator_List_Render then
		QAT.Aggregator_List_Render()
	end
	if QAT.Aggregator_Inspector_RenderBuilder then
		QAT.Aggregator_Inspector_RenderBuilder()
	end
end

-- Remove a row from the selection (the builder's Selected-list × button).
function QAT.Aggregator_RemoveSelected(key)
	if QAT.aggregator.selectedSet[key] then
		QAT.Aggregator_ToggleSelected(key)
	end
end

-- Move a selected row up (-1) or down (+1) in the order (= stage order). Clamped.
function QAT.Aggregator_MoveSelected(key, dir)
	local sel = QAT.aggregator.selected
	for i, k in ipairs(sel) do
		if k == key then
			local j = i + dir
			if j >= 1 and j <= #sel then
				sel[i], sel[j] = sel[j], sel[i]
				if QAT.Aggregator_Inspector_RenderBuilder then
					QAT.Aggregator_Inspector_RenderBuilder()
				end
			end
			return
		end
	end
end

-- Enter/leave multi-select mode. Leaving clears the selection and returns the
-- inspector to the single-row detail.
function QAT.Aggregator_SetSelecting(on)
	local a = QAT.aggregator
	a.selecting = on and true or false
	if not a.selecting then
		a.selected, a.selectedSet = {}, {}
	end
	if a.selectBtn then
		a.selectBtn:SetText(a.selecting and "Selecting" or "Select multiple")
		a.selectBtn:SetSelected(a.selecting)
	end
	if QAT.Aggregator_List_Render then
		QAT.Aggregator_List_Render()
	end
	if a.selecting then
		if QAT.Aggregator_Inspector_RenderBuilder then
			QAT.Aggregator_Inspector_RenderBuilder()
		end
	elseif QAT.Aggregator_Inspector_Render then
		local sel = a.selectedKey and QAT.capture.store[a.selectedKey]
		QAT.Aggregator_Inspector_Render(sel or nil)
	end
end

-- The build action's single source of truth: 1 effect -> a simple tracker, 2+ ->
-- one switch tracker (shows whichever of the chosen effects is active). Selection
-- order is stage order. Exits select mode and opens the Editor on the result.
function QAT.Aggregator_BuildFromSelection()
	local a = QAT.aggregator
	local rows = {}
	for _, key in ipairs(a.selected or {}) do
		local r = QAT.capture.store[key]
		if r then
			rows[#rows + 1] = r
		end
	end
	if #rows == 0 then
		return
	end
	if #rows == 1 then
		QAT.Aggregator_BuildTracker(rows[1])
		QAT.Aggregator_SetSelecting(false)
		return
	end

	local effects = {}
	for _, r in ipairs(rows) do
		-- Watch each effect on the unit it actually lives on: a self→self buff on the
		-- player, anything else (a debuff you put on the boss, a boss mechanic) on the
		-- reticle target.
		effects[#effects + 1] = {
			id = r.abilityId,
			name = r.name,
			unit = (r.targetRole == "me") and "player" or "reticleover",
		}
	end
	buildCounter = buildCounter + 1
	local def = QAT.BuildMutexTrackerDef({
		name = "Stages",
		effects = effects,
		manual = a.builderManual,
		x = math.floor(GuiRoot:GetWidth() / 2 - 110),
		y = math.floor(GuiRoot:GetHeight() / 2 - 20),
		suffix = buildCounter,
	})
	if not def then
		return
	end
	table.insert(QAT.sv.trackers, def)
	QAT.log.capture:Info("build-switch: '%s' from %d selected effect(s)", def.id, #effects)
	if QAT.widgets.NotifyTrackerChanged then
		QAT.widgets.NotifyTrackerChanged()
	end
	if QAT.editor and QAT.editor.frame and QAT.editor.frame:IsHidden() and QAT.Editor_Toggle then
		QAT.Editor_Toggle()
	end
	if QAT.Editor_SelectNode then
		QAT.Editor_SelectNode(def.id)
	end
	d(string.format("%s: built a switch tracker from %d effects — opened in the Editor.", QAT.displayName, #effects))
	QAT.Aggregator_SetSelecting(false)
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
