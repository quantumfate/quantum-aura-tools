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

-- Registered source names (sorted), for the editor's source picker.
function QAT.Targeting.SourceNames()
	local out = {}
	for name in pairs(QAT.Targeting.sources) do
		out[#out + 1] = name
	end
	table.sort(out)
	return out
end

-- ===== Taunt source =====
--
-- Which enemies the player currently holds a taunt on. Detection is
-- ACTION_RESULT_TAUNT from a player source (language-independent, covers every taunt
-- ability). Keyed by the target's combat unitId, refreshed on every re-taunt.

-- Default taunt duration. ESO taunts last 15s; a future ability catalog can override
-- this per abilityId at the seam in OnTaunt.
local TAUNT_DURATION = 15

-- Reserved synthetic ability the taunt source drives its instances with.
local Taunt = { byId = {}, abilityId = 990001 }

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

	local ev = QAT.name .. "_taunt"
	EVENT_MANAGER:RegisterForEvent(ev, EVENT_COMBAT_EVENT, OnTauntEvent)
	EVENT_MANAGER:AddFilterForEvent(ev, EVENT_COMBAT_EVENT, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_TAUNT)

	EVENT_MANAGER:RegisterForEvent(QAT.name .. "_taunt_combat", EVENT_PLAYER_COMBAT_STATE, OnCombatState)

	QAT.log.engine:Info("targeting up: taunt source registered (result=%d)", ACTION_RESULT_TAUNT)
end
