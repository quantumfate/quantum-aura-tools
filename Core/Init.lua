-- Quantum's Aura Tools — core bootstrap.
-- Owns the namespace, SavedVariables, the migration runner, and slash commands.

QAT = {
	name = "QuantumAuraTools",
	displayName = "Quantum's Aura Tools",
	author = "@quantumfate",
	version = "0.2.0-beta3",
	-- Internal data-schema version. Independent of the ZO_SavedVars version
	-- (which we keep pinned at 1 so it never wipes data); migrations below own
	-- all schema evolution. See Core/Migrations.lua.
	schemaVersion = 12,
	slash = "/qat",
}

-- Default account-wide saved state. Anything added here later must also get a
-- migration step so existing installs gain the field without losing data.
QAT.defaults = {
	schemaVersion = QAT.schemaVersion,
	account = {
		enabled = true,
		backgroundCapture = false, -- passive recently-seen recording; off by default
		persistCapture = true, -- keep captured effects across reloads (the standing library)
		capturePopupSeen = false, -- whether the one-time capture popup has been dismissed
		uiFont = "default", -- LibMediaProvider font key for editor chrome (default = game font)
		customSources = {}, -- user-defined Lua target sources
		editorWidth = nil, -- unpinned: the editor remembers its last width
		editorHeight = nil, -- unpinned
		editorX = nil, -- unpinned
		editorY = nil, -- unpinned
	},
	trackers = {}, -- tree of tracker and folder defs
	userLibrary = {}, -- user-captured ability ids, kept separate from the bundled library
	capture = { -- effect-aggregator persistence
		records = {}, -- key -> frozen CapturedEffect, the standing library (persist-by-default)
		favourites = {}, -- key -> frozen CapturedEffect record, floated to the top
		ignored = {}, -- abilityId -> true, permanently suppressed known-noise
	},
	editor = { -- editor window geometry
		x = 200,
		y = 200,
		width = 1080,
		height = 560,
		treeWidth = 340,
	},
}

-- Copy the bundled example trackers into saved data once, so they appear in the
-- Add any bundled example trackers not already present (matched by id), as
-- canonical copies. Returns how many were added. Used both for the one-time seed
-- and for an explicit restore.
local function addMissingExamples()
	if not QAT.Examples then
		return 0
	end
	local present = {}
	for _, def in ipairs(QAT.sv.trackers) do
		present[def.id] = true
	end
	local added = 0
	for _, example in ipairs(QAT.Examples) do
		if not present[example.id] then
			local copy = QAT.util.DeepCopy(example)
			QAT.CanonicalizeDef(copy)
			table.insert(QAT.sv.trackers, copy)
			added = added + 1
		end
	end
	return added
end

-- Copy the bundled example trackers into saved data once, so they appear in the
-- editor tree and are editable. After this one-time seed the trackers live solely
-- in SavedVariables; deleting them is permanent unless explicitly restored.
local function SeedExamples()
	if QAT.sv.account.examplesSeeded then
		return
	end
	QAT.sv.account.examplesSeeded = true
	local n = addMissingExamples()
	QAT.log.root:Info("seeded %d example tracker(s)", n)
end

-- Example custom-source code that demonstrates the taunt binding format, used as
-- a teaching reference in the Source Manager.
local TAUNT_EXAMPLE_CODE = [=[
-- Taunt example: returns mock bindings for demonstration.
-- Replace with your own logic that returns {key, name, remaining, duration, ...} per target.
-- `now` = GetFrameTimeSeconds() float.
function(now)
	local targets = {
		{ key = 1001, name = "Dummy Tank", remaining = 9.2, duration = 15 },
		{ key = 1002, name = "Overseer Naemon", remaining = 4.7, duration = 15 },
	}
	local out = {}
	for _, t in ipairs(targets) do
		t.remaining = t.remaining - (now % 1) * 0.3 -- simulate countdown
		if t.remaining > 0 then
			table.insert(out, {
				key = t.key,
				name = t.name,
				remaining = t.remaining,
				duration = t.duration,
				beginTime = now - (t.duration - t.remaining),
				endTime = now + t.remaining,
				stacks = 0,
			})
		end
	end
	table.sort(out, function(a, b) return a.remaining < b.remaining end)
	return out
end
]=]

-- Re-add any deleted example trackers and example custom sources. They are restored
-- into SavedVariables immediately; a /reloadui makes the trackers render on the HUD.
function QAT.RestoreExamples()
	local n = addMissingExamples()

	-- Restore the taunt example custom source if missing (teaching reference).
	QAT.sv.account = QAT.sv.account or {}
	QAT.sv.account.customSources = QAT.sv.account.customSources or {}
	if not QAT.sv.account.customSources["taunt_example"] then
		QAT.sv.account.customSources["taunt_example"] = TAUNT_EXAMPLE_CODE
		if QAT.Targeting then
			QAT.Targeting.RegisterCode("taunt_example", TAUNT_EXAMPLE_CODE)
		end
		n = n + 1
	end

	if QAT.widgets and QAT.widgets.NotifyTrackerChanged then
		QAT.widgets.NotifyTrackerChanged()
	end
	d(QAT.displayName .. ": restored " .. n .. " example(s). /reloadui to show trackers on screen.")
	return n
end

-- Create the "Taunts" dynamic tracker if it isn't already present: a `kind="dynamic"`
-- entry fed by the taunt source, so every enemy the player has taunted shows as a name +
-- remaining-time bar that packs/unpacks live.
local TAUNT_DYN_ID = "qat_taunt_dyn"
function QAT.SeedTauntTracker()
	for _, def in ipairs(QAT.sv.trackers) do
		if def.id == TAUNT_DYN_ID then
			d(QAT.displayName .. ": taunt tracker already exists (see the editor tree).")
			return
		end
	end
	local cx = math.floor((GuiRoot and GuiRoot:GetWidth() or 1920) / 2) - 110
	local def = QAT.CanonicalizeDef({
		id = TAUNT_DYN_ID,
		kind = "dynamic",
		name = "Taunts",
		enabled = true,
		source = "taunt",
		columns = 1,
		fill = { axis = "rows", from = "left" },
		pos = { x = cx, y = 260, width = 220, height = 30 },
		initial = "idle",
		phases = {
			{
				id = "idle",
				layer = 0,
				look = { display = "none" },
				duration = { type = "none" },
				transitions = { { when = { kind = "source", result = "gained" }, to = "active" } },
			},
			{
				id = "active",
				layer = 0,
				look = { display = "bar", showTime = true },
				duration = { type = "source" },
				transitions = {},
			},
		},
	})
	QAT.CanonicalizeDynamicDef(def)
	table.insert(QAT.sv.trackers, def)
	if QAT.widgets and QAT.widgets.NotifyTrackerChanged then
		QAT.widgets.NotifyTrackerChanged()
	end
	d(QAT.displayName .. ": added the Taunts dynamic tracker. Taunt an enemy to see it fill.")
end

local function OnAddOnLoaded(_, addonName)
	if addonName ~= QAT.name then
		return
	end
	EVENT_MANAGER:UnregisterForEvent(QAT.name, EVENT_ADD_ON_LOADED)

	QAT.SetupLogging()
	QAT.log.root:Info("OnAddOnLoaded: bootstrapping %s v%s", QAT.displayName, QAT.version)

	-- ZO version pinned at 1 on purpose; QAT.RunMigrations handles schema drift.
	QAT.sv = ZO_SavedVars:NewAccountWide("QuantumAuraToolsSV", 1, nil, QAT.defaults)
	QAT.RunMigrations(QAT.sv)
	SeedExamples()
	QAT.log.root:Debug("SavedVars ready: %d top-level tracker(s), schema %d", #QAT.sv.trackers, QAT.sv.schemaVersion)

	-- Each subsystem is guarded so a failure logs with context instead of
	-- aborting the rest of load (critical while the UI is unverified in-game).
	QAT.Safe("Settings_Register", QAT.Settings_Register)
	QAT.Safe("Targeting_Init", QAT.Targeting_Init)
	QAT.Safe("Runtime_Init", QAT.Runtime_Init)
	QAT.Safe("Capture_Init", QAT.Capture_Init)
	QAT.Safe("Editor_Init", QAT.Editor_Init)
	QAT.Safe("Aggregator_Init", QAT.Aggregator_Init)
	if AddonCategory then
		AddonCategory.AssignAddonToCategory(addonName, AddonCategory.baseCategories.Combat)
	end
	QAT.log.root:Info("%s v%s loaded (schema %d)", QAT.displayName, QAT.version, QAT.sv.schemaVersion)
end

-- /qat                 -> open the settings panel
-- /qat capture on/off  -> start/stop passive background capture
-- /qat aggregator|agg  -> open the effect aggregator window
-- /qat restore examples-> re-add deleted example trackers
local function HandleSlash(args)
	args = zo_strlower(zo_strtrim(args or ""))
	if args == "" or args == "settings" or args == "config" then
		if LibAddonMenu2 then
			LibAddonMenu2:OpenToPanel(QAT.settingsPanel)
		end
		return
	end
	if args == "capture on" then
		QAT.Capture_Start()
		d(QAT.displayName .. ": background capture ENABLED")
		return
	end
	if args == "capture off" then
		QAT.Capture_Stop()
		d(QAT.displayName .. ": background capture DISABLED")
		return
	end
	if args == "aggregator" or args == "agg" then
		QAT.Aggregator_Toggle()
		return
	end
	if args == "restore examples" or args == "examples" then
		QAT.RestoreExamples()
		return
	end
	if args == "taunt" or args == "taunts" then
		QAT.SeedTauntTracker()
		return
	end
	if args == "taunt test" then
		QAT.Targeting_TestTaunts(3)
		d(QAT.displayName .. ": injected 3 test taunts (expire in ~12-20s).")
		return
	end
	-- "on / off" not "on|off": the pipe is ESO's colour-escape char and is eaten.
	d(QAT.displayName .. " commands:")
	d("  /qat                   open settings")
	d("  /qat capture on / off  start / stop passive ID capture")
	d("  /qat aggregator (agg)  open the effect aggregator window")
	d("  /qat restore examples  re-add deleted example trackers")
	d("  /qat taunt             add the dynamic taunt tracker")
end
SLASH_COMMANDS["/qat"] = HandleSlash

EVENT_MANAGER:RegisterForEvent(QAT.name, EVENT_ADD_ON_LOADED, OnAddOnLoaded)
