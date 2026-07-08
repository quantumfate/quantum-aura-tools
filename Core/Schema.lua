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
-- "border" draws only an animated square frame whose perimeter drains clockwise as
-- the timer runs out; its background is transparent so it can overlay another phase
-- (e.g. an icon phase) without occluding it. The icon can optionally sit behind it.
-- "bar" is a progress bar with an optional square icon on the left; the bar's height
-- (thin/half/full) and vertical anchor (top/middle/bottom) are configurable and it
-- always shares the row with the icon (never hidden behind it). "gradient" keeps the
-- icon fully lit and sweeps a translucent fill across it in a chosen direction.
-- (The former "barbeside" kind folded into "bar"; it now normalizes to "bar".)
local DISPLAY_KINDS = {
	bar = true,
	icon = true,
	text = true,
	none = true,
	audio = true,
	border = true,
	gradient = true,
	graphic = true,
}
-- Stats a graphic-kind texture rule can switch on (same vocabulary as transitions).
local GRAPHIC_RULE_STATS = { remaining = true, stacks = true }
local COLOR_KEYS = { "background", "bar", "border", "stacks", "text", "timer", "cooldown" }

-- The 9-point alignment a parallel layer uses to sit within the tracker's box (its
-- only positional control — layers stack at the shared origin, no free offset).
QAT.LAYER_ALIGNS = {
	topleft = true,
	top = true,
	topright = true,
	left = true,
	center = true,
	right = true,
	bottomleft = true,
	bottom = true,
	bottomright = true,
}

-- Normalize the graphic-kind texture spec: a default texture plus ordered rules that
-- swap it while a stat threshold holds (first match wins, evaluated at draw time).
local function canonicalGraphic(src)
	src = src or {}
	local rules = {}
	for _, r in ipairs(src.rules or {}) do
		if
			type(r) == "table"
			and GRAPHIC_RULE_STATS[r.stat]
			and r.texture
			and r.texture ~= ""
			and not (QAT.TextureBanned and QAT.TextureBanned(r.texture))
		then
			rules[#rules + 1] = {
				stat = r.stat,
				op = r.op or "<=",
				value = tonumber(r.value) or 0,
				texture = r.texture,
			}
		end
	end
	local default = (src.default ~= nil and src.default ~= "") and src.default or nil
	if default and QAT.TextureBanned and QAT.TextureBanned(default) then
		default = nil
	end
	local align = src.align
	if align ~= "left" and align ~= "right" then
		align = "center"
	end
	return {
		default = default,
		align = align, -- horizontal placement of the aspect-kept texture
		rules = rules,
	}
end

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
	local icon = src.icon
	if icon and QAT.TextureBanned and QAT.TextureBanned(icon) then
		icon = nil -- refuse a reserved texture (e.g. the GM circle) as an icon override
	end
	return {
		display = display,
		name = src.name,
		icon = icon,
		decimals = src.decimals,
		showStacks = src.showStacks or false,
		showTime = src.showTime ~= false, -- default on; the time number is the common readout
		showIcon = src.showIcon ~= false, -- unified icon gate for all icon-capable kinds (default on)
		font = src.font, -- optional LibMediaProvider font family name (nil = default face)
		fontSizes = { label = f.label, time = f.time, stacks = f.stacks },
		colors = colors,
		borderThickness = src.borderThickness, -- nil = default 1px
		-- border-kind options (the icon behind the frame is now the unified showIcon).
		-- borderStyle: "drain" empties the frame as time runs out; "fill" grows it.
		borderStyle = src.borderStyle == "fill" and "fill" or "drain",
		lowThreshold = src.lowThreshold, -- seconds; below this the frame recolors/pulses (nil = off)
		lowColor = src.lowColor, -- rgba for the low-time state
		lowPulse = src.lowPulse or false, -- also pulse the frame alpha while low
		-- bar-kind options (icon is optional; bar shares the row and resizes for it)
		barHeight = src.barHeight or "full", -- "thin" | "half" | "full"
		barAnchor = src.barAnchor or "middle", -- "top" | "middle" | "bottom"
		-- gradient-kind options: always a reveal (fill = remaining time); only the
		-- direction it drains from is configurable.
		sweepDir = src.sweepDir or "rtl", -- "ltr" | "rtl" | "ttb" | "btt"
		sweepColor = src.sweepColor, -- optional rgba tint for the translucent fill
		-- graphic-kind: a curated/custom texture with optional stat-driven swaps.
		graphic = canonicalGraphic(src.graphic),
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
	elseif kind == "source" then
		-- Emitter subscription (dynamic groups): the phase reacts to the group's source
		-- emitting/dropping an element. Resolved to a concrete effect per instance at
		-- build time (see Engine/GridLayout instanceDef); has no ability id here.
		when.result = when.result or "gained"
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

	-- Keep a target debuff on screen after the reticle leaves the target: the phase
	-- holds and runs out on its own timer instead of vanishing, updating only when a
	-- new target is acquired (see Engine/Tracker.lua). Opt-in, aura-wide.
	def.stickyTarget = def.stickyTarget and true or false

	-- Normalize every phase: look defaults, duration/trigger units default to the
	-- tracker unit, transitions and runtime are present and normalized. Transitions
	-- whose target phase no longer exists are dropped.
	for _, phase in ipairs(def.phases) do
		phase.look = canonicalLook(phase.look)
		-- Layer: phases sharing a layer form one mutually-exclusive state machine;
		-- different layers run in parallel and draw in ascending order. Default 0, so
		-- every pre-existing single-layer tracker is unchanged.
		phase.layer = tonumber(phase.layer) or 0
		phase.duration = phase.duration or { type = "none" }
		phase.duration.unit = phase.duration.unit or def.unit
		phase.transitions = phase.transitions or {}
		local kept = {}
		for _, tr in ipairs(phase.transitions) do
			if not tr.to or phaseIds[tr.to] then
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

	-- Per-layer starting phase. def.initial is layer 0's start; other layers keep
	-- theirs in def.layerInitial (keyed by layer number). Each present layer defaults
	-- to its first phase; stale entries for empty layers are dropped.
	local firstOf, seen = {}, {}
	for _, p in ipairs(def.phases) do
		if firstOf[p.layer] == nil then
			firstOf[p.layer] = p.id
		end
		seen[p.id] = p.layer
	end
	def.layerInitial = def.layerInitial or {}
	def.layerInitial[0] = def.initial
	for layer, first in pairs(firstOf) do
		local li = def.layerInitial[layer]
		if not (li and seen[li] == layer) then
			def.layerInitial[layer] = first
		end
	end
	for layer in pairs(def.layerInitial) do
		if firstOf[layer] == nil then
			def.layerInitial[layer] = nil
		end
	end

	-- Per-layer display settings: a 9-point alignment within the tracker's box (so a
	-- small layer can sit centered/right over a wider one) + visibility. Keyed by layer
	-- number; defaulted per present layer, stale entries dropped. Layers only stack at
	-- the shared origin — there is no free x/y offset (that was a misfeature used to
	-- fake tables; the group grid layout is the real table). Legacy offsets are dropped.
	def.layerSettings = def.layerSettings or {}
	for layer in pairs(firstOf) do
		local s = def.layerSettings[layer] or {}
		s.xOffset, s.yOffset = nil, nil
		s.align = QAT.LAYER_ALIGNS[s.align] and s.align or "topleft"
		if s.visible == nil then
			s.visible = true
		end
		def.layerSettings[layer] = s
	end
	for layer in pairs(def.layerSettings) do
		if firstOf[layer] == nil then
			def.layerSettings[layer] = nil
		end
	end

	return def
end

-- Per-element defaults for a grid's drawn chrome. Copied (never shared) into each
-- grid so authored edits stay isolated.
local GRID_STYLE = {
	headerBg = { 0.10, 0.13, 0.18, 1 },
	headerText = { 0.85, 0.90, 0.96, 1 },
	cellBg = { 0.06, 0.08, 0.11, 0.85 },
	cellText = { 0.90, 0.92, 0.95, 1 },
	border = { 0.16, 0.22, 0.30, 1 },
}

local function copyColor(c, fallback)
	if type(c) == "table" then
		return { c[1] or fallback[1], c[2] or fallback[2], c[3] or fallback[3], c[4] or fallback[4] }
	end
	return { fallback[1], fallback[2], fallback[3], fallback[4] }
end

--- Is this def a dynamic group — a folder fed by a target source (emitter) that stamps
--- its single template child once per live target? A distinct kind of group: it is
--- always a grid, binds 1:many (template → targets), and has no free-form members.
---@param def table|nil
---@return boolean
function QAT.IsDynamicGroup(def)
	return def ~= nil
		and def.kind == "folder"
		and def.grid ~= nil
		and def.grid.dynamic ~= nil
		and def.grid.dynamic.source ~= nil
end

--- Is this def a dynamic tracker — a first-class kind that feeds its own phases as a
--- template to a source emitter, stamping one instance per live target?
---@param def table|nil
---@return boolean
function QAT.IsDynamicDef(def)
	return def ~= nil and def.kind == "dynamic"
end

--- Normalize a dynamic tracker def in place. Seeds defaults for source, columns, fill
--- direction, and slot dimensions.
---@param def table dynamic def
function QAT.CanonicalizeDynamicDef(def)
	local sources = QAT.Targeting and QAT.Targeting.SourceNames() or {}
	def.source = def.source or sources[1]
	def.columns = math.max(1, math.floor(tonumber(def.columns) or 2))
	def.fill = def.fill or {}
	def.fill.enabled = true
	if def.fill.axis ~= "cols" then
		def.fill.axis = "rows"
	end
	if def.fill.from ~= "right" and def.fill.from ~= "top" and def.fill.from ~= "bottom" then
		def.fill.from = "left"
	end
	def.maxRows = tonumber(def.maxRows) or nil
	def.sortBy = def.sortBy or "timeLeft"
	def.sortDir = def.sortDir or "asc"
	def.pos = def.pos or {}
	def.pos.width = math.max(16, math.floor(tonumber(def.pos.width) or 220))
	def.pos.height = math.max(8, math.floor(tonumber(def.pos.height) or 30))
	def.slot = nil
end

--- Normalize a folder's optional grid (table-layout) block in place. Absent grid =
--- the folder is a plain logical group. Prunes label arrays to the row/column count,
--- drops cell assignments that point outside the grid or at a non-member tracker,
--- enforces the "fill perpendicular to headers" rule, and fills style defaults.
---@param def table folder def
function QAT.CanonicalizeGrid(def)
	local g = def.grid
	if not g then
		return
	end
	g.enabled = g.enabled == true
	g.cols = math.max(1, math.floor(tonumber(g.cols) or 2))
	g.rows = math.max(1, math.floor(tonumber(g.rows) or 2))
	if g.colHeaders == nil then
		g.colHeaders = false
	end
	if g.rowHeaders == nil then
		g.rowHeaders = false
	end

	-- Header labels are free text, one per column/row; trim any past the current count.
	g.colLabels = g.colLabels or {}
	g.rowLabels = g.rowLabels or {}
	for i = #g.colLabels, g.cols + 1, -1 do
		g.colLabels[i] = nil
	end
	for i = #g.rowLabels, g.rows + 1, -1 do
		g.rowLabels[i] = nil
	end

	-- Cell assignments: "r{n}c{n}" -> member tracker id. Drop any that fall outside the
	-- grid, target a non-member (or a sub-folder), or duplicate an already-placed member.
	local members = {}
	for _, c in ipairs(def.children or {}) do
		if c.kind ~= "folder" then
			members[c.id] = true
		end
	end
	g.cells = g.cells or {}
	local placed = {}
	for key, tid in pairs(g.cells) do
		local r, c = tostring(key):match("^r(%d+)c(%d+)$")
		r, c = tonumber(r), tonumber(c)
		if not r or r < 1 or r > g.rows or c < 1 or c > g.cols or not members[tid] or placed[tid] then
			g.cells[key] = nil
		else
			placed[tid] = true
		end
	end

	-- Fake-growth reflow. `axis` is the packing direction (rows = pack horizontally
	-- within each row; cols = pack vertically within each column); `from` is the side
	-- growth starts from. Fill and headers are independent — headers stay drawn at their
	-- fixed track positions while the cells pack, so either combination is allowed.
	g.fill = g.fill or {}
	g.fill.enabled = g.fill.enabled == true
	if g.fill.axis ~= "cols" then
		g.fill.axis = "rows"
	end
	if g.fill.from ~= "left" then
		g.fill.from = "right"
	end

	-- Drawn-chrome style.
	local s = g.style or {}
	s.headerBg = copyColor(s.headerBg, GRID_STYLE.headerBg)
	s.headerText = copyColor(s.headerText, GRID_STYLE.headerText)
	s.cellBg = copyColor(s.cellBg, GRID_STYLE.cellBg)
	s.cellText = copyColor(s.cellText, GRID_STYLE.cellText)
	s.border = copyColor(s.border, GRID_STYLE.border)
	s.borderWidth = math.max(0, math.floor(tonumber(s.borderWidth) or 1))
	s.corner = math.max(0, math.floor(tonumber(s.corner) or 4))
	s.gap = math.max(0, math.floor(tonumber(s.gap) or 6))
	s.striped = s.striped == true
	g.style = s

	-- Horizontal placement of each member within its cell (vertical stays centered).
	if g.align ~= "left" and g.align ~= "right" then
		g.align = "center"
	end

	-- Dynamic mode: instead of authored cell->member assignments, the grid is fed by a
	-- named target source (see Engine/Targeting) that yields an unknown-count set of live
	-- entries; the layout pass packs them into cells using a reusable slot pool. `slot` is
	-- each entry's footprint. Absent `source` = plain (authored) grid.
	if g.dynamic then
		local d = g.dynamic
		if type(d) ~= "table" or not d.source or d.source == "" then
			g.dynamic = nil
		else
			local slot = d.slot or {}
			g.dynamic = {
				source = d.source,
				slot = {
					width = math.max(16, math.floor(tonumber(slot.width) or 220)),
					height = math.max(8, math.floor(tonumber(slot.height) or 30)),
				},
			}
		end
	end

	-- Origin: the grid draws as one movable unit from a top-left corner. Seed a grid
	-- near screen-centre the first time it is enabled (plain folders default to the
	-- origin in CanonicalizeFolder so existing member coordinates render unchanged).
	if g.enabled and not def.pos then
		def.pos = { x = math.floor((GuiRoot and GuiRoot:GetWidth() or 1920) / 2) - 120, y = 300 }
	end
end

--- Normalize a group/folder def: guarantee a screen anchor (its top-left corner).
--- Members are positioned relative to this anchor, so a plain folder defaults to the
--- origin — existing absolute member coordinates then render exactly where they were.
---@param def table folder def
function QAT.CanonicalizeFolder(def)
	QAT.CanonicalizeGrid(def) -- seeds a grid origin when grid mode is on
	def.pos = def.pos or { x = 0, y = 0 }
	def.pos.x = tonumber(def.pos.x) or 0
	def.pos.y = tonumber(def.pos.y) or 0
end

--- Canonicalize a whole tracker tree in place (recurses into folder children).
---@param defs table[] array of tracker/folder defs
function QAT.CanonicalizeTree(defs)
	for _, def in ipairs(defs or {}) do
		if def.kind == "folder" then
			def.children = def.children or {}
			QAT.CanonicalizeTree(def.children)
			QAT.CanonicalizeFolder(def) -- after children, so member-id pruning sees them
		elseif def.kind == "dynamic" then
			QAT.CanonicalizeDef(def)
			QAT.CanonicalizeDynamicDef(def)
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
		return QAT.util.UniqueSlug(text, fallback, used)
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
