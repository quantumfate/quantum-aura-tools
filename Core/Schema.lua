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

local DISPLAY_KINDS = { bar = true, icon = true, text = true, none = true }
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
		fontSizes = { label = f.label, time = f.time, stacks = f.stacks },
		colors = colors,
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

	-- Normalize every phase: look defaults, duration/trigger units default to the
	-- tracker unit, transitions and runtime are present and normalized.
	for _, phase in ipairs(def.phases) do
		phase.look = canonicalLook(phase.look)
		phase.duration = phase.duration or { type = "none" }
		phase.duration.unit = phase.duration.unit or def.unit
		phase.transitions = phase.transitions or {}
		for _, tr in ipairs(phase.transitions) do
			tr.when = canonicalWhen(tr.when, def.unit)
		end
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
