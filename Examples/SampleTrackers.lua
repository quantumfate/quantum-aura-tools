-- Hand-authored example trackers, loaded by the runtime alongside saved ones.
--
-- All trackers use the canonical phased shape: a tracker has `phases`, and each
-- phase's `look.display` is its render kind (bar / icon / text / none). A
-- single-phase tracker is simply one phase. (A flat shorthand without `phases`
-- is also accepted on import and expanded to this shape; these examples are
-- written canonically to show the real model.)
--
-- The ability ids here are placeholders for wiring; confirm real values with the
-- in-game ID viewer.

QAT.Examples = {
	-- Single-phase bar: shows a buff's remaining time, red under 3s.
	{
		id = "sample_major_resolve",
		kind = "tracker",
		name = "Major Resolve",
		unit = "player",
		pos = { point = CENTER, x = 0, y = -220, width = 220, height = 30 },
		phases = {
			{
				id = "active",
				look = { display = "bar", name = "Major Resolve", color = { 0.20, 0.55, 0.90, 1 } },
				duration = { type = "effect", abilityIds = { 61694 } },
				enter = { { kind = "effect", abilityIds = { 61694 }, result = "gained" } },
			},
		},
		runtime = {
			{ stat = "remaining", op = "<", value = 3, action = "color", color = { 0.85, 0.15, 0.15, 1 } },
		},
	},

	-- Single-phase text.
	{
		id = "sample_rapid_text",
		kind = "tracker",
		name = "Rapid Maneuver",
		unit = "player",
		pos = { point = CENTER, x = 0, y = -185 },
		phases = {
			{
				id = "active",
				look = { display = "text", name = "Rapid Maneuver", color = { 0.20, 0.80, 0.35, 1 } },
				duration = { type = "effect", abilityIds = { 40211 } },
				enter = { { kind = "effect", abilityIds = { 40211 }, result = "gained" } },
			},
		},
	},

	-- Single-phase icon: an ability icon that desaturates when not active.
	{
		id = "sample_icon",
		kind = "tracker",
		name = "Inner Light",
		unit = "player",
		pos = { point = CENTER, x = -120, y = -150, width = 40, height = 40 },
		phases = {
			{
				id = "active",
				look = { display = "icon", name = "Inner Light", icon = "/esoui/art/icons/ability_mageguild_002.dds" },
				duration = { type = "effect", abilityIds = { 30920 } },
				enter = { { kind = "effect", abilityIds = { 30920 }, result = "gained" } },
			},
		},
	},

	-- Phased proc with a fixed-timer lockout: one tracker, three looks.
	{
		id = "sample_huntsman",
		kind = "tracker",
		name = "Huntsman",
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
				duration = { type = "effect", abilityIds = { 999001 } },
				enter = { { kind = "effect", abilityIds = { 999001 }, result = "gained" } },
				cues = { flash = { color = { 0.2, 0.8, 0.3, 0.35 }, duration = 250 } },
			},
			{
				id = "cooldown",
				look = { display = "bar", name = "Huntsman: CD", color = { 0.55, 0.55, 0.55, 1 } },
				duration = { type = "fixed", seconds = 60 },
				onExpire = "ready",
				enter = {
					{ kind = "effect", abilityIds = { 999001 }, result = "faded", from = { "active" } },
				},
			},
		},
	},
}
