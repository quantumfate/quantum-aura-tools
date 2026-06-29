-- Runtime: owns all live trackers, the filtered effect subscriptions that drive
-- their phase transitions, and the single render tick that animates them.
--
-- Design principle (DESIGN.md): transitions come from filtered
-- EVENT_EFFECT_CHANGED (one registration per tracked ability id); the render
-- tick only advances/draws trackers that are in a timed phase. Idle and static
-- phases early-return in Tracker:Tick, so the per-frame cost scales with what's
-- actually counting down.

QAT.runtime = {
	trackers = {}, -- id -> Tracker
	list = {}, -- array of Trackers (tick order)
	byAbilityId = {}, -- abilityId -> { Tracker, ... }
}

local TICK_MS = 50 -- ~20 Hz

local function OnEffectChanged(
	_,
	changeType,
	_,
	_,
	unitTag,
	beginTime,
	endTime,
	stackCount,
	_,
	_,
	_,
	_,
	_,
	_,
	_,
	abilityId
)
	local listeners = QAT.runtime.byAbilityId[abilityId]
	if not listeners then
		return
	end
	QAT.log.runtime:Verbose(
		"effect %d on %s change=%d (%d listener(s))",
		abilityId,
		tostring(unitTag),
		changeType,
		#listeners
	)
	for _, tracker in ipairs(listeners) do
		tracker:OnEffect(unitTag, abilityId, changeType, beginTime, endTime, stackCount)
	end
end

local function OnUpdate()
	local now = GetFrameTimeSeconds()
	for _, tracker in ipairs(QAT.runtime.list) do
		tracker:Tick(now)
	end
end

-- One filtered EVENT_EFFECT_CHANGED per distinct tracked ability id.
local function RegisterEffectFilters()
	for abilityId in pairs(QAT.runtime.byAbilityId) do
		local evName = QAT.name .. "_eff_" .. abilityId
		EVENT_MANAGER:UnregisterForEvent(evName, EVENT_EFFECT_CHANGED)
		EVENT_MANAGER:RegisterForEvent(evName, EVENT_EFFECT_CHANGED, OnEffectChanged)
		EVENT_MANAGER:AddFilterForEvent(evName, EVENT_EFFECT_CHANGED, REGISTER_FILTER_ABILITY_ID, abilityId)
	end
end

-- Build Tracker objects from a list of defs. Folders are pass-through containers
-- (no display); their load defs cascade to children via the loadChain.
local function BuildTrackers(defs, parentLoads)
	for _, def in ipairs(defs or {}) do
		if def.enabled == false then
			-- A disabled tracker or folder is skipped entirely (a disabled folder
			-- disables its whole subtree). Its controls were hidden before rebuild.
		elseif def.kind == "folder" then
			local childLoads = QAT.util.DeepCopy(parentLoads)
			if def.load then
				table.insert(childLoads, def.load)
			end
			BuildTrackers(def.children, childLoads)
		else
			local chain = QAT.util.DeepCopy(parentLoads)
			if def.load then
				table.insert(chain, def.load)
			end

			local tracker = QAT.Tracker.New(def, chain)
			QAT.runtime.trackers[def.id] = tracker
			table.insert(QAT.runtime.list, tracker)
			for id in pairs(tracker:AbilityIds()) do
				QAT.runtime.byAbilityId[id] = QAT.runtime.byAbilityId[id] or {}
				table.insert(QAT.runtime.byAbilityId[id], tracker)
			end
		end
	end
end

-- Re-evaluate every tracker's load conditions.
function QAT.Runtime_RefreshLoad()
	for _, tracker in ipairs(QAT.runtime.list) do
		tracker:RefreshLoad()
	end
end

-- Load conditions are checked on the events that can change them (not polled).
-- A short debounce coalesces bursts (e.g. swapping a full gear set).
local loadCheckPending = false
local function RequestLoadRecompute()
	if loadCheckPending then
		return
	end
	loadCheckPending = true
	zo_callLater(function()
		loadCheckPending = false
		QAT.log.runtime:Debug("load recompute (debounced)")
		QAT.Runtime_RefreshLoad()
	end, 100)
end

local function RegisterLoadEvents()
	local events = {
		EVENT_SKILLS_FULL_UPDATE,
		EVENT_ACTION_SLOTS_ALL_HOTBARS_UPDATED, -- skill slotted in/out
		EVENT_ACTIVE_WEAPON_PAIR_CHANGED, -- bar swap (current-bar set mode)
		EVENT_INVENTORY_SINGLE_SLOT_UPDATE, -- gear changes
		EVENT_PLAYER_ACTIVATED, -- zone load
		EVENT_BOSSES_CHANGED, -- boss conditions
		EVENT_PLAYER_COMBAT_STATE, -- in-combat conditions
	}
	for _, ev in ipairs(events) do
		EVENT_MANAGER:RegisterForEvent(QAT.name .. "_load", ev, RequestLoadRecompute)
	end
	EVENT_MANAGER:AddFilterForEvent(
		QAT.name .. "_load",
		EVENT_INVENTORY_SINGLE_SLOT_UPDATE,
		REGISTER_FILTER_INVENTORY_UPDATE_REASON,
		INVENTORY_UPDATE_REASON_DEFAULT
	)
end

function QAT.Runtime_Init()
	BuildTrackers(QAT.sv.trackers, {})

	RegisterEffectFilters()
	RegisterLoadEvents()

	for _, tracker in ipairs(QAT.runtime.list) do
		tracker:Start() -- evaluates load conditions, enters initial phase if loaded
	end

	EVENT_MANAGER:UnregisterForUpdate(QAT.name .. "_tick")
	EVENT_MANAGER:RegisterForUpdate(QAT.name .. "_tick", TICK_MS, OnUpdate)

	QAT.log.runtime:Info(
		"runtime up: %d tracker(s), %d ability filter(s)",
		#QAT.runtime.list,
		NonContiguousCount(QAT.runtime.byAbilityId)
	)
end

-- Rebuild all live trackers from the current saved defs. Used when the editor
-- changes a def, so the on-screen trackers update without a reload. Display
-- controls are reused by name (see Display.Create), so this neither leaks nor
-- collides; it only swaps the in-memory Tracker objects and event filters.
local function rebuildAll()
	-- Hide every current phase control so removed trackers/phases don't linger.
	for _, tracker in ipairs(QAT.runtime.list) do
		for _, phase in pairs(tracker.phases) do
			phase.control:SetState(false)
		end
	end

	-- Drop the per-ability effect subscriptions before rebuilding the index.
	for abilityId in pairs(QAT.runtime.byAbilityId) do
		EVENT_MANAGER:UnregisterForEvent(QAT.name .. "_eff_" .. abilityId, EVENT_EFFECT_CHANGED)
	end

	QAT.runtime.trackers = {}
	QAT.runtime.list = {}
	QAT.runtime.byAbilityId = {}

	BuildTrackers(QAT.sv.trackers, {})
	RegisterEffectFilters()
	for _, tracker in ipairs(QAT.runtime.list) do
		tracker:Start()
	end
	QAT.log.runtime:Debug("runtime rebuilt: %d tracker(s)", #QAT.runtime.list)
end

-- Coalesce rapid edits (e.g. typing) into one rebuild.
local rebuildPending = false
function QAT.Runtime_RequestRebuild()
	if rebuildPending then
		return
	end
	rebuildPending = true
	zo_callLater(function()
		rebuildPending = false
		QAT.Safe("runtime rebuild", rebuildAll)
	end, 80)
end

-- A def changed in the editor: rebuild the affected runtime. (A full rebuild is
-- simple and cheap at these counts; per-tracker rebuild can come later.)
CALLBACK_MANAGER:RegisterCallback("QAT_TrackerChanged", function()
	if QAT.runtime then
		QAT.Runtime_RequestRebuild()
	end
end)
