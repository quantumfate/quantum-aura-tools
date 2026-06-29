-- Runtime: owns all live trackers, the event subscriptions that drive their
-- state, and the single render tick that animates the active ones.
--
-- The design principle (see DESIGN.md): state transitions come from filtered
-- EVENT_EFFECT_CHANGED (one registration per tracked ability id, near-zero idle
-- cost); the render tick only *draws* the trackers that are currently active.

QAT.runtime = {
    trackers = {},        -- id -> Tracker
    byAbilityId = {},     -- abilityId -> { Tracker, ... }
    active = {},          -- set of active Trackers (keyed by Tracker)
    ticking = false,
}

local TICK_MS = 50 -- render cadence for active countdowns (~20 Hz)

local function OnEffectChanged(_, changeType, _, _, unitTag, beginTime, endTime,
                              stackCount, _, _, _, _, _, _, _, abilityId)
    local listeners = QAT.runtime.byAbilityId[abilityId]
    if not listeners then return end

    for _, tracker in ipairs(listeners) do
        if tracker:Matches(unitTag, abilityId) then
            if changeType == EFFECT_RESULT_FADED then
                tracker:Deactivate()
                QAT.runtime.active[tracker] = nil
            else -- GAINED or UPDATED
                tracker:Activate(beginTime, endTime, stackCount)
                QAT.runtime.active[tracker] = true
            end
        end
    end
end

local function OnUpdate()
    local now = GetFrameTimeSeconds()
    local any = false
    for tracker in pairs(QAT.runtime.active) do
        if tracker:Tick(now) then
            any = true
        else
            QAT.runtime.active[tracker] = nil
        end
    end
    -- Keep the tick registered even when idle; it is cheap and avoids
    -- register/unregister churn. (Revisit if profiling says otherwise.)
    return any
end

-- Register one filtered EVENT_EFFECT_CHANGED per distinct tracked ability id.
local function RegisterEffectFilters()
    for abilityId in pairs(QAT.runtime.byAbilityId) do
        local evName = QAT.name .. "_eff_" .. abilityId
        EVENT_MANAGER:UnregisterForEvent(evName, EVENT_EFFECT_CHANGED)
        EVENT_MANAGER:RegisterForEvent(evName, EVENT_EFFECT_CHANGED, OnEffectChanged)
        EVENT_MANAGER:AddFilterForEvent(evName, EVENT_EFFECT_CHANGED,
            REGISTER_FILTER_ABILITY_ID, abilityId)
    end
end

-- Build Tracker objects from a flat list of defs (folders are walked for their
-- children; M1 renders trackers only, folders are pass-through containers).
local function BuildTrackers(defs)
    for _, def in ipairs(defs or {}) do
        if def.kind == "folder" then
            BuildTrackers(def.children)
        else
            local tracker = QAT.Tracker.New(def)
            QAT.runtime.trackers[def.id] = tracker
            for _, id in ipairs(tracker.abilityIds) do
                QAT.runtime.byAbilityId[id] = QAT.runtime.byAbilityId[id] or {}
                table.insert(QAT.runtime.byAbilityId[id], tracker)
            end
        end
    end
end

function QAT.Runtime_Init()
    -- Saved trackers + bundled examples (examples go away once the editor lands).
    BuildTrackers(QAT.sv.trackers)
    if QAT.Examples then
        BuildTrackers(QAT.Examples)
    end

    RegisterEffectFilters()

    EVENT_MANAGER:UnregisterForUpdate(QAT.name .. "_tick")
    EVENT_MANAGER:RegisterForUpdate(QAT.name .. "_tick", TICK_MS, OnUpdate)
    QAT.runtime.ticking = true

    if QAT.Log then
        local n = 0
        for _ in pairs(QAT.runtime.trackers) do n = n + 1 end
        QAT.Log("runtime up: %d tracker(s), %d ability filter(s)",
            n, NonContiguousCount(QAT.runtime.byAbilityId))
    end
end
