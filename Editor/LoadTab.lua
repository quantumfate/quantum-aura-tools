-- Load tab: the conditions that decide whether a tracker (or folder) is active.
-- All matching is by stable id. Searchable set/skill pickers arrive later; for now
-- ids and "use current zone/boss" buttons keep entry practical.

local WM = GetWindowManager()
local ROW_H = 26
local GAP = 6
local MROW_H = 30

local CLASS_OPTS = {
	{ label = "Any", value = nil },
	{ label = "Dragonknight", value = 1 },
	{ label = "Sorcerer", value = 2 },
	{ label = "Nightblade", value = 3 },
	{ label = "Warden", value = 4 },
	{ label = "Necromancer", value = 5 },
	{ label = "Templar", value = 6 },
	{ label = "Arcanist", value = 117 },
}
local ROLE_OPTS = {
	{ label = "Any", value = nil },
	{ label = "Tank", value = LFG_ROLE_TANK },
	{ label = "Healer", value = LFG_ROLE_HEAL },
	{ label = "DPS", value = LFG_ROLE_DPS },
}
local COMBAT_OPTS = {
	{ label = "Ignore", value = "ignore" },
	{ label = "In combat", value = "in" },
	{ label = "Out of combat", value = "out" },
}
-- The per-set bar toggle: which weapon bar a set's pieces are counted on (gear
-- placement, never the drawn bar).
local BAR_OPTS = { { "any", "Any bar" }, { "front", "Front bar" }, { "back", "Back bar" } }
-- Bar-mode accent colors: amber = any, teal = front, blue = back. Ties the group
-- badge to the segmented control.
local BAR_COLOR = {
	any = { 0.90, 0.72, 0.30 },
	front = { 0.35, 0.80, 0.72 },
	back = { 0.45, 0.62, 0.90 },
}
local BAR_LABEL = { any = "Any bar", front = "Front bar", back = "Back bar" }
-- Current-loadout groups, in display order. Category keys match ScanEquippedSets.
local LOADOUT_GROUPS = {
	{ key = "body", header = "Body & jewelry", badge = "Any bar", note = "counts on both bars" },
	{ key = "front", header = "Front bar", badge = "Front bar", note = "front-bar weapons" },
	{ key = "back", header = "Back bar", badge = "Back bar", note = "back-bar weapons" },
	{ key = "mythic", header = "Mythic", badge = "Any bar", note = "one-piece unique" },
	{ key = "monster", header = "Monster set", badge = "Any bar", note = "head / shoulder" },
}

local function commit(def)
	QAT.widgets.NotifyTrackerChanged(def.id)
end

local function combatToValue(v)
	if v == "in" then
		return true
	elseif v == "out" then
		return false
	end
	return nil
end
local function combatFromLoad(load)
	if load.inCombat == true then
		return "in"
	elseif load.inCombat == false then
		return "out"
	end
	return "ignore"
end

-- Best icon to represent a member tracker: the first phase icon it resolves, else
-- a placeholder.
local function memberIcon(kid)
	for _, p in ipairs(kid.phases or {}) do
		local ic = QAT.util.PhaseIcon(p)
		if ic then
			return ic
		end
	end
	return "/esoui/art/icons/icon_missing.dds"
end

-- Forward declaration so the Members card's remove button can re-render.
local render

-- The group Members card (folders only): a titled list of member trackers with a
-- swatch, name and remove button, plus a "+ Add tracker" action. Returns the
-- container-space y at which the load-conditions card below it should start.
local function renderMembers(container, def, get, cw, OUT)
	local card = get("mcard", function()
		return QAT.widgets.Card(container, "QAT_Load_MCard", "Members")
	end)
	card:SetTitle("Members")
	card:ClearAnchors()
	card:SetAnchor(TOPLEFT, container, TOPLEFT, OUT, OUT)
	local PAD = OUT + card.padX
	local rowW = cw - OUT * 2 - card.padX * 2
	local y = OUT + card.contentY

	local addBtn = get("mAdd", function()
		return QAT.widgets.TextButton(container, "QAT_Load_MAdd", "+ Add tracker", nil)
	end)
	addBtn:SetHeight(24)
	addBtn:ClearAnchors()
	addBtn:SetAnchor(TOPRIGHT, card, TOPRIGHT, -card.padX, 6)
	addBtn.onClick = function()
		if QAT.Editor_AddTrackerToGroup then
			QAT.Editor_AddTrackerToGroup(def.id)
		end
	end

	local sub = get("mSub", function()
		return QAT.widgets.Label(container, "QAT_Load_MSub", "")
	end)
	sub:SetText("Trackers in this group share the load rules below. Drag in the tree also works.")
	sub:SetColor(0.55, 0.6, 0.7, 1)
	sub:ClearAnchors()
	sub:SetAnchor(TOPLEFT, container, TOPLEFT, PAD, y + 3)
	y = y + 24

	local kids = def.children or {}
	if #kids == 0 then
		local empty = get("mEmpty", function()
			return QAT.widgets.Label(container, "QAT_Load_MEmpty", "")
		end)
		empty:SetText("No trackers yet — use + Add tracker, or drag one in.")
		empty:SetColor(0.5, 0.55, 0.64, 1)
		empty:ClearAnchors()
		empty:SetAnchor(TOPLEFT, container, TOPLEFT, PAD, y + 2)
		y = y + MROW_H
	end

	for i, kid in ipairs(kids) do
		local kidId = kid.id
		local mrow = get("mrow" .. i, function()
			return QAT.widgets.Panel(container, "QAT_Load_MRow" .. i, { 0.10, 0.13, 0.18, 1 })
		end)
		mrow:SetHidden(false)
		mrow:ClearAnchors()
		mrow:SetAnchor(TOPLEFT, container, TOPLEFT, PAD, y)
		mrow:SetDimensions(rowW, MROW_H)

		-- Drag-handle hint (functional drag lives in the tree, per the subtext).
		local handle = get("mHandle" .. i, function()
			return QAT.widgets.Label(container, "QAT_Load_MHandle" .. i, "⋮⋮")
		end)
		handle:SetColor(0.4, 0.45, 0.55, 1)
		handle:ClearAnchors()
		handle:SetAnchor(LEFT, mrow, LEFT, 8, 0)

		local sw = get("mSw" .. i, function()
			local t = WM:CreateControl("QAT_Load_MSw" .. i, container, CT_TEXTURE)
			t:SetDimensions(18, 18)
			return t
		end)
		sw:SetTexture(memberIcon(kid))
		sw:ClearAnchors()
		sw:SetAnchor(LEFT, mrow, LEFT, 28, 0)

		local nm = get("mNm" .. i, function()
			return QAT.widgets.Label(container, "QAT_Load_MNm" .. i, "")
		end)
		nm:SetText(kid.name or kid.id)
		nm:SetColor(0.9, 0.92, 0.95, 1)
		nm:ClearAnchors()
		nm:SetAnchor(LEFT, sw, RIGHT, 10, 0)

		local del = get("mDel" .. i, function()
			return QAT.widgets.TextButton(container, "QAT_Load_MDel" .. i, "X", nil)
		end)
		del:SetDimensions(24, 24)
		del:ClearAnchors()
		del:SetAnchor(RIGHT, mrow, RIGHT, -6, 0)
		QAT.widgets.Tooltip(del, "Remove from this group (keeps the tracker at the top level).")
		del.onClick = function()
			if QAT.Editor_UnparentTracker then
				QAT.Editor_UnparentTracker(kidId)
				render(container, def)
			end
		end

		y = y + MROW_H + 4
	end

	card:SetDimensions(cw - OUT * 2, (y - OUT) + 8)
	return y + 22 -- start the load card a gap below the members card
end

-- The "current loadout" card: read equipped gear live and, per set, offer a
-- one-click "add as condition" that pre-fills the piece count and the correct bar
-- (front/back detected from the slot). Anchored at container-space y = top.
local function renderLoadout(container, def, load, get, cw, OUT, top)
	local card = get("locard", function()
		return QAT.widgets.Card(container, "QAT_Load_LoCard", "Current loadout")
	end)
	card:SetTitle("Current loadout")
	card:ClearAnchors()
	card:SetAnchor(TOPLEFT, container, TOPLEFT, OUT, top)
	local PAD = OUT + card.padX
	local y = top + card.contentY

	local sub = get("loSub", function()
		return QAT.widgets.Label(container, "QAT_Load_LoSub", "")
	end)
	sub:SetText("Read from your equipped gear. Add pre-fills the piece count and the bar (front/back from the slot).")
	sub:SetColor(0.55, 0.6, 0.7, 1)
	sub:ClearAnchors()
	sub:SetAnchor(TOPLEFT, container, TOPLEFT, PAD, y + 3)
	y = y + 26

	local entries = QAT.conditions.ScanEquippedSets()
	local byCat = {}
	for _, e in ipairs(entries) do
		byCat[e.category] = byCat[e.category] or {}
		table.insert(byCat[e.category], e)
	end

	local function addAsCondition(e)
		load.sets = load.sets or {}
		local existing
		for _, s in ipairs(load.sets) do
			if s.setId == e.setId then
				existing = s
				break
			end
		end
		if existing then
			existing.pieces, existing.mode = e.pieces, e.bar
		else
			table.insert(load.sets, { setId = e.setId, pieces = e.pieces, mode = e.bar })
		end
		commit(def)
		render(container, def)
	end

	if #entries == 0 then
		local empty = get("loEmpty", function()
			return QAT.widgets.Label(container, "QAT_Load_LoEmpty", "")
		end)
		empty:SetText("No set pieces equipped.")
		empty:SetColor(0.5, 0.55, 0.64, 1)
		empty:ClearAnchors()
		empty:SetAnchor(TOPLEFT, container, TOPLEFT, PAD, y + 2)
		y = y + ROW_H
	end

	local rowW = cw - OUT * 2 - card.padX * 2
	local ROWH = 64
	local n, chipN = 0, 0 -- running indices for pooled controls
	for _, g in ipairs(LOADOUT_GROUPS) do
		local list = byCat[g.key]
		if list and #list > 0 then
			-- Group header: name + colored bar badge + muted hint.
			local h = get("loH" .. g.key, function()
				return QAT.widgets.Label(container, "QAT_Load_LoH" .. g.key, "", "$(BOLD_FONT)|15|soft-shadow-thin")
			end)
			h:SetText(g.header)
			h:SetColor(0.68, 0.74, 0.84, 1)
			h:ClearAnchors()
			h:SetAnchor(TOPLEFT, container, TOPLEFT, PAD, y + 2)
			local mode = (g.key == "front" and "front") or (g.key == "back" and "back") or "any"
			local badge = get("loB" .. g.key, function()
				return QAT.widgets.Badge(container, "QAT_Load_LoB" .. g.key, "", BAR_COLOR[mode])
			end)
			badge:SetColorRGB(BAR_COLOR[mode])
			badge:SetText(BAR_LABEL[mode])
			badge:ClearAnchors()
			badge:SetAnchor(LEFT, h, RIGHT, 10, 0)
			local note = get("loN" .. g.key, function()
				return QAT.widgets.Label(container, "QAT_Load_LoN" .. g.key, "")
			end)
			note:SetText(g.note)
			note:SetColor(0.45, 0.5, 0.6, 1)
			note:ClearAnchors()
			note:SetAnchor(LEFT, badge, RIGHT, 8, 0)
			y = y + ROW_H

			for _, e in ipairs(list) do
				n = n + 1
				-- Each set sits in its own bordered row card so the list is scannable.
				local rowc = get("loRow" .. n, function()
					return QAT.widgets.Panel(
						container,
						"QAT_Load_LoRow" .. n,
						{ 0.039, 0.078, 0.110, 1 },
						{ 0.114, 0.165, 0.208, 1 }
					)
				end)
				rowc:SetHidden(false)
				rowc:ClearAnchors()
				rowc:SetAnchor(TOPLEFT, container, TOPLEFT, PAD, y)
				rowc:SetDimensions(rowW, ROWH)

				local swatch = get("loSw" .. n, function()
					return QAT.widgets.IconWell(container, "QAT_Load_LoSw" .. n, 34)
				end)
				swatch:SetTexture(e.icon or "/esoui/art/icons/icon_missing.dds")
				swatch:ClearAnchors()
				swatch:SetAnchor(LEFT, rowc, LEFT, 12, 0)

				local nm = get("loNm" .. n, function()
					return QAT.widgets.Label(container, "QAT_Load_LoNm" .. n, "")
				end)
				nm:SetText(string.format("%s  |c888888#%d · %d pc|r", e.name or "?", e.setId, e.pieces))
				nm:ClearAnchors()
				nm:SetAnchor(TOPLEFT, rowc, TOPLEFT, 58, 13)
				QAT.widgets.ItemTooltip(nm, e.link)

				-- Slot occupancy as chips.
				local cx = 58
				for _, slotName in ipairs(e.slots) do
					chipN = chipN + 1
					local chip = get("loChip" .. chipN, function()
						return QAT.widgets.Chip(container, "QAT_Load_LoChip" .. chipN, "")
					end)
					chip:SetHidden(false)
					chip:SetText(slotName)
					chip:ClearAnchors()
					chip:SetAnchor(TOPLEFT, rowc, TOPLEFT, cx, 38)
					cx = cx + chip:GetWidth() + 6
				end

				local addBtn = get("loAdd" .. n, function()
					return QAT.widgets.TextButton(container, "QAT_Load_LoAdd" .. n, "+ Add as condition", nil)
				end)
				addBtn:SetHeight(ROW_H)
				addBtn:ClearAnchors()
				addBtn:SetAnchor(RIGHT, rowc, RIGHT, -12, 0)
				local ent = e
				addBtn.onClick = function()
					addAsCondition(ent)
				end

				y = y + ROWH + 8
			end
			y = y + 4
		end
	end

	card:SetDimensions(cw - OUT * 2, (y - top) + 8)
end

render = function(container, def)
	local pool = container.pool or QAT.widgets.NewPool()
	container.pool = pool
	QAT.widgets.PoolBegin(pool)
	local function get(key, factory)
		return QAT.widgets.PoolGet(pool, key, factory)
	end

	local load = def.load or {}
	def.load = load

	-- Wrap the content in a titled card (created first so it draws behind). Groups
	-- get a Members card stacked above the load card.
	local cw = container.qatViewportW or container:GetWidth()
	if cw < 240 then
		cw = 900
	end
	local OUT = 14
	local isFolder = def.kind == "folder"
	local loadTop = OUT
	if isFolder then
		loadTop = renderMembers(container, def, get, cw, OUT)
	end

	local card = get("card", function()
		return QAT.widgets.Card(container, "QAT_Load_Card", "Load conditions")
	end)
	card:SetTitle(isFolder and "Group load conditions" or "Load conditions")
	card:ClearAnchors()
	card:SetAnchor(TOPLEFT, container, TOPLEFT, OUT, loadTop)
	local PAD = OUT + card.padX
	local LX = PAD + 78
	local y = loadTop + card.contentY

	-- Scope subtitle: what these conditions gate and how member/phase rules relate.
	local subtitle = get("subtitle", function()
		return QAT.widgets.Label(container, "QAT_Load_Subtitle", "")
	end)
	if isFolder then
		subtitle:SetText(
			(def.name or def.id)
				.. " — Applies to every tracker in this group at once — individual auras can still narrow it further."
		)
	else
		subtitle:SetText(
			(def.name or def.id) .. " — Determines when the whole tracker is active — applies across all phases."
		)
	end
	subtitle:SetColor(0.55, 0.6, 0.7, 1)
	subtitle:ClearAnchors()
	subtitle:SetAnchor(TOPLEFT, container, TOPLEFT, PAD, y + 3)
	y = y + 24

	local function label(key, text, yy)
		local l = get(key, function()
			return QAT.widgets.Label(container, "QAT_Load_" .. key, "")
		end)
		l:SetText(text)
		l:ClearAnchors()
		l:SetAnchor(TOPLEFT, container, TOPLEFT, PAD, yy + 3)
		return l
	end

	-- Class.
	label("lClass", "Class", y)
	local classDD = get("classDD", function()
		return QAT.widgets.Dropdown(container, "QAT_Load_Class", 160, CLASS_OPTS, nil)
	end)
	classDD.onSelect = function(v)
		load.classId = v
		commit(def)
	end
	classDD:SetValue(load.classId)
	classDD:ClearAnchors()
	classDD:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y)
	y = y + ROW_H + GAP

	-- Role.
	label("lRole", "Role", y)
	local roleDD = get("roleDD", function()
		return QAT.widgets.Dropdown(container, "QAT_Load_Role", 160, ROLE_OPTS, nil)
	end)
	roleDD.onSelect = function(v)
		load.role = v
		commit(def)
	end
	roleDD:SetValue(load.role)
	roleDD:ClearAnchors()
	roleDD:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y)
	y = y + ROW_H + GAP

	-- In combat.
	label("lCombat", "Combat", y)
	local combatDD = get("combatDD", function()
		return QAT.widgets.Dropdown(container, "QAT_Load_Combat", 160, COMBAT_OPTS, "ignore")
	end)
	combatDD.onSelect = function(v)
		load.inCombat = combatToValue(v)
		commit(def)
	end
	combatDD:SetValue(combatFromLoad(load))
	combatDD:ClearAnchors()
	combatDD:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y)
	y = y + ROW_H + GAP

	-- Skills slotted (ability ids).
	label("lSkills", "Skill ids", y)
	local skillBox = get("skillBox", function()
		return QAT.widgets.EditBox(container, "QAT_Load_Skills", 220, ROW_H)
	end)
	skillBox.onChange = function(text)
		local ids = {}
		for t in tostring(text):gmatch("%d+") do
			table.insert(ids, tonumber(t))
		end
		load.skills = ids
		commit(def)
	end
	skillBox:SetText(table.concat(load.skills or {}, ", "))
	skillBox:ClearAnchors()
	skillBox:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y)
	y = y + ROW_H + GAP

	-- Zones.
	label("lZones", "Zones", y)
	load.zoneIds = load.zoneIds or {}
	local zonesText = {}
	for _, z in ipairs(load.zoneIds) do
		table.insert(zonesText, (GetZoneNameById(z) or "?") .. " (" .. z .. ")")
	end
	local zonesLabel = get("zonesVal", function()
		return QAT.widgets.Label(container, "QAT_Load_ZonesVal", "")
	end)
	zonesLabel:SetText(#zonesText > 0 and table.concat(zonesText, ", ") or "(any)")
	zonesLabel:ClearAnchors()
	zonesLabel:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y + 3)
	local addZone = get("addZone", function()
		return QAT.widgets.TextButton(container, "QAT_Load_AddZone", "+ current", nil)
	end)
	addZone:SetHeight(ROW_H)
	addZone:ClearAnchors()
	addZone:SetAnchor(TOPLEFT, container, TOPLEFT, LX + 240, y)
	QAT.widgets.Tooltip(addZone, "Add the zone you are currently in.")
	addZone.onClick = function()
		local z = GetZoneId(GetUnitZoneIndex("player"))
		if z and z > 0 then
			table.insert(load.zoneIds, z)
			commit(def)
			render(container, def)
		end
	end
	local clearZone = get("clearZone", function()
		return QAT.widgets.TextButton(container, "QAT_Load_ClearZone", "clear", nil)
	end)
	clearZone:SetHeight(ROW_H)
	clearZone:ClearAnchors()
	clearZone:SetAnchor(LEFT, addZone, RIGHT, 8, 0)
	QAT.widgets.Tooltip(clearZone, "Clear the zone list (load in any zone).")
	clearZone.onClick = function()
		load.zoneIds = {}
		commit(def)
		render(container, def)
	end
	y = y + ROW_H + GAP

	-- Bosses.
	label("lBosses", "Bosses", y)
	load.bosses = load.bosses or {}
	local bossesLabel = get("bossesVal", function()
		return QAT.widgets.Label(container, "QAT_Load_BossesVal", "")
	end)
	bossesLabel:SetText(#load.bosses > 0 and table.concat(load.bosses, ", ") or "(any)")
	bossesLabel:ClearAnchors()
	bossesLabel:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y + 3)
	local addBoss = get("addBoss", function()
		return QAT.widgets.TextButton(container, "QAT_Load_AddBoss", "+ current", nil)
	end)
	addBoss:SetHeight(ROW_H)
	addBoss:ClearAnchors()
	addBoss:SetAnchor(TOPLEFT, container, TOPLEFT, LX + 240, y)
	QAT.widgets.Tooltip(addBoss, "Add the boss(es) currently engaged.")
	addBoss.onClick = function()
		for i = 1, 6 do
			local tag = "boss" .. i
			if DoesUnitExist(tag) then
				table.insert(load.bosses, GetUnitName(tag))
			end
		end
		commit(def)
		render(container, def)
	end
	local clearBoss = get("clearBoss", function()
		return QAT.widgets.TextButton(container, "QAT_Load_ClearBoss", "clear", nil)
	end)
	clearBoss:SetHeight(ROW_H)
	clearBoss:ClearAnchors()
	clearBoss:SetAnchor(LEFT, addBoss, RIGHT, 8, 0)
	QAT.widgets.Tooltip(clearBoss, "Clear the boss list (load against any boss).")
	clearBoss.onClick = function()
		load.bosses = {}
		commit(def)
		render(container, def)
	end
	y = y + ROW_H + GAP

	-- Equipped sets: pieces + id, the resolved set name, and which bar to count
	-- (any / front / back — gear placement, never the drawn bar). One row per set.
	label("lSets", "Sets", y)
	load.sets = load.sets or {}
	y = y + ROW_H
	for i, s in ipairs(load.sets) do
		local x = LX
		local idx = i
		if s.mode ~= "front" and s.mode ~= "back" then
			s.mode = "any" -- normalize legacy "current"/nil so a toggle reads as selected
		end

		local piecesBox = get("setPc" .. i, function()
			return QAT.widgets.EditBox(container, "QAT_Load_SetPc" .. i, 44, ROW_H)
		end)
		piecesBox.onChange = function(text)
			s.pieces = tonumber(text) or 5
			commit(def)
		end
		piecesBox:SetText(tostring(s.pieces or 5))
		piecesBox:ClearAnchors()
		piecesBox:SetAnchor(TOPLEFT, container, TOPLEFT, x, y)
		x = x + 50

		local pcLbl = get("setPcL" .. i, function()
			return QAT.widgets.Label(container, "QAT_Load_SetPcL" .. i, "pc")
		end)
		pcLbl:ClearAnchors()
		pcLbl:SetAnchor(TOPLEFT, container, TOPLEFT, x, y + 3)
		x = x + 24

		local setIdBox = get("setId" .. i, function()
			return QAT.widgets.EditBox(container, "QAT_Load_SetId" .. i, 60, ROW_H)
		end)
		setIdBox.onChange = function(text)
			s.setId = tonumber(text) or 0
			commit(def)
		end
		setIdBox:SetText(tostring(s.setId or 0))
		setIdBox:ClearAnchors()
		setIdBox:SetAnchor(TOPLEFT, container, TOPLEFT, x, y)
		x = x + 66

		local link = QAT.conditions.SetItemLink(s.setId or 0)
		local swatch = get("setSw" .. i, function()
			return QAT.widgets.IconWell(container, "QAT_Load_SetSw" .. i, ROW_H)
		end)
		swatch:SetTexture((link and GetItemLinkIcon(link)) or "/esoui/art/icons/icon_missing.dds")
		swatch:ClearAnchors()
		swatch:SetAnchor(TOPLEFT, container, TOPLEFT, x, y)
		x = x + ROW_H + 6

		-- The × is right-aligned to the card edge. The segmented Any/Front/Back control
		-- appears only for sets that have weapons (body/jewelry, mythic and monster sets
		-- are always active while worn, on both bars — no choice to make). The name
		-- fills the flexible space left of the controls (truncate; hover shows full).
		local hasWeapons = QAT.conditions.SetHasWeapons(s.setId or 0)
		if not hasWeapons then
			s.mode = "any"
		end
		local rightX = cw - OUT - card.padX
		local closeX = rightX - ROW_H
		local segX = closeX -- no toggle: the name runs up to just left of the ×

		local barBtns = {}
		if hasWeapons then
			local segW = 0
			for _, o in ipairs(BAR_OPTS) do
				local b = get("setBar" .. o[1] .. i, function()
					return QAT.widgets.TextButton(container, "QAT_Load_SetBar" .. o[1] .. i, o[2], nil)
				end)
				b:SetHeight(ROW_H)
				b:SetMinWidth(62)
				b:SetSelected((s.mode or "any") == o[1])
				b.onClick = function()
					s.mode = o[1]
					commit(def)
				end
				barBtns[#barBtns + 1] = b
				segW = segW + b:GetWidth()
			end
			segW = segW - (#barBtns - 1) -- 1px border overlaps
			segX = closeX - 8 - segW
		end

		local nameLbl = get("setName" .. i, function()
			return QAT.widgets.Label(container, "QAT_Load_SetName" .. i, "")
		end)
		nameLbl:SetText(QAT.conditions.SetName(s.setId or 0))
		nameLbl:SetMaxLineCount(1) -- truncate long names; hover shows the full set tooltip
		nameLbl:ClearAnchors()
		nameLbl:SetAnchor(TOPLEFT, container, TOPLEFT, x, y + 3)
		nameLbl:SetAnchor(TOPRIGHT, container, TOPLEFT, segX - 10, y + 3)
		QAT.widgets.ItemTooltip(nameLbl, link)

		local bx = segX
		for _, b in ipairs(barBtns) do
			b:ClearAnchors()
			b:SetAnchor(TOPLEFT, container, TOPLEFT, bx, y)
			bx = bx + b:GetWidth() - 1
		end

		local del = get("setDel" .. i, function()
			return QAT.widgets.CloseButton(container, "QAT_Load_SetDel" .. i, nil)
		end)
		del:SetDimensions(ROW_H, ROW_H)
		del:ClearAnchors()
		del:SetAnchor(TOPLEFT, container, TOPLEFT, closeX, y)
		del.onClick = function()
			table.remove(load.sets, idx)
			commit(def)
			render(container, def)
		end
		y = y + ROW_H + GAP
	end
	local addSet = get("addSet", function()
		return QAT.widgets.TextButton(container, "QAT_Load_AddSet", "+ Set", nil)
	end)
	addSet:SetHeight(ROW_H)
	addSet:ClearAnchors()
	addSet:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y)
	QAT.widgets.Tooltip(addSet, "Add an equipped-set requirement.")
	addSet.onClick = function()
		table.insert(load.sets, { setId = 0, pieces = 5, mode = "any" })
		commit(def)
		render(container, def)
	end

	card:SetDimensions(cw - OUT * 2, y + ROW_H + 8 - loadTop)

	-- Current-loadout card: read equipped gear live and offer one-click
	-- "add as condition" per set. Shown for groups too (a group's sets cascade to
	-- its members), just as for a single tracker.
	local loadoutTop = y + ROW_H + 8 + 14
	renderLoadout(container, def, load, get, cw, OUT, loadoutTop)

	QAT.widgets.PoolEnd(pool)
end

QAT.editor.tabRenderers = QAT.editor.tabRenderers or {}
QAT.editor.tabRenderers["Load"] = render
