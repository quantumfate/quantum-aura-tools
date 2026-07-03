-- Effect Aggregator — inspector / teaching panel (right pane).
--
-- The learning surface: for the selected row it shows a header + actions, the RAW
-- ESO data behind the effect (the enums/tags the API actually returns), an observed
-- grid, and a plain-English "what this means" note keyed to the relationship bucket.
-- Controls are built once and re-bound per selection (one row shown at a time).

local WM = GetWindowManager()
local W = QAT.widgets

local PAD = 16
local INNER_W = 436

local COL_BUFF = { 0.561, 0.816, 0.478 }
local COL_DEBUFF = { 0.878, 0.525, 0.435 }
local COL_TIMED = { 0.541, 0.714, 0.839 }
local COL_PASSIVE = { 0.561, 0.635, 0.698 }
local BUCKET_COL = {
	bs = { 0.851, 0.541, 0.416 },
	sb = { 0.310, 0.690, 0.627 },
	xb = { 0.780, 0.639, 0.400 },
	gs = { 0.435, 0.604, 0.816 },
	os = { 0.55, 0.60, 0.68 },
	ss = { 0.490, 0.557, 0.627 },
	xx = { 0.5, 0.5, 0.5 },
}
local BUCKET_LABEL = {
	bs = "BOSS→SELF",
	sb = "SELF→BOSS",
	xb = "OTHER→BOSS",
	gs = "GROUP→SELF",
	os = "OTHER→SELF",
	ss = "SELF→SELF",
	xx = "OTHER",
}
local MEANING = {
	bs = "An incoming boss mechanic — cast on you by the boss (or the environment). The one you usually want to track and react to.",
	sb = "One of your own debuffs sitting on the boss. Track it to watch your uptime.",
	xb = "An effect on your target that you didn't apply — its own buffs/states, or the debuffs a trial dummy puts on itself to simulate a raid.",
	gs = "A buff applied to you by a group member.",
	os = "Applied to you by an add or the environment (not the boss frame).",
	ss = "Your own standing buff or passive (your kit, gear, food, CP).",
	xx = "Unclassified relationship.",
}

-- Reverse enum maps so the raw table shows the real constant names ESO returns.
local EFFECT_TYPE_NAME = {
	[BUFF_EFFECT_TYPE_BUFF] = "BUFF_EFFECT_TYPE_BUFF",
	[BUFF_EFFECT_TYPE_DEBUFF] = "BUFF_EFFECT_TYPE_DEBUFF",
}
local UNIT_TYPE_NAME = {
	[COMBAT_UNIT_TYPE_NONE] = "COMBAT_UNIT_TYPE_NONE",
	[COMBAT_UNIT_TYPE_PLAYER] = "COMBAT_UNIT_TYPE_PLAYER",
	[COMBAT_UNIT_TYPE_PLAYER_PET] = "COMBAT_UNIT_TYPE_PLAYER_PET",
	[COMBAT_UNIT_TYPE_GROUP] = "COMBAT_UNIT_TYPE_GROUP",
	[COMBAT_UNIT_TYPE_OTHER] = "COMBAT_UNIT_TYPE_OTHER",
}

local RAW_FIELDS = {
	"abilityId",
	"effectType",
	"sourceName",
	"sourceType",
	"targetName",
	"targetUnitTag",
	"castByPlayer",
	"isBuff/debuff",
	"timed",
	"buffSlot",
}

local function ago(ts)
	if not ts then
		return "—"
	end
	local s = GetTimeStamp() - ts
	if s < 2 then
		return "just now"
	elseif s < 60 then
		return s .. "s ago"
	elseif s < 3600 then
		return math.floor(s / 60) .. "m ago"
	else
		return math.floor(s / 3600) .. "h ago"
	end
end

-- Fill a raw-field value map { [field] = valueLabel } from a captured row. Shared
-- by the single-row detail and the builder's per-tab raw view.
local function fillRaw(rr, row)
	local isDebuff = row.effectType == BUFF_EFFECT_TYPE_DEBUFF
	rr["abilityId"]:SetText(tostring(row.abilityId))
	rr["effectType"]:SetText(EFFECT_TYPE_NAME[row.effectType] or "—")
	rr["sourceName"]:SetText((row.sourceName and row.sourceName ~= "") and row.sourceName or "—")
	rr["sourceType"]:SetText(UNIT_TYPE_NAME[row.sourceType] or "—")
	rr["targetName"]:SetText((row.targetName and row.targetName ~= "") and row.targetName or "—")
	rr["targetUnitTag"]:SetText('"' .. (row.targetTag or "?") .. '"')
	rr["castByPlayer"]:SetText(row.castByPlayer == nil and "—" or tostring(row.castByPlayer))
	rr["isBuff/debuff"]:SetText(isDebuff and "debuff" or "buff")
	rr["timed"]:SetText(row.timed and "true (has duration)" or "false (passive)")
	rr["buffSlot"]:SetText(row.buffSlot and tostring(row.buffSlot) or "—")
end

-- One row of the builder's ordered Selected list: number, icon, name, id, reorder
-- (up/down), remove. Order here is the stage order in the built switch tracker.
local ARROW_UP = "EsoUI/Art/Miscellaneous/list_sortUp.dds"
local ARROW_DOWN = "EsoUI/Art/Miscellaneous/list_sortDown.dds"
local function makeSelRow(parent, name)
	local p = W.Panel(parent, name, { 0.05, 0.08, 0.11, 1 }, { 0.11, 0.16, 0.21, 1 })
	p:SetHeight(34)
	local num = W.Badge(p, name .. "_N", "1", { 0.55, 0.62, 0.72 })
	num:SetAnchor(LEFT, p, LEFT, 8, 0)
	local icon = WM:CreateControl(name .. "_Ic", p, CT_TEXTURE)
	icon:SetDimensions(22, 22)
	icon:SetAnchor(LEFT, num, RIGHT, 8, 0)
	local nm = W.Label(p, name .. "_Nm", "", "$(MEDIUM_FONT)|16|soft-shadow-thin")
	nm:SetAnchor(LEFT, icon, RIGHT, 8, -1)
	local del = W.CloseButton(p, name .. "_X", nil)
	del:SetDimensions(24, 24)
	del:SetAnchor(RIGHT, p, RIGHT, -4, 0)
	local down = W.IconButton(p, name .. "_Dn", ARROW_DOWN, 16, nil)
	down:SetAnchor(RIGHT, del, LEFT, -6, 0)
	local up = W.IconButton(p, name .. "_Up", ARROW_UP, 16, nil)
	up:SetAnchor(RIGHT, down, LEFT, -4, 0)
	local idl = W.Label(p, name .. "_Id", "", "$(MEDIUM_FONT)|13|soft-shadow-thin")
	idl:SetColor(0.5, 0.58, 0.68, 1)
	idl:SetAnchor(RIGHT, up, LEFT, -10, 0)
	function p:Bind(n, row, cb)
		num:SetText(tostring(n))
		icon:SetTexture(row.icon)
		nm:SetText(row.name or ("#" .. row.abilityId))
		idl:SetText("#" .. row.abilityId)
		del.onClick = cb.onRemove
		up.onClick, down.onClick = cb.onUp, cb.onDown
		up:SetHidden(cb.onUp == nil) -- hidden at the top of the list
		down:SetHidden(cb.onDown == nil) -- hidden at the bottom
		self:SetHidden(false)
	end
	return p
end

-- A raw-data tab for one selected effect (icon + name), highlighted when active.
local function makeTab(parent, name)
	local c = W.Clickable(parent, name, { 0.06, 0.10, 0.14, 1 })
	c.bg:SetEdgeColor(0.13, 0.19, 0.24, 1)
	c.bg:SetEdgeTexture("", 1, 1, 1)
	c:SetHeight(24)
	local ic = WM:CreateControl(name .. "_Ic", c, CT_TEXTURE)
	ic:SetDimensions(16, 16)
	ic:SetAnchor(LEFT, c, LEFT, 5, 0)
	local l = W.Label(c, name .. "_L", "", "$(MEDIUM_FONT)|14|soft-shadow-thin")
	l:SetAnchor(LEFT, ic, RIGHT, 5, -1)
	c:SetHandler("OnMouseUp", function(self, b, inside)
		if inside and b == MOUSE_BUTTON_INDEX_LEFT and self.onClick then
			self.onClick()
		end
	end)
	function c:Bind(row, active, onClick)
		ic:SetTexture(row.icon)
		l:SetText(row.name or ("#" .. row.abilityId))
		l:SetColor(active and 0.95 or 0.7, active and 0.97 or 0.77, active and 1 or 0.86, 1)
		self.bg:SetCenterColor(active and 0.12 or 0.06, active and 0.20 or 0.10, active and 0.30 or 0.14, 1)
		self.bg:SetEdgeColor(0.13, 0.19, 0.24, 1)
		self.bg:SetEdgeTexture("", 1, 1, 1)
		self.onClick = onClick
		self:SetWidth(5 + 16 + 5 + math.ceil(l:GetTextWidth()) + 10)
		self:SetHidden(false)
	end
	return c
end

-- ---------------------------------------------------------------------------
-- Build (once)
-- ---------------------------------------------------------------------------

function QAT.Aggregator_Inspector_Build(pane)
	local I = {}
	QAT.aggregator.insp = I

	-- Placeholder shown when nothing is selected.
	local ph =
		W.Label(pane, "QAT_AggIns_PH", "Select an effect to inspect its data.", "$(MEDIUM_FONT)|16|soft-shadow-thin")
	ph:SetColor(0.42, 0.48, 0.56, 1)
	ph:SetAnchor(TOP, pane, TOP, 0, 60)
	ph:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
	I.placeholder = ph

	-- Scroll host for the detail (raw table + note can exceed the pane).
	local sc = WM:CreateControlFromVirtual("QAT_AggIns_Scroll", pane, "ZO_ScrollContainer")
	sc:SetAnchor(TOPLEFT, pane, TOPLEFT, 0, 0)
	sc:SetAnchor(BOTTOMRIGHT, pane, BOTTOMRIGHT, 0, 0)
	local body = GetControl(sc, "ScrollChild")
	body:SetResizeToFitDescendents(true)
	body:SetResizeToFitPadding(0, 12)
	I.scroll = sc
	I.body = body

	-- Header: icon, name, id + copy, badges.
	I.icon = W.IconWell(body, "QAT_AggIns_Icon", 44)
	I.icon:SetAnchor(TOPLEFT, body, TOPLEFT, PAD, PAD)

	I.name = W.Label(body, "QAT_AggIns_Name", "", "$(BOLD_FONT)|20|soft-shadow-thin")
	I.name:SetAnchor(TOPLEFT, I.icon, TOPRIGHT, 12, 0)

	I.id = W.Label(body, "QAT_AggIns_Id", "", "$(MEDIUM_FONT)|15|soft-shadow-thin")
	I.id:SetColor(0.5, 0.58, 0.68, 1)
	I.id:SetAnchor(TOPLEFT, I.icon, TOPRIGHT, 12, 26)

	I.typeBadge = W.Badge(body, "QAT_AggIns_TB", "", COL_BUFF)
	I.typeBadge:SetAnchor(TOPLEFT, I.icon, BOTTOMLEFT, 0, 12)
	I.timeBadge = W.Badge(body, "QAT_AggIns_TmB", "", COL_TIMED)
	I.timeBadge:SetAnchor(LEFT, I.typeBadge, RIGHT, 6, 0)
	I.relBadge = W.Badge(body, "QAT_AggIns_RB", "", BUCKET_COL.bs)
	I.relBadge:SetAnchor(LEFT, I.timeBadge, RIGHT, 6, 0)

	-- Actions: Build Tracker (primary) then Pin / Copy id / Ignore.
	local build = W.TextButton(body, "QAT_AggIns_Build", "Build Tracker", function()
		QAT.Aggregator_BuildTracker(I.row)
	end)
	build:SetHeight(32)
	build:SetSelected(true) -- primary-blue
	build:SetAnchor(TOPLEFT, I.typeBadge, BOTTOMLEFT, 0, 16)
	build:SetMinWidth(INNER_W)
	I.buildBtn = build

	I.favBtn = W.TextButton(body, "QAT_AggIns_Fav", "Favourite", function()
		if not I.row then
			return
		end
		local key = I.row.key
		if I.row.favourited then
			QAT.Capture_Unfavourite(I.row)
		else
			QAT.Capture_Favourite(I.row)
		end
		-- Unfavouriting a library-only row drops it: fall back to the placeholder.
		local stillThere = QAT.capture.store[key]
		if not stillThere then
			QAT.aggregator.selectedKey = nil
		end
		QAT.Aggregator_Inspector_Render(stillThere or nil)
		QAT.Aggregator_List_Render()
	end)
	I.favBtn:SetHeight(28)
	I.favBtn:SetAnchor(TOPLEFT, build, BOTTOMLEFT, 0, 8)

	I.copyBtn = W.TextButton(body, "QAT_AggIns_Copy", "Copy id", function()
		if I.row then
			d(string.format("%s #%d — %s", QAT.displayName, I.row.abilityId, I.row.name or ""))
			I.copyBtn:SetText("printed to chat")
			zo_callLater(function()
				I.copyBtn:SetText("Copy id")
			end, 1500)
		end
	end)
	I.copyBtn:SetHeight(28)
	I.copyBtn:SetAnchor(LEFT, I.favBtn, RIGHT, 8, 0)

	I.ignoreBtn = W.TextButton(body, "QAT_AggIns_Ignore", "Ignore", function()
		if I.row then
			QAT.Capture_Ignore(I.row.abilityId)
			QAT.aggregator.selectedKey = nil
			QAT.Aggregator_Inspector_Render(nil)
			QAT.Aggregator_List_Render()
		end
	end)
	I.ignoreBtn:SetHeight(28)
	I.ignoreBtn:SetAnchor(LEFT, I.copyBtn, RIGHT, 8, 0)

	-- RAW DATA card.
	local raw = W.Card(body, "QAT_AggIns_Raw", "Raw data")
	raw:SetAnchor(TOPLEFT, I.favBtn, BOTTOMLEFT, 0, 16)
	raw:SetWidth(INNER_W)
	I.rawCard = raw
	I.rawRows = {}
	local ry = raw.contentY
	for i, field in ipairs(RAW_FIELDS) do
		local lab = W.Label(raw, "QAT_AggIns_RL" .. i, field, "$(MEDIUM_FONT)|14|soft-shadow-thin")
		lab:SetColor(0.5, 0.57, 0.66, 1)
		lab:SetAnchor(TOPLEFT, raw, TOPLEFT, PAD, ry)
		local val = W.Label(raw, "QAT_AggIns_RV" .. i, "", "$(MEDIUM_FONT)|14|soft-shadow-thin")
		val:SetColor(0.82, 0.87, 0.93, 1)
		val:SetAnchor(TOPLEFT, raw, TOPLEFT, 160, ry)
		val:SetAnchor(TOPRIGHT, raw, TOPRIGHT, -PAD, ry)
		val:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
		I.rawRows[field] = val
		ry = ry + 22
	end
	raw:SetHeight(ry + 8)

	-- OBSERVED grid (2x2).
	local obs = W.Card(body, "QAT_AggIns_Obs", "Observed")
	obs:SetAnchor(TOPLEFT, raw, BOTTOMLEFT, 0, 12)
	obs:SetWidth(INNER_W)
	I.obsCard = obs
	local function cell(key, title, x, y)
		local t = W.Label(obs, "QAT_AggIns_O" .. key .. "T", title, "$(MEDIUM_FONT)|13|soft-shadow-thin")
		t:SetColor(0.5, 0.57, 0.66, 1)
		t:SetAnchor(TOPLEFT, obs, TOPLEFT, x, y)
		local v = W.Label(obs, "QAT_AggIns_O" .. key .. "V", "", "$(BOLD_FONT)|17|soft-shadow-thin")
		v:SetColor(0.85, 0.9, 0.95, 1)
		v:SetAnchor(TOPLEFT, obs, TOPLEFT, x, y + 16)
		return v
	end
	local half = INNER_W / 2
	I.obsSeen = cell("Seen", "Seen count", PAD, obs.contentY)
	I.obsStacks = cell("Stk", "Max stacks", half, obs.contentY)
	I.obsFirst = cell("First", "First seen", PAD, obs.contentY + 44)
	I.obsLast = cell("Last", "Last seen", half, obs.contentY + 44)
	obs:SetHeight(obs.contentY + 88)

	-- WHAT THIS MEANS note.
	local note = W.Card(body, "QAT_AggIns_Note", "What this means")
	note:SetAnchor(TOPLEFT, obs, BOTTOMLEFT, 0, 12)
	note:SetWidth(INNER_W)
	I.noteCard = note
	local nt = W.Label(note, "QAT_AggIns_NoteT", "", "$(MEDIUM_FONT)|15|soft-shadow-thin")
	nt:SetColor(0.68, 0.75, 0.83, 1)
	nt:SetAnchor(TOPLEFT, note, TOPLEFT, PAD, note.contentY)
	nt:SetWidth(INNER_W - PAD * 2)
	nt:SetVerticalAlignment(TEXT_ALIGN_TOP)
	I.noteText = nt

	-- --------------------------------------------------------------------------
	-- Builder-mode skeleton (multi-select): swaps in over the single-row detail.
	-- Header + Done, the Build Tracker button, a "what this builds" info card, the
	-- ordered Selected list (pooled), and per-effect raw-data tabs (pooled) driving
	-- a reused set of raw-field rows.
	-- --------------------------------------------------------------------------
	I.builderPool = W.NewPool()
	I.tabPool = W.NewPool()

	I.bTitle = W.Label(body, "QAT_AggIns_BTitle", "Tracker builder", "$(BOLD_FONT)|20|soft-shadow-thin")
	I.bTitle:SetAnchor(TOPLEFT, body, TOPLEFT, PAD, PAD)
	I.bSub = W.Label(body, "QAT_AggIns_BSub", "", "$(MEDIUM_FONT)|15|soft-shadow-thin")
	I.bSub:SetColor(0.55, 0.62, 0.72, 1)
	I.bSub:SetAnchor(TOPLEFT, body, TOPLEFT, PAD, PAD + 26)
	I.bDone = W.TextButton(body, "QAT_AggIns_BDone", "Done", function()
		QAT.Aggregator_SetSelecting(false)
	end)
	I.bDone:SetHeight(26)
	I.bDone:SetAnchor(TOPRIGHT, body, TOPLEFT, PAD + INNER_W, PAD)

	-- The single source of truth for creating the tracker; same anchor family as the
	-- single-mode Build button so it reads as "the" action.
	I.bBuild = W.TextButton(body, "QAT_AggIns_BBuild", "Build Tracker", function()
		QAT.Aggregator_BuildFromSelection()
	end)
	I.bBuild:SetSelected(true)
	I.bBuild:SetHeight(32)
	I.bBuild:SetMinWidth(INNER_W)
	I.bBuild:SetAnchor(TOPLEFT, body, TOPLEFT, PAD, PAD + 58)
	I.bBuildNote = W.Label(body, "QAT_AggIns_BBNote", "", "$(MEDIUM_FONT)|14|soft-shadow-thin")
	I.bBuildNote:SetColor(0.5, 0.58, 0.68, 1)
	I.bBuildNote:SetAnchor(TOPLEFT, body, TOPLEFT, PAD, PAD + 96)

	I.bInfo = W.Card(body, "QAT_AggIns_BInfo", "Builds a simple tracker")
	I.bInfo:SetWidth(INNER_W)
	I.bInfo:SetAnchor(TOPLEFT, body, TOPLEFT, PAD, PAD + 122)
	I.bInfoText = W.Label(I.bInfo, "QAT_AggIns_BInfoT", "", "$(MEDIUM_FONT)|15|soft-shadow-thin")
	I.bInfoText:SetColor(0.68, 0.75, 0.83, 1)
	I.bInfoText:SetAnchor(TOPLEFT, I.bInfo, TOPLEFT, PAD, I.bInfo.contentY)
	I.bInfoText:SetWidth(INNER_W - PAD * 2)
	I.bInfoText:SetVerticalAlignment(TEXT_ALIGN_TOP)

	-- Opt out of auto-switching: build the phases only and wire transitions yourself.
	-- Only meaningful for a switch tracker (2+), so shown/hidden per render.
	I.bManualChk = W.Checkbox(body, "QAT_AggIns_BManual", false, function(v)
		QAT.aggregator.builderManual = v
		QAT.Aggregator_Inspector_RenderBuilder()
	end)
	I.bManualLbl =
		W.Label(body, "QAT_AggIns_BManualL", "Wire the switching myself", "$(MEDIUM_FONT)|15|soft-shadow-thin")
	I.bManualLbl:SetColor(0.68, 0.75, 0.83, 1)
	QAT.widgets.Tooltip(
		I.bManualLbl,
		"Build one phase per effect plus a fallback, with no transitions — you add the switching rules yourself in the editor."
	)

	I.bSelHdr = W.Label(body, "QAT_AggIns_BSelHdr", "SELECTED", "$(BOLD_FONT)|13|soft-shadow-thin")
	I.bSelHdr:SetColor(0.5, 0.57, 0.66, 1)
	I.bRawHdr = W.Label(body, "QAT_AggIns_BRawHdr", "RAW DATA", "$(BOLD_FONT)|13|soft-shadow-thin")
	I.bRawHdr:SetColor(0.5, 0.57, 0.66, 1)

	-- Raw-field rows reused for whichever tab is active; positioned each render.
	I.bRawRows = {}
	I.bRawByField = {}
	for i, field in ipairs(RAW_FIELDS) do
		local lab = W.Label(body, "QAT_AggIns_BRL" .. i, field, "$(MEDIUM_FONT)|14|soft-shadow-thin")
		lab:SetColor(0.5, 0.57, 0.66, 1)
		local val = W.Label(body, "QAT_AggIns_BRV" .. i, "", "$(MEDIUM_FONT)|14|soft-shadow-thin")
		val:SetColor(0.82, 0.87, 0.93, 1)
		val:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
		I.bRawRows[i] = { lab = lab, val = val }
		I.bRawByField[field] = val
	end

	I.builder =
		{ I.bTitle, I.bSub, I.bDone, I.bBuild, I.bBuildNote, I.bInfo, I.bManualChk, I.bManualLbl, I.bSelHdr, I.bRawHdr }
	for _, r in ipairs(I.bRawRows) do
		I.builder[#I.builder + 1] = r.lab
		I.builder[#I.builder + 1] = r.val
	end

	-- The detail controls are grouped so render can show/hide them wholesale.
	I.detail = {
		I.icon,
		I.name,
		I.id,
		I.typeBadge,
		I.timeBadge,
		I.relBadge,
		build,
		I.favBtn,
		I.copyBtn,
		I.ignoreBtn,
		raw,
		obs,
		note,
	}
	QAT.Aggregator_Inspector_Render(nil)
end

-- ---------------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------------

local function setDetailShown(shown)
	local I = QAT.aggregator.insp
	I.placeholder:SetHidden(shown)
	for _, c in ipairs(I.detail) do
		c:SetHidden(not shown)
	end
	-- Single mode owns the pane: hide the builder chrome and its pooled controls.
	for _, c in ipairs(I.builder or {}) do
		c:SetHidden(true)
	end
	if I.builderPool then
		W.PoolBegin(I.builderPool)
		W.PoolEnd(I.builderPool)
	end
	if I.tabPool then
		W.PoolBegin(I.tabPool)
		W.PoolEnd(I.tabPool)
	end
end

function QAT.Aggregator_Inspector_Render(row)
	local I = QAT.aggregator.insp
	if not I then
		return
	end
	I.row = row
	if not row then
		setDetailShown(false)
		return
	end
	setDetailShown(true)

	I.icon:SetTexture(row.icon)
	I.name:SetText(row.name or ("#" .. row.abilityId))
	I.id:SetText("#" .. row.abilityId)

	local isDebuff = row.effectType == BUFF_EFFECT_TYPE_DEBUFF
	I.typeBadge:SetText(isDebuff and "DEBUFF" or "BUFF")
	I.typeBadge:SetColorRGB(isDebuff and COL_DEBUFF or COL_BUFF)
	I.timeBadge:SetText(row.timed and "TIMED" or "PASSIVE")
	I.timeBadge:SetColorRGB(row.timed and COL_TIMED or COL_PASSIVE)
	I.relBadge:SetText(BUCKET_LABEL[row.bucket] or "?")
	I.relBadge:SetColorRGB(BUCKET_COL[row.bucket] or BUCKET_COL.os)

	I.favBtn:SetText(row.favourited and "Favourited" or "Favourite")
	I.favBtn:SetSelected(row.favourited)

	-- Raw data.
	fillRaw(I.rawRows, row)

	I.obsSeen:SetText(tostring(row.seenCount or 0))
	I.obsStacks:SetText(tostring(row.maxStacks or 0))
	I.obsFirst:SetText(ago(row.firstSeen))
	I.obsLast:SetText(ago(row.lastSeen))

	I.noteText:SetText(MEANING[row.bucket] or "")
end

-- ---------------------------------------------------------------------------
-- Builder render (multi-select) — the Tracker builder pane
-- ---------------------------------------------------------------------------

function QAT.Aggregator_Inspector_RenderBuilder()
	local I = QAT.aggregator.insp
	if not I then
		return
	end
	local a = QAT.aggregator

	-- Builder owns the pane: hide the single-row detail + placeholder, show builder.
	I.placeholder:SetHidden(true)
	for _, c in ipairs(I.detail) do
		c:SetHidden(true)
	end
	for _, c in ipairs(I.builder) do
		c:SetHidden(false)
	end

	-- Resolve the selection (in pick order) to live rows; drop any that vanished.
	local rows = {}
	for _, key in ipairs(a.selected or {}) do
		local r = QAT.capture.store[key]
		if r then
			rows[#rows + 1] = r
		end
	end
	local n = #rows
	local switch = n >= 2

	I.bSub:SetText(n .. " effect" .. (n == 1 and "" or "s") .. " selected")

	-- Build button note + info card copy communicate intent without jargon.
	if n == 0 then
		I.bBuildNote:SetText("select effects to build")
		I.bInfo:SetTitle("Nothing selected yet")
		I.bInfoText:SetText(
			"Tick effects in the list on the left. One becomes a simple tracker; two or more that are never active at the same time become a switch tracker."
		)
	elseif switch and a.builderManual then
		I.bBuildNote:SetText("phases only, from " .. n)
		I.bInfo:SetTitle("Builds phases only")
		I.bInfoText:SetText(
			"One phase per effect plus a fallback, with no transitions — you wire the switching yourself in the editor."
		)
	elseif switch then
		I.bBuildNote:SetText("one switch tracker from " .. n)
		I.bInfo:SetTitle("Builds a switch tracker")
		I.bInfoText:SetText(
			"One aura that shows whichever of these "
				.. n
				.. " effects is active right now, switching as they come and go — like the four vampire stages."
		)
	else
		I.bBuildNote:SetText("a simple tracker")
		I.bInfo:SetTitle("Builds a simple tracker")
		I.bInfoText:SetText(
			"One aura for this single effect. Add another effect that is never active at the same time to turn it into a switch tracker."
		)
	end
	local th = I.bInfoText:GetTextHeight() or 40
	I.bInfo:SetHeight(I.bInfo.contentY + math.max(28, th) + 12)
	I.bBuild:SetMouseEnabled(n > 0)

	-- Flowing section below the fixed header/build/info block.
	local y = (PAD + 122) + I.bInfo:GetHeight() + 14

	-- Manual opt-out (switch trackers only): build phases without the auto-mesh.
	I.bManualChk:SetChecked(a.builderManual)
	if switch then
		I.bManualChk:SetHidden(false)
		I.bManualLbl:SetHidden(false)
		I.bManualChk:ClearAnchors()
		I.bManualChk:SetAnchor(TOPLEFT, I.body, TOPLEFT, PAD, y)
		I.bManualLbl:ClearAnchors()
		I.bManualLbl:SetAnchor(LEFT, I.bManualChk, RIGHT, 8, 0)
		y = y + 30
	else
		I.bManualChk:SetHidden(true)
		I.bManualLbl:SetHidden(true)
	end

	I.bSelHdr:ClearAnchors()
	I.bSelHdr:SetAnchor(TOPLEFT, I.body, TOPLEFT, PAD, y)
	y = y + 22

	W.PoolBegin(I.builderPool)
	if n == 0 then
		local e = W.PoolGet(I.builderPool, "selEmpty", function()
			return W.Label(I.body, "QAT_AggIns_BSelEmpty", "", "$(MEDIUM_FONT)|14|soft-shadow-thin")
		end)
		e:SetHidden(false)
		e:SetColor(0.5, 0.55, 0.62, 1)
		e:SetText("No effects ticked yet.")
		e:ClearAnchors()
		e:SetAnchor(TOPLEFT, I.body, TOPLEFT, PAD, y + 2)
		y = y + 30
	else
		for i, r in ipairs(rows) do
			local key = r.key
			local sr = W.PoolGet(I.builderPool, "sel" .. i, function()
				return makeSelRow(I.body, "QAT_AggIns_BSel" .. i)
			end)
			sr:ClearAnchors()
			sr:SetAnchor(TOPLEFT, I.body, TOPLEFT, PAD, y)
			sr:SetWidth(INNER_W)
			sr:Bind(i, r, {
				onRemove = function()
					QAT.Aggregator_RemoveSelected(key)
				end,
				onUp = (i > 1) and function()
					QAT.Aggregator_MoveSelected(key, -1)
				end or nil,
				onDown = (i < n) and function()
					QAT.Aggregator_MoveSelected(key, 1)
				end or nil,
			})
			y = y + 34 + 4
		end
	end
	W.PoolEnd(I.builderPool)

	-- Raw-data tabs + fields for the active tab (only when something is selected).
	if n == 0 then
		I.bRawHdr:SetHidden(true)
		for _, rr in ipairs(I.bRawRows) do
			rr.lab:SetHidden(true)
			rr.val:SetHidden(true)
		end
		W.PoolBegin(I.tabPool)
		W.PoolEnd(I.tabPool)
		return
	end

	if not (I.activeTab and a.selectedSet[I.activeTab]) then
		I.activeTab = rows[1].key
	end

	y = y + 10
	I.bRawHdr:SetHidden(false)
	I.bRawHdr:ClearAnchors()
	I.bRawHdr:SetAnchor(TOPLEFT, I.body, TOPLEFT, PAD, y)
	y = y + 22

	W.PoolBegin(I.tabPool)
	local tx, ty = PAD, y
	for i, r in ipairs(rows) do
		local key = r.key
		local tab = W.PoolGet(I.tabPool, "tab" .. i, function()
			return makeTab(I.body, "QAT_AggIns_BTab" .. i)
		end)
		tab:Bind(r, key == I.activeTab, function()
			I.activeTab = key
			QAT.Aggregator_Inspector_RenderBuilder()
		end)
		local w = tab:GetWidth()
		if tx > PAD and tx + w > PAD + INNER_W then
			tx, ty = PAD, ty + 28
		end
		tab:ClearAnchors()
		tab:SetAnchor(TOPLEFT, I.body, TOPLEFT, tx, ty)
		tx = tx + w + 6
	end
	W.PoolEnd(I.tabPool)
	y = ty + 32

	local active = QAT.capture.store[I.activeTab]
	if active then
		fillRaw(I.bRawByField, active)
		for _, rr in ipairs(I.bRawRows) do
			rr.lab:SetHidden(false)
			rr.val:SetHidden(false)
			rr.lab:ClearAnchors()
			rr.lab:SetAnchor(TOPLEFT, I.body, TOPLEFT, PAD, y)
			rr.val:ClearAnchors()
			rr.val:SetAnchor(TOPLEFT, I.body, TOPLEFT, PAD + 160, y)
			rr.val:SetAnchor(TOPRIGHT, I.body, TOPLEFT, PAD + INNER_W, y)
			y = y + 22
		end
	end
end
