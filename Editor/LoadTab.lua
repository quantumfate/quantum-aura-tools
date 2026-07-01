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
	addBtn:SetAnchor(TOPRIGHT, container, TOPRIGHT, -(OUT + card.padX), OUT + 6)
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
	local cw = container:GetWidth()
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

	-- Equipped sets (id + pieces + bar mode). One row per set.
	label("lSets", "Sets", y)
	load.sets = load.sets or {}
	y = y + ROW_H
	for i, s in ipairs(load.sets) do
		local x = LX
		local idx = i
		local setIdBox = get("setId" .. i, function()
			return QAT.widgets.EditBox(container, "QAT_Load_SetId" .. i, 90, ROW_H)
		end)
		setIdBox.onChange = function(text)
			s.setId = tonumber(text) or 0
			commit(def)
		end
		setIdBox:SetText(tostring(s.setId or 0))
		setIdBox:ClearAnchors()
		setIdBox:SetAnchor(TOPLEFT, container, TOPLEFT, x, y)
		x = x + 96

		local piecesBox = get("setPc" .. i, function()
			return QAT.widgets.EditBox(container, "QAT_Load_SetPc" .. i, 50, ROW_H)
		end)
		piecesBox.onChange = function(text)
			s.pieces = tonumber(text) or 5
			commit(def)
		end
		piecesBox:SetText(tostring(s.pieces or 5))
		piecesBox:ClearAnchors()
		piecesBox:SetAnchor(TOPLEFT, container, TOPLEFT, x, y)
		x = x + 56

		local modeDD = get("setMode" .. i, function()
			return QAT.widgets.Dropdown(container, "QAT_Load_SetMode" .. i, 110, {
				{ label = "Any bar", value = "any" },
				{ label = "Current bar", value = "current" },
			}, "any")
		end)
		modeDD.onSelect = function(v)
			s.mode = v
			commit(def)
		end
		modeDD:SetValue(s.mode or "any")
		modeDD:ClearAnchors()
		modeDD:SetAnchor(TOPLEFT, container, TOPLEFT, x, y)
		x = x + 116

		local del = get("setDel" .. i, function()
			return QAT.widgets.TextButton(container, "QAT_Load_SetDel" .. i, "X", nil)
		end)
		del:SetDimensions(ROW_H, ROW_H)
		del:ClearAnchors()
		del:SetAnchor(TOPLEFT, container, TOPLEFT, x, y)
		QAT.widgets.Tooltip(del, "Remove this set condition.")
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

	QAT.widgets.PoolEnd(pool)
end

QAT.editor.tabRenderers = QAT.editor.tabRenderers or {}
QAT.editor.tabRenderers["Load"] = render
