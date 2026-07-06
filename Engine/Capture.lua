-- Effect Aggregator — capture engine.
--
-- A window into ESO's live effect/combat stream, aggregated into deduped rows the
-- authoring UI harvests from. This module owns only the data: the two feeds, the
-- source/target resolution, the in-memory store and its persistence. The window
-- (Editor-style TLW) is a separate consumer that reads QAT.capture.* and listens
-- for the "QAT_CaptureChanged" callback.
--
-- Two feeds, fused into one row (see AGGREGATOR.md):
--   * combat feed  (EVENT_COMBAT_EVENT, effect-gained results) — the identity /
--     relationship spine: it alone carries sourceName, so it establishes who cast
--     what on whom.
--   * effect feed  (EVENT_EFFECT_CHANGED, unit-filtered player + boss1-6, plus a
--     seed-sweep of GetUnitBuffInfo) — enrichment: duration/stacks/effectType and,
--     crucially, passives that never emit a combat event.
--
-- A row's identity is frozen at ingest: sourceRole/targetRole/zoneId are resolved
-- once, while the units are live, because the viewer is detached in time from the
-- capture (boss1-6 tags are long gone by the time the window is read).

QAT.capture = {
	running = false, -- feeds registered? (mirrors sv.account.backgroundCapture)
	frozen = false, -- VIEW pause only; capture keeps running when true
	store = {}, -- key -> row (the live session catch)
	list = {}, -- rows in stable insertion order (never resorted under the user)
	byAbilityTarget = {}, -- "abilityId\ttargetTag" -> { row, ... }, for feed fusion
	observations = 0, -- total ingests this session (unique = #list)
	everCaptured = false, -- has anything ever been captured this session/catch?
	currentZoneId = 0, -- where capture is happening now (status line)
}

local EV_COMBAT_GAINED = QAT.name .. "_cap_cg"
local EV_COMBAT_GAINED_DUR = QAT.name .. "_cap_cgd"
local EV_EFFECT_PREFIX = QAT.name .. "_cap_eff_"
-- reticleover watches whatever you're targeting (a trial dummy or any non-frame
-- enemy that never gets a boss1-6 slot); name-keying merges it with boss1-6 when
-- you happen to be targeting the actual boss.
local CAPTURE_UNITS = { "player", "reticleover", "boss1", "boss2", "boss3", "boss4", "boss5", "boss6" }

-- ---------------------------------------------------------------------------
-- Resolution (all frozen at ingest)
-- ---------------------------------------------------------------------------

-- Target tag -> coarse role. Intake is scoped to self + the enemy you're fighting
-- (boss frame or current hostile target); friendly/neutral reticle targets and
-- everything else are rejected upstream. "me" and "boss" are the only stored roles.
local function targetRoleOf(tag)
	if tag == "player" then
		return "me"
	end
	if tag and tag:find("^boss%d") then
		return "boss"
	end
	if tag and tag:find("^group%d") then
		return "group"
	end
	-- Your current target when it isn't on a boss frame (e.g. a trial dummy): count
	-- it as the "boss" for bucketing, but only when it's an attackable enemy.
	if tag == "reticleover" and DoesUnitExist("reticleover") and IsUnitAttackable("reticleover") then
		return "boss"
	end
	return "other"
end

-- Resolve a name to a friendly group unit tag (group1-12), excluding the player's own
-- slot. Group-applied auras (e.g. a buff you put on your group) surface only through the
-- combat feed, where the player is the source — the effect feed can't read allies' buffs.
local function groupTagForName(name)
	if not name or name == "" then
		return nil
	end
	for i = 1, GetGroupSize() do
		local t = "group" .. i
		if DoesUnitExist(t) and not AreUnitsEqual(t, "player") and GetUnitName(t) == name then
			return t
		end
	end
	return nil
end

-- Does this name currently belong to a boss frame? (Distinguishes the boss from a
-- trash add sharing the enemy sourceType.)
local function nameIsLiveBoss(name)
	if not name or name == "" then
		return false
	end
	for i = 1, 6 do
		local bt = "boss" .. i
		if DoesUnitExist(bt) and GetUnitName(bt) == name then
			return true
		end
	end
	return false
end

-- Authoritative sourceRole resolver (supersedes the handoff spec's enum-only cut).
-- Name-match first, then the sourceType enum so environmental boss mechanics (empty
-- sourceName, COMBAT_UNIT_TYPE_NONE) still land in Boss→Self, then castByPlayer, and
-- finally: an unknown-source buff sitting on you is treated as self-noise (it
-- self-corrects to group/boss if it later refreshes through a feed that carries a
-- real source). The seed-sweep has only castByPlayer + targetIsMe to go on.
---@param sourceName string?
---@param sourceType integer? COMBAT_UNIT_TYPE_*
---@param castByPlayer boolean?
---@param targetIsMe boolean?
---@return string role  "self" | "boss" | "group" | "other"
local function sourceRoleOf(sourceName, sourceType, castByPlayer, targetIsMe)
	if sourceName and sourceName ~= "" then
		if sourceName == GetUnitName("player") then
			return "self"
		end
		if nameIsLiveBoss(sourceName) then
			return "boss"
		end
	end
	if sourceType == COMBAT_UNIT_TYPE_PLAYER then
		return "self"
	end
	if sourceType == COMBAT_UNIT_TYPE_GROUP then
		return "group"
	end
	-- Environmental / untyped source while fighting: treat as a boss mechanic.
	if sourceType == COMBAT_UNIT_TYPE_NONE and IsUnitInCombat("player") then
		return "boss"
	end
	if castByPlayer then
		return "self"
	end
	-- No source info at all (typical for the passive seed-sweep): a buff on you is
	-- your own standing noise until a richer observation says otherwise.
	if targetIsMe then
		return "self"
	end
	return "other"
end

-- The relationship bucket code used for grouping/filtering (sourceRole → targetRole).
local function bucketOf(sourceRole, targetRole)
	if targetRole == "me" then
		if sourceRole == "boss" then
			return "bs"
		end -- Boss → Self (the money bucket)
		if sourceRole == "self" then
			return "ss"
		end -- Self → Self (passives; noise)
		if sourceRole == "group" then
			return "gs"
		end -- Group → Self
		return "os" -- Other → Self
	elseif targetRole == "boss" then
		if sourceRole == "self" then
			return "sb"
		end -- Self → Boss (your debuffs)
		return "xb" -- anything else → Boss
	elseif targetRole == "group" then
		if sourceRole == "self" then
			return "sg"
		end -- Self → Group (auras/buffs you apply to your group)
		if sourceRole == "group" then
			return "gg"
		end -- Group → Group (a groupmate buffing the group)
		return "xg" -- anything else → Group
	end
	return "xx"
end

local function currentZoneId()
	return GetZoneId(GetUnitZoneIndex("player")) or 0
end

-- ---------------------------------------------------------------------------
-- Store
-- ---------------------------------------------------------------------------

-- Identity is keyed by resolved NAMES, never by the raw slot tag: boss1-6 slots are
-- assignment-order and shuffle between pulls, which would fragment the same effect on
-- the same boss into separate rows. The name (GetUnitName) is stable within a locale.
local function keyOf(abilityId, sourceName, targetName, zoneId)
	return abilityId .. "\t" .. (sourceName or "") .. "\t" .. (targetName or "") .. "\t" .. (zoneId or 0)
end

local function atIndex(abilityId, targetName)
	return abilityId .. "\t" .. (targetName or "")
end

-- A shallow, self-describing copy of a row safe to store in SavedVars (drops the live
-- fusion/seed bookkeeping). Used for both the persisted library records and favourites.
local function frozenCopy(row)
	return {
		key = row.key,
		abilityId = row.abilityId,
		name = row.name,
		sourceName = row.sourceName,
		sourceType = row.sourceType,
		sourceRole = row.sourceRole,
		targetTag = row.targetTag,
		targetName = row.targetName,
		targetRole = row.targetRole,
		bucket = row.bucket,
		zoneId = row.zoneId,
		effectType = row.effectType,
		timed = row.timed,
		castByPlayer = row.castByPlayer,
		buffSlot = row.buffSlot,
		maxStacks = row.maxStacks,
		seenCount = row.seenCount,
		firstSeen = row.firstSeen,
		lastSeen = row.lastSeen,
		icon = row.icon,
		favourited = row.favourited == true,
	}
end

-- Persist-by-default: every captured row is written to the standing library
-- (sv.capture.records) so the catch survives reloads. A game setting can turn this
-- off; favourites persist regardless via their own bucket.
local function persistEnabled()
	return not QAT.sv or QAT.sv.account.persistCapture ~= false
end

-- Rows touched since the last notify, flushed to the library in one batch on the
-- coalesced tick (so a busy fight writes SavedVars once per cycle, not per event).
local dirtyRows = {}
local function markDirty(row)
	dirtyRows[row] = true
end
local function flushPersist()
	if not persistEnabled() then
		dirtyRows = {}
		return
	end
	local records = QAT.sv.capture.records
	if records then
		for row in pairs(dirtyRows) do
			records[row.key] = frozenCopy(row)
		end
	end
	dirtyRows = {}
end

-- Coalesced change notification so a busy fight doesn't fire per-event.
local changePending = false
local function notifyChanged()
	if changePending then
		return
	end
	changePending = true
	zo_callLater(function()
		changePending = false
		flushPersist()
		CALLBACK_MANAGER:FireCallbacks("QAT_CaptureChanged")
	end, 120)
end

-- Merge one observation into the store. `obs` is a normalized field bag; either
-- feed fills what it knows and this upserts by identity, enriching an existing row
-- rather than duplicating it.
---@param obs table
local function ingest(obs)
	local abilityId = obs.abilityId
	if not abilityId or abilityId == 0 then
		return
	end
	if QAT.sv and QAT.sv.capture.ignored[abilityId] then
		return
	end

	local targetRole = targetRoleOf(obs.targetTag)
	if targetRole == "other" then
		return -- out of intake scope (self, bosses, and group members)
	end

	-- Resolve the target's stable name once (never the shuffling slot tag).
	local targetName = obs.targetName
	if (not targetName or targetName == "") and obs.targetTag and DoesUnitExist(obs.targetTag) then
		targetName = GetUnitName(obs.targetTag)
	end

	QAT.capture.observations = QAT.capture.observations + 1
	QAT.capture.everCaptured = true
	local now = GetTimeStamp()

	-- Fusion: an effect-feed observation (no sourceName) enriches the combat-feed
	-- row(s) for the same ability+target instead of creating a sourceless twin.
	if not obs.sourceName or obs.sourceName == "" then
		local existing = QAT.capture.byAbilityTarget[atIndex(abilityId, targetName)]
		if existing and #existing > 0 then
			for _, row in ipairs(existing) do
				row.seenCount = row.seenCount + 1
				row.lastSeen = now
				if obs.stacks and obs.stacks > (row.maxStacks or 0) then
					row.maxStacks = obs.stacks
				end
				if obs.timed ~= nil then
					row.timed = obs.timed
				end
				if obs.effectType then
					row.effectType = obs.effectType
				end
				if obs.buffSlot then
					row.buffSlot = obs.buffSlot
				end
				if obs.castByPlayer ~= nil then
					row.castByPlayer = obs.castByPlayer
				end
				markDirty(row)
			end
			notifyChanged()
			return
		end
	end

	local zoneId = obs.zoneId or QAT.capture.currentZoneId
	local sourceRole = sourceRoleOf(obs.sourceName, obs.sourceType, obs.castByPlayer, targetRole == "me")
	local key = keyOf(abilityId, obs.sourceName, targetName, zoneId)
	local row = QAT.capture.store[key]

	if row then
		row.seeded = nil -- a live sighting: no longer a library-only placeholder
		row.seenCount = row.seenCount + 1
		row.lastSeen = now
		if obs.stacks and obs.stacks > (row.maxStacks or 0) then
			row.maxStacks = obs.stacks
		end
		if obs.timed ~= nil then
			row.timed = obs.timed
		end
		if obs.effectType then
			row.effectType = obs.effectType
		end
		if obs.buffSlot then
			row.buffSlot = obs.buffSlot
		end
		markDirty(row)
		notifyChanged()
		return
	end

	row = {
		key = key,
		abilityId = abilityId,
		name = GetAbilityName(abilityId),
		icon = GetAbilityIcon(abilityId),
		sourceName = obs.sourceName or "",
		sourceType = obs.sourceType,
		sourceRole = sourceRole,
		targetTag = obs.targetTag,
		targetName = targetName,
		targetRole = targetRole,
		bucket = bucketOf(sourceRole, targetRole),
		zoneId = zoneId,
		effectType = obs.effectType,
		timed = obs.timed,
		castByPlayer = obs.castByPlayer,
		buffSlot = obs.buffSlot,
		maxStacks = obs.stacks or 0,
		seenCount = 1,
		firstSeen = now,
		lastSeen = now,
		favourited = false,
	}
	QAT.capture.store[key] = row
	table.insert(QAT.capture.list, row)

	local ati = atIndex(abilityId, targetName)
	QAT.capture.byAbilityTarget[ati] = QAT.capture.byAbilityTarget[ati] or {}
	table.insert(QAT.capture.byAbilityTarget[ati], row)

	markDirty(row)
	notifyChanged()
end

-- ---------------------------------------------------------------------------
-- Feeds
-- ---------------------------------------------------------------------------

-- Effect-gained results carry a caster (sourceName) with the buff/debuff — the
-- identity/relationship spine. Damage/heal ticks are filtered out at registration.
local function onCombatEvent(_, _, _, _, _, _, sourceName, sourceType, targetName, _, _, _, _, _, _, _, abilityId)
	-- Resolve the target name to one of our in-scope unit tags.
	local targetTag
	if targetName == GetUnitName("player") then
		targetTag = "player"
	else
		for i = 1, 6 do
			local bt = "boss" .. i
			if DoesUnitExist(bt) and GetUnitName(bt) == targetName then
				targetTag = bt
				break
			end
		end
		-- A groupmate you applied the effect to (e.g. a group buff / aura).
		if not targetTag then
			targetTag = groupTagForName(targetName)
		end
		-- Fall back to the current target (dummy / non-frame enemy).
		if not targetTag and DoesUnitExist("reticleover") and GetUnitName("reticleover") == targetName then
			targetTag = "reticleover"
		end
	end
	if not targetTag then
		return
	end

	ingest({
		abilityId = abilityId,
		sourceName = sourceName,
		sourceType = sourceType,
		targetTag = targetTag,
		targetName = targetName, -- authoritative from the event; stable across pulls
		zoneId = QAT.capture.currentZoneId,
	})
end

local function onEffectChanged(
	_,
	changeType,
	effectSlot,
	_,
	unitTag,
	beginTime,
	endTime,
	stackCount,
	_,
	_,
	effectType,
	_,
	_,
	_,
	_,
	abilityId,
	sourceType
)
	if changeType == EFFECT_RESULT_FADED then
		return -- we aggregate presence, not uptime; a fade adds no new identity
	end
	ingest({
		abilityId = abilityId,
		targetTag = unitTag,
		sourceType = sourceType,
		effectType = effectType,
		timed = (endTime or 0) > (beginTime or 0),
		stacks = stackCount,
		buffSlot = effectSlot,
		zoneId = QAT.capture.currentZoneId,
	})
end

-- Sweep already-active buffs on the in-scope units. The only way to see passives,
-- which never fire EVENT_EFFECT_CHANGED mid-session.
function QAT.Capture_SeedSweep()
	if not QAT.capture.running then
		return
	end
	for _, unit in ipairs(CAPTURE_UNITS) do
		if DoesUnitExist(unit) then
			for i = 1, GetNumBuffs(unit) do
				local _, started, ending, buffSlot, stacks, _, _, effectType, _, _, abilityId, _, castByPlayer =
					GetUnitBuffInfo(unit, i)
				if abilityId then
					ingest({
						abilityId = abilityId,
						targetTag = unit,
						effectType = effectType,
						timed = (ending or 0) > (started or 0),
						stacks = stacks,
						buffSlot = buffSlot,
						castByPlayer = castByPlayer,
						zoneId = QAT.capture.currentZoneId,
					})
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

local function registerFeeds()
	-- Combat feed: two effect-gained results, filtered at registration to keep the
	-- handler off the damage-tick firehose.
	EVENT_MANAGER:RegisterForEvent(EV_COMBAT_GAINED, EVENT_COMBAT_EVENT, onCombatEvent)
	EVENT_MANAGER:AddFilterForEvent(
		EV_COMBAT_GAINED,
		EVENT_COMBAT_EVENT,
		REGISTER_FILTER_COMBAT_RESULT,
		ACTION_RESULT_EFFECT_GAINED
	)
	EVENT_MANAGER:RegisterForEvent(EV_COMBAT_GAINED_DUR, EVENT_COMBAT_EVENT, onCombatEvent)
	EVENT_MANAGER:AddFilterForEvent(
		EV_COMBAT_GAINED_DUR,
		EVENT_COMBAT_EVENT,
		REGISTER_FILTER_COMBAT_RESULT,
		ACTION_RESULT_EFFECT_GAINED_DURATION
	)

	-- Effect feed: one unit-filtered registration per in-scope unit tag, no ability
	-- filter (we want everything on these units).
	for _, unit in ipairs(CAPTURE_UNITS) do
		local ev = EV_EFFECT_PREFIX .. unit
		EVENT_MANAGER:RegisterForEvent(ev, EVENT_EFFECT_CHANGED, onEffectChanged)
		EVENT_MANAGER:AddFilterForEvent(ev, EVENT_EFFECT_CHANGED, REGISTER_FILTER_UNIT_TAG, unit)
	end

	-- New bosses appearing = sweep them for already-active auras.
	EVENT_MANAGER:RegisterForEvent(QAT.name .. "_cap_boss", EVENT_BOSSES_CHANGED, function()
		QAT.capture.currentZoneId = currentZoneId()
		QAT.Safe("capture seed-sweep (bosses)", QAT.Capture_SeedSweep)
	end)

	-- New reticle target = sweep it, so debuffs already on it (that never fire an
	-- effect-changed while you watch) are captured the moment you select it.
	EVENT_MANAGER:RegisterForEvent(QAT.name .. "_cap_ret", EVENT_RETICLE_TARGET_CHANGED, function()
		QAT.Safe("capture seed-sweep (target)", QAT.Capture_SeedSweep)
	end)
end

local function unregisterFeeds()
	EVENT_MANAGER:UnregisterForEvent(EV_COMBAT_GAINED, EVENT_COMBAT_EVENT)
	EVENT_MANAGER:UnregisterForEvent(EV_COMBAT_GAINED_DUR, EVENT_COMBAT_EVENT)
	for _, unit in ipairs(CAPTURE_UNITS) do
		EVENT_MANAGER:UnregisterForEvent(EV_EFFECT_PREFIX .. unit, EVENT_EFFECT_CHANGED)
	end
	EVENT_MANAGER:UnregisterForEvent(QAT.name .. "_cap_ret", EVENT_RETICLE_TARGET_CHANGED)
	EVENT_MANAGER:UnregisterForEvent(QAT.name .. "_cap_boss", EVENT_BOSSES_CHANGED)
end

--- Start the background feeds. Idempotent. Persists the on-state so it survives a
--- reload (capture is decoupled from the window).
function QAT.Capture_Start()
	if QAT.capture.running then
		return
	end
	QAT.capture.running = true
	QAT.sv.account.backgroundCapture = true
	QAT.capture.currentZoneId = currentZoneId()
	registerFeeds()
	QAT.Capture_SeedSweep()
	QAT.log.capture:Info("capture started (zone %d)", QAT.capture.currentZoneId)
	notifyChanged()
end

--- Stop the feeds; the catch is kept (static/frozen view still readable).
function QAT.Capture_Stop()
	if not QAT.capture.running then
		return
	end
	QAT.capture.running = false
	QAT.sv.account.backgroundCapture = false
	unregisterFeeds()
	QAT.log.capture:Info("capture stopped (%d unique rows)", #QAT.capture.list)
	notifyChanged()
end

function QAT.Capture_Toggle()
	if QAT.capture.running then
		QAT.Capture_Stop()
	else
		QAT.Capture_Start()
	end
end

--- Freeze/unfreeze the VIEW only (never affects capture). The window reads this.
function QAT.Capture_SetFrozen(on)
	QAT.capture.frozen = on and true or false
	notifyChanged()
end

--- Drop the current aggregation (keeps favourited rows, which are re-seeded).
function QAT.Capture_Clear()
	QAT.capture.store = {}
	QAT.capture.list = {}
	QAT.capture.byAbilityTarget = {}
	QAT.capture.observations = 0
	QAT.capture.everCaptured = false
	QAT.Capture_SeedLibrary()
	QAT.log.capture:Debug("catch cleared")
	notifyChanged()
end

--- Forget the entire persisted library (all recorded rows). Favourites are kept
--- (they have their own bucket); the live catch is rebuilt from what remains.
function QAT.Capture_ForgetLibrary()
	QAT.sv.capture.records = {}
	dirtyRows = {}
	QAT.Capture_Clear()
	QAT.log.capture:Info("persisted capture library cleared")
end

-- ---------------------------------------------------------------------------
-- Favourite / ignore (persisted)
-- ---------------------------------------------------------------------------

--- Promote a row to the persisted favourites (survives reloads; floats to the top).
function QAT.Capture_Favourite(row)
	if not row then
		return
	end
	row.favourited = true
	QAT.sv.capture.favourites[row.key] = frozenCopy(row)
	-- Keep the library record's flag in step (create it if persistence had it absent).
	if persistEnabled() then
		QAT.sv.capture.records[row.key] = frozenCopy(row)
	elseif QAT.sv.capture.records[row.key] then
		QAT.sv.capture.records[row.key].favourited = true
	end
	notifyChanged()
end

function QAT.Capture_Unfavourite(row)
	if not row then
		return
	end
	row.favourited = false
	QAT.sv.capture.favourites[row.key] = nil
	if QAT.sv.capture.records[row.key] then
		QAT.sv.capture.records[row.key].favourited = false
	end
	-- A library-only placeholder with nothing persisting it (records off / never
	-- recorded) has nothing left once unfavourited, so drop it rather than leave a dead,
	-- dataless entry. A row with live data this session, or a standing library record,
	-- stays.
	if row.seeded and not QAT.sv.capture.records[row.key] then
		QAT.capture.store[row.key] = nil
		local list = QAT.capture.list
		for i = #list, 1, -1 do
			if list[i] == row then
				table.remove(list, i)
			end
		end
		local ati = atIndex(row.abilityId, row.targetName)
		local bucket = QAT.capture.byAbilityTarget[ati]
		if bucket then
			for i = #bucket, 1, -1 do
				if bucket[i] == row then
					table.remove(bucket, i)
				end
			end
		end
	end
	notifyChanged()
end

--- Permanently suppress an ability id and drop any rows already holding it.
function QAT.Capture_Ignore(abilityId)
	if not abilityId then
		return
	end
	QAT.sv.capture.ignored[abilityId] = true
	local kept = {}
	for _, row in ipairs(QAT.capture.list) do
		if row.abilityId == abilityId then
			QAT.capture.store[row.key] = nil
			QAT.capture.byAbilityTarget[atIndex(abilityId, row.targetName)] = nil
			QAT.sv.capture.records[row.key] = nil -- purge from the persisted library too
			dirtyRows[row] = nil
		else
			table.insert(kept, row)
		end
	end
	QAT.capture.list = kept
	QAT.log.capture:Debug("ignored ability %d", abilityId)
	notifyChanged()
end

function QAT.Capture_Unignore(abilityId)
	if abilityId then
		QAT.sv.capture.ignored[abilityId] = nil
		notifyChanged()
	end
end

-- Insert one persisted record back into the live store as a library placeholder (until
-- a live sighting upgrades it). No-op if already present or the ability is ignored.
local function seedRow(key, saved, favourited)
	if QAT.capture.store[key] or QAT.sv.capture.ignored[saved.abilityId] then
		return
	end
	local row = QAT.util.DeepCopy(saved)
	row.favourited = favourited and true or false
	row.seeded = true -- library placeholder until a live sighting arrives
	-- Recompute from the id so the icon (and name) are always valid, even for records
	-- saved before icons were persisted.
	row.icon = GetAbilityIcon(saved.abilityId)
	if not saved.name or saved.name == "" then
		row.name = GetAbilityName(saved.abilityId)
	end
	QAT.capture.store[key] = row
	table.insert(QAT.capture.list, row)
	local ati = atIndex(row.abilityId, row.targetName)
	QAT.capture.byAbilityTarget[ati] = QAT.capture.byAbilityTarget[ati] or {}
	table.insert(QAT.capture.byAbilityTarget[ati], row)
end

-- Load the persisted library (all recorded rows + favourites) back into the live store
-- so it shows before/without any fresh capture this session.
function QAT.Capture_SeedLibrary()
	local favs = QAT.sv.capture.favourites or {}
	for key, saved in pairs(QAT.sv.capture.records or {}) do
		seedRow(key, saved, favs[key] ~= nil)
	end
	-- Favourites saved on an install that predates the records bucket (or with records
	-- disabled) still seed, so nothing favourited is ever lost.
	for key, saved in pairs(favs) do
		seedRow(key, saved, true)
	end
end

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------

function QAT.Capture_Init()
	QAT.capture.currentZoneId = currentZoneId()
	QAT.Capture_SeedLibrary()
	-- Capture is decoupled from the window: if it was left on, resume on load.
	if QAT.sv.account.backgroundCapture then
		QAT.Capture_Start()
	end
	QAT.log.capture:Info(
		"capture engine ready (%d recorded, %d favourited)",
		NonContiguousCount(QAT.sv.capture.records),
		NonContiguousCount(QAT.sv.capture.favourites)
	)
end
