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
			type = "dropdown",
			name = "UI font",
			tooltip = "Font family for the editor and aggregator windows "
				.. "(from LibMediaProvider). Tracker HUD readouts keep their own per-phase fonts.",
			choices = (function()
				local c = { "Default" }
				for _, f in ipairs(QAT.util.FontList()) do
					c[#c + 1] = f
				end
				return c
			end)(),
			getFunc = function()
				return account.uiFont or "Default"
			end,
			setFunc = function(v)
				account.uiFont = (v ~= "Default") and v or nil
			end,
			default = "Default",
			requiresReload = true,
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
		{
			type = "checkbox",
			name = "Persist captured effects",
			tooltip = "Keep captured effects across reloads and sessions (the standing "
				.. "library the viewer shows). Turn off to keep them only for the current "
				.. "session. Favourites are always kept.",
			getFunc = function()
				return account.persistCapture ~= false
			end,
			setFunc = function(v)
				account.persistCapture = v
			end,
			default = QAT.defaults.account.persistCapture,
		},
		{
			type = "button",
			name = "Clear captured library",
			tooltip = "Forget every persisted captured effect. Favourites are kept.",
			warning = "This cannot be undone.",
			isDangerous = true,
			func = function()
				if QAT.Capture_ForgetLibrary then
					QAT.Capture_ForgetLibrary()
				end
			end,
		},
	}

	LAM:RegisterOptionControls(QAT.name .. "Panel", optionsData)
end
