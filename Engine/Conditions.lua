--- Load conditions (is a tracker active right now?) and the comparison helper
--- used by runtime conditions.
---
--- All predicates match stable numeric IDs (setId / abilityId / zoneId / classId),
--- never localized name strings, so conditions are language-independent. Set
--- conditions are gear-placement checks: they count body/jewelry pieces plus a
--- chosen weapon bar ("any" = the better of the two, "front"/"back" = that bar),
--- and never depend on which weapon bar is currently drawn — so a tracker does not
--- flicker on weapon swap.

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

--- Whether an equipped-set condition is satisfied. Gear placement only — the check
--- never depends on which weapon bar is currently drawn.
---@param cond table { setId:number, pieces:number, mode:"any"|"front"|"back" }
---  "any" (default) counts body/jewelry plus the better weapon bar; "front"/"back"
---  count body/jewelry plus that specific weapon bar's pieces.
---@return boolean
function QAT.conditions.SetSatisfied(cond)
	local body = countSetInSlots(cond.setId, BODY_JEWELRY_SLOTS)
	local front = countSetOnWeaponBar(cond.setId, FRONT_WEAPON_SLOTS)
	local back = countSetOnWeaponBar(cond.setId, BACK_WEAPON_SLOTS)
	local need = cond.pieces or 5

	local weapons
	if cond.mode == "front" then
		weapons = front
	elseif cond.mode == "back" then
		weapons = back
	else
		-- "any" (default; also legacy "current"): the better of the two bars.
		weapons = front > back and front or back
	end
	return (body + weapons) >= need
end

--- The client-language name of a set id via LibSets (a hard dependency), or a
--- "#<id>" fallback so the editor still shows something for an unknown id.
---@param setId number
---@return string
function QAT.conditions.SetName(setId)
	if setId and setId > 0 and LibSets and LibSets.GetSetName then
		local name = LibSets.GetSetName(setId)
		if type(name) == "table" then
			name = name[GetCVar("Language.2")] or name["en"]
		end
		if type(name) == "string" and name ~= "" then
			return name
		end
	end
	return setId and setId > 0 and ("#" .. setId) or ""
end

--- A representative item link for a set, via LibSets, for the native set tooltip and
--- icon. Prefers the chest, then head, then any piece, so the icon is a stable armor
--- tile (a weapon-only set falls back to its weapon). nil if unavailable.
---@param setId number
---@return string|nil
function QAT.conditions.SetItemLink(setId)
	if not (setId and setId > 0 and LibSets) then
		return nil
	end
	local byType = LibSets.GetSetItemId
	local itemId = byType and (byType(setId, nil, EQUIP_TYPE_CHEST) or byType(setId, nil, EQUIP_TYPE_HEAD))
	itemId = itemId or (LibSets.GetSetFirstItemId and LibSets.GetSetFirstItemId(setId))
	if itemId and itemId > 0 and LibSets.buildItemLink then
		return LibSets.buildItemLink(itemId)
	end
	return nil
end

--- Whether a set has weapon pieces (so a bar choice is meaningful). Body/jewelry-
--- only sets, mythics and monster sets are always active while worn, on both bars.
---@param setId number
---@return boolean
function QAT.conditions.SetHasWeapons(setId)
	if not (setId and setId > 0 and LibSets and LibSets.GetSetItemId) then
		return false
	end
	return (
		LibSets.GetSetItemId(setId, nil, EQUIP_TYPE_ONE_HAND) or LibSets.GetSetItemId(setId, nil, EQUIP_TYPE_TWO_HAND)
	) ~= nil
end

-- Worn slots grouped for the loadout view. region drives which bar a slot's set
-- pieces count toward; label is what the editor shows.
local LOADOUT_SLOTS = {
	{ slot = EQUIP_SLOT_HEAD, label = "Head", region = "body" },
	{ slot = EQUIP_SLOT_SHOULDERS, label = "Shoulders", region = "body" },
	{ slot = EQUIP_SLOT_CHEST, label = "Chest", region = "body" },
	{ slot = EQUIP_SLOT_HAND, label = "Hands", region = "body" },
	{ slot = EQUIP_SLOT_WAIST, label = "Waist", region = "body" },
	{ slot = EQUIP_SLOT_LEGS, label = "Legs", region = "body" },
	{ slot = EQUIP_SLOT_FEET, label = "Feet", region = "body" },
	{ slot = EQUIP_SLOT_NECK, label = "Neck", region = "body" },
	{ slot = EQUIP_SLOT_RING1, label = "Ring", region = "body" },
	{ slot = EQUIP_SLOT_RING2, label = "Ring", region = "body" },
	{ slot = EQUIP_SLOT_MAIN_HAND, label = "Front main hand", region = "front" },
	{ slot = EQUIP_SLOT_OFF_HAND, label = "Front off hand", region = "front" },
	{ slot = EQUIP_SLOT_BACKUP_MAIN, label = "Back main hand", region = "back" },
	{ slot = EQUIP_SLOT_BACKUP_OFF, label = "Back off hand", region = "back" },
}

local function slotsOnlyHeadShoulder(slotIds)
	for _, s in ipairs(slotIds) do
		if s ~= EQUIP_SLOT_HEAD and s ~= EQUIP_SLOT_SHOULDERS then
			return false
		end
	end
	return #slotIds > 0
end

--- Scan the player's equipped gear into set entries for the editor's "current
--- loadout" view. Each entry carries the piece count and the bar a condition
--- should use (front/back for weapon-only sets, otherwise any), the slots the
--- pieces sit in, and a display category (grouping only — not part of the check).
---@return table[] entries { setId, name, icon, pieces, bar, category, slots:string[] }
function QAT.conditions.ScanEquippedSets()
	local byId, order = {}, {}
	for _, info in ipairs(LOADOUT_SLOTS) do
		local link = GetItemLink(BAG_WORN, info.slot)
		if link and link ~= "" then
			local hasSet, setName, _, _, maxEquipped, setId = GetItemLinkSetInfo(link, false)
			if hasSet and setId and setId > 0 then
				local e = byId[setId]
				if not e then
					e = {
						setId = setId,
						name = (setName ~= "" and setName) or QAT.conditions.SetName(setId),
						icon = GetItemLinkIcon(link),
						link = link, -- a real worn piece; drives the hover tooltip
						maxEquipped = maxEquipped or 0,
						body = 0,
						front = 0,
						back = 0,
						slots = {},
						slotIds = {},
					}
					byId[setId] = e
					order[#order + 1] = setId
				end
				local weight = 1
				if info.region == "front" or info.region == "back" then
					weight = (GetItemLinkEquipType(link) == EQUIP_TYPE_TWO_HAND) and 2 or 1
				end
				e[info.region] = e[info.region] + weight
				e.slots[#e.slots + 1] = info.label
				e.slotIds[#e.slotIds + 1] = info.slot
			end
		end
	end

	local entries = {}
	for _, setId in ipairs(order) do
		local e = byId[setId]
		-- The bar is decided by where the set's WEAPON pieces sit: weapons on one bar
		-- mean the set is completed on that bar (its body/jewelry pieces count on
		-- both). Only a set with no weapon pieces (or weapons on both bars) is "any".
		local bar, pieces, category
		if e.front > 0 and e.back == 0 then
			bar, category, pieces = "front", "front", e.body + e.front
		elseif e.back > 0 and e.front == 0 then
			bar, category, pieces = "back", "back", e.body + e.back
		else
			bar = "any"
			pieces = e.body + (e.front > e.back and e.front or e.back)
			if e.maxEquipped == 1 then
				category = "mythic"
			elseif e.maxEquipped <= 2 and slotsOnlyHeadShoulder(e.slotIds) then
				category = "monster"
			else
				category = "body"
			end
		end
		-- Canonical chest/head icon so a set looks the same in the loadout and in a
		-- condition row, but keep the real worn piece for the hover tooltip so it shows
		-- your actual equipped item (trait/enchant/set count), not a generic piece.
		local canonLink = QAT.conditions.SetItemLink(e.setId)
		entries[#entries + 1] = {
			setId = e.setId,
			name = e.name,
			icon = (canonLink and GetItemLinkIcon(canonLink)) or e.icon,
			link = e.link,
			pieces = pieces,
			bar = bar,
			category = category,
			slots = e.slots,
		}
	end
	return entries
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

-- Abilities currently slotted on both action bars, for the "add as condition"
-- helper. Slots 3-8 are the five actives plus the ultimate; the hotbar tells us
-- which weapon bar (primary = front, backup = back). Empty/non-ability slots skip.
---@return table[] entries { abilityId, name, icon, bar = "front"|"back", slot }
function QAT.conditions.ScanSlottedAbilities()
	local out = {}
	local bars = { { HOTBAR_CATEGORY_PRIMARY, "front" }, { HOTBAR_CATEGORY_BACKUP, "back" } }
	for _, hb in ipairs(bars) do
		local hotbar, bar = hb[1], hb[2]
		for slot = 3, 8 do
			if GetSlotType(slot, hotbar) == ACTION_TYPE_ABILITY then
				local id = GetSlotBoundId(slot, hotbar)
				if id and id > 0 then
					out[#out + 1] = {
						abilityId = id,
						name = GetAbilityName(id),
						icon = GetAbilityIcon(id),
						bar = bar,
						slot = slot,
					}
				end
			end
		end
	end
	return out
end

-- Grimoires (scribed skills) this character can scribe. We expose only the grimoire
-- cast id (the base ability), never the fused script ids, since which scripts a
-- grimoire allows is fixed by the game's compatibility table and not condition-worthy.
---@return table[] entries { craftedId, abilityId, name, icon }
function QAT.conditions.ScribedGrimoires()
	local out = {}
	if not (IsScribingEnabled and IsScribingEnabled()) then
		return out
	end
	for i = 1, GetNumCraftedAbilities() do
		local craftedId = GetCraftedAbilityIdAtIndex(i)
		if craftedId and craftedId > 0 and IsCraftedAbilityUnlocked(craftedId) then
			local abilityId = GetAbilityIdForCraftedAbilityId(craftedId)
			-- A 0 cast id means the grimoire isn't scribed/active on this character, so
			-- there's nothing to add as a condition — skip it.
			if abilityId and abilityId > 0 then
				out[#out + 1] = {
					craftedId = craftedId,
					abilityId = abilityId,
					name = GetCraftedAbilityDisplayName(craftedId),
					icon = GetCraftedAbilityIcon(craftedId),
				}
			end
		end
	end
	return out
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

	if load.curse then
		-- Affliction check (Vampire/Werewolf skill line), not the werewolf transform.
		-- Matches the stable CURSE_TYPE_* enum, never a localized name.
		local want = (load.curse == "vampire" and CURSE_TYPE_VAMPIRE)
			or (load.curse == "werewolf" and CURSE_TYPE_WEREWOLF)
		if (GetPlayerCurseType and GetPlayerCurseType() or CURSE_TYPE_NONE) ~= want then
			return false
		end
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
