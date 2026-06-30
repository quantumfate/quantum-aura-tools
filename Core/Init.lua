-- Quantum's Aura Tools — core bootstrap.
-- Owns the namespace, SavedVariables, the migration runner, and slash commands.

QAT = {
	name = "QuantumAuraTools",
	displayName = "Quantum's Aura Tools",
	author = "Quantum (quantumfate)",
	version = "0.1.0",
	-- Internal data-schema version. Independent of the ZO_SavedVars version
	-- (which we keep pinned at 1 so it never wipes data); migrations below own
	-- all schema evolution. See Core/Migrations.lua.
	schemaVersion = 4,
	slash = "/qat",
}

-- Default account-wide saved state. Anything added here later must also get a
-- migration step so existing installs gain the field without losing data.
QAT.defaults = {
	schemaVersion = QAT.schemaVersion,
	account = {
		enabled = true,
		backgroundCapture = false, -- passive recently-seen recording; off by default
		capturePopupSeen = false, -- whether the one-time capture popup has been dismissed
		examplesSeeded = false, -- whether starter example trackers were seeded once
		addTrackerHintSeen = false, -- whether the "trackers start hidden" hint was dismissed for good
	},
	trackers = {}, -- tree of tracker and folder defs
	userLibrary = {}, -- user-captured ability ids, kept separate from the bundled library
	editor = { -- editor window geometry
		x = 200,
		y = 200,
		width = 1080,
		height = 560,
		treeWidth = 300,
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

-- Re-add any deleted example trackers. They are restored into SavedVariables and
-- the editor tree immediately; a /reloadui makes them render on the HUD.
function QAT.RestoreExamples()
	local n = addMissingExamples()
	if QAT.widgets and QAT.widgets.NotifyTrackerChanged then
		QAT.widgets.NotifyTrackerChanged()
	end
	d(QAT.displayName .. ": restored " .. n .. " example tracker(s). /reloadui to show them on screen.")
	return n
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
	QAT.Safe("Runtime_Init", QAT.Runtime_Init)
	QAT.Safe("Editor_Init", QAT.Editor_Init)

	QAT.log.root:Info("%s v%s loaded (schema %d)", QAT.displayName, QAT.version, QAT.sv.schemaVersion)
end

-- /qat                -> open the settings panel
-- /qat capture on|off -> toggle passive background capture
-- /qat help           -> list commands
local function HandleSlash(args)
	args = zo_strlower(zo_strtrim(args or ""))
	if args == "" or args == "settings" or args == "config" then
		if LibAddonMenu2 then
			LibAddonMenu2:OpenToPanel(QAT.settingsPanel)
		end
		return
	end
	if args == "capture on" or args == "capture off" then
		local on = (args == "capture on")
		QAT.sv.account.backgroundCapture = on
		d(QAT.displayName .. ": background capture " .. (on and "ENABLED" or "DISABLED"))
		return
	end
	if args == "restore examples" or args == "examples" then
		QAT.RestoreExamples()
		return
	end
	d(QAT.displayName .. " commands:")
	d("  /qat                 open settings")
	d("  /qat capture on|off  toggle passive ID capture")
	d("  /qat restore examples  re-add deleted example trackers")
end
SLASH_COMMANDS["/qat"] = HandleSlash

EVENT_MANAGER:RegisterForEvent(QAT.name, EVENT_ADD_ON_LOADED, OnAddOnLoaded)
