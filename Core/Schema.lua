-- Canonical tracker schema and the transform that produces it.
--
-- A tracker is stored in one canonical shape:
--
--   {
--     id, kind = "tracker", name, unit,
--     enabled = true,
--     pos     = { point, x, y, width, height },
--     initial = <phaseId>,                 -- starting phase (always a real phase;
--                                          -- usually a hidden "idle" one)
--     phases  = {                          -- the state machine
--       {
--         id,
--         look = { display = "bar"|"icon"|"text"|"none",
--                  name, icon, decimals,
--                  showStacks, showTime,   -- which readouts to draw (stacks is author-declared)
--                  fontSizes = { label, time, stacks },
--                  colors = { background, bar, border, stacks, text, timer, cooldown } },
--         duration    = { type = "none"|"fixed"|"effect", seconds?, abilityIds?, unit? },
--         transitions = {                  -- outgoing, source-attached, first match wins
--           { when = <trigger>, to = <phaseId> },
--           ...
--         },
--         runtime = { <condition>, ... },  -- per-phase reactive look overrides (ephemeral)
--         cues    = { sound, flash } | nil,-- additive on-enter cues (not a look)
--       }, ...
--     },
--     load = { ... } | nil,
--   }
--
-- A transition trigger (`when`) is one of:
--   { kind = "effect",    result = "gained"|"faded", abilityIds = {..}, unit }
--   { kind = "stacks",    op, value }      -- current stack count crosses a threshold
--   { kind = "remaining", op, value }      -- seconds left crosses a threshold
--   { kind = "expire" }                    -- the phase's timer reached zero
--
-- The model is uniform: every tracker is phases + transitions, idle is just a
-- hidden phase. A flat single-phase shorthand and the older enter/onExpire shape
-- are both accepted and expanded/migrated here.

-- "audio" is a non-visual kind: it draws nothing and plays the phase's cue on
-- enter (the sound is stored in phase.cues.sound).
local DISPLAY_KINDS = { bar = true, icon = true, text = true, none = true, audio = true }
local COLOR_KEYS = { "background", "bar", "border", "stacks", "text", "timer", "cooldown" }

local function canonicalLook(src)
	src = src or {}
	local display = src.display
	if not DISPLAY_KINDS[display] then
		display = "bar"
	end

	-- Per-element colors. Migrate the older single `color` (bar fill) and `bgColor`.
	local srcColors = src.colors or {}
	local colors = {}
	for _, k in ipairs(COLOR_KEYS) do
		colors[k] = srcColors[k]
	end
	if colors.bar == nil and src.color ~= nil then
		colors.bar = src.color
	end
	if colors.background == nil and src.bgColor ~= nil then
		colors.background = src.bgColor
	end

	local f = src.fontSizes or {}
	return {
		display = display,
		name = src.name,
		icon = src.icon,
		decimals = src.decimals,
		showStacks = src.showStacks or false,
		showTime = src.showTime ~= false, -- default on; the time number is the common readout
		font = src.font, -- optional LibMediaProvider font family name (nil = default face)
		fontSizes = { label = f.label, time = f.time, stacks = f.stacks },
		colors = colors,
		borderThickness = src.borderThickness, -- nil = default 1px
	}
end

-- Normalize one transition trigger in place, defaulting against the tracker unit.
local function canonicalWhen(when, defUnit)
	when = when or {}
	local kind = when.kind
	if kind == "effect" then
		when.result = when.result or "gained"
		when.abilityIds = when.abilityIds or {}
		when.unit = when.unit or defUnit
	elseif kind == "stacks" or kind == "remaining" then
		when.op = when.op or ">="
		when.value = when.value or 0
	else
		when.kind = "expire"
	end
	return when
end

-- Old runtime-condition actions used a single "color" (bar) / "hide". Map them to
-- the per-element vocabulary; drop "hide" (visibility is owned by phases now).
local function migrateRuntime(list)
	local out = {}
	for _, c in ipairs(list or {}) do
		if c.action == "hide" then
			-- dropped
		elseif c.action == "color" then
			table.insert(out, { stat = c.stat, op = c.op, value = c.value, action = "setBarColor", color = c.color })
		else
			table.insert(out, c)
		end
	end
	return out
end

-- Convert the older enter[]/onExpire phase shape into source-attached transitions.
-- Runs once: it is a no-op once no phase carries `enter`/`onExpire`.
local function migrateLegacyTransitions(def)
	local hasLegacy = false
	for _, p in ipairs(def.phases) do
		if p.enter or p.onExpire ~= nil then
			hasLegacy = true
		end
	end
	if not hasLegacy then
		return
	end

	local byId = {}
	for _, p in ipairs(def.phases) do
		p.transitions = p.transitions or {}
		byId[p.id] = p
	end

	-- A tracker that started idle (no initial phase) needs a real hidden idle phase
	-- to own its entry transitions.
	if def.initial == nil or not byId[def.initial] then
		if not byId["idle"] then
			local idle = { id = "idle", look = { display = "none" }, duration = { type = "none" }, transitions = {} }
			table.insert(def.phases, 1, idle)
			byId["idle"] = idle
		end
		def.initial = "idle"
	end

	local allIds = {}
	for _, p in ipairs(def.phases) do
		table.insert(allIds, p.id)
	end

	for _, q in ipairs(def.phases) do
		for _, t in ipairs(q.enter or {}) do
			if t.kind == "effect" then
				-- "enter q on T (from S)" becomes "from S: when T -> q". A trigger with
				-- no `from` matched from any state, so attach it to every phase.
				local sources = t.from or allIds
				for _, sid in ipairs(sources) do
					local s = byId[sid]
					if s then
						table.insert(s.transitions, {
							when = {
								kind = "effect",
								result = t.result or "gained",
								abilityIds = t.abilityIds or {},
								unit = t.unit,
							},
							to = q.id,
						})
					end
				end
			end
		end
		if q.onExpire ~= nil then
			table.insert(q.transitions, { when = { kind = "expire" }, to = q.onExpire })
		end
	end

	for _, p in ipairs(def.phases) do
		p.enter = nil
		p.onExpire = nil
	end
end

--- Convert one tracker def to canonical form in place. Idempotent: a def that is
--- already canonical is only normalized for defaults.
---@param def table tracker def (flat shorthand, legacy phased, or canonical)
---@return table def the same table, canonicalized
function QAT.CanonicalizeDef(def)
	def.unit = def.unit or "player"
	if def.enabled == nil then
		def.enabled = true
	end

	-- Fold flat position fields into pos (canonical), then drop the flat ones.
	def.pos = def.pos or { point = def.point, x = def.x, y = def.y, width = def.width, height = def.height }
	def.point, def.x, def.y, def.width, def.height = nil, nil, nil, nil, nil

	if not def.phases then
		-- Flat shorthand -> a hidden idle phase plus a visible "active" phase shown
		-- while the buff is up. Uniform two-phase shape (idle <-> active).
		local ids = def.abilityIds or {}
		def.phases = {
			{
				id = "idle",
				look = { display = "none" },
				duration = { type = "none" },
				transitions = { { when = { kind = "effect", result = "gained", abilityIds = ids }, to = "active" } },
			},
			{
				id = "active",
				look = canonicalLook(def),
				duration = { type = "effect", abilityIds = ids },
				transitions = {},
			},
		}
		def.initial = "idle"
		def.display = nil
		def.color, def.icon, def.font, def.decimals, def.abilityIds, def.effectType, def.bgColor =
			nil, nil, nil, nil, nil, nil, nil
	end

	-- Legacy enter[]/onExpire -> transitions (once).
	migrateLegacyTransitions(def)

	-- Legacy tracker-level runtime conditions move onto every phase (once).
	if def.runtime ~= nil then
		local migrated = migrateRuntime(def.runtime)
		for _, phase in ipairs(def.phases) do
			phase.runtime = phase.runtime or {}
			for _, c in ipairs(migrated) do
				table.insert(phase.runtime, c)
			end
		end
		def.runtime = nil
	end

	-- The set of existing phase ids, so dangling transition targets (e.g. a phase
	-- deleted in the editor) can be pruned below rather than crashing the runtime.
	local phaseIds = {}
	for _, phase in ipairs(def.phases) do
		phaseIds[phase.id] = true
	end

	-- Normalize every phase: look defaults, duration/trigger units default to the
	-- tracker unit, transitions and runtime are present and normalized. Transitions
	-- whose target phase no longer exists are dropped.
	for _, phase in ipairs(def.phases) do
		phase.look = canonicalLook(phase.look)
		phase.duration = phase.duration or { type = "none" }
		phase.duration.unit = phase.duration.unit or def.unit
		phase.transitions = phase.transitions or {}
		local kept = {}
		for _, tr in ipairs(phase.transitions) do
			if phaseIds[tr.to] then
				tr.when = canonicalWhen(tr.when, def.unit)
				kept[#kept + 1] = tr
			end
		end
		phase.transitions = kept
		phase.runtime = migrateRuntime(phase.runtime)
	end

	-- Guarantee a valid initial phase.
	if
		def.initial == nil
		or not (function()
			for _, p in ipairs(def.phases) do
				if p.id == def.initial then
					return true
				end
			end
			return false
		end)()
	then
		def.initial = def.phases[1] and def.phases[1].id
	end

	return def
end

--- Canonicalize a whole tracker tree in place (recurses into folder children).
---@param defs table[] array of tracker/folder defs
function QAT.CanonicalizeTree(defs)
	for _, def in ipairs(defs or {}) do
		if def.kind == "folder" then
			def.children = def.children or {}
			QAT.CanonicalizeTree(def.children)
		else
			QAT.CanonicalizeDef(def)
		end
	end
end

--- Build a canonical "mutually-exclusive effects" tracker: one phase per effect
--- (shown while that effect is on the unit) plus a fallback phase, wired into a
--- full mesh so any effect is reachable from any state. Exactly one of the effects
--- is expected to be live at a time (e.g. vampire stages, a charge -> ready proc).
--- When the active effect fades the engine advances to whichever sibling effect is
--- now live (via Tracker:TakeLiveTransition), or falls back when none is.
---@param opts table { name?, unit?, fallbackName?, x?, y?, suffix?, manual?, effects = { { id, name?, unit? }, ... } }
---  manual = true builds the phases (one per effect + fallback) with NO transitions,
---  for the user to wire switching themselves. Each effect may carry its own unit
---  (e.g. a self debuff on the boss watches "reticleover", not "player").
---@return table|nil def canonical tracker def, or nil if fewer than two effects
function QAT.BuildMutexTrackerDef(opts)
	local effects = opts.effects or {}
	if #effects < 2 then
		return nil -- a mutex group needs at least two states to switch between
	end
	local unit = opts.unit or "player"

	-- Readable, unique slug ids from names so transitions/initial reference phases
	-- by a stable key (never a localized display string at match time).
	local used = {}
	local function slug(text, fallback)
		local s = tostring(text or ""):lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
		if s == "" then
			s = fallback
		end
		local base, n = s, 2
		while used[s] do
			s, n = base .. "_" .. n, n + 1
		end
		used[s] = true
		return s
	end

	local fallbackName = opts.fallbackName or "Inactive"
	local fallbackId = slug(fallbackName, "fallback")

	-- Resolve each effect to its phase id + display name + unit up front so the mesh
	-- below can cross-reference every sibling (and watch it on the right unit).
	local stages = {}
	for i, e in ipairs(effects) do
		local nm = e.name
		if not nm or nm == "" then
			nm = QAT.util and QAT.util.AbilityInfo(e.id) or ("#" .. tostring(e.id))
		end
		stages[i] = { id = e.id, name = nm, phaseId = slug(nm, "stage_" .. i), unit = e.unit or unit }
	end

	-- Every phase can jump to every OTHER stage when that stage's effect is gained
	-- (watched on that stage's own unit). Manual mode skips the mesh entirely.
	local function meshExcept(selfPhaseId)
		if opts.manual then
			return {}
		end
		local trs = {}
		for _, s in ipairs(stages) do
			if s.phaseId ~= selfPhaseId then
				trs[#trs + 1] = {
					when = { kind = "effect", result = "gained", abilityIds = { s.id }, unit = s.unit },
					to = s.phaseId,
				}
			end
		end
		return trs
	end

	local phases = {
		{
			id = fallbackId,
			look = { display = "bar", name = fallbackName, showTime = false },
			duration = { type = "none" },
			transitions = meshExcept(fallbackId),
		},
	}
	for _, s in ipairs(stages) do
		phases[#phases + 1] = {
			id = s.phaseId,
			look = { display = "bar", name = s.name },
			duration = { type = "effect", abilityIds = { s.id }, unit = s.unit },
			transitions = meshExcept(s.phaseId),
		}
	end

	return QAT.CanonicalizeDef({
		id = "tracker_mutex_" .. GetTimeStamp() .. "_" .. (opts.suffix or 0),
		kind = "tracker",
		name = opts.name or (stages[1].name .. " …"),
		unit = unit,
		initial = fallbackId,
		phases = phases,
		x = opts.x,
		y = opts.y,
		enabled = true,
	})
end
