--- Tracker: one or more phase-based state machines for an on-screen aura.
---
--- Phases are grouped into layers. Phases sharing a layer form one mutually-exclusive
--- machine (a "lane"): the tracker is in exactly one of them at a time, idle included,
--- so the model is uniform — every behaviour is a phase plus its outgoing,
--- source-attached transitions. Different layers run as independent lanes at the same
--- time and draw in ascending layer order, so a tracker can show, say, a duration icon
--- and a cooldown frame together. A single-layer tracker (layer 0 only) behaves
--- exactly as a plain state machine.
---
--- A phase owns:
---   * look       - how it draws (display kind, colors, stacks readout)
---   * duration   - the timer that animates it and defines when it "ends"
---   * transitions- ordered { when, to }; the first satisfied `when` wins (same layer)
---   * runtime    - reactive look overrides (ephemeral; never saved)
---
--- A transition `when` is an effect event (gained/faded), a stacks/remaining
--- threshold, or "expire" (the timer hit zero). Effect whens fire on the event;
--- threshold/expire whens are polled on the render tick.

QAT.Tracker = {}
QAT.Tracker.__index = QAT.Tracker

-- One lane's state machine. Lives inside a tracker; shares the tracker's phase table
-- (controls) and loaded flag but keeps its own current phase and timer.
local Lane = {}
Lane.__index = Lane

-- When a follows-effect phase's effect fades with no sibling yet live, hold the
-- phase this long before falling back to idle. A switch to a sibling effect (e.g.
-- Off Balance -> its immunity) usually lands a frame or two later; without the
-- hold the fallback phase flickers through the gap. Imperceptible on a real drop.
local FALLBACK_GRACE = 0.25 -- seconds

-- Whether a real, attackable reticle target exists right now. Used to tell "looking
-- away from a target" (hold sticky target trackers, let them run out) apart from
-- "acquired a new target" (re-evaluate the phase against it).
local function targetLive()
	return DoesUnitExist("reticleover") and IsUnitAttackable("reticleover")
end

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

-- Horizontal offset a layer's control takes within the tracker's box for a given
-- 9-point alignment. A square (icon/border/gradient) layer is `height` wide, so it
-- can sit left / centered / right inside a wider bar; bar/text layers fill the box
-- width and never shift. Vertical alignment is a no-op: every layer is box-height.
local function alignOffset(align, display, boxW, boxH)
	boxW, boxH = boxW or 220, boxH or 30 -- pos may omit width/height (Display defaults them)
	local lw = (display == "icon" or display == "border" or display == "gradient") and boxH or boxW
	local slack = boxW - lw
	if slack <= 0 then
		return 0
	end
	if align == "top" or align == "center" or align == "bottom" then
		return math.floor(slack / 2)
	elseif align == "topright" or align == "right" or align == "bottomright" then
		return slack
	end
	return 0 -- topleft / left / bottomleft
end

--- Build runtime phase tables (each with its display control) from a canonical
--- def. The def must already be canonical (see QAT.CanonicalizeDef).
local function Normalize(def)
	local pos = def.pos
	local phases, order = {}, {}
	for _, p in ipairs(def.phases) do
		local look = p.look
		local ls = (def.layerSettings and def.layerSettings[p.layer or 0]) or {}
		-- A square layer (icon/border/gradient) can sit left/centre/right within a wider
		-- box; this per-phase x offset is added to the tracker's relative position when
		-- the control is placed (see Tracker:ApplyPosition).
		local alignX = alignOffset(ls.align, look.display, pos.width, pos.height)
		-- Every icon-capable kind falls back to the tracked ability's icon when the
		-- phase carries no explicit override, so authors never hunt .dds paths.
		local icon = look.icon
		if not icon or icon == "" then
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
			showIcon = look.showIcon,
			font = look.font,
			fontSizes = look.fontSizes,
			colors = look.colors,
			borderThickness = look.borderThickness,
			borderStyle = look.borderStyle,
			lowThreshold = look.lowThreshold,
			lowColor = look.lowColor,
			lowPulse = look.lowPulse,
			barHeight = look.barHeight,
			barAnchor = look.barAnchor,
			sweepDir = look.sweepDir,
			sweepColor = look.sweepColor,
			graphic = look.graphic,
			-- Higher layers draw above lower ones so a transparent frame can overlay
			-- an icon phase in the same tracker.
			drawLevel = p.layer or 0,
			point = pos.point,
			-- Created at the tracker's relative position (anchor added by ApplyPosition,
			-- called right after Normalize). The align offset lets a smaller square layer
			-- sit within the tracker's box rather than only top-left.
			x = pos.x + alignX,
			y = pos.y,
			forceHidden = ls.visible == false,
			width = pos.width,
			height = pos.height,
		}
		phases[p.id] = {
			id = p.id,
			layer = p.layer or 0,
			control = QAT.display.Create(displayDef),
			duration = p.duration,
			transitions = p.transitions,
			runtime = p.runtime,
			cues = p.cues,
			alignX = alignX, -- per-phase x offset within the box (see ApplyPosition)
		}
		table.insert(order, p.id)
	end
	return phases, order
end

--- Construct a tracker from an authored def.
---@param def table authored tracker def
---@param loadChain table[] load defs (ancestor folders first, this tracker last)
---@param anchor table|nil parent group's absolute screen anchor { x, y } (nil = origin)
---@return table tracker
function QAT.Tracker.New(def, loadChain, anchor)
	QAT.CanonicalizeDef(def) -- idempotent; guarantees canonical shape
	local self = setmetatable({}, QAT.Tracker)
	self.def = def
	self.id = def.id
	self.phases, self.order = Normalize(def)
	self.loadChain = loadChain or {}
	self.loaded = false
	-- Screen position = parent group anchor + this tracker's relative offset. A
	-- top-level tracker has a zero anchor, so its offset is its absolute position.
	self.anchorX = (anchor and anchor.x) or 0
	self.anchorY = (anchor and anchor.y) or 0
	self.relX = (def.pos and def.pos.x) or 0
	self.relY = (def.pos and def.pos.y) or 0
	self:ApplyPosition()

	-- One lane per layer, each with its starting phase. def.layerInitial (canonical)
	-- maps layer -> initial phase id and always contains layer 0.
	self.lanes = {}
	for layer, initial in pairs(def.layerInitial or { [0] = def.initial }) do
		self.lanes[#self.lanes + 1] = Lane.New(self, layer, initial)
	end
	table.sort(self.lanes, function(a, b)
		return a.layer < b.layer
	end)
	return self
end

-- Place every phase control at its absolute screen position (parent anchor + this
-- tracker's relative offset + the phase's align offset). Called on construction, when
-- the relative position changes (inspector / drag), and when an ancestor group moves.
function QAT.Tracker:ApplyPosition()
	for _, phase in pairs(self.phases) do
		phase.control:Reposition(self.anchorX + self.relX + (phase.alignX or 0), self.anchorY + self.relY)
	end
end

-- Set the relative offset (from the parent group anchor) and re-place. `x`/`y` are the
-- values stored in def.pos; the inspector and HUD drag both feed relative coordinates.
function QAT.Tracker:SetRelativePosition(x, y)
	self.relX, self.relY = x or 0, y or 0
	self:ApplyPosition()
end

-- Update this tracker's parent anchor (an ancestor group moved) and re-place.
function QAT.Tracker:SetAnchor(x, y)
	self.anchorX, self.anchorY = x or 0, y or 0
	self:ApplyPosition()
end

-- Place a phase control at an explicit absolute position, bypassing the anchor/offset
-- math. Used by the grid layout pass, which computes cell positions in screen space.
function QAT.Tracker:PlaceAbsolute(x, y)
	for _, phase in pairs(self.phases) do
		phase.control:Reposition(x + (phase.alignX or 0), y)
	end
end

function Lane.New(tracker, layer, initial)
	return setmetatable({
		tracker = tracker,
		layer = layer,
		initial = initial,
		current = nil, -- current phase id, or nil = hidden
		expiresAt = nil,
		duration = nil,
		stacks = 0,
		pendingEnd = nil,
	}, Lane)
end

-- Re-evaluate load conditions; enter each lane's initial phase when newly loaded,
-- hide when newly unloaded.
function QAT.Tracker:RefreshLoad()
	local want = QAT.conditions.EvaluateLoad(self.loadChain)
	if want == self.loaded then
		return
	end
	self.loaded = want
	QAT.log.engine:Debug("tracker '%s' loaded=%s", self.id, tostring(want))
	for _, lane in ipairs(self.lanes) do
		lane:Enter(want and lane.initial or nil)
	end
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

-- ===== Lane state machine =====

-- Apply timing from a triggering effect (or a carry from a threshold transition)
-- to this lane's duration. A permanent buff reports endTime <= beginTime; that is
-- treated as "present, no countdown" (expiresAt nil) so it shows a static bar/lit
-- icon instead of instantly expiring.
function Lane:applyTiming(d, timing, now)
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
function Lane:Enter(phaseId, timing)
	local phases = self.tracker.phases
	if self.current and phases[self.current] then
		phases[self.current].control:SetState(false)
	end
	QAT.log.engine:Debug(
		"tracker '%s' lane %d: %s -> %s",
		self.tracker.id,
		self.layer,
		tostring(self.current),
		tostring(phaseId or "hidden")
	)
	self.pendingEnd = nil -- entering any phase cancels a pending fall-back
	self.current = phaseId
	local phase = phaseId and phases[phaseId]
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
-- present on its unit. Returns true if one was taken.
function Lane:TakeLiveTransition()
	local cur = self.tracker.phases[self.current]
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

-- Go to the current phase's expire target, or the lane's initial phase if none.
function Lane:EndPhase()
	local cur = self.tracker.phases[self.current]
	local target = self.initial
	for _, tr in ipairs(cur.transitions) do
		if tr.when.kind == "expire" then
			target = tr.to
			break
		end
	end
	self:Enter(target)
end

-- Handle an effect event against this lane's CURRENT phase's transitions
-- (source-attached: only the active phase's exits are candidates). Returns true if
-- consumed.
function Lane:OnEffect(unitTag, abilityId, result, beginTime, endTime, stackCount)
	if not self.current then
		return false
	end
	local cur = self.tracker.phases[self.current]
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
			-- Sticky target: a "faded" with no live reticle target is the reticle leaving
			-- the target, not the debuff ending. Ignore it so the phase keeps its timer and
			-- runs out on its own; a newly-acquired target re-seeds via ScanBuffs.
			if d.unit == "reticleover" and self.tracker.def.stickyTarget and not targetLive() then
				return true
			end
			-- The effect keeping this phase alive ended. Before falling back, check
			-- whether we actually advanced: if an outgoing effect-gained transition's
			-- trigger buff is already live (a stage-up where the fade of the old stage
			-- and the gain of the new arrive in the same frame), take it instead.
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

-- Reconcile this lane's current phase against a freshly-enumerated set of live
-- effects (see QAT.Tracker:ReconcilePresence for why).
function Lane:ReconcilePresence(presentByUnit)
	if not self.current then
		return
	end
	local d = self.tracker.phases[self.current].duration
	if d.type ~= "effect" then
		return -- fixed/none phases aren't kept alive by a tracked effect
	end
	local present = presentByUnit[d.unit]
	for _, id in ipairs(d.abilityIds or {}) do
		if present and present[id] then
			return -- still up; nothing to reconcile
		end
	end
	-- Sticky target: don't end just because the reticle is off a target; only
	-- reconcile (and possibly clear) against a genuinely-acquired new target.
	if d.unit == "reticleover" and self.tracker.def.stickyTarget and not targetLive() then
		return
	end
	self:EndPhase()
end

-- Per-phase reactive conditions: ephemeral element recolors plus the Show-Proc
-- glow. Returns (overrides, procActive). Never writes to the def.
function Lane:EvalRuntime(remaining)
	local cur = self.tracker.phases[self.current]
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

function Lane:Render(now)
	if not self.current then
		return
	end
	local control = self.tracker.phases[self.current].control
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

-- Poll this lane's threshold/expire transitions. Returns true if it transitioned.
function Lane:CheckAutoTransitions(now)
	local cur = self.tracker.phases[self.current]
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

-- Render tick for one lane: advance the state machine, then animate a counting-down
-- phase.
function Lane:Tick(now)
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

-- ===== Tracker: fan events out to every lane =====

function QAT.Tracker:OnEffect(unitTag, abilityId, result, beginTime, endTime, stackCount)
	if not self.loaded then
		return false
	end
	local consumed = false
	for _, lane in ipairs(self.lanes) do
		if lane:OnEffect(unitTag, abilityId, result, beginTime, endTime, stackCount) then
			consumed = true
		end
	end
	return consumed
end

---@param presentByUnit table unit tag -> { [abilityId] = true } of live effects
function QAT.Tracker:ReconcilePresence(presentByUnit)
	if not self.loaded then
		return
	end
	for _, lane in ipairs(self.lanes) do
		lane:ReconcilePresence(presentByUnit)
	end
end

function QAT.Tracker:Tick(now)
	for _, lane in ipairs(self.lanes) do
		lane:Tick(now)
	end
end

-- Put the tracker into its starting state by evaluating load conditions.
function QAT.Tracker:Start()
	self:RefreshLoad()
end

-- ===== Dynamic-instance driving =====
-- A dynamic-group instance is a normal tracker whose tracked effect is supplied by a
-- Targeting source (per live target) rather than the game's event bus. The source feeds
-- synthetic gained/faded events for the instance's reserved ability on QAT.DYN_UNIT; the
-- phase machine (transitions, timers, cues, runtime conditions) then runs unchanged.

-- Override the display name on every phase control (the bound target's name).
function QAT.Tracker:SetDisplayName(name)
	for _, phase in pairs(self.phases) do
		phase.control.name = name or ""
	end
end

-- Reset every lane to its hidden initial phase (used when a slot is (re)bound to a
-- different target).
function QAT.Tracker:ResetDynamic()
	for _, lane in ipairs(self.lanes) do
		lane:Enter(lane.initial)
	end
end

-- Feed the source's effect for the bound target: present=true is a gained event with
-- the target's timing, present=false a faded event (letting the fade phase play out).
function QAT.Tracker:FeedDynamic(present, beginTime, endTime, stacks)
	local ab = self.dynAbilityId
	if not ab then
		return
	end
	local result = present and EFFECT_RESULT_GAINED or EFFECT_RESULT_FADED
	self:OnEffect(QAT.DYN_UNIT, ab, result, beginTime, endTime, stacks or 0)
end
