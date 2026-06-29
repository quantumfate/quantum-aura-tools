-- Hand-authored test trackers for M1 (no editor yet).
--
-- These let us verify the engine in-game by slotting a known skill and watching
-- the bar count down. They are loaded by the Runtime alongside saved trackers
-- and will be removed once the editor (M4) can create real ones.

QAT.Examples = {
    {
        id = "sample_major_resolve",
        kind = "tracker",
        display = "bar",
        name = "Major Resolve",
        -- Major Resolve buff id (e.g. from Ironclad / many sources). Verify live
        -- with the ID viewer in M5; easy to swap.
        abilityIds = { 61694 },
        unit = "player",
        effectType = "buff",
        point = CENTER, x = 0, y = -220,
        color = { 0.20, 0.55, 0.90, 1 },
    },
    {
        id = "sample_self_buff_text",
        kind = "tracker",
        display = "text",
        name = "Rapid Maneuver",
        abilityIds = { 40211 },
        unit = "player",
        effectType = "buff",
        point = CENTER, x = 0, y = -185,
        color = { 0.20, 0.80, 0.35, 1 },
    },
}
