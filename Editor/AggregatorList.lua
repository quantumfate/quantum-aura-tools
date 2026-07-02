-- Effect Aggregator — grouped list (left pane).
--
-- Renders the capture store into collapsible relationship sections of two-line rows.
-- Rows are pooled by their stable row.key so the same control is reused across
-- renders (cheap, and selection/scroll survive). Live refresh is a full re-render;
-- the window's change callback skips it while the view is frozen, so reading a busy
-- fight is stable (Freeze view is the intended escape hatch).

local WM = GetWindowManager()
local W = QAT.widgets

local TOOLBAR_H = 30
local HEADER_H = 26
local ROW_H = 46

-- Section order + copy. Boss→Self leads (the money bucket); Self→Self trails (noise).
local BUCKET_ORDER = { "bs", "sb", "gs", "os", "ss" }
local BUCKET_META = {
	bs = { label = "Boss → Self", hint = "incoming boss mechanics", color = { 0.851, 0.541, 0.416 } },
	sb = { label = "Self → Boss", hint = "your debuffs on the boss", color = { 0.310, 0.690, 0.627 } },
	gs = { label = "Group → Self", hint = "buffs from your group", color = { 0.435, 0.604, 0.816 } },
	os = { label = "Other → Self", hint = "from adds / environment", color = { 0.55, 0.60, 0.68 } },
	ss = { label = "Self → Self", hint = "your passives", color = { 0.490, 0.557, 0.627 } },
}

local COL_BUFF = { 0.561, 0.816, 0.478 }
local COL_DEBUFF = { 0.878, 0.525, 0.435 }
local COL_TIMED = { 0.541, 0.714, 0.839 }
local COL_PASSIVE = { 0.561, 0.635, 0.698 }
local COL_PINNED = { 0.851, 0.722, 0.290 }

local SORTS = {
	lastSeen = function(a, b)
		return (a.lastSeen or 0) > (b.lastSeen or 0)
	end,
	seen = function(a, b)
		return (a.seenCount or 0) > (b.seenCount or 0)
	end,
	name = function(a, b)
		return (a.name or "") < (b.name or "")
	end,
}

local headerPool, rowPool
local rowW = 360

-- "2s ago" / "5m ago" from a timestamp.
local function ago(ts)
	if not ts then
		return ""
	end
	local secs = GetTimeStamp() - ts
	if secs < 2 then
		return "just now"
	end
	if secs < 60 then
		return secs .. "s ago"
	end
	if secs < 3600 then
		return math.floor(secs / 60) .. "m ago"
	end
	return math.floor(secs / 3600) .. "h ago"
end

-- ---------------------------------------------------------------------------
-- Row control (built once per key, then re-bound)
-- ---------------------------------------------------------------------------

local function makeRow(parent, name)
	local c = W.Clickable(parent, name, { 0.039, 0.078, 0.11, 1 })
	c.bg:SetEdgeColor(0.11, 0.165, 0.208, 1)
	c.bg:SetEdgeTexture("", 1, 1, 1)
	c:SetHeight(ROW_H)

	-- Left selection accent (shown when selected).
	local accent = W.Panel(c, name .. "_Acc", { 0.475, 0.69, 0.925, 1 })
	accent:SetDimensions(3, ROW_H)
	accent:SetAnchor(TOPLEFT, c, TOPLEFT, 0, 0)
	c.accent = accent

	local icon = W.IconWell(c, name .. "_Icon", 34)
	icon:SetAnchor(TOPLEFT, c, TOPLEFT, 8, 6)
	c.icon = icon

	local nameL = W.Label(c, name .. "_Name", "", "$(MEDIUM_FONT)|17|soft-shadow-thin")
	nameL:SetAnchor(TOPLEFT, icon, TOPRIGHT, 10, 0)
	c.nameL = nameL

	local pin = W.Label(c, name .. "_Pin", "", "$(MEDIUM_FONT)|15|soft-shadow-thin")
	pin:SetColor(COL_PINNED[1], COL_PINNED[2], COL_PINNED[3], 1)
	pin:SetAnchor(LEFT, nameL, RIGHT, 6, 0)
	c.pin = pin

	local seenL = W.Label(c, name .. "_Seen", "", "$(MEDIUM_FONT)|14|soft-shadow-thin")
	seenL:SetColor(0.6, 0.68, 0.78, 1)
	seenL:SetAnchor(TOPRIGHT, c, TOPRIGHT, -10, 6)
	c.seenL = seenL

	local idL = W.Label(c, name .. "_Id", "", "$(MEDIUM_FONT)|14|soft-shadow-thin")
	idL:SetColor(0.5, 0.58, 0.68, 1)
	idL:SetAnchor(TOPLEFT, icon, TOPRIGHT, 10, 22)
	c.idL = idL

	local effBadge = W.Badge(c, name .. "_Eff", "", COL_BUFF)
	effBadge:SetAnchor(LEFT, idL, RIGHT, 8, 0)
	c.effBadge = effBadge

	local timeBadge = W.Badge(c, name .. "_Time", "", COL_TIMED)
	timeBadge:SetAnchor(LEFT, effBadge, RIGHT, 5, 0)
	c.timeBadge = timeBadge

	local stacksL = W.Label(c, name .. "_Stacks", "", "$(MEDIUM_FONT)|14|soft-shadow-thin")
	stacksL:SetColor(0.7, 0.75, 0.82, 1)
	stacksL:SetAnchor(LEFT, timeBadge, RIGHT, 6, 0)
	c.stacksL = stacksL

	local lastL = W.Label(c, name .. "_Last", "", "$(MEDIUM_FONT)|14|soft-shadow-thin")
	lastL:SetColor(0.45, 0.52, 0.6, 1)
	lastL:SetAnchor(BOTTOMRIGHT, c, BOTTOMRIGHT, -10, -6)
	c.lastL = lastL

	c:SetHandler("OnMouseEnter", function(self)
		if QAT.aggregator.selectedKey ~= self.rowKey then
			self.bg:SetCenterColor(0.06, 0.11, 0.15, 1)
		end
	end)
	c:SetHandler("OnMouseExit", function(self)
		if QAT.aggregator.selectedKey ~= self.rowKey then
			self.bg:SetCenterColor(0.039, 0.078, 0.11, 1)
		end
	end)
	c:SetHandler("OnMouseUp", function(self, button, upInside)
		if upInside and button == MOUSE_BUTTON_INDEX_LEFT then
			QAT.aggregator.selectedKey = self.rowKey
			QAT.Aggregator_List_Render()
			if QAT.Aggregator_Inspector_Render then
				QAT.Aggregator_Inspector_Render(QAT.aggregator.selectedRow)
			end
		end
	end)
	return c
end

local function bindRow(c, row, y)
	c.rowKey = row.key
	c:SetWidth(rowW)
	c:ClearAnchors()
	c:SetAnchor(TOPLEFT, QAT.aggregator.listContent, TOPLEFT, 0, y)

	c.icon:SetTexture(row.icon)
	c.nameL:SetText(row.name or ("#" .. row.abilityId))
	c.pin:SetText(row.pinned and "★" or "")
	c.seenL:SetText("seen " .. (row.seenCount or 0))
	c.idL:SetText("#" .. row.abilityId)

	if row.effectType == BUFF_EFFECT_TYPE_DEBUFF then
		c.effBadge:SetText("DEBUFF")
		c.effBadge:SetColorRGB(COL_DEBUFF)
	else
		c.effBadge:SetText("BUFF")
		c.effBadge:SetColorRGB(COL_BUFF)
	end
	if row.timed then
		c.timeBadge:SetText("timed")
		c.timeBadge:SetColorRGB(COL_TIMED)
	else
		c.timeBadge:SetText("passive")
		c.timeBadge:SetColorRGB(COL_PASSIVE)
	end
	c.stacksL:SetText((row.maxStacks or 0) > 0 and ("×" .. row.maxStacks) or "")
	c.lastL:SetText(ago(row.lastSeen))

	local selected = (QAT.aggregator.selectedKey == row.key)
	c.accent:SetHidden(not selected)
	c.bg:SetCenterColor(selected and 0.12 or 0.039, selected and 0.20 or 0.078, selected and 0.30 or 0.11, 1)
	if selected then
		QAT.aggregator.selectedRow = row
	end
end

-- ---------------------------------------------------------------------------
-- Section header (collapsible)
-- ---------------------------------------------------------------------------

local function makeHeader(parent, name)
	local c = W.Clickable(parent, name, { 0, 0, 0, 0 })
	c:SetHeight(HEADER_H)

	local arrow = W.Label(c, name .. "_Arw", "", "$(MEDIUM_FONT)|15|soft-shadow-thin")
	arrow:SetColor(0.5, 0.58, 0.68, 1)
	arrow:SetAnchor(LEFT, c, LEFT, 2, 0)
	c.arrow = arrow

	local dot = W.Panel(c, name .. "_Dot", { 1, 1, 1, 1 })
	dot:SetDimensions(8, 8)
	dot:SetAnchor(LEFT, arrow, RIGHT, 6, 0)
	c.dot = dot

	local label = W.Label(c, name .. "_L", "", "$(BOLD_FONT)|15|soft-shadow-thin")
	label:SetColor(0.72, 0.79, 0.88, 1)
	label:SetAnchor(LEFT, dot, RIGHT, 8, 0)
	c.label = label

	local count = W.Label(c, name .. "_C", "", "$(MEDIUM_FONT)|14|soft-shadow-thin")
	count:SetColor(0.5, 0.58, 0.68, 1)
	count:SetAnchor(LEFT, label, RIGHT, 8, 0)
	c.count = count

	local hint = W.Label(c, name .. "_H", "", "$(MEDIUM_FONT)|13|soft-shadow-thin")
	hint:SetColor(0.42, 0.48, 0.56, 1)
	hint:SetAnchor(RIGHT, c, RIGHT, -10, 0)
	c.hint = hint

	c:SetHandler("OnMouseUp", function(self, button, upInside)
		if upInside and button == MOUSE_BUTTON_INDEX_LEFT then
			QAT.aggregator.collapsed[self.bucket] = not QAT.aggregator.collapsed[self.bucket]
			QAT.Aggregator_List_Render()
		end
	end)
	return c
end

local function bindHeader(c, bucket, n, y)
	local meta = BUCKET_META[bucket]
	local collapsed = QAT.aggregator.collapsed[bucket]
	c.bucket = bucket
	c:SetWidth(rowW)
	c:ClearAnchors()
	c:SetAnchor(TOPLEFT, QAT.aggregator.listContent, TOPLEFT, 0, y)
	c.arrow:SetText(collapsed and "+" or "–")
	c.dot:SetCenterColor(meta.color[1], meta.color[2], meta.color[3], 1)
	c.label:SetText(meta.label)
	c.count:SetText("(" .. n .. ")")
	c.hint:SetText(meta.hint)
end

-- ---------------------------------------------------------------------------
-- Build / render
-- ---------------------------------------------------------------------------

function QAT.Aggregator_List_Build(pane)
	QAT.aggregator.collapsed = QAT.aggregator.collapsed or { ss = true }
	headerPool = W.NewPool()
	rowPool = W.NewPool()

	-- Toolbar: visible count + hidden-passives note + sort segment.
	local tb = WM:CreateControl("QAT_AggList_Toolbar", pane, CT_CONTROL)
	tb:SetAnchor(TOPLEFT, pane, TOPLEFT, 10, 4)
	tb:SetAnchor(TOPRIGHT, pane, TOPRIGHT, -10, 4)
	tb:SetHeight(TOOLBAR_H)
	QAT.aggregator.listToolbar = tb

	local count = W.Label(tb, "QAT_AggList_Count", "", "$(MEDIUM_FONT)|14|soft-shadow-thin")
	count:SetColor(0.55, 0.62, 0.72, 1)
	count:SetAnchor(LEFT, tb, LEFT, 0, 0)
	QAT.aggregator.listCountLabel = count

	-- Sort segment (right).
	local sortOpts = { { v = "lastSeen", l = "Last seen" }, { v = "seen", l = "Seen×" }, { v = "name", l = "Name" } }
	local prev
	QAT.aggregator.sortButtons = {}
	for _, o in ipairs(sortOpts) do
		local b = W.TextButton(tb, "QAT_AggList_Sort_" .. o.v, o.l, function()
			QAT.aggregator.filter.sort = o.v
			for v, btn in pairs(QAT.aggregator.sortButtons) do
				btn:SetSelected(v == o.v)
			end
			QAT.Aggregator_List_Render()
		end)
		b:SetHeight(24)
		if prev then
			b:SetAnchor(LEFT, prev, RIGHT, -1, 0)
		else
			b:SetAnchor(LEFT, count, RIGHT, 20, 0)
		end
		b:SetSelected(o.v == QAT.aggregator.filter.sort)
		QAT.aggregator.sortButtons[o.v] = b
		prev = b
	end

	-- Scroll viewport below the toolbar.
	local sc = WM:CreateControlFromVirtual("QAT_AggList_Scroll", pane, "ZO_ScrollContainer")
	sc:SetAnchor(TOPLEFT, pane, TOPLEFT, 0, TOOLBAR_H + 6)
	sc:SetAnchor(BOTTOMRIGHT, pane, BOTTOMRIGHT, 0, 0)
	local content = GetControl(sc, "ScrollChild")
	content:SetResizeToFitDescendents(true)
	content:SetResizeToFitPadding(0, 8)
	QAT.aggregator.listScroll = sc
	QAT.aggregator.listContent = content
end

function QAT.Aggregator_List_Relayout()
	if QAT.aggregator.listScroll then
		rowW = math.max(320, QAT.aggregator.listScroll:GetWidth() - 16)
		QAT.Aggregator_List_Render()
	end
end

function QAT.Aggregator_List_Render()
	local a = QAT.aggregator
	if not a.listContent then
		return
	end
	local fq = a.filter

	-- Group passing rows by bucket.
	local groups, shown, hiddenPassive = {}, 0, 0
	for _, row in ipairs(QAT.capture.list) do
		if QAT.Aggregator_RowPasses(row, fq) then
			groups[row.bucket] = groups[row.bucket] or {}
			table.insert(groups[row.bucket], row)
			shown = shown + 1
		elseif row.bucket == "ss" then
			hiddenPassive = hiddenPassive + 1
		end
	end

	local cmp = SORTS[fq.sort] or SORTS.lastSeen
	for _, g in pairs(groups) do
		table.sort(g, cmp)
	end

	W.PoolBegin(headerPool)
	W.PoolBegin(rowPool)
	local y = 0
	for _, bucket in ipairs(BUCKET_ORDER) do
		local g = groups[bucket]
		if g and #g > 0 then
			local hc = W.PoolGet(headerPool, "hdr_" .. bucket, function()
				return makeHeader(a.listContent, "QAT_AggHdr_" .. bucket)
			end)
			bindHeader(hc, bucket, #g, y)
			y = y + HEADER_H + 2
			if not a.collapsed[bucket] then
				for _, row in ipairs(g) do
					local rc = W.PoolGet(rowPool, row.key, function()
						return makeRow(a.listContent, "QAT_AggRow_" .. NonContiguousCount(rowPool.cache))
					end)
					bindRow(rc, row, y)
					y = y + ROW_H + 2
				end
			end
			y = y + 8 -- gap between sections
		end
	end
	W.PoolEnd(headerPool)
	W.PoolEnd(rowPool)
	a.listContent:SetHeight(y)

	-- Toolbar count.
	local text = shown .. " effect" .. (shown == 1 and "" or "s")
	if hiddenPassive > 0 and not fq.revealPassives and fq.relationship == "all" then
		text = text .. "  ·  " .. hiddenPassive .. " passive rows hidden"
	end
	if a.listCountLabel then
		a.listCountLabel:SetText(text)
	end
end
