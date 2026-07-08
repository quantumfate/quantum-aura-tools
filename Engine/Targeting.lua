-- Targeting: track an effect on a SPECIFIC target, or on an unknown-count SET of
-- targets, rather than on a fixed unit tag (player / reticleover / boss1-6).
--
-- A TargetSource yields a live, ordered list of bindings, each:
--   { key = <stable id within a fight>, name = <display name>, remaining, duration }
-- A dynamic grid (see Engine/GridLayout) consumes a source's snapshot each tick and
-- packs the bindings into its cells, so the on-screen list grows and shrinks with the
-- set of live targets. This is the substrate for the taunt tracker now, and for
-- group-member buff sharing (via LibGroupBroadcast) later.
--
-- Boss-name localization is deferred to a future library: `name` is taken straight
-- from the game here, and a catalog can later override it (and supply per-ability
-- durations) at the marked seam.

QAT.Targeting = QAT.Targeting or { sources = {} }

-- Reserved unit tag the dynamic feed uses. It is never a real ESO unit (DoesUnitExist is
-- false), so the phase engine's live-buff peeks safely find nothing — the source is the
-- only driver of these instances.
QAT.DYN_UNIT = "qatdyn"

--- Register a target source under a name. `source` must expose
--- `source:Snapshot(now) -> { {key,name,remaining,duration}, ... }`.
function QAT.Targeting.Register(name, source)
	QAT.Targeting.sources[name] = source
end

--- Ordered live bindings for a registered source (empty list if unknown).
---@param name string source name (e.g. "taunt")
---@param now number|nil frame time in seconds
---@return table[] bindings
function QAT.Targeting.Snapshot(name, now)
	local src = QAT.Targeting.sources[name]
	if not src then
		return {}
	end
	return src:Snapshot(now or GetFrameTimeSeconds()) or {}
end

-- The synthetic abilityId a source drives its instances with (the value is arbitrary but
-- stable; instances are fed directly, never via a real EVENT_EFFECT_CHANGED).
function QAT.Targeting.PrimaryAbilityId(name)
	local src = QAT.Targeting.sources[name]
	return (src and src.abilityId) or 1
end

-- Icon provided by a registered source (nil if none).
function QAT.Targeting.GetIcon(name)
	local src = QAT.Targeting.sources[name]
	return (src and src.icon) or nil
end

-- Registered source names (sorted), for the editor's source picker.
function QAT.Targeting.SourceNames()
	local out = {}
	for name in pairs(QAT.Targeting.sources) do
		out[#out + 1] = name
	end
	table.sort(out)
	return out
end

-- Stable synthetic abilityId from a source name (hash).
local function nameAbilityId(name)
	local h = 0
	for i = 1, #name do
		h = (h * 31 + string.byte(name, i)) % 99999
	end
	return 990000 + h
end

-- Register (or replace) a custom source from a Lua code string. The code, when called
-- with `code(now)`, must return an array of binding tables, each with:
--   { key = <unique id>, name = <display text>, remaining, duration, beginTime, endTime, stacks }
-- Custom sources are persisted in `sv.account.customSources` and restored on reload.
function QAT.Targeting.RegisterCode(name, code)
	local obj = {
		abilityId = nameAbilityId(name),
		_fromCode = true,
		_code = code,
	}
	function obj:Snapshot(now)
		local fn = loadstring("return " .. self._code)
		if not fn then
			return {}
		end
		local ok, result = pcall(fn, now or GetFrameTimeSeconds())
		if not ok or type(result) ~= "table" then
			return {}
		end
		return result
	end
	QAT.Targeting.sources[name] = obj
end

-- Unregister a custom source (built-in sources like "taunt" are protected).
function QAT.Targeting.Unregister(name)
	if name == "taunt" then
		return -- cannot unregister built-in sources
	end
	QAT.Targeting.sources[name] = nil
end

-- ===== Taunt source =====
--
-- Which enemies the player currently holds a taunt on. Detection is
-- ACTION_RESULT_TAUNT from a player source (language-independent, covers every taunt
-- ability). Keyed by the target's combat unitId, refreshed on every re-taunt.

-- Default taunt duration. ESO taunts last 15s; a future ability catalog can override
-- this per abilityId at the seam in OnTaunt.
local TAUNT_DURATION = 15

-- Example code string shown in the Source Manager as a teaching reference.
local TAUNT_EXAMPLE_CODE = [=[
-- Taunt source example: tracks enemies you are actively taunting.
-- Receives `now` (float) and returns an array of binding tables.
-- In the real source, `state` is maintained by combat events.
-- function(now)
--   local out = {}
--   for unitId, rec in pairs(state) do
--     local remaining = rec.expiresAt - now
--     if remaining <= 0 then
--       state[unitId] = nil
--     else
--       out[#out + 1] = {
--         key = unitId,           -- unique per-target id (stable in combat)
--         name = rec.name,        -- display name
--         remaining = remaining,  -- seconds until expiry
--         duration = rec.duration,
--         beginTime = rec.expiresAt - rec.duration,
--         endTime = rec.expiresAt,
--         stacks = 0,
--       }
--     end
--   end
--   table.sort(out, function(a, b) return a.remaining < b.remaining end)
--   return out
-- end
]=]

-- Reserved synthetic ability the taunt source drives its instances with.
local Taunt = {
	byId = {},
	abilityId = 990001,
	_exampleCode = TAUNT_EXAMPLE_CODE,
	icon = "esoui/art/icons/ability_warrior_010.dds",
}

-- Record (or refresh) a taunt on a target. `now` lets tests inject time.
function Taunt:OnTaunt(unitId, name, abilityId, now)
	if not unitId or unitId == 0 then
		return
	end
	-- Seam: a boss/ability catalog can later resolve a localized display name and a
	-- per-ability duration here instead of the raw combat-event values.
	local duration = TAUNT_DURATION
	local display = (name and name ~= "" and zo_strformat("<<1>>", name)) or ("#" .. tostring(unitId))
	self.byId[unitId] = { name = display, abilityId = abilityId, expiresAt = now + duration, duration = duration }
end

-- A target died / the fight reset: forget it.
function Taunt:Remove(unitId)
	if unitId then
		self.byId[unitId] = nil
	end
end

function Taunt:Clear()
	self.byId = {}
end

--- Check whether the reticleover matches this specific taunt instance by name.
--- Only the instance whose bound target is under the reticle lights up.
function Taunt:ReticleMatch(bindingKey)
	if not QAT.Targeting.reticleExists then
		return false
	end
	local reticleName = GetUnitName("reticleover")
	if not reticleName or reticleName == "" then
		return false
	end
	if bindingKey then
		local rec = self.byId[bindingKey]
		return rec ~= nil and rec.name == reticleName
	end
	return false
end

-- Prune expired entries, then return the live ones sorted soonest-expiry-first so the
-- most urgent re-taunt sits at the top of the list.
function Taunt:Snapshot(now)
	local out = {}
	for unitId, rec in pairs(self.byId) do
		local remaining = rec.expiresAt - now
		if remaining <= 0 then
			self.byId[unitId] = nil
		else
			out[#out + 1] = {
				key = unitId,
				name = rec.name,
				remaining = remaining,
				duration = rec.duration,
				beginTime = rec.expiresAt - rec.duration,
				endTime = rec.expiresAt,
				stacks = 0,
			}
		end
	end
	table.sort(out, function(a, b)
		return a.remaining < b.remaining
	end)
	return out
end

-- Inject synthetic taunt entries so the dynamic-grid render path can be verified
-- outside combat (see /qat taunt test). Not used in normal play.
function QAT.Targeting_TestTaunts(n)
	local now = GetFrameTimeSeconds()
	for i = 1, (n or 3) do
		Taunt:OnTaunt(900000 + i, "Test Dummy " .. i, 0, now)
		Taunt.byId[900000 + i].expiresAt = now + 8 + i * 4 -- staggered so they expire in order
	end
end

-- This client does not expose ACTION_RESULT_TAUNT as a global (it reads nil, which
-- silently disables a REGISTER_FILTER_COMBAT_RESULT filter). The taunt combat result is
-- 2392 — verified from the live combat log — so use that, honouring the named constant
-- if a future client restores it.
local ACTION_RESULT_TAUNT = rawget(_G, "ACTION_RESULT_TAUNT") or 2392

-- A taunt landed (event is already filtered to the taunt result): record it on the
-- target's combat unitId. No source filter yet — a taunt's source is often reported as an
-- effect proxy, not COMBAT_UNIT_TYPE_PLAYER; distinguishing "my" taunts from a co-tank's
-- comes with the group source. targetName/targetUnitId are args 9 and 16.
local function OnTauntEvent(_, _, _, _, _, _, _, _, targetName, _, _, _, _, _, _, targetUnitId, abilityId)
	Taunt:OnTaunt(targetUnitId, targetName, abilityId, GetFrameTimeSeconds())
end

local function OnCombatState(_, inCombat)
	if not inCombat then
		Taunt:Clear() -- taunts don't carry between fights
	end
end

function QAT.Targeting_Init()
	QAT.Targeting.Register("taunt", Taunt)

	-- Restore persisted custom sources.
	local custom = QAT.sv and QAT.sv.account and QAT.sv.account.customSources
	if custom then
		for name, code in pairs(custom) do
			QAT.Targeting.RegisterCode(name, code)
		end
	end

	-- ===== Reticle tracking =====

	-- Whether the reticle is currently over a valid unit (updated on EVENT_RETICLE_TARGET_CHANGED).
	QAT.Targeting.reticleExists = false

	--- Update cached reticle state. Call from the reticle-changed event.
	function QAT.Targeting.UpdateReticle()
		QAT.Targeting.reticleExists = DoesUnitExist("reticleover")
	end

	--- Check whether a reticle runtime condition (`stat = "reticle"`) is active for a lane/def pair.
	--- Source-driven dynamic trackers delegate to the source's ReticleMatch when present.
	function QAT.Targeting.IsReticleActive(lane, def)
		if not QAT.Targeting.reticleExists then
			return false
		end
		if def and def.source then
			local src = QAT.Targeting.sources[def.source]
			if src and src.ReticleMatch then
				return src:ReticleMatch(lane and lane.tracker and lane.tracker.boundKey)
			end
			return false
		end
		return true
	end

	local ev = QAT.name .. "_taunt"
	EVENT_MANAGER:RegisterForEvent(ev, EVENT_COMBAT_EVENT, OnTauntEvent)
	EVENT_MANAGER:AddFilterForEvent(ev, EVENT_COMBAT_EVENT, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_TAUNT)

	EVENT_MANAGER:RegisterForEvent(QAT.name .. "_taunt_combat", EVENT_PLAYER_COMBAT_STATE, OnCombatState)

	QAT.log.engine:Info("targeting up: taunt source registered (result=%d)", ACTION_RESULT_TAUNT)
end
