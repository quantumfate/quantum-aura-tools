-- Canonical tracker schema and the transform that produces it.
--
-- A tracker is stored in one canonical shape:
--
--   {
--     id, kind = "tracker", name, unit,
--     enabled = true,
--     pos   = { point, x, y, width, height },
--     initial = <phaseId> | nil,          -- starting phase, nil = start idle
--     phases  = {                          -- the state machine
--       {
--         id,
--         look    = { display = "bar"|"icon"|"text"|"none",
--                     name, color, icon, font, decimals, bgColor },
--         duration = { type = "none"|"fixed"|"effect", seconds?, abilityIds?, unit? },
--         enter   = { <trigger>, ... },    -- effect triggers that enter this phase
--         onExpire = <phaseId> | nil,      -- where a timed phase goes when it ends
--         cues    = { sound, flash } | nil,-- additive on-enter cues (not a look)
--       }, ...
--     },
--     runtime = { <condition>, ... } | nil,
--     load    = { ... } | nil,
--   }
--
-- A flat single-phase shorthand is accepted as authoring/import convenience and
-- expanded here into the canonical form. Folders are passed through unchanged
-- except for recursion into children.

local DISPLAY_KINDS = { bar = true, icon = true, text = true, none = true }

local function canonicalLook(src)
	local display = src.display
	if not DISPLAY_KINDS[display] then
		display = "bar"
	end
	return {
		display = display,
		name = src.name,
		color = src.color,
		icon = src.icon,
		font = src.font,
		decimals = src.decimals,
		bgColor = src.bgColor,
	}
end

--- Convert one tracker def to canonical form in place. Idempotent: a def that is
--- already canonical is only normalized for defaults.
---@param def table tracker def (flat shorthand or canonical)
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
		-- Flat shorthand -> a single "active" phase shown while the buff is up.
		def.phases = {
			{
				id = "active",
				look = canonicalLook(def),
				duration = { type = "effect", abilityIds = def.abilityIds or {} },
				enter = {
					{ kind = "effect", abilityIds = def.abilityIds or {}, result = "gained" },
				},
			},
		}
		def.initial = nil
		-- Drop the consumed flat look/source fields.
		def.display = nil
		def.color, def.icon, def.font, def.decimals, def.abilityIds, def.effectType = nil, nil, nil, nil, nil, nil
	end

	-- Normalize every phase: look defaults, and default the unit on the duration
	-- and on each effect trigger to the tracker's unit (so authored phases can
	-- omit it for the common "on the player" case).
	for _, phase in ipairs(def.phases) do
		phase.look = canonicalLook(phase.look or {})
		phase.duration = phase.duration or { type = "none" }
		phase.duration.unit = phase.duration.unit or def.unit
		phase.enter = phase.enter or {}
		for _, trig in ipairs(phase.enter) do
			if trig.kind == "effect" then
				trig.unit = trig.unit or def.unit
				trig.result = trig.result or "gained"
			end
		end
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
