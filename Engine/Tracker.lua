-- Tracker object (M1: single phase).
--
-- A Tracker wraps an authored def, owns one display control, and holds runtime
-- state (active / expiresAt / duration / stacks). In M2 the single implicit
-- phase here becomes the default of a phase list.

QAT.Tracker = {}
QAT.Tracker.__index = QAT.Tracker

-- def shape (M1):
--   { id, kind="tracker", display="bar"|"icon"|"text", name,
--     abilityIds = { ... }, unit = "player"|"reticleover",
--     effectType = "buff"|"debuff", + styling fields (see Display.lua) }
function QAT.Tracker.New(def)
    local self = setmetatable({}, QAT.Tracker)
    self.def = def
    self.id = def.id
    self.unit = def.unit or "player"
    self.abilityIds = def.abilityIds or {}
    self.active = false
    self.expiresAt = 0
    self.duration = 0
    self.stacks = 0
    self.control = QAT.display.Create(def)
    return self
end

-- True if this tracker cares about (unitTag, abilityId).
function QAT.Tracker:Matches(unitTag, abilityId)
    if unitTag ~= self.unit then return false end
    for _, id in ipairs(self.abilityIds) do
        if id == abilityId then return true end
    end
    return false
end

function QAT.Tracker:Activate(beginTime, endTime, stackCount)
    self.active = true
    self.expiresAt = endTime
    self.duration = (endTime and beginTime) and (endTime - beginTime) or 0
    self.stacks = stackCount or 0
end

function QAT.Tracker:Deactivate()
    self.active = false
    self.expiresAt = 0
    self.duration = 0
    self.stacks = 0
    self.control:SetState(false)
end

-- Called by the render tick while active. Returns false once expired so the
-- Runtime can drop it from the active set.
function QAT.Tracker:Tick(now)
    if not self.active then return false end
    local remaining = self.expiresAt - now
    if remaining <= 0 then
        self:Deactivate()
        return false
    end
    self.control:SetState(true, remaining, self.duration, self.stacks)
    return true
end
