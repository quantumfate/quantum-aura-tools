-- Load tab: the conditions that decide whether a tracker (or folder) is active.
-- All matching is by stable id. Searchable set/skill pickers arrive later; for now
-- ids and "use current zone/boss" buttons keep entry practical.

local PAD = 12
local ROW_H = 26
local GAP = 6
local LX = PAD + 90

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

local function render(container, def)
	local pool = container.pool or QAT.widgets.NewPool()
	container.pool = pool
	QAT.widgets.PoolBegin(pool)
	local function get(key, factory)
		return QAT.widgets.PoolGet(pool, key, factory)
	end

	local load = def.load or {}
	def.load = load
	local y = PAD

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
	addZone:SetDimensions(90, ROW_H)
	addZone:ClearAnchors()
	addZone:SetAnchor(TOPLEFT, container, TOPLEFT, LX + 240, y)
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
	clearZone:SetDimensions(60, ROW_H)
	clearZone:ClearAnchors()
	clearZone:SetAnchor(TOPLEFT, container, TOPLEFT, LX + 336, y)
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
	addBoss:SetDimensions(90, ROW_H)
	addBoss:ClearAnchors()
	addBoss:SetAnchor(TOPLEFT, container, TOPLEFT, LX + 240, y)
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
	clearBoss:SetDimensions(60, ROW_H)
	clearBoss:ClearAnchors()
	clearBoss:SetAnchor(TOPLEFT, container, TOPLEFT, LX + 336, y)
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
	addSet:SetDimensions(70, ROW_H)
	addSet:ClearAnchors()
	addSet:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y)
	addSet.onClick = function()
		table.insert(load.sets, { setId = 0, pieces = 5, mode = "any" })
		commit(def)
		render(container, def)
	end

	QAT.widgets.PoolEnd(pool)
end

QAT.editor.tabRenderers = QAT.editor.tabRenderers or {}
QAT.editor.tabRenderers["Load"] = render
