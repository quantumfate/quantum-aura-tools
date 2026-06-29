--- Account-wide options panel, registered in the native Settings -> Addons menu
--- via LibAddonMenu-2. Global options only; per-tracker authoring is in the
--- editor window.

function QAT.Settings_Register()
	local LAM = LibAddonMenu2
	if not LAM then
		d(QAT.displayName .. ": LibAddonMenu-2.0 missing — settings panel unavailable.")
		return
	end

	local account = QAT.sv.account

	local panelData = {
		type = "panel",
		name = QAT.displayName,
		displayName = QAT.displayName,
		author = QAT.author,
		version = QAT.version,
		registerForRefresh = true,
		registerForDefaults = true,
		slashCommand = "/qatsettings",
		website = "https://github.com/quantumfate/quantums-uptime",
	}

	QAT.settingsPanel = LAM:RegisterAddonPanel(QAT.name .. "Panel", panelData)

	local optionsData = {
		{
			type = "header",
			name = "General",
		},
		{
			type = "checkbox",
			name = "Enabled",
			tooltip = "Master switch for all trackers.",
			getFunc = function()
				return account.enabled
			end,
			setFunc = function(v)
				account.enabled = v
			end,
			default = QAT.defaults.account.enabled,
		},
		{
			type = "header",
			name = "ID Capture",
		},
		{
			type = "description",
			text = "Background capture passively records recently-seen skill "
				.. "effects so the viewer is populated when you open it. It is "
				.. "off by default to save resources; enable it while hunting "
				.. "ability IDs, then turn it back off.",
		},
		{
			type = "checkbox",
			name = "Background ID capture",
			tooltip = "Record recently-seen effects even when no viewer is open. "
				.. "Independent of the tracker runtime.",
			getFunc = function()
				return account.backgroundCapture
			end,
			setFunc = function(v)
				account.backgroundCapture = v
			end,
			default = QAT.defaults.account.backgroundCapture,
			warning = "Adds a persistent combat-event subscription while on.",
		},
	}

	LAM:RegisterOptionControls(QAT.name .. "Panel", optionsData)
end
