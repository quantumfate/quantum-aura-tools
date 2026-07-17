-- Effect Aggregator — grouped list (left pane).
--
-- Renders the capture store into collapsible relationship sections of two-line rows.
-- The catch can hold well over a thousand rows, so the list is virtualized: a render
-- builds a layout-only draw plan for every item, but only the slice inside the scroll
-- viewport is bound to controls. Pooled controls are keyed by slot index, so ~one
-- screenful of controls is recycled as the user scrolls — the per-frame draw cost stays
-- flat regardless of catch size. Live refresh rebuilds the plan; the window's change
-- callback skips it while the view is frozen (Freeze view is the intended escape hatch).

local WM = GetWindowManager()
local W = QAT.widgets

local TOOLBAR_H = 30
local HEADER_H = 26
local ROW_H = 46

-- Section order + copy. Boss→Self leads (the money bucket); Self→Self trails (noise).
local BUCKET_ORDER = { "bs", "sb", "xb", "sg", "gg", "xg", "gs", "os", "ss", "xx" }
local BUCKET_META = {
	bs = { label = "Boss → Self", hint = "incoming boss mechanics", color = { 0.851, 0.541, 0.416 } },
	sb = { label = "Self → Boss", hint = "your debuffs on the boss", color = { 0.310, 0.690, 0.627 } },
	xb = {
		label = "Other → Boss",
		hint = "on the target, not by you (its own states / dummy debuffs)",
		color = { 0.780, 0.639, 0.400 },
	},
	sg = { label = "Self → Group", hint = "auras / buffs you apply to your group", color = { 0.463, 0.780, 0.627 } },
	gg = { label = "Group → Group", hint = "a groupmate buffing the group", color = { 0.435, 0.604, 0.816 } },
	xg = { label = "Other → Group", hint = "on a groupmate, not by you", color = { 0.55, 0.60, 0.68 } },
	gs = { label = "Group → Self", hint = "buffs from your group", color = { 0.435, 0.604, 0.816 } },
	os = { label = "Other → Self", hint = "from adds / environment", color = { 0.55, 0.60, 0.68 } },
	ss = { label = "Self → Self", hint = "your passives", color = { 0.490, 0.557, 0.627 } },
	xx = { label = "Other", hint = "unclassified", color = { 0.5, 0.5, 0.5 } },
}

local COL_BUFF = { 0.561, 0.816, 0.478 }
local COL_DEBUFF = { 0.878, 0.525, 0.435 }
local COL_TIMED = { 0.541, 0.714, 0.839 }
local COL_PASSIVE = { 0.561, 0.635, 0.698 }
local COL_FAV = { 0.921, 0.784, 0.353 } -- gold favourite star
local STAR_TEX = "EsoUI/Art/Collections/Favorite_StarOnly.dds"
local SELECT_INSET = 26 -- left space reserved for the row checkbox in select mode

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
local onScrollUpdate -- forward decl (Build wires it as the scroll OnUpdate handler)

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

	-- Checkbox (only shown in multi-select mode): a bordered box with a filled inner
	-- square when ticked (font-proof — a glyph check boxes out). The whole row toggles
	-- it, so this is a passive visual.
	local check = W.Panel(c, name .. "_Chk", { 0.09, 0.13, 0.18, 1 }, { 0.30, 0.42, 0.58, 1 })
	check:SetDimensions(18, 18)
	check:SetAnchor(LEFT, c, LEFT, 8, 0)
	local checkMark = W.Panel(check, name .. "_ChkM", { 0.475, 0.69, 0.925, 1 })
	checkMark:SetDimensions(10, 10)
	checkMark:SetAnchor(CENTER, check, CENTER, 0, 0)
	c.check, c.checkMark = check, checkMark

	local icon = W.IconWell(c, name .. "_Icon", 34)
	icon:SetAnchor(TOPLEFT, c, TOPLEFT, 8, 6)
	c.icon = icon

	local nameL = W.Label(c, name .. "_Name", "", "$(MEDIUM_FONT)|17|soft-shadow-thin")
	nameL:SetAnchor(TOPLEFT, icon, TOPRIGHT, 10, 0)
	c.nameL = nameL

	-- Merge-count chip (collapse-by-name only): "+N" hidden IDs folded into this row.
	local mergeBadge = W.Badge(c, name .. "_Merge", "", { 0.45, 0.55, 0.72 })
	mergeBadge:SetAnchor(LEFT, nameL, RIGHT, 8, 0)
	mergeBadge:SetHidden(true)
	c.mergeBadge = mergeBadge

	-- Gold favourite star (real texture; a glyph star boxes out in the default font).
	local star = WM:CreateControl(name .. "_Star", c, CT_TEXTURE)
	star:SetTexture(STAR_TEX)
	star:SetColor(COL_FAV[1], COL_FAV[2], COL_FAV[3], 1)
	star:SetDimensions(14, 14)
	star:SetAnchor(LEFT, mergeBadge, RIGHT, 8, 0)
	c.star = star

	-- Scribed source, shown on the right (like a "from <source>" column): the grimoire's
	-- icon plus a "from <grimoire>" label, for effects that are a scribable grimoire's
	-- own cast id. Sits left of the seen/ago column.
	local scribe = W.IconWell(c, name .. "_Scr", 32)
	scribe:SetAnchor(RIGHT, c, RIGHT, -74, 0)
	scribe:SetHidden(true)
	c.scribe = scribe
	local scribeL = W.Label(c, name .. "_ScrL", "", "$(MEDIUM_FONT)|14|soft-shadow-thin")
	scribeL:SetColor(0.55, 0.62, 0.74, 1)
	scribeL:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
	scribeL:SetAnchor(RIGHT, scribe, LEFT, -8, 0)
	scribeL:SetHidden(true)
	c.scribeL = scribeL

	local seenL = W.Label(c, name .. "_Seen", "", "$(MEDIUM_FONT)|15|soft-shadow-thin")
	seenL:SetColor(0.6, 0.68, 0.78, 1)
	seenL:SetAnchor(TOPRIGHT, c, TOPRIGHT, -10, 6)
	c.seenL = seenL

	local idL = W.Label(c, name .. "_Id", "", "$(MEDIUM_FONT)|15|soft-shadow-thin")
	idL:SetColor(0.5, 0.58, 0.68, 1)
	idL:SetAnchor(TOPLEFT, icon, TOPRIGHT, 10, 22)
	c.idL = idL

	local effBadge = W.Badge(c, name .. "_Eff", "", COL_BUFF)
	effBadge:SetAnchor(LEFT, idL, RIGHT, 8, 0)
	c.effBadge = effBadge

	local timeBadge = W.Badge(c, name .. "_Time", "", COL_TIMED)
	timeBadge:SetAnchor(LEFT, effBadge, RIGHT, 5, 0)
	c.timeBadge = timeBadge

	local stacksL = W.Label(c, name .. "_Stacks", "", "$(MEDIUM_FONT)|15|soft-shadow-thin")
	stacksL:SetColor(0.7, 0.75, 0.82, 1)
	stacksL:SetAnchor(LEFT, timeBadge, RIGHT, 6, 0)
	c.stacksL = stacksL

	-- Direction chip: who applies this to whom (You → Boss, mixed dir for a mixed merge).
	local dirBadge = W.Badge(c, name .. "_Dir", "", { 0.45, 0.55, 0.72 })
	dirBadge:SetAnchor(LEFT, stacksL, RIGHT, 8, 0)
	c.dirBadge = dirBadge

	local lastL = W.Label(c, name .. "_Last", "", "$(MEDIUM_FONT)|15|soft-shadow-thin")
	lastL:SetColor(0.45, 0.52, 0.6, 1)
	lastL:SetAnchor(BOTTOMRIGHT, c, BOTTOMRIGHT, -10, -6)
	c.lastL = lastL

	c:SetHandler("OnMouseEnter", function(self)
		if not self.active then
			self.bg:SetCenterColor(0.06, 0.11, 0.15, 1)
		end
	end)
	c:SetHandler("OnMouseExit", function(self)
		if not self.active then
			self.bg:SetCenterColor(0.039, 0.078, 0.11, 1)
		end
	end)
	c:SetHandler("OnMouseUp", function(self, button, upInside)
		if not (upInside and button == MOUSE_BUTTON_INDEX_LEFT) then
			return
		end
		if QAT.aggregator.selecting then
			if self.collapseKeys then
				QAT.Aggregator_ToggleSelectedCollapsed(self.collapseKeys)
			else
				QAT.Aggregator_ToggleSelected(self.rowKey)
			end
		else
			-- Mode A: a plain row → single inspect; a collapsed row (2+ IDs) → a
			-- one-phase merge build. Aggregator_SelectRow owns the layout + panes.
			local rowKey = (self.collapseKeys and self.collapseKeys[1]) or self.rowKey
			local row = QAT.capture.store[rowKey]
			if row then
				QAT.Aggregator_SelectRow(row, self.collapseKeys or { rowKey })
			end
		end
	end)
	return c
end

local function bindRow(c, row, y, collapseKeys, collapseIds)
	local a = QAT.aggregator
	local selecting = a.selecting
	local nCollapsed = collapseKeys and #collapseKeys or 0
	local collapsed = nCollapsed > 1
	c.rowKey = row.key
	c.collapseKeys = collapsed and collapseKeys or nil
	c.collapseIds = collapsed and collapseIds or nil
	c:SetWidth(rowW)
	c:ClearAnchors()
	c:SetAnchor(TOPLEFT, a.listContent, TOPLEFT, 0, y)

	-- Reserve room for the checkbox and shift the icon (everything else hangs off it).
	local inset = selecting and SELECT_INSET or 0
	c.check:SetHidden(not selecting)
	c.icon:ClearAnchors()
	c.icon:SetAnchor(TOPLEFT, c, TOPLEFT, 8 + inset, 6)

	c.icon:SetTexture(row.icon)
	c.nameL:SetText(row.name or ("#" .. row.abilityId))
	c.star:SetHidden(not row.favourited)
	-- Scribed source column: "from <grimoire>" + the grimoire icon, when the effect is
	-- a scribable grimoire's own cast id.
	local scribedName = QAT.Aggregator_RowScribedFrom and QAT.Aggregator_RowScribedFrom(row)
	local scrIcon = QAT.Aggregator_RowScribedIcon and QAT.Aggregator_RowScribedIcon(row)
	if scribedName and (not scrIcon or scrIcon == "") then
		scrIcon = row.icon -- grimoire icon unavailable; use the ability icon
	end
	local showScribe = scribedName ~= nil
	c.scribe:SetHidden(not showScribe)
	c.scribeL:SetHidden(not showScribe)
	if showScribe then
		c.scribe:SetTexture(scrIcon or row.icon)
		c.scribeL:SetText("from  " .. scribedName)
	end
	c.seenL:SetText("seen " .. (row.seenCount or 0))
	c.idL:SetText("#" .. row.abilityId)

	-- Merge-count chip: "+N" IDs folded under this collapsed row.
	if collapsed then
		c.mergeBadge:SetText("+" .. (nCollapsed - 1))
		c.mergeBadge:SetHidden(false)
	else
		c.mergeBadge:SetText("")
		c.mergeBadge:SetHidden(true)
	end

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

	-- Direction chip. For a collapsed row that mixes directions show "mixed dir" (warn
	-- colour); otherwise the row's own bucket direction in the bucket's colour.
	local dirText, dirCol = QAT.Aggregator_BucketDirection(row.bucket), BUCKET_META[row.bucket].color
	if collapsed then
		local rows = {}
		for _, k in ipairs(collapseKeys) do
			local r = QAT.capture.store[k]
			if r then
				rows[#rows + 1] = r
			end
		end
		if QAT.Aggregator_StackDirection(rows) == nil then
			dirText, dirCol = "mixed dir", { 0.878, 0.686, 0.196 }
		end
	end
	c.dirBadge:SetText(dirText or "")
	c.dirBadge:SetColorRGB(dirCol)
	c.dirBadge:SetHidden(not dirText or dirText == "")

	-- "Active" = ticked in select mode, or the inspected row otherwise. Drives the
	-- accent bar, the row highlight, and (in select mode) the check mark.
	local active
	if selecting then
		if collapsed then
			-- Collapsed row is active if ANY of the underlying keys is selected.
			local found = false
			for _, k in ipairs(collapseKeys) do
				if a.selectedSet[k] then
					found = true
					break
				end
			end
			active = found
		else
			active = a.selectedSet[row.key] and true or false
		end
		c.checkMark:SetHidden(not active)
	else
		active = (a.selectedKey == row.key)
		QAT.aggregator.selectedRow = active and row or QAT.aggregator.selectedRow
	end
	c.active = active
	c.accent:SetHidden(not active)
	c.bg:SetCenterColor(active and 0.12 or 0.039, active and 0.20 or 0.078, active and 0.30 or 0.11, 1)
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

	local count = W.Label(c, name .. "_C", "", "$(MEDIUM_FONT)|15|soft-shadow-thin")
	count:SetColor(0.5, 0.58, 0.68, 1)
	count:SetAnchor(LEFT, label, RIGHT, 8, 0)
	c.count = count

	local hint = W.Label(c, name .. "_H", "", "$(MEDIUM_FONT)|15|soft-shadow-thin")
	hint:SetColor(0.42, 0.48, 0.56, 1)
	hint:SetAnchor(RIGHT, c, RIGHT, -10, 0)
	c.hint = hint

	c:SetHandler("OnMouseUp", function(self, button, upInside)
		-- Self→Self is pinned open (it's easy to lose in the noise); it never collapses.
		if upInside and button == MOUSE_BUTTON_INDEX_LEFT and self.bucket ~= "ss" then
			QAT.aggregator.collapsed[self.bucket] = not QAT.aggregator.collapsed[self.bucket]
			QAT.Aggregator_List_Render()
		end
	end)
	return c
end

local function bindHeader(c, bucket, n, y)
	local meta = BUCKET_META[bucket]
	local collapsed = bucket ~= "ss" and QAT.aggregator.collapsed[bucket]
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

	-- Sort band: a darker control strip separating the row list from the filter bar
	-- above. Holds the multi-select toggle (left), the count, and the sort segment.
	local band = W.Panel(pane, "QAT_AggList_Band", { 0.031, 0.055, 0.075, 1 })
	band:SetAnchor(TOPLEFT, pane, TOPLEFT, 0, 0)
	band:SetAnchor(TOPRIGHT, pane, TOPRIGHT, 0, 0)
	band:SetHeight(TOOLBAR_H + 8)
	local bandRule = W.Divider(pane, "QAT_AggList_BandRule")
	bandRule:SetAnchor(BOTTOMLEFT, band, BOTTOMLEFT, 0, 0)
	bandRule:SetAnchor(BOTTOMRIGHT, band, BOTTOMRIGHT, 0, 0)

	local tb = WM:CreateControl("QAT_AggList_Toolbar", pane, CT_CONTROL)
	tb:SetAnchor(TOPLEFT, pane, TOPLEFT, 10, 4)
	tb:SetAnchor(TOPRIGHT, pane, TOPRIGHT, -10, 4)
	tb:SetHeight(TOOLBAR_H)
	QAT.aggregator.listToolbar = tb

	-- Multi-select toggle: turns on row checkboxes and swaps the inspector for the
	-- Tracker builder. Label flips to "Selecting" while on.
	local selectBtn = W.TextButton(tb, "QAT_AggList_Select", "Select multiple", function()
		QAT.Aggregator_SetSelecting(not QAT.aggregator.selecting)
	end)
	selectBtn:SetHeight(28)
	selectBtn:SetAnchor(LEFT, tb, LEFT, 0, 0)
	QAT.widgets.Tooltip(
		selectBtn,
		"Tick two or more effects, then Build Tracker makes one aura that switches between them."
	)
	QAT.aggregator.selectBtn = selectBtn

	local count = W.Label(tb, "QAT_AggList_Count", "", "$(MEDIUM_FONT)|15|soft-shadow-thin")
	count:SetColor(0.55, 0.62, 0.72, 1)
	count:SetAnchor(LEFT, selectBtn, RIGHT, 12, 0)
	QAT.aggregator.listCountLabel = count

	-- Collapse by name toggle (default on): deduplicate rows with the same name.
	local collapseBtn = W.TextButton(tb, "QAT_AggList_Collapse", "Collapse by name", function(self)
		local f = QAT.aggregator and QAT.aggregator.filter
		if f then
			f.collapseByName = not f.collapseByName
			self:SetSelected(f.collapseByName)
			QAT.Aggregator_Refresh()
		end
	end)
	collapseBtn:SetHeight(28)
	collapseBtn:SetAnchor(LEFT, count, RIGHT, 12, 0)
	collapseBtn:SetSelected(QAT.aggregator.filter.collapseByName)
	QAT.widgets.Tooltip(
		collapseBtn,
		"Group effects with the same name together. Building a tracker from a collapsed group merges all matching ability IDs into one phase."
	)

	-- Sort segment (right).
	local sortOpts = { { v = "lastSeen", l = "Last seen" }, { v = "seen", l = "× Seen" }, { v = "name", l = "Name" } }
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
		b:SetHeight(28)
		if prev then
			b:SetAnchor(LEFT, prev, RIGHT, -1, 0)
		else
			b:SetAnchor(LEFT, collapseBtn, RIGHT, 12, 0)
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
	-- Windowing sets the child height explicitly (only visible rows are bound, so
	-- resize-to-fit would collapse it) — keep the scrollbar range correct manually.
	content:SetResizeToFitDescendents(false)
	QAT.aggregator.listScroll = sc
	QAT.aggregator.listScrollRegion = GetControl(sc, "Scroll")
	QAT.aggregator.listContent = content
	-- Re-window the visible slice as the user scrolls (cheap per-frame position check).
	QAT.aggregator.listScrollRegion:SetHandler("OnUpdate", onScrollUpdate)
end

function QAT.Aggregator_List_Relayout()
	if QAT.aggregator.listScroll then
		rowW = math.max(320, QAT.aggregator.listScroll:GetWidth() - 16)
		QAT.Aggregator_List_Render()
	end
end

-- Viewport windowing. The catch can hold a thousand-plus rows; ZO_ScrollContainer
-- clips but does not cull, so binding every row leaves that many live controls the UI
-- must process every frame — a per-frame draw cost that scales with row count and
-- tanks FPS. Instead we build a cheap layout-only draw "plan" (all items with their y
-- positions) and only bind the slice inside the visible viewport (plus a small buffer).
-- Pooled controls are keyed by a stable slot (the item's ordinal within the plan,
-- modulo a fixed slot count), not row identity. A row keeps the same slot for as long as
-- it stays visible, so the control set is bounded (~one plan's worth of slots reused) AND
-- a slot already holding the right row for this render can be skipped entirely — see the
-- generation check below.
local BUFFER_ROWS = 6 -- rows kept live above/below the viewport for smooth scrolling
-- Bound rows are children of the scrolling content, so they slide with the view without
-- any rebind. We only need a fresh windowBind once the view has travelled far enough to
-- start eating into the buffer — rebinding every frame is wasted work. Rebind every few
-- rows of travel; the buffer (above) hides the seam.
local REBIND_STEP = (BUFFER_ROWS - 2) * (ROW_H + 2)
-- Distinct pooled slots. Must exceed the most rows/headers ever on screen at once
-- (viewport + both buffers); comfortably clears that even on a tall 4K window.
local ROW_SLOTS, HDR_SLOTS = 128, 24
local planItems = {}
local lastScrollTop = -1
-- Bumped on every full render so windowBind knows which slot bindings are stale. A slot
-- whose control already holds this row at this generation needs no rebind (its data and
-- anchor are already current), which is what makes scrolling cheap.
local renderGen = 0

-- Bind only the plan items whose vertical span intersects the visible window. Called on
-- every render and on scroll; cheap because it touches ~one screenful of controls and
-- skips slots already bound to the right row this generation.
local function windowBind()
	local a = QAT.aggregator
	local content = a.listContent
	local scroll = a.listScrollRegion
	if not content or not scroll then
		return
	end
	-- Amount scrolled down = how far the child's top sits above the viewport's top.
	local top = scroll:GetTop() - content:GetTop()
	local viewH = scroll:GetHeight()
	local pad = BUFFER_ROWS * (ROW_H + 2)
	local visTop, visBot = top - pad, top + viewH + pad

	W.PoolBegin(headerPool)
	W.PoolBegin(rowPool)
	local hOrd, rOrd = 0, 0 -- stable ordinals over ALL items (visible or not)
	for i = 1, #planItems do
		local item = planItems[i]
		if item.kind == "hdr" then
			if item.y + HEADER_H >= visTop and item.y <= visBot then
				local slot = hOrd % HDR_SLOTS
				local hc = W.PoolGet(headerPool, slot, function()
					return makeHeader(content, "QAT_AggHdr_" .. slot)
				end)
				bindHeader(hc, item.bucket, item.n, item.y)
			end
			hOrd = hOrd + 1
		else
			if item.y + ROW_H >= visTop and item.y <= visBot then
				local slot = rOrd % ROW_SLOTS
				local rc = W.PoolGet(rowPool, slot, function()
					return makeRow(content, "QAT_AggRow_" .. slot)
				end)
				-- Bind key includes collapse state so a toggle invalidates stale slots.
				local bindKey = item.row.key
				if item.collapseKeys then
					bindKey = "_collapsed_" .. item.row.key
				end
				if rc._boundKey ~= bindKey or rc._boundGen ~= renderGen then
					bindRow(rc, item.row, item.y, item.collapseKeys, item.collapseIds)
					rc._boundKey, rc._boundGen = bindKey, renderGen
				end
			end
			rOrd = rOrd + 1
		end
	end
	W.PoolEnd(headerPool)
	W.PoolEnd(rowPool)
end

-- OnUpdate hook: re-window when the scroll position has moved. Comparing one number
-- per frame is free; the rebind only fires on actual movement.
function onScrollUpdate()
	local content = QAT.aggregator.listContent
	local scroll = QAT.aggregator.listScrollRegion
	if not content or not scroll then
		return
	end
	local top = scroll:GetTop() - content:GetTop()
	if math.abs(top - lastScrollTop) >= REBIND_STEP then
		lastScrollTop = top
		windowBind()
	end
end

local function startRender(plan, totalH)
	planItems = plan
	renderGen = renderGen + 1 -- invalidate all slot bindings; data may have changed
	local content = QAT.aggregator.listContent
	if content then
		content:SetHeight(totalH)
	end
	lastScrollTop = -1 -- force a rebind (content height/anchors may have shifted)
	windowBind()
end

function QAT.Aggregator_List_Render()
	local a = QAT.aggregator
	if not a.listContent then
		return
	end
	-- Refresh the loadout lookup so the scribed marker + Focus sorting reflect the
	-- current bars/grimoires (cheap; runs once per render, not per row).
	if QAT.Aggregator_RefreshMine then
		QAT.Aggregator_RefreshMine()
	end
	local fq = a.filter

	-- Group passing rows by bucket.
	local groups, shown = {}, 0
	for _, row in ipairs(QAT.capture.list) do
		if QAT.Aggregator_RowPasses(row, fq) then
			groups[row.bucket] = groups[row.bucket] or {}
			table.insert(groups[row.bucket], row)
			shown = shown + 1
		end
	end

	-- Favourites float to the top of every section regardless of the active sort;
	-- within each of the two bands the chosen sort applies.
	local base = SORTS[fq.sort] or SORTS.lastSeen
	local focusOn = fq.prioritiseMine
	local cmp = function(a, b)
		-- Favourites always outrank everything: favourite → non-favourite first.
		local fa, fb = a.favourited and true or false, b.favourited and true or false
		if fa ~= fb then
			return fa
		end
		-- Within each favourite band, Focus Scribing floats scribed abilities up (a
		-- scribed non-favourite can never beat a favourite — this tier is below it).
		if focusOn then
			local sa = QAT.Aggregator_RowScribedFrom(a) ~= nil
			local sb = QAT.Aggregator_RowScribedFrom(b) ~= nil
			if sa ~= sb then
				return sa
			end
		end
		return base(a, b)
	end
	for _, g in pairs(groups) do
		table.sort(g, cmp)
	end

	-- Collapse by name: deduplicate rows within each bucket so only one row per
	-- unique name is displayed. The collapsed row carries the extra keys/IDs for
	-- multi-select.
	if fq.collapseByName then
		for bucket, g in pairs(groups) do
			local seen = {}
			local deduped = {}
			for _, row in ipairs(g) do
				local nk = (row.name or ""):lower()
				local e = seen[nk]
				if not e then
					e = { row = row, keys = {}, ids = {} }
					seen[nk] = e
					table.insert(deduped, e)
				end
				e.keys[#e.keys + 1] = row.key
				e.ids[#e.ids + 1] = row.abilityId
			end
			groups[bucket] = deduped
		end
	end

	local function iterRows(g)
		if fq.collapseByName then
			-- Each entry is { row, keys, ids } — yield the first row once.
			local i = 0
			return function()
				i = i + 1
				local e = g and g[i]
				if not e then
					return nil
				end
				return e.row, e.keys, e.ids
			end
		else
			local i = 0
			return function()
				i = i + 1
				local r = g and g[i]
				if not r then
					return nil
				end
				return r, nil, nil
			end
		end
	end

	-- Build the flat draw plan (layout math only — no control ops, so it's cheap even
	-- for a big catch). The binding happens later, spread across frames.
	local plan, y = {}, 0
	for _, bucket in ipairs(BUCKET_ORDER) do
		local g = groups[bucket]
		if g and #g > 0 then
			plan[#plan + 1] = { kind = "hdr", bucket = bucket, n = #g, y = y }
			y = y + HEADER_H + 2
			if bucket == "ss" or not a.collapsed[bucket] then
				for row, collapseKeys, collapseIds in iterRows(g) do
					plan[#plan + 1] = {
						kind = "row",
						row = row,
						y = y,
						collapseKeys = collapseKeys,
						collapseIds = collapseIds,
					}
					y = y + ROW_H + 2
				end
			end
			y = y + 8 -- gap between sections
		end
	end

	-- Toolbar count (immediate; doesn't wait on the async bind).
	if a.listCountLabel then
		a.listCountLabel:SetText(shown .. " effect" .. (shown == 1 and "" or "s"))
	end

	startRender(plan, y)
end
