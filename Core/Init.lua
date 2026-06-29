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
	schemaVersion = 2,
	slash = "/qat",
}

-- Default account-wide saved state. Anything added here later must also get a
-- migration step so existing installs gain the field without losing data.
QAT.defaults = {
	schemaVersion = QAT.schemaVersion,
	account = {
		enabled = true,
		backgroundCapture = false, -- passive recently-seen recording; off by default
		capturePopupSeen = false, -- one-time editor popup (shown in a later milestone)
	},
	trackers = {}, -- tree of trackers / folder-groups (M1+)
	userLibrary = {}, -- user-captured raid IDs, separate from the bundled library (M6)
	editor = { -- editor window geometry (schema 2)
		x = 200,
		y = 200,
		width = 900,
		height = 560,
		treeWidth = 260,
	},
}

local logger
local function Log(...)
	if logger then
		logger:Info(...)
	end
end
QAT.Log = Log

local function OnAddOnLoaded(_, addonName)
	if addonName ~= QAT.name then
		return
	end
	EVENT_MANAGER:UnregisterForEvent(QAT.name, EVENT_ADD_ON_LOADED)

	if LibDebugLogger then
		logger = LibDebugLogger.Create(QAT.name)
		QAT.logger = logger
	end

	-- ZO version pinned at 1 on purpose; QAT.RunMigrations handles schema drift.
	QAT.sv = ZO_SavedVars:NewAccountWide("QuantumAuraToolsSV", 1, nil, QAT.defaults)
	QAT.RunMigrations(QAT.sv)

	QAT.Settings_Register()
	QAT.Runtime_Init()
	QAT.Editor_Init()

	Log("%s v%s loaded (schema %d)", QAT.displayName, QAT.version, QAT.sv.schemaVersion)
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
	d(QAT.displayName .. " commands:")
	d("  /qat                 open settings")
	d("  /qat capture on|off  toggle passive ID capture")
end
SLASH_COMMANDS["/qat"] = HandleSlash

EVENT_MANAGER:RegisterForEvent(QAT.name, EVENT_ADD_ON_LOADED, OnAddOnLoaded)
