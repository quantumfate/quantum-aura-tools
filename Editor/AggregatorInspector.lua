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
	gs = { 0.435, 0.604, 0.816 },
	os = { 0.55, 0.60, 0.68 },
	ss = { 0.490, 0.557, 0.627 },
}
local BUCKET_LABEL =
	{ bs = "BOSS→SELF", sb = "SELF→BOSS", gs = "GROUP→SELF", os = "OTHER→SELF", ss = "SELF→SELF" }
local MEANING = {
	bs = "An incoming boss mechanic — cast on you by the boss (or the environment). The one you usually want to track and react to.",
	sb = "One of your own debuffs sitting on the boss. Track it to watch your uptime.",
	gs = "A buff applied to you by a group member.",
	os = "Applied to you by an add or the environment (not the boss frame).",
	ss = "Your own standing buff or passive (your kit, gear, food, CP).",
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
	local build = W.TextButton(body, "QAT_AggIns_Build", "➜ Build Tracker", function()
		QAT.Aggregator_BuildTracker(I.row)
	end)
	build:SetHeight(32)
	build:SetSelected(true) -- primary-blue
	build:SetAnchor(TOPLEFT, I.typeBadge, BOTTOMLEFT, 0, 16)
	build:SetMinWidth(INNER_W)
	I.buildBtn = build

	I.pinBtn = W.TextButton(body, "QAT_AggIns_Pin", "★ Pin", function()
		if not I.row then
			return
		end
		if I.row.pinned then
			QAT.Capture_Unpin(I.row)
		else
			QAT.Capture_Pin(I.row)
		end
		QAT.Aggregator_Inspector_Render(I.row)
		QAT.Aggregator_List_Render()
	end)
	I.pinBtn:SetHeight(28)
	I.pinBtn:SetAnchor(TOPLEFT, build, BOTTOMLEFT, 0, 8)

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
	I.copyBtn:SetAnchor(LEFT, I.pinBtn, RIGHT, 8, 0)

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
	raw:SetAnchor(TOPLEFT, I.pinBtn, BOTTOMLEFT, 0, 16)
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

	-- The detail controls are grouped so render can show/hide them wholesale.
	I.detail = {
		I.icon,
		I.name,
		I.id,
		I.typeBadge,
		I.timeBadge,
		I.relBadge,
		build,
		I.pinBtn,
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

	I.pinBtn:SetText(row.pinned and "★ Pinned" or "★ Pin")
	I.pinBtn:SetSelected(row.pinned)

	-- Raw data.
	local rr = I.rawRows
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

	I.obsSeen:SetText(tostring(row.seenCount or 0))
	I.obsStacks:SetText(tostring(row.maxStacks or 0))
	I.obsFirst:SetText(ago(row.firstSeen))
	I.obsLast:SetText(ago(row.lastSeen))

	I.noteText:SetText(MEANING[row.bucket] or "")
end
