--- Tracker: a phase-based state machine for an on-screen aura.
---
--- A tracker holds a set of named phases and is in exactly one of them at a time
--- (or idle/hidden). Each phase owns its display and its countdown source, plus
--- the triggers that enter it:
---   * effect trigger - an EVENT_EFFECT_CHANGED gained/faded for an ability id,
---     optionally guarded by the phase it must transition from
---   * onExpire       - when a timed phase's countdown reaches zero it advances
---     to a named phase (or to idle)
---
--- Example: a set proc with a lockout is one tracker with three phases —
--- Ready -> Active (while the buff is up) -> Cooldown (a fixed timer) -> Ready.
--- The common case (show a buff's remaining time) is a single phase; a def that
--- omits `phases` is normalized into one implicit "active" phase.

QAT.Tracker = {}
QAT.Tracker.__index = QAT.Tracker

local function contains(arr, v)
	for _, x in ipairs(arr or {}) do
		if x == v then
			return true
		end
	end
	return false
end

--- Build runtime phase tables (each with its display control) from a canonical
--- def. The def must already be canonical (see QAT.CanonicalizeDef).
---@param def table canonical tracker def
---@return table phases map of phaseId -> phase
---@return string[] order phase ids in declared order
---@return string|nil initial starting phase id, or nil to start idle
local function Normalize(def)
	local pos = def.pos
	local phases, order = {}, {}
	for _, p in ipairs(def.phases) do
		local look = p.look
		-- A phase's display combines the tracker's shared position with the
		-- phase's own look (display kind, name, color, icon, font). Icon-display
		-- phases without an explicit icon fall back to the tracked ability's icon.
		local icon = look.icon
		if look.display == "icon" and (not icon or icon == "") then
			icon = QAT.util.PhaseIcon(p)
		end
		local displayDef = {
			id = def.id .. "_" .. p.id,
			display = look.display,
			name = look.name or def.name or def.id,
			color = look.color,
			icon = icon,
			font = look.font,
			decimals = look.decimals,
			point = pos.point,
			x = pos.x,
			y = pos.y,
			width = pos.width,
			height = pos.height,
			bgColor = look.bgColor,
		}
		phases[p.id] = {
			id = p.id,
			control = QAT.display.Create(displayDef),
			duration = p.duration,
			onExpire = p.onExpire,
			enter = p.enter,
			cues = p.cues,
		}
		table.insert(order, p.id)
	end

	return phases, order, def.initial
end

--- Construct a tracker from an authored def.
---@param def table authored tracker def
---@param loadChain table[] load defs (ancestor folders first, this tracker last),
---  AND-ed together to decide whether the tracker is loaded
---@return table tracker
function QAT.Tracker.New(def, loadChain)
	QAT.CanonicalizeDef(def) -- idempotent; guarantees canonical shape
	local self = setmetatable({}, QAT.Tracker)
	self.def = def
	self.id = def.id
	self.phases, self.order, self.initial = Normalize(def)
	self.loadChain = loadChain or {}

	self.loaded = false -- gated by load conditions; set by RefreshLoad/Start
	self.current = nil -- current phase id, or nil = idle/hidden
	self.expiresAt = nil
	self.duration = nil
	self.stacks = 0
	return self
end

-- Re-evaluate load conditions; enter the initial phase when newly loaded, hide
-- when newly unloaded. Called on the debounced load-recompute events.
function QAT.Tracker:RefreshLoad()
	local want = QAT.conditions.EvaluateLoad(self.loadChain)
	if want == self.loaded then
		return
	end
	self.loaded = want
	QAT.log.engine:Debug("tracker '%s' loaded=%s", self.id, tostring(want))
	if want then
		self:Enter(self.initial)
	else
		self:Enter(nil)
	end
end

-- All ability ids referenced by any trigger or effect-duration (for filter
-- registration and event dispatch).
function QAT.Tracker:AbilityIds()
	local ids = {}
	for _, phase in pairs(self.phases) do
		for _, trig in ipairs(phase.enter) do
			if trig.kind == "effect" then
				for _, id in ipairs(trig.abilityIds or {}) do
					ids[id] = true
				end
			end
		end
		if phase.duration.type == "effect" then
			for _, id in ipairs(phase.duration.abilityIds or {}) do
				ids[id] = true
			end
		end
	end
	return ids
end

-- Enter a phase (or idle when phaseId is nil). timing = {beginTime,endTime,stacks}
-- carried from the triggering effect event, used when the new phase's countdown
-- follows that effect.
function QAT.Tracker:Enter(phaseId, timing)
	if self.current and self.phases[self.current] then
		self.phases[self.current].control:SetState(false)
	end

	QAT.log.engine:Debug("tracker '%s': %s -> %s", self.id, tostring(self.current), tostring(phaseId or "idle"))
	self.current = phaseId
	if not phaseId then
		self.expiresAt, self.duration, self.stacks = nil, nil, 0
		return
	end

	local phase = self.phases[phaseId]
	local now = GetFrameTimeSeconds()
	timing = timing or {}
	self.stacks = timing.stacks or 0

	local d = phase.duration
	if d.type == "fixed" then
		self.duration = d.seconds
		self.expiresAt = now + d.seconds
	elseif d.type == "effect" and timing.endTime then
		self.duration = timing.endTime - (timing.beginTime or now)
		self.expiresAt = timing.endTime
	else -- "none", or an effect phase entered without timing
		self.duration = nil
		self.expiresAt = nil
	end

	QAT.FireCues(phase.cues)
	self:Render(now)
end

-- Handle an effect event; returns true if it changed state or refreshed timing.
function QAT.Tracker:OnEffect(unitTag, abilityId, result, beginTime, endTime, stacks)
	if not self.loaded then
		return false
	end
	local rstr = (result == EFFECT_RESULT_FADED) and "faded" or "gained"
	local timing = { beginTime = beginTime, endTime = endTime, stacks = stacks }

	-- 1) Transitions: first matching enter-trigger wins.
	for _, phaseId in ipairs(self.order) do
		local phase = self.phases[phaseId]
		for _, trig in ipairs(phase.enter) do
			if
				trig.kind == "effect"
				and trig.unit == unitTag
				and contains(trig.abilityIds, abilityId)
				and trig.result == rstr
				and (trig.from == nil or contains(trig.from, self.current))
			then
				self:Enter(phaseId, timing)
				return true
			end
		end
	end

	-- 2) No transition consumed it. If it concerns the current phase's effect
	--    countdown, refresh it (gained/updated) or drop to idle (faded).
	if self.current then
		local d = self.phases[self.current].duration
		if d.type == "effect" and d.unit == unitTag and contains(d.abilityIds, abilityId) then
			if rstr == "faded" then
				self:Enter(nil)
			else
				self.expiresAt = endTime
				self.duration = endTime and (endTime - (beginTime or GetFrameTimeSeconds()))
				self.stacks = stacks or 0
			end
			return true
		end
	end

	return false
end

-- Runtime conditions: reactive look changes on the current phase, evaluated each
-- render against the live stat (remaining time or stacks). Pure: returns
-- (hidden, colorOverride). def.runtime = { { stat, op, value, action, color }, ... }
function QAT.Tracker:EvalRuntime(remaining)
	local hidden, colorOverride = false, nil
	for _, c in ipairs(self.def.runtime or {}) do
		local statVal = (c.stat == "stacks") and self.stacks or (remaining or 0)
		if QAT.conditions.Compare(statVal, c.op, c.value) then
			if c.action == "hide" then
				hidden = true
			elseif c.action == "color" then
				colorOverride = c.color
			end
		end
	end
	return hidden, colorOverride
end

function QAT.Tracker:Render(now)
	if not self.current then
		return
	end
	local control = self.phases[self.current].control
	local remaining = self.expiresAt and (self.expiresAt - now) or nil

	local hidden, colorOverride = self:EvalRuntime(remaining)
	if hidden then
		control:SetState(false)
		return
	end

	control:SetState(true, remaining, self.duration, self.stacks)
	if colorOverride then
		control:SetBarColor(colorOverride)
	end -- after SetState's reset
end

-- Render tick. Advances the state machine when a timed phase expires.
function QAT.Tracker:Tick(now)
	if not self.current then
		return
	end
	if self.expiresAt == nil then
		return
	end -- static phase, nothing to animate

	local remaining = self.expiresAt - now
	if remaining <= 0 then
		local onExpire = self.phases[self.current].onExpire
		self:Enter(onExpire) -- onExpire phase, or idle when nil
		return
	end
	self:Render(now)
end

-- Put the tracker into its starting state by evaluating load conditions.
function QAT.Tracker:Start()
	self:RefreshLoad()
end
