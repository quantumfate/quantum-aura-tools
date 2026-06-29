--- Load conditions (is a tracker active right now?) and the comparison helper
--- used by runtime conditions.
---
--- All predicates match stable numeric IDs (setId / abilityId / zoneId / classId),
--- never localized name strings, so conditions are language-independent. Set
--- conditions count the cross-bar theoretical maximum (body/jewelry pieces plus
--- the better of the two weapon bars) so a set placed on a single weapon bar does
--- not make a tracker flicker on weapon swap.

QAT.conditions = {}

local BODY_JEWELRY_SLOTS = {
	EQUIP_SLOT_HEAD,
	EQUIP_SLOT_CHEST,
	EQUIP_SLOT_SHOULDERS,
	EQUIP_SLOT_HAND,
	EQUIP_SLOT_WAIST,
	EQUIP_SLOT_LEGS,
	EQUIP_SLOT_FEET,
	EQUIP_SLOT_NECK,
	EQUIP_SLOT_RING1,
	EQUIP_SLOT_RING2,
}
-- A weapon bar's two slots: main hand and off hand. A two-handed weapon (greatsword,
-- bow, staff) occupies only the main-hand slot and leaves the off hand empty.
local FRONT_WEAPON_SLOTS = { main = EQUIP_SLOT_MAIN_HAND, off = EQUIP_SLOT_OFF_HAND }
local BACK_WEAPON_SLOTS = { main = EQUIP_SLOT_BACKUP_MAIN, off = EQUIP_SLOT_BACKUP_OFF }

local function setIdInSlot(slot)
	local link = GetItemLink(BAG_WORN, slot)
	if not link or link == "" then
		return nil
	end
	local _, _, _, _, _, setId = GetItemLinkSetInfo(link, false)
	return setId
end

local function countSetInSlots(setId, slots)
	local n = 0
	for _, slot in ipairs(slots) do
		if setIdInSlot(slot) == setId then
			n = n + 1
		end
	end
	return n
end

-- Count a single weapon bar's set pieces. A two-handed weapon counts as 2 set
-- pieces (and fills only the main hand); each one-handed weapon or shield counts
-- as 1.
local function countSetOnWeaponBar(setId, slots)
	local n = 0
	local mainLink = GetItemLink(BAG_WORN, slots.main)
	if mainLink and mainLink ~= "" then
		local _, _, _, _, _, mainSetId = GetItemLinkSetInfo(mainLink, false)
		if mainSetId == setId then
			n = n + (GetItemLinkEquipType(mainLink) == EQUIP_TYPE_TWO_HAND and 2 or 1)
		end
	end
	if setIdInSlot(slots.off) == setId then
		n = n + 1
	end
	return n
end

--- Whether an equipped-set condition is satisfied.
---@param cond table { setId:number, pieces:number, mode:"any"|"current" }
---  mode "any" (default) counts the cross-bar maximum; "current" counts only the
---  drawn weapon bar's pieces (live bonus state).
---@return boolean
function QAT.conditions.SetSatisfied(cond)
	local body = countSetInSlots(cond.setId, BODY_JEWELRY_SLOTS)
	local front = countSetOnWeaponBar(cond.setId, FRONT_WEAPON_SLOTS)
	local back = countSetOnWeaponBar(cond.setId, BACK_WEAPON_SLOTS)
	local need = cond.pieces or 5

	if cond.mode == "current" then
		-- Only the drawn bar's weapons count (live bonus state).
		local activePair = GetActiveWeaponPairInfo()
		local weapons = (activePair == 1) and front or back
		return (body + weapons) >= need
	end

	-- "any" (default): can the set reach the threshold on *either* bar?
	local best = front > back and front or back
	return (body + best) >= need
end

-- True if any of abilityIds is slotted on either hotbar.
function QAT.conditions.SkillSlotted(abilityIds)
	local want = QAT.util.ToSet(abilityIds)
	for _, hotbar in ipairs({ HOTBAR_CATEGORY_PRIMARY, HOTBAR_CATEGORY_BACKUP }) do
		for slot = 3, 8 do
			if want[GetSlotBoundId(slot, hotbar)] then
				return true
			end
		end
	end
	return false
end

local function anyBossMatches(names)
	local want = QAT.util.ToSet(names)
	for i = 1, 6 do
		local tag = "boss" .. i
		if DoesUnitExist(tag) and want[GetUnitName(tag)] then
			return true
		end
	end
	return false
end

-- Evaluate a single load def. An empty/nil def loads (true).
local function evaluateOne(load)
	if not load then
		return true
	end
	if load.never then
		return false
	end
	if load.always then
		return true
	end

	if load.classId and GetUnitClassId("player") ~= load.classId then
		return false
	end
	if load.role and GetSelectedLFGRole() ~= load.role then
		return false
	end
	if load.inCombat ~= nil and IsUnitInCombat("player") ~= load.inCombat then
		return false
	end

	if load.zoneIds and #load.zoneIds > 0 then
		local zone = GetZoneId(GetUnitZoneIndex("player"))
		local ok = false
		for _, z in ipairs(load.zoneIds) do
			if z == zone then
				ok = true
				break
			end
		end
		if not ok then
			return false
		end
	end

	if load.skills and #load.skills > 0 and not QAT.conditions.SkillSlotted(load.skills) then
		return false
	end

	if load.sets then
		for _, s in ipairs(load.sets) do
			if not QAT.conditions.SetSatisfied(s) then
				return false
			end
		end
	end

	if load.bosses and #load.bosses > 0 and not anyBossMatches(load.bosses) then
		return false
	end

	return true
end

--- Evaluate a chain of load defs. A tracker loads only if its own def and every
--- ancestor folder's def pass (folder conditions cascade to children).
---@param loadChain table[] load defs, ancestors first
---@return boolean
function QAT.conditions.EvaluateLoad(loadChain)
	for _, load in ipairs(loadChain or {}) do
		if not evaluateOne(load) then
			return false
		end
	end
	return true
end

local OPS = {
	["<"] = function(a, b)
		return a < b
	end,
	["<="] = function(a, b)
		return a <= b
	end,
	["=="] = function(a, b)
		return a == b
	end,
	["~="] = function(a, b)
		return a ~= b
	end,
	[">="] = function(a, b)
		return a >= b
	end,
	[">"] = function(a, b)
		return a > b
	end,
}

function QAT.conditions.Compare(a, op, b)
	local fn = OPS[op]
	return fn ~= nil and fn(a, b) or false
end
