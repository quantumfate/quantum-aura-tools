-- Hand-authored example trackers, loaded by the runtime alongside saved ones.
--
-- All trackers use the canonical model: phases plus source-attached transitions,
-- with idle expressed as a real (hidden) phase. Effect transitions fire on
-- EVENT_EFFECT_CHANGED; "stacks"/"remaining" transitions are polled each tick;
-- "expire" fires when a phase's timer runs out. The common "show a buff's uptime"
-- case is Idle <-> Active.
--
-- The ability ids here are placeholders for wiring; confirm real values with the
-- in-game ID viewer.

QAT.Examples = {
	-- Single buff (bar): Idle until the buff is gained, then Active with its uptime,
	-- bar turns red under 3s via a per-phase runtime condition.
	{
		id = "sample_major_resolve",
		kind = "tracker",
		name = "Major Resolve",
		unit = "player",
		pos = { x = 850, y = 300, width = 220, height = 30 },
		initial = "idle",
		phases = {
			{
				id = "idle",
				look = { display = "none" },
				duration = { type = "none" },
				transitions = {
					{ when = { kind = "effect", result = "gained", abilityIds = { 61694 } }, to = "active" },
				},
			},
			{
				id = "active",
				look = { display = "bar", name = "Major Resolve", colors = { bar = { 0.20, 0.55, 0.90, 1 } } },
				duration = { type = "effect", abilityIds = { 61694 } },
				transitions = { { when = { kind = "effect", result = "faded", abilityIds = { 61694 } }, to = "idle" } },
				runtime = {
					{
						stat = "remaining",
						op = "<",
						value = 3,
						action = "setBarColor",
						color = { 0.85, 0.15, 0.15, 1 },
					},
				},
			},
		},
	},

	-- Single buff (text).
	{
		id = "sample_rapid_text",
		kind = "tracker",
		name = "Rapid Maneuver",
		unit = "player",
		pos = { x = 850, y = 340 },
		initial = "idle",
		phases = {
			{
				id = "idle",
				look = { display = "none" },
				duration = { type = "none" },
				transitions = {
					{ when = { kind = "effect", result = "gained", abilityIds = { 40211 } }, to = "active" },
				},
			},
			{
				id = "active",
				look = { display = "text", name = "Rapid Maneuver", colors = { text = { 0.20, 0.80, 0.35, 1 } } },
				duration = { type = "effect", abilityIds = { 40211 } },
				transitions = { { when = { kind = "effect", result = "faded", abilityIds = { 40211 } }, to = "idle" } },
			},
		},
	},

	-- Single buff (icon): an ability icon that desaturates when not active.
	{
		id = "sample_icon",
		kind = "tracker",
		name = "Inner Light",
		unit = "player",
		pos = { x = 740, y = 400, width = 40, height = 40 },
		initial = "idle",
		phases = {
			{
				id = "idle",
				look = { display = "none" },
				duration = { type = "none" },
				transitions = {
					{ when = { kind = "effect", result = "gained", abilityIds = { 30920 } }, to = "active" },
				},
			},
			{
				id = "active",
				look = { display = "icon", name = "Inner Light", icon = "/esoui/art/icons/ability_mageguild_002.dds" },
				duration = { type = "effect", abilityIds = { 30920 } },
				transitions = { { when = { kind = "effect", result = "faded", abilityIds = { 30920 } }, to = "idle" } },
			},
		},
	},

	-- Phased proc with a fixed lockout: Ready -> Active (debuff uptime) -> Cooldown
	-- (a fixed timer) -> Ready. Ready is the visible resting state.
	{
		id = "sample_huntsman",
		kind = "tracker",
		name = "Huntsman",
		unit = "player",
		pos = { x = 840, y = 450, width = 240, height = 34 },
		initial = "ready",
		phases = {
			{
				id = "ready",
				look = { display = "icon", name = "Huntsman: READY", colors = { bar = { 1, 0.85, 0.2, 1 } } },
				duration = { type = "none" },
				transitions = {
					{ when = { kind = "effect", result = "gained", abilityIds = { 999001 } }, to = "active" },
				},
			},
			{
				id = "active",
				look = { display = "bar", name = "Huntsman", colors = { bar = { 0.20, 0.80, 0.35, 1 } } },
				duration = { type = "effect", abilityIds = { 999001 } },
				transitions = {
					{ when = { kind = "effect", result = "faded", abilityIds = { 999001 } }, to = "cooldown" },
				},
				cues = { flash = { color = { 0.2, 0.8, 0.3, 0.35 }, duration = 250 } },
			},
			{
				id = "cooldown",
				look = { display = "bar", name = "Huntsman: CD", colors = { bar = { 0.55, 0.55, 0.55, 1 } } },
				duration = { type = "fixed", seconds = 60 },
				transitions = { { when = { kind = "expire" }, to = "ready" } },
			},
		},
	},

	-- Passive stack-builder with no duration (the case HyperTools could not show).
	-- Merciless Resolve is permanent while slotted and builds stacks; the icon shows
	-- the live stack count, and a "proc ready" phase lights up at 5 stacks.
	{
		id = "sample_merciless",
		kind = "tracker",
		name = "Merciless Resolve",
		unit = "player",
		pos = { x = 1040, y = 450, width = 44, height = 44 },
		initial = "idle",
		phases = {
			{
				id = "idle",
				look = { display = "none" },
				duration = { type = "none" },
				transitions = {
					{ when = { kind = "effect", result = "gained", abilityIds = { 61919 } }, to = "building" },
				},
			},
			{
				id = "building",
				look = { display = "icon", name = "Merciless", showStacks = true },
				duration = { type = "effect", abilityIds = { 61919 } }, -- effect-typed so stacks refresh; no real duration = static
				transitions = {
					{ when = { kind = "stacks", op = ">=", value = 5 }, to = "ready" },
					{ when = { kind = "effect", result = "faded", abilityIds = { 61919 } }, to = "idle" },
				},
			},
			{
				id = "ready",
				look = {
					display = "icon",
					name = "Merciless: PROC",
					showStacks = true,
					colors = { stacks = { 1, 0.9, 0.3, 1 } },
				},
				duration = { type = "effect", abilityIds = { 61919 } },
				transitions = {
					{ when = { kind = "stacks", op = "<", value = 5 }, to = "building" },
					{ when = { kind = "effect", result = "faded", abilityIds = { 61919 } }, to = "idle" },
				},
				-- Glow on the icon while proc-ready (the game's ability-proc swirl).
				runtime = {
					{ stat = "stacks", op = ">=", value = 5, action = "showProc" },
				},
			},
		},
	},
}
