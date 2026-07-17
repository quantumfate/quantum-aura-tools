-- Effect Aggregator — context / inspector (right pane, always rightmost).
--
-- Shows one captured effect's context: header, a DIRECTION card (who applies this to
-- whom), the raw ESO data, and a plain-English note. When the shown stack is a
-- collapse-by-name merge it also carries a `< idx / N >` navigator: stepping it chooses
-- which stacked ID *leads* the built tracker (its direction/source/target), and a yellow
-- warning chip fires when the merge mixes directions. Driven entirely by
-- QAT.aggregator.contextTarget. In 2-pane mode (single inspect, no builder) it also hosts
-- the Build / Favourite / Copy / Ignore actions so the pane stands alone.

local WM = GetWindowManager()
local W = QAT.widgets

local PAD = 14
local INNER_W = 474 -- INSPECTOR_W (520) minus side padding and the scrollbar gutter
local WARN_COL = { 0.878, 0.686, 0.196 }

local COL_BUFF = { 0.561, 0.816, 0.478 }
local COL_DEBUFF = { 0.878, 0.525, 0.435 }
local COL_TIMED = { 0.541, 0.714, 0.839 }
local COL_PASSIVE = { 0.561, 0.635, 0.698 }
local BUCKET_COL = {
	bs = { 0.851, 0.541, 0.416 },
	sb = { 0.310, 0.690, 0.627 },
	xb = { 0.780, 0.639, 0.400 },
	sg = { 0.463, 0.780, 0.627 },
	gg = { 0.435, 0.604, 0.816 },
	xg = { 0.55, 0.60, 0.68 },
	gs = { 0.435, 0.604, 0.816 },
	os = { 0.55, 0.60, 0.68 },
	ss = { 0.490, 0.557, 0.627 },
	xx = { 0.5, 0.5, 0.5 },
}
local MEANING = {
	bs = "An incoming boss mechanic — cast on you by the boss or the environment. The one you usually want to react to.",
	sb = "One of your own debuffs sitting on the boss. Track it to watch your uptime.",
	xb = "An effect on your target you didn't apply — its own states, or a dummy's self-debuffs.",
	sg = "A buff you apply to your group.",
	gg = "A groupmate buffing the group.",
	xg = "On a groupmate, not applied by you.",
	gs = "A buff applied to you by a group member.",
	os = "Applied to you by an add or the environment (not the boss frame).",
	ss = "Your own standing buff or passive (kit, gear, food, CP).",
	xx = "Unclassified relationship.",
}
local EFFECT_TYPE_NAME = {
	[BUFF_EFFECT_TYPE_BUFF] = "BUFF_EFFECT_TYPE_BUFF",
	[BUFF_EFFECT_TYPE_DEBUFF] = "BUFF_EFFECT_TYPE_DEBUFF",
}
local RAW_FIELDS = {
	"abilityId",
	"effectType",
	"sourceName",
	"targetName",
	"targetUnitTag",
	"castByPlayer",
	"isBuff/debuff",
	"timed",
	"buffSlot",
}

-- Display names for the two ends of the DIRECTION card.
local function endpoints(row)
	local src = (row.castByPlayer or row.sourceType == COMBAT_UNIT_TYPE_PLAYER) and "You"
		or (row.sourceName ~= "" and row.sourceName)
		or "Other"
	local tgt = row.targetTag == "player" and "You" or (row.targetName ~= "" and row.targetName) or "Target"
	return src, tgt
end

-----------------------------------------------------------------------------------
-- Build
-----------------------------------------------------------------------------------

function QAT.Aggregator_Context_Build(pane)
	local C = {}
	QAT.aggregator.ctx = C

	-- Placeholder (nothing selected).
	C.placeholder =
		W.Label(pane, "QAT_AggCtx_PH", "Select an effect to inspect its data.", "$(MEDIUM_FONT)|16|soft-shadow-thin")
	C.placeholder:SetColor(0.42, 0.48, 0.56, 1)
	C.placeholder:SetAnchor(TOP, pane, TOP, 0, 60)
	C.placeholder:SetHorizontalAlignment(TEXT_ALIGN_CENTER)

	local sc = WM:CreateControlFromVirtual("QAT_AggCtx_Scroll", pane, "ZO_ScrollContainer")
	sc:SetAnchor(TOPLEFT, pane, TOPLEFT, 0, 0)
	sc:SetAnchor(BOTTOMRIGHT, pane, BOTTOMRIGHT, 0, 0)
	local body = GetControl(sc, "ScrollChild")
	body:SetResizeToFitDescendents(true)
	body:SetResizeToFitPadding(0, 12)
	C.body = body

	-- Header: icon, name, id, badges, and the merge navigator (right).
	C.icon = W.IconWell(body, "QAT_AggCtx_Ic", 40)
	C.icon:SetAnchor(TOPLEFT, body, TOPLEFT, PAD, PAD)
	C.name = W.Label(body, "QAT_AggCtx_Nm", "", "$(BOLD_FONT)|20|soft-shadow-thin")
	C.name:SetAnchor(TOPLEFT, C.icon, TOPRIGHT, 12, 0)
	C.id = W.Label(body, "QAT_AggCtx_Id", "", "$(MEDIUM_FONT)|15|soft-shadow-thin")
	C.id:SetColor(0.5, 0.58, 0.68, 1)
	C.id:SetAnchor(TOPLEFT, C.icon, TOPRIGHT, 12, 24)

	C.typeBadge = W.Badge(body, "QAT_AggCtx_TB", "", COL_BUFF)
	C.typeBadge:SetAnchor(TOPLEFT, C.icon, BOTTOMLEFT, 0, 10)
	C.timeBadge = W.Badge(body, "QAT_AggCtx_TmB", "", COL_TIMED)
	C.timeBadge:SetAnchor(LEFT, C.typeBadge, RIGHT, 6, 0)

	-- Merge navigator (hidden unless the stack has 2+ IDs). Built right-to-left from the
	-- content's right edge so it never spills under the scrollbar / past the pane.
	C.navNext = W.TextButton(body, "QAT_AggCtx_Next", ">", function()
		QAT.Aggregator_Context_Navigate(1)
	end)
	C.navNext:SetHeight(26)
	C.navNext:SetAnchor(TOPLEFT, body, TOPLEFT, PAD + INNER_W - 26, PAD)
	C.navLabel = W.Label(body, "QAT_AggCtx_NavL", "", "$(MEDIUM_FONT)|14|soft-shadow-thin")
	C.navLabel:SetColor(0.8, 0.85, 0.92, 1)
	C.navLabel:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
	C.navLabel:SetWidth(48)
	C.navLabel:SetAnchor(RIGHT, C.navNext, LEFT, -4, 0)
	C.navPrev = W.TextButton(body, "QAT_AggCtx_Prev", "<", function()
		QAT.Aggregator_Context_Navigate(-1)
	end)
	C.navPrev:SetHeight(26)
	C.navPrev:SetAnchor(RIGHT, C.navLabel, LEFT, -4, 0)
	C.mergeLbl = W.Label(body, "QAT_AggCtx_Merge", "", "$(MEDIUM_FONT)|13|soft-shadow-thin")
	C.mergeLbl:SetColor(0.5, 0.58, 0.68, 1)
	C.mergeLbl:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
	C.mergeLbl:SetAnchor(BOTTOMRIGHT, C.navPrev, TOPRIGHT, 40, -2)

	-- DIRECTION card.
	C.dirCard = W.Card(body, "QAT_AggCtx_Dir", "Direction")
	C.dirCard:SetWidth(INNER_W)
	C.dirBadge = W.Badge(C.dirCard, "QAT_AggCtx_DirB", "", BUCKET_COL.sb)
	C.dirBadge:SetAnchor(TOPRIGHT, C.dirCard, TOPRIGHT, -PAD, 8)
	C.dirSrc = W.Label(C.dirCard, "QAT_AggCtx_DirS", "", "$(BOLD_FONT)|17|soft-shadow-thin")
	C.dirSrc:SetColor(0.85, 0.9, 0.95, 1)
	C.dirSrc:SetAnchor(TOPLEFT, C.dirCard, TOPLEFT, PAD, C.dirCard.contentY + 6)
	C.dirArrow = W.Label(C.dirCard, "QAT_AggCtx_DirA", "→", "$(BOLD_FONT)|20|soft-shadow-thin")
	C.dirArrow:SetColor(0.45, 0.72, 0.66, 1)
	C.dirArrow:SetAnchor(LEFT, C.dirSrc, RIGHT, 12, 0)
	C.dirTgt = W.Label(C.dirCard, "QAT_AggCtx_DirT", "", "$(BOLD_FONT)|17|soft-shadow-thin")
	C.dirTgt:SetColor(0.85, 0.9, 0.95, 1)
	C.dirTgt:SetAnchor(LEFT, C.dirArrow, RIGHT, 12, 0)
	C.dirCard:SetHeight(C.dirCard.contentY + 40)

	-- RAW DATA card.
	C.rawCard = W.Card(body, "QAT_AggCtx_Raw", "Raw data")
	C.rawCard:SetWidth(INNER_W)
	C.rawCard:SetAnchor(TOPLEFT, C.dirCard, BOTTOMLEFT, 0, 12)
	C.rawRows = {}
	local ry = C.rawCard.contentY
	for i, field in ipairs(RAW_FIELDS) do
		local lab = W.Label(C.rawCard, "QAT_AggCtx_RL" .. i, field, "$(MEDIUM_FONT)|14|soft-shadow-thin")
		lab:SetColor(0.5, 0.57, 0.66, 1)
		lab:SetAnchor(TOPLEFT, C.rawCard, TOPLEFT, PAD, ry)
		local val = W.Label(C.rawCard, "QAT_AggCtx_RV" .. i, "", "$(MEDIUM_FONT)|14|soft-shadow-thin")
		val:SetColor(0.82, 0.87, 0.93, 1)
		val:SetAnchor(TOPLEFT, C.rawCard, TOPLEFT, 160, ry)
		val:SetAnchor(TOPRIGHT, C.rawCard, TOPRIGHT, -PAD, ry)
		val:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
		C.rawRows[field] = val
		ry = ry + 22
	end
	C.rawCard:SetHeight(ry + 8)

	-- WHAT THIS MEANS note.
	C.noteCard = W.Card(body, "QAT_AggCtx_Note", "What this means")
	C.noteCard:SetWidth(INNER_W)
	C.noteCard:SetAnchor(TOPLEFT, C.rawCard, BOTTOMLEFT, 0, 12)
	C.noteText = W.Label(C.noteCard, "QAT_AggCtx_NoteT", "", "$(MEDIUM_FONT)|15|soft-shadow-thin")
	C.noteText:SetColor(0.68, 0.75, 0.83, 1)
	C.noteText:SetAnchor(TOPLEFT, C.noteCard, TOPLEFT, PAD, C.noteCard.contentY)
	C.noteText:SetWidth(INNER_W - PAD * 2)
	C.noteText:SetVerticalAlignment(TEXT_ALIGN_TOP)

	-- Actions (2-pane single inspect only): Build + Favourite / Copy / Ignore.
	C.buildBtn = W.TextButton(body, "QAT_AggCtx_Build", "Build Tracker", function()
		if C.row then
			QAT.Aggregator_BuildTracker(C.row)
		end
	end)
	C.buildBtn:SetSelected(true)
	C.buildBtn:SetHeight(32)
	C.buildBtn:SetMinWidth(INNER_W)
	C.buildBtn:SetAnchor(TOPLEFT, C.noteCard, BOTTOMLEFT, 0, 12)

	C.favBtn = W.TextButton(body, "QAT_AggCtx_Fav", "Favourite", function()
		local row = C.row
		if not row then
			return
		end
		if row.favourited then
			QAT.Capture_Unfavourite(row)
		else
			QAT.Capture_Favourite(row)
		end
		QAT.Aggregator_List_Render()
		QAT.Aggregator_Context_Render()
	end)
	C.favBtn:SetHeight(30)
	C.favBtn:SetAnchor(TOPLEFT, C.buildBtn, BOTTOMLEFT, 0, 8)

	C.copyBtn = W.TextButton(body, "QAT_AggCtx_Copy", "Copy id", function()
		if C.row then
			d(string.format("%s #%d — %s", QAT.displayName, C.row.abilityId, C.row.name or ""))
		end
	end)
	C.copyBtn:SetHeight(30)
	C.copyBtn:SetAnchor(LEFT, C.favBtn, RIGHT, 8, 0)

	C.ignoreBtn = W.TextButton(body, "QAT_AggCtx_Ignore", "Ignore", function()
		if C.row then
			QAT.Capture_Ignore(C.row.abilityId)
			QAT.aggregator.contextTarget = nil
			QAT.aggregator.selectedKey = nil
			QAT.Aggregator_List_Render()
			QAT.Aggregator_Context_Render()
		end
	end)
	C.ignoreBtn:SetHeight(30)
	C.ignoreBtn:SetAnchor(LEFT, C.copyBtn, RIGHT, 8, 0)

	-- Warning chip (mixed-direction merge). Anchored last, below the actions.
	C.warnBg = W.Panel(body, "QAT_AggCtx_Warn", { 0.878 * 0.12, 0.686 * 0.12, 0.196 * 0.12, 0.35 }, WARN_COL)
	C.warnLbl = W.Label(C.warnBg, "QAT_AggCtx_WarnL", "", "$(MEDIUM_FONT)|13|soft-shadow-thin")
	C.warnLbl:SetColor(WARN_COL[1], WARN_COL[2], WARN_COL[3], 1)
	C.warnLbl:SetAnchor(TOPLEFT, C.warnBg, TOPLEFT, 8, 6)
	C.warnLbl:SetAnchor(TOPRIGHT, C.warnBg, TOPRIGHT, -8, 6)
	C.warnLbl:SetVerticalAlignment(TEXT_ALIGN_TOP)

	-- Grouped for wholesale show/hide.
	C.detail = {
		C.icon,
		C.name,
		C.id,
		C.typeBadge,
		C.timeBadge,
		C.dirCard,
		C.rawCard,
		C.noteCard,
	}
	C.actions = { C.buildBtn, C.favBtn, C.copyBtn, C.ignoreBtn }
	C.nav = { C.navPrev, C.navLabel, C.navNext, C.mergeLbl }

	QAT.Aggregator_Context_Render()
end

-----------------------------------------------------------------------------------
-- Navigation — steps the leading card and remembers the choice for Build
-----------------------------------------------------------------------------------

function QAT.Aggregator_Context_Navigate(dir)
	local a = QAT.aggregator
	local ct = a.contextTarget
	if not ct or #ct.keys <= 1 then
		return
	end
	local nkeys = #ct.keys
	ct.index = ((ct.index or 1) - 1 + dir + nkeys) % nkeys + 1
	if ct.leadKey then
		a.leadIndex[ct.leadKey] = ct.index
	end
	QAT.Aggregator_Context_Render()
	-- The builder's phase-item subtitle / lead follow the chosen card.
	if (a.selecting or a.singleMerge) and QAT.Aggregator_Inspector_RenderBuilder then
		QAT.Aggregator_Inspector_RenderBuilder()
	end
end

-----------------------------------------------------------------------------------
-- Render
-----------------------------------------------------------------------------------

local function showAll(list, shown)
	for _, c in ipairs(list) do
		c:SetHidden(not shown)
	end
end

function QAT.Aggregator_Context_Render()
	local C = QAT.aggregator.ctx
	if not C then
		return
	end
	local a = QAT.aggregator
	local ct = a.contextTarget

	-- Resolve the leading row of the stack.
	local rows = {}
	if ct then
		for _, k in ipairs(ct.keys) do
			local r = QAT.capture.store[k]
			if r then
				rows[#rows + 1] = r
			end
		end
	end
	if #rows == 0 then
		C.placeholder:SetHidden(false)
		showAll(C.detail, false)
		showAll(C.actions, false)
		showAll(C.nav, false)
		C.warnBg:SetHidden(true)
		C.row = nil
		return
	end
	C.placeholder:SetHidden(true)
	showAll(C.detail, true)

	local idx = math.max(1, math.min(ct.index or 1, #rows))
	local row = rows[idx]
	C.row = row

	-- Merge navigator.
	local merged = #rows > 1
	showAll(C.nav, merged)
	if merged then
		C.navLabel:SetText(idx .. " / " .. #rows)
		C.mergeLbl:SetText(#rows .. " IDs merged")
	end

	C.icon:SetTexture(row.icon)
	C.name:SetText(row.name or ("#" .. row.abilityId))
	C.id:SetText("#" .. row.abilityId)

	local isDebuff = row.effectType == BUFF_EFFECT_TYPE_DEBUFF
	C.typeBadge:SetText(isDebuff and "DEBUFF" or "BUFF")
	C.typeBadge:SetColorRGB(isDebuff and COL_DEBUFF or COL_BUFF)
	C.timeBadge:SetText(row.timed and "TIMED" or "PASSIVE")
	C.timeBadge:SetColorRGB(row.timed and COL_TIMED or COL_PASSIVE)

	-- DIRECTION card.
	local src, tgt = endpoints(row)
	C.dirSrc:SetText(src)
	C.dirTgt:SetText(tgt)
	C.dirBadge:SetText(QAT.Aggregator_BucketDirection(row.bucket))
	C.dirBadge:SetColorRGB(BUCKET_COL[row.bucket] or BUCKET_COL.xx)

	-- Position the DIRECTION card below whichever header element sits lowest (the badges
	-- or, when merged, the merge label / nav).
	C.dirCard:ClearAnchors()
	C.dirCard:SetAnchor(TOPLEFT, C.typeBadge, BOTTOMLEFT, 0, 14)

	-- RAW DATA.
	local rr = C.rawRows
	rr["abilityId"]:SetText(tostring(row.abilityId))
	rr["effectType"]:SetText(EFFECT_TYPE_NAME[row.effectType] or "—")
	rr["sourceName"]:SetText((row.sourceName and row.sourceName ~= "") and row.sourceName or "—")
	rr["targetName"]:SetText((row.targetName and row.targetName ~= "") and row.targetName or "—")
	rr["targetUnitTag"]:SetText('"' .. (row.targetTag or "?") .. '"')
	rr["castByPlayer"]:SetText(row.castByPlayer == nil and "—" or tostring(row.castByPlayer))
	rr["isBuff/debuff"]:SetText(isDebuff and "debuff" or "buff")
	rr["timed"]:SetText(row.timed and "true (has duration)" or "false (passive)")
	rr["buffSlot"]:SetText(row.buffSlot and tostring(row.buffSlot) or "—")

	C.noteText:SetText(MEANING[row.bucket] or "")
	local nh = C.noteText:GetTextHeight() or 20
	C.noteCard:SetHeight(C.noteCard.contentY + math.max(20, nh) + 12)

	-- Actions only when NOT building (the builder pane owns Build then).
	local building = a.selecting or a.singleMerge
	showAll(C.actions, not building)
	C.favBtn:SetText(row.favourited and "Favourited" or "Favourite")
	C.favBtn:SetSelected(row.favourited)

	-- Warning chip: a mixed-direction merge. Anchor below the note (building) or below
	-- the actions (2-pane inspect).
	local mixed = merged and QAT.Aggregator_StackDirection(rows) == nil
	C.warnBg:SetHidden(not mixed)
	if mixed then
		C.warnLbl:SetText(
			"This row merges "
				.. #rows
				.. " IDs that don't all share the same direction. The tracker wires the direction, source & target of the front card shown above — step through to choose which one leads."
		)
		local wt = C.warnLbl:GetTextHeight() or 30
		C.warnBg:SetHeight(wt + 12)
		C.warnBg:ClearAnchors()
		C.warnBg:SetWidth(INNER_W)
		local anchorTo = building and C.noteCard or C.favBtn
		C.warnBg:SetAnchor(TOPLEFT, anchorTo, BOTTOMLEFT, 0, 12)
	end
end
