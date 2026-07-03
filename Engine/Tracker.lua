--- Tracker: a phase-based state machine for an on-screen aura.
---
--- A tracker holds named phases and is in exactly one at a time. Idle is just a
--- (usually hidden) phase, so the model is uniform: every behaviour is a phase
--- plus its outgoing, source-attached transitions. A phase owns:
---   * look       - how it draws (display kind, colors, stacks readout)
---   * duration   - the timer that animates it and defines when it "ends"
---   * transitions- ordered { when, to }; the first satisfied `when` wins
---   * runtime    - reactive look overrides (ephemeral; never saved)
---
--- A transition `when` is an effect event (gained/faded), a stacks/remaining
--- threshold, or "expire" (the timer hit zero). Effect whens fire on the event;
--- threshold/expire whens are polled on the render tick.
---
--- Example: Huntsman is Ready -> Active (while the debuff is up) -> Cooldown (a
--- fixed lockout) -> Ready. The common "show a buff's uptime" case is Idle <->
--- Active and is generated from a flat shorthand by QAT.CanonicalizeDef.

QAT.Tracker = {}
QAT.Tracker.__index = QAT.Tracker

-- When a follows-effect phase's effect fades with no sibling yet live, hold the
-- phase this long before falling back to idle. A switch to a sibling effect (e.g.
-- Off Balance -> its immunity) usually lands a frame or two later; without the
-- hold the fallback phase flickers through the gap. Imperceptible on a real drop.
local FALLBACK_GRACE = 0.25 -- seconds

-- Runtime-condition action -> the display element it recolors.
local ACTION_ELEMENT = {
	setBackgroundColor = "background",
	setBarColor = "bar",
	setBorderColor = "border",
	setStacksColor = "stacks",
	setTextColor = "text",
	setTimerColor = "timer",
}
local function contains(arr, v)
	for _, x in ipairs(arr or {}) do
		if x == v then
			return true
		end
	end
	return false
end

-- Live timing (begin/end/stacks) for a specific ability on a unit, or nil if the
-- buff isn't currently present. Used to look ahead at a transition target whose
-- trigger effect may already be up.
local function buffTiming(unit, abilityId)
	if not (unit and DoesUnitExist(unit)) then
		return nil
	end
	for i = 1, GetNumBuffs(unit) do
		local _, started, ending, _, stackCount, _, _, _, _, _, id = GetUnitBuffInfo(unit, i)
		if id == abilityId then
			return started, ending, stackCount
		end
	end
	return nil
end

--- Build runtime phase tables (each with its display control) from a canonical
--- def. The def must already be canonical (see QAT.CanonicalizeDef).
local function Normalize(def)
	local pos = def.pos
	local phases, order = {}, {}
	for _, p in ipairs(def.phases) do
		local look = p.look
		-- Icon- and bar-display phases without an explicit icon fall back to the
		-- tracked ability's icon (bars show it on the left).
		local icon = look.icon
		if (look.display == "icon" or look.display == "bar") and (not icon or icon == "") then
			icon = QAT.util.PhaseIcon(p)
		end
		local displayDef = {
			id = def.id .. "_" .. p.id,
			trackerId = def.id, -- so an on-HUD drag knows which tracker to move
			display = look.display,
			name = look.name or def.name or def.id,
			icon = icon,
			decimals = look.decimals,
			showStacks = look.showStacks,
			showTime = look.showTime,
			font = look.font,
			fontSizes = look.fontSizes,
			colors = look.colors,
			borderThickness = look.borderThickness,
			point = pos.point,
			x = pos.x,
			y = pos.y,
			width = pos.width,
			height = pos.height,
		}
		phases[p.id] = {
			id = p.id,
			control = QAT.display.Create(displayDef),
			duration = p.duration,
			transitions = p.transitions,
			runtime = p.runtime,
			cues = p.cues,
		}
		table.insert(order, p.id)
	end
	return phases, order, def.initial
end

--- Construct a tracker from an authored def.
---@param def table authored tracker def
---@param loadChain table[] load defs (ancestor folders first, this tracker last)
---@return table tracker
function QAT.Tracker.New(def, loadChain)
	QAT.CanonicalizeDef(def) -- idempotent; guarantees canonical shape
	local self = setmetatable({}, QAT.Tracker)
	self.def = def
	self.id = def.id
	self.phases, self.order, self.initial = Normalize(def)
	self.loadChain = loadChain or {}

	self.loaded = false
	self.current = nil -- current phase id, or nil = unloaded/hidden
	self.expiresAt = nil
	self.duration = nil
	self.stacks = 0
	return self
end

-- Re-evaluate load conditions; enter the initial phase when newly loaded, hide
-- when newly unloaded.
function QAT.Tracker:RefreshLoad()
	local want = QAT.conditions.EvaluateLoad(self.loadChain)
	if want == self.loaded then
		return
	end
	self.loaded = want
	QAT.log.engine:Debug("tracker '%s' loaded=%s", self.id, tostring(want))
	self:Enter(want and self.initial or nil)
end

-- All ability ids referenced by any effect transition or effect-duration.
function QAT.Tracker:AbilityIds()
	local ids = {}
	for _, phase in pairs(self.phases) do
		for _, tr in ipairs(phase.transitions) do
			if tr.when.kind == "effect" then
				for _, id in ipairs(tr.when.abilityIds or {}) do
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

-- Apply timing from a triggering effect (or a carry from a threshold transition)
-- to the current phase's duration. A permanent buff reports endTime <= beginTime;
-- that is treated as "present, no countdown" (expiresAt nil) so it shows a static
-- bar/lit icon instead of instantly expiring.
function QAT.Tracker:applyTiming(d, timing, now)
	if d.type == "fixed" then
		self.duration = d.seconds
		self.expiresAt = now + (d.seconds or 0)
	elseif d.type == "effect" and timing.endTime and timing.endTime > (timing.beginTime or 0) then
		self.duration = timing.endTime - (timing.beginTime or now)
		self.expiresAt = timing.endTime
	else
		self.duration = nil
		self.expiresAt = nil
	end
end

-- Enter a phase (or hide when phaseId is nil).
function QAT.Tracker:Enter(phaseId, timing)
	if self.current and self.phases[self.current] then
		self.phases[self.current].control:SetState(false)
	end
	QAT.log.engine:Debug("tracker '%s': %s -> %s", self.id, tostring(self.current), tostring(phaseId or "hidden"))
	self.pendingEnd = nil -- entering any phase cancels a pending fall-back
	self.current = phaseId
	local phase = phaseId and self.phases[phaseId]
	if not phase then
		-- No target, or a transition pointed at a phase that no longer exists (deleted
		-- mid-session before the def was re-canonicalized): hide rather than crash.
		self.current = nil
		self.expiresAt, self.duration, self.stacks = nil, nil, 0
		return
	end

	local now = GetFrameTimeSeconds()
	timing = timing or {}
	self.stacks = timing.stacks or 0
	self:applyTiming(phase.duration, timing, now)

	QAT.FireCues(phase.cues)
	self:Render(now)
end

-- Take the first outgoing effect-gained transition whose trigger effect is already
-- present on its unit. Returns true if one was taken. Lets a phase advance on the
-- strength of a buff that is already up, independent of event ordering.
function QAT.Tracker:TakeLiveTransition()
	local cur = self.phases[self.current]
	for _, tr in ipairs(cur.transitions) do
		local w = tr.when
		if w.kind == "effect" and w.result == "gained" then
			for _, id in ipairs(w.abilityIds or {}) do
				local started, ending, stacks = buffTiming(w.unit, id)
				if started then
					self:Enter(tr.to, { beginTime = started, endTime = ending, stacks = stacks })
					return true
				end
			end
		end
	end
	return false
end

-- Go to the current phase's expire target, or the initial phase if it has none.
function QAT.Tracker:EndPhase()
	local cur = self.phases[self.current]
	local target = self.initial
	for _, tr in ipairs(cur.transitions) do
		if tr.when.kind == "expire" then
			target = tr.to
			break
		end
	end
	self:Enter(target)
end

-- Handle an effect event against the CURRENT phase's transitions (source-attached:
-- only the active phase's exits are candidates). Returns true if consumed.
function QAT.Tracker:OnEffect(unitTag, abilityId, result, beginTime, endTime, stackCount)
	if not self.loaded or not self.current then
		return false
	end
	local cur = self.phases[self.current]
	local rstr = (result == EFFECT_RESULT_FADED) and "faded" or "gained"

	for _, tr in ipairs(cur.transitions) do
		local w = tr.when
		if w.kind == "effect" and w.unit == unitTag and w.result == rstr and contains(w.abilityIds, abilityId) then
			self:Enter(tr.to, { beginTime = beginTime, endTime = endTime, stacks = stackCount })
			return true
		end
	end

	-- Not a transition. If it is the current phase's duration effect, refresh its
	-- timer / stacks, or end the phase when it fades.
	local d = cur.duration
	if d.type == "effect" and d.unit == unitTag and contains(d.abilityIds, abilityId) then
		if rstr == "faded" then
			-- The effect keeping this phase alive ended. Before falling back to the
			-- initial phase, check whether we actually advanced: if an outgoing
			-- effect-gained transition's trigger buff is already live (a stage-up where
			-- the fade of the old stage and the gain of the new arrive in the same
			-- frame, in either order), take that transition instead of resetting.
			if not self:TakeLiveTransition() then
				-- Nothing live yet: hold the phase (shown static) for a short grace
				-- window. A sibling effect gained within it wins via the transition
				-- path above; otherwise Tick falls back once the window elapses.
				local now = GetFrameTimeSeconds()
				self.expiresAt, self.duration = nil, nil
				self.pendingEnd = now + FALLBACK_GRACE
				self:Render(now)
			end
		else
			local now = GetFrameTimeSeconds()
			self.pendingEnd = nil -- the effect is back; cancel any pending fall-back
			self:applyTiming(d, { beginTime = beginTime, endTime = endTime }, now)
			self.stacks = stackCount or 0
			self:Render(now)
		end
		return true
	end
	return false
end

-- Reconcile the current phase against a freshly-enumerated set of live effects.
-- EVENT_EFFECT_CHANGED only fires on change, and a "faded" can be missed across a
-- /reloadui, zone change or armory swap (which silently drop buffs). The seed sweep
-- feeds re-appeared effects as "gained"; this closes the opposite gap: if the phase
-- is held up by a duration effect that is no longer present on its unit, end it.
---@param presentByUnit table unit tag -> { [abilityId] = true } of live effects
function QAT.Tracker:ReconcilePresence(presentByUnit)
	if not self.loaded or not self.current then
		return
	end
	local d = self.phases[self.current].duration
	if d.type ~= "effect" then
		return -- fixed/none phases aren't kept alive by a tracked effect
	end
	local present = presentByUnit[d.unit]
	for _, id in ipairs(d.abilityIds or {}) do
		if present and present[id] then
			return -- still up; nothing to reconcile
		end
	end
	self:EndPhase()
end

-- Per-phase reactive conditions: ephemeral element recolors plus the Show-Proc
-- glow. Returns (overrides, procActive): a table { element = color, ... } (or nil)
-- and whether any Show-Proc condition currently holds. Never writes to the def.
function QAT.Tracker:EvalRuntime(remaining)
	local cur = self.phases[self.current]
	local overrides, procActive = nil, false
	for _, c in ipairs(cur.runtime or {}) do
		local statVal = (c.stat == "stacks") and self.stacks or (remaining or 0)
		local sat = QAT.conditions.Compare(statVal, c.op, c.value)
		if c.action == "showProc" then
			procActive = procActive or sat -- sustained glow while the condition holds
		elseif sat then
			local elem = ACTION_ELEMENT[c.action]
			if elem and c.color then
				overrides = overrides or {}
				overrides[elem] = c.color
			end
		end
	end
	return overrides, procActive
end

function QAT.Tracker:Render(now)
	if not self.current then
		return
	end
	local control = self.phases[self.current].control
	local remaining = self.expiresAt and (self.expiresAt - now) or nil

	control:SetState(true, remaining, self.duration, self.stacks)
	local overrides, procActive = self:EvalRuntime(remaining)
	if overrides then
		for elem, c in pairs(overrides) do
			control:SetElementColor(elem, c) -- after SetState's reset to base colors
		end
	end
	control:SetProc(procActive)
end

-- Poll the current phase's threshold/expire transitions. Returns true if it
-- transitioned. Carries the live timing/stacks so a follow-on phase (e.g. a
-- "last 10s" warning that shares the effect) keeps counting.
function QAT.Tracker:CheckAutoTransitions(now)
	local cur = self.phases[self.current]
	local remaining = self.expiresAt and (self.expiresAt - now) or nil
	local carry = {
		stacks = self.stacks,
		endTime = self.expiresAt,
		beginTime = self.expiresAt and self.duration and (self.expiresAt - self.duration),
	}
	for _, tr in ipairs(cur.transitions) do
		local w = tr.when
		if w.kind == "expire" then
			if self.expiresAt and now >= self.expiresAt then
				self:Enter(tr.to)
				return true
			end
		elseif w.kind == "stacks" then
			if QAT.conditions.Compare(self.stacks, w.op, w.value) then
				self:Enter(tr.to, carry)
				return true
			end
		elseif w.kind == "remaining" then
			if remaining ~= nil and QAT.conditions.Compare(remaining, w.op, w.value) then
				self:Enter(tr.to, carry)
				return true
			end
		end
	end
	-- Timer reached zero with no explicit expire transition.
	if self.expiresAt and now >= self.expiresAt then
		self:EndPhase()
		return true
	end
	return false
end

-- Render tick: advance the state machine, then animate a counting-down phase.
function QAT.Tracker:Tick(now)
	if not self.current then
		return
	end
	-- Holding a faded phase during its grace window: fall back only once it elapses,
	-- and skip the normal auto-transition/render (the effect is already gone).
	if self.pendingEnd then
		if now >= self.pendingEnd then
			self.pendingEnd = nil
			self:EndPhase()
		end
		return
	end
	if self:CheckAutoTransitions(now) then
		return
	end
	if self.expiresAt then
		self:Render(now)
	end
end

-- Put the tracker into its starting state by evaluating load conditions.
function QAT.Tracker:Start()
	self:RefreshLoad()
end
