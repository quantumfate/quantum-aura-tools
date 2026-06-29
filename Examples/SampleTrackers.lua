-- Hand-authored test trackers (no editor yet).
--
-- Two shapes are shown:
--   1. Legacy single-phase defs (M1) - still valid; the normalizer wraps them
--      in one implicit "active" phase.
--   2. A phased def (M2) - the Huntsman warmask aura as ONE tracker that changes
--      appearance across Ready -> Active -> Cooldown -> Ready.
--
-- All ability ids here are placeholders to verify wiring; swap them once the
-- M5 ID viewer can confirm live values.

QAT.Examples = {
	-- 1) Simple buff-uptime trackers (legacy shape).
	{
		id = "sample_major_resolve",
		kind = "tracker",
		display = "bar",
		name = "Major Resolve",
		abilityIds = { 61694 },
		unit = "player",
		effectType = "buff",
		point = CENTER,
		x = 0,
		y = -220,
		color = { 0.20, 0.55, 0.90, 1 },
		-- Runtime condition: turn the bar red when under 3s remaining.
		runtime = {
			{ stat = "remaining", op = "<", value = 3, action = "color", color = { 0.85, 0.15, 0.15, 1 } },
		},
	},
	{
		id = "sample_rapid_text",
		kind = "tracker",
		display = "text",
		name = "Rapid Maneuver",
		abilityIds = { 40211 },
		unit = "player",
		effectType = "buff",
		point = CENTER,
		x = 0,
		y = -185,
		color = { 0.20, 0.80, 0.35, 1 },
	},

	-- 2) Phased proc-with-lockout (the design's flagship example).
	{
		id = "sample_huntsman",
		kind = "tracker",
		unit = "player",
		pos = { point = CENTER, x = 0, y = -150, width = 240, height = 34 },
		initial = "ready",
		phases = {
			{
				id = "ready",
				look = { display = "icon", name = "Huntsman: READY", color = { 1, 0.85, 0.2, 1 } },
				duration = { type = "none" },
				-- reached as the initial phase and via cooldown's onExpire
			},
			{
				id = "active",
				look = { display = "bar", name = "Huntsman", color = { 0.20, 0.80, 0.35, 1 } },
				duration = { type = "effect", abilityIds = { 999001 }, unit = "player" },
				enter = {
					{ kind = "effect", abilityIds = { 999001 }, result = "gained", unit = "player" },
				},
			},
			{
				id = "cooldown",
				look = { display = "bar", name = "Huntsman: CD", color = { 0.55, 0.55, 0.55, 1 } },
				duration = { type = "fixed", seconds = 60 },
				onExpire = "ready",
				enter = {
					{
						kind = "effect",
						abilityIds = { 999001 },
						result = "faded",
						unit = "player",
						from = { "active" },
					},
				},
			},
		},
	},
}
