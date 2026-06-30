-- Appearance tab: how the selected phase draws. The phase is chosen by the shared
-- phase strip in the header (QAT.editor.selectedPhaseId); only the fields relevant
-- to the chosen Kind are shown.

local PAD = 12
local ROW_H = 26
local GAP = 8

local KIND_OPTS = {
	{ label = "Bar", value = "bar" },
	{ label = "Icon", value = "icon" },
	{ label = "Text", value = "text" },
	{ label = "None (hidden)", value = "none" },
	{ label = "Audio Cue", value = "audio" },
}
local FONT_DEFAULTS = { label = 20, time = 20, stacks = 16 }

local function selectedPhase(def)
	local id = QAT.editor.selectedPhaseId
	for _, p in ipairs(def.phases) do
		if p.id == id then
			return p
		end
	end
	return def.phases[1]
end

local function commit(def)
	QAT.CanonicalizeDef(def)
	QAT.widgets.NotifyTrackerChanged(def.id)
end

local function render(container, def)
	local pool = container.pool or QAT.widgets.NewPool()
	container.pool = pool
	QAT.widgets.PoolBegin(pool)
	local function get(key, factory)
		return QAT.widgets.PoolGet(pool, key, factory)
	end

	QAT.CanonicalizeDef(def)
	local phase = selectedPhase(def)
	if not phase then
		QAT.widgets.PoolEnd(pool)
		return
	end

	local LX = PAD + 110
	local y = PAD

	local function fieldLabel(key, text, yy, tip)
		local l = get(key, function()
			return QAT.widgets.Label(container, "QAT_App_" .. key, "")
		end)
		l:SetText(text)
		l:ClearAnchors()
		l:SetAnchor(TOPLEFT, container, TOPLEFT, PAD, yy + 3)
		QAT.widgets.Tooltip(l, tip)
		return l
	end

	-- Phase id.
	fieldLabel(
		"lId",
		"Phase id",
		y,
		"Internal name for this phase (e.g. Idle, Active, Cooldown). Transitions target phases by this name."
	)
	local idBox = get("idBox", function()
		return QAT.widgets.EditBox(container, "QAT_App_IdBox", 180, ROW_H)
	end)
	idBox.onChange = function(text)
		text = zo_strtrim(text)
		if text ~= "" then
			local was = phase.id
			phase.id = text
			if def.initial == was then
				def.initial = text
			end
			-- repoint transitions that targeted this phase
			for _, p in ipairs(def.phases) do
				for _, tr in ipairs(p.transitions) do
					if tr.to == was then
						tr.to = text
					end
				end
			end
			QAT.editor.selectedPhaseId = text
			commit(def)
			QAT.Editor_Inspector_Refresh()
		end
	end
	idBox:SetText(phase.id)
	idBox:ClearAnchors()
	idBox:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y)
	y = y + ROW_H + GAP

	-- Kind.
	fieldLabel(
		"lKind",
		"Kind",
		y,
		"What this phase is: Bar / Icon / Text draw on screen, None is hidden (e.g. an idle phase), Audio Cue plays a sound on enter and draws nothing."
	)
	local kindDD = get("kindDD", function()
		return QAT.widgets.Dropdown(container, "QAT_App_Kind", 180, KIND_OPTS, "bar")
	end)
	kindDD.onSelect = function(v)
		phase.look.display = v
		commit(def)
		render(container, def)
	end
	kindDD:SetValue(phase.look.display or "bar")
	kindDD:ClearAnchors()
	kindDD:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y)
	y = y + ROW_H + GAP

	local kind = phase.look.display or "bar"
	local isVisual = kind == "bar" or kind == "icon" or kind == "text"
	local canLabel = kind == "bar" or kind == "text"
	local canColor = kind == "bar" or kind == "text"

	if kind == "icon" then
		fieldLabel(
			"lIcon",
			"Icon",
			y,
			"Texture path for the icon. Leave empty to use the tracked ability's own icon automatically."
		)
		local iconBox = get("iconBox", function()
			return QAT.widgets.EditBox(container, "QAT_App_IconBox", 260, ROW_H)
		end)
		iconBox.onChange = function(text)
			text = zo_strtrim(text or "")
			phase.look.icon = (text ~= "" and text) or nil
			commit(def)
			render(container, def)
		end
		iconBox:SetText(phase.look.icon or "")
		iconBox:ClearAnchors()
		iconBox:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y)
		local iconPreview = get("iconPreview", function()
			return QAT.widgets.IconWell(container, "QAT_App_IconPreview", ROW_H)
		end)
		iconPreview:SetTexture(QAT.util.PhaseIcon(phase) or "/esoui/art/icons/icon_missing.dds")
		iconPreview:ClearAnchors()
		iconPreview:SetAnchor(LEFT, iconBox, RIGHT, 8, 0)
		y = y + ROW_H + GAP
	end

	if canLabel then
		fieldLabel(
			"lName",
			"Label text",
			y,
			"Text drawn next to the bar / as the text. Leave empty to use the tracker's name."
		)
		local nameBox = get("nameBox", function()
			return QAT.widgets.EditBox(container, "QAT_App_NameBox", 220, ROW_H)
		end)
		nameBox.onChange = function(text)
			phase.look.name = text
			commit(def)
		end
		nameBox:SetText(phase.look.name or "")
		nameBox:ClearAnchors()
		nameBox:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y)
		y = y + ROW_H + GAP
	end

	if canColor then
		local colorKey = (kind == "text") and "text" or "bar"
		local default = (kind == "text") and { 1, 1, 1, 1 } or { 0.2, 0.8, 0.35, 1 }
		fieldLabel(
			"lColor",
			"Color",
			y,
			"The "
				.. (kind == "text" and "text" or "bar fill")
				.. " colour. Other elements get their own colours below."
		)
		local colorSw = get("colorSw", function()
			return QAT.widgets.ColorSwatch(container, "QAT_App_Color", ROW_H, { 1, 1, 1, 1 })
		end)
		colorSw.onChange = function(c)
			phase.look.colors = phase.look.colors or {}
			phase.look.colors[colorKey] = c
			commit(def)
		end
		colorSw:SetColor((phase.look.colors and phase.look.colors[colorKey]) or default)
		colorSw:ClearAnchors()
		colorSw:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y)
		y = y + ROW_H + GAP
	end

	if isVisual then
		fieldLabel("lShowTime", "Show time", y, "Show the remaining-time number while this phase has a running timer.")
		local timeChk = get("timeChk", function()
			return QAT.widgets.Checkbox(container, "QAT_App_ShowTime", true)
		end)
		timeChk:SetChecked(phase.look.showTime ~= false)
		timeChk.onToggle = function(v)
			phase.look.showTime = v
			commit(def)
		end
		timeChk:ClearAnchors()
		timeChk:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y + 2)

		local decLabel = get("lDec", function()
			return QAT.widgets.Label(container, "QAT_App_lDec", "Decimals")
		end)
		decLabel:SetText("Decimals")
		decLabel:ClearAnchors()
		decLabel:SetAnchor(TOPLEFT, container, TOPLEFT, LX + 44, y + 3)
		QAT.widgets.Tooltip(decLabel, "Decimal places on the time readout.")
		local decBox = get("decBox", function()
			return QAT.widgets.EditBox(container, "QAT_App_Dec", 50, ROW_H)
		end)
		decBox.onChange = function(text)
			phase.look.decimals = tonumber(text) or 0
			commit(def)
		end
		decBox:SetText(tostring(phase.look.decimals or 1))
		decBox:ClearAnchors()
		decBox:SetAnchor(TOPLEFT, container, TOPLEFT, LX + 120, y)
		y = y + ROW_H + GAP

		fieldLabel(
			"lShowStacks",
			"Show stacks",
			y,
			"This effect has stacks - show the stack number when the game reports stacks (>= 1)."
		)
		local stacksChk = get("stacksChk", function()
			return QAT.widgets.Checkbox(container, "QAT_App_ShowStacks", false)
		end)
		stacksChk:SetChecked(phase.look.showStacks or false)
		stacksChk.onToggle = function(v)
			phase.look.showStacks = v or nil
			commit(def)
		end
		stacksChk:ClearAnchors()
		stacksChk:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y + 2)
		y = y + ROW_H + GAP

		fieldLabel("lFont", "Font size", y, "Font size of each readout. Blank uses the default.")
		phase.look.fontSizes = phase.look.fontSizes or {}
		local fkeys = canLabel and { "label", "time", "stacks" } or { "time", "stacks" }
		local fx = LX
		for _, key in ipairs(fkeys) do
			local cap = get("fcap_" .. key, function()
				return QAT.widgets.Label(container, "QAT_App_FCap_" .. key, "")
			end)
			cap:SetText(key:sub(1, 1):upper())
			cap:ClearAnchors()
			cap:SetAnchor(TOPLEFT, container, TOPLEFT, fx, y + 3)
			QAT.widgets.Tooltip(cap, key:gsub("^%l", string.upper) .. " font size")
			local box = get("fbox_" .. key, function()
				return QAT.widgets.EditBox(container, "QAT_App_FBox_" .. key, 42, ROW_H)
			end)
			box.onChange = function(text)
				phase.look.fontSizes[key] = tonumber(text) or nil
				commit(def)
			end
			box:SetText(
				phase.look.fontSizes[key] and tostring(phase.look.fontSizes[key]) or tostring(FONT_DEFAULTS[key])
			)
			box:ClearAnchors()
			box:SetAnchor(TOPLEFT, container, TOPLEFT, fx + 14, y)
			fx = fx + 14 + 42 + 12
		end
		y = y + ROW_H + GAP
	end

	if kind == "audio" then
		phase.cues = phase.cues or {}
		fieldLabel(
			"lSound",
			"Sound",
			y,
			"ESO sound name played when this phase is entered (e.g. NEW_NOTIFICATION). A sound picker comes later."
		)
		local soundBox = get("soundBox", function()
			return QAT.widgets.EditBox(container, "QAT_App_Sound", 220, ROW_H)
		end)
		soundBox.onChange = function(text)
			text = zo_strtrim(text or "")
			phase.cues.sound = (text ~= "" and text) or nil
			commit(def)
		end
		soundBox:SetText(phase.cues.sound or "")
		soundBox:ClearAnchors()
		soundBox:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y)
		local testBtn = get("soundTest", function()
			return QAT.widgets.TextButton(container, "QAT_App_SoundTest", "Test", nil)
		end)
		testBtn:SetHeight(ROW_H)
		testBtn:ClearAnchors()
		QAT.widgets.Tooltip(testBtn, "Play this sound now.")
		testBtn:SetAnchor(LEFT, soundBox, RIGHT, 8, 0)
		testBtn.onClick = function()
			QAT.FireCues({ sound = phase.cues.sound })
		end
		y = y + ROW_H + GAP
	end

	QAT.widgets.PoolEnd(pool)
end

QAT.editor.tabRenderers = QAT.editor.tabRenderers or {}
QAT.editor.tabRenderers["Appearance"] = render
