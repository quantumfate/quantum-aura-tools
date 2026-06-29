-- Runtime: owns all live trackers, the filtered effect subscriptions that drive
-- their phase transitions, and the single render tick that animates them.
--
-- Design principle (DESIGN.md): transitions come from filtered
-- EVENT_EFFECT_CHANGED (one registration per tracked ability id); the render
-- tick only advances/draws trackers that are in a timed phase. Idle and static
-- phases early-return in Tracker:Tick, so the per-frame cost scales with what's
-- actually counting down.

QAT.runtime = {
    trackers = {},     -- id -> Tracker
    list = {},         -- array of Trackers (tick order)
    byAbilityId = {},  -- abilityId -> { Tracker, ... }
}

local TICK_MS = 50 -- ~20 Hz

local function OnEffectChanged(_, changeType, _, _, unitTag, beginTime, endTime,
                              stackCount, _, _, _, _, _, _, _, abilityId)
    local listeners = QAT.runtime.byAbilityId[abilityId]
    if not listeners then return end
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
        EVENT_MANAGER:AddFilterForEvent(evName, EVENT_EFFECT_CHANGED,
            REGISTER_FILTER_ABILITY_ID, abilityId)
    end
end

-- Build Tracker objects from a list of defs (folders are walked for children;
-- they are pass-through containers with no display of their own).
local function BuildTrackers(defs)
    for _, def in ipairs(defs or {}) do
        if def.kind == "folder" then
            BuildTrackers(def.children)
        else
            local tracker = QAT.Tracker.New(def)
            QAT.runtime.trackers[def.id] = tracker
            table.insert(QAT.runtime.list, tracker)
            for id in pairs(tracker:AbilityIds()) do
                QAT.runtime.byAbilityId[id] = QAT.runtime.byAbilityId[id] or {}
                table.insert(QAT.runtime.byAbilityId[id], tracker)
            end
        end
    end
end

function QAT.Runtime_Init()
    BuildTrackers(QAT.sv.trackers)
    if QAT.Examples then
        BuildTrackers(QAT.Examples)
    end

    RegisterEffectFilters()

    for _, tracker in ipairs(QAT.runtime.list) do
        tracker:Start()
    end

    EVENT_MANAGER:UnregisterForUpdate(QAT.name .. "_tick")
    EVENT_MANAGER:RegisterForUpdate(QAT.name .. "_tick", TICK_MS, OnUpdate)

    if QAT.Log then
        QAT.Log("runtime up: %d tracker(s), %d ability filter(s)",
            #QAT.runtime.list, NonContiguousCount(QAT.runtime.byAbilityId))
    end
end
