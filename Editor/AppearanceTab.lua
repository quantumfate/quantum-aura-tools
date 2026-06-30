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
-- Constrained numeric choices (dropdowns) so invalid values can't be entered.
local function numOpts(vals)
	local t = {}
	for _, v in ipairs(vals) do
		t[#t + 1] = { label = tostring(v), value = v }
	end
	return t
end
local FONT_OPTS = numOpts({ 10, 12, 14, 16, 18, 20, 22, 24, 28, 32, 36, 40, 48 })
local BORDER_OPTS = numOpts({ 1, 2, 4, 8, 16 }) -- backdrop edge must be a power of two
local DECIMAL_OPTS = numOpts({ 0, 1, 2 })
-- Swatch fallbacks (match Display's DEFAULT_COLORS).
local DEFAULT_COLORS = {
	background = { 0, 0, 0, 0.55 },
	bar = { 0.20, 0.80, 0.35, 1 },
	border = { 0, 0, 0, 1 },
	stacks = { 1, 0.82, 0.20, 1 },
	text = { 1, 1, 1, 1 },
	timer = { 1, 1, 1, 1 },
}
-- Which colour elements each Kind exposes, in display order. (Icon has no bar /
-- background / text label; Text has no bar fill or stacks.)
local COLOR_SET = {
	icon = { { "stacks", "Stacks" }, { "timer", "Timer" }, { "border", "Border" } },
	bar = {
		{ "bar", "Bar" },
		{ "background", "Background" },
		{ "text", "Text" },
		{ "timer", "Timer" },
		{ "stacks", "Stacks" },
		{ "border", "Border" },
	},
	text = { { "text", "Text" }, { "timer", "Timer" }, { "background", "Background" }, { "border", "Border" } },
}

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

	-- Two columns: General (left) and Colors (right, see below).
	local COLX = 430
	local genHeader = get("hGen", function()
		return QAT.widgets.SectionHeader(container, "QAT_App_hGen", "General")
	end)
	genHeader:ClearAnchors()
	genHeader:SetAnchor(TOPLEFT, container, TOPLEFT, PAD, y)
	y = y + ROW_H

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

	-- Border width (General column; the colours live in the right column).
	if isVisual then
		fieldLabel("lBorderT", "Border width", y, "Border thickness in pixels (must be a power of two).")
		local btDD = get("btDD", function()
			return QAT.widgets.Dropdown(container, "QAT_App_BorderT", 70, BORDER_OPTS, 1)
		end)
		btDD.onSelect = function(v)
			phase.look.borderThickness = v
			commit(def)
		end
		btDD:SetValue(phase.look.borderThickness or 1)
		btDD:ClearAnchors()
		btDD:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y)
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
		local decDD = get("decDD", function()
			return QAT.widgets.Dropdown(container, "QAT_App_Dec", 60, DECIMAL_OPTS, 1)
		end)
		decDD.onSelect = function(v)
			phase.look.decimals = v
			commit(def)
		end
		decDD:SetValue(phase.look.decimals or 1)
		decDD:ClearAnchors()
		decDD:SetAnchor(TOPLEFT, container, TOPLEFT, LX + 120, y)
		y = y + ROW_H + GAP

		-- Stacks only apply to bar/icon (text never shows them).
		if kind ~= "text" then
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
		end

		fieldLabel("lFont", "Font size", y, "Font size of each readout. Blank uses the default.")
		phase.look.fontSizes = phase.look.fontSizes or {}
		local fkeys = { "label", "time", "stacks" }
		if kind == "icon" then
			fkeys = { "time", "stacks" } -- icons have no label
		elseif kind == "text" then
			fkeys = { "label", "time" } -- text has no stacks
		end
		local fx = LX
		for _, key in ipairs(fkeys) do
			local fkey = key
			local cap = get("fcap_" .. fkey, function()
				return QAT.widgets.Label(container, "QAT_App_FCap_" .. fkey, "")
			end)
			cap:SetText(fkey:sub(1, 1):upper())
			cap:ClearAnchors()
			cap:SetAnchor(TOPLEFT, container, TOPLEFT, fx, y + 3)
			QAT.widgets.Tooltip(cap, fkey:gsub("^%l", string.upper) .. " font size")
			local dd = get("fdd_" .. fkey, function()
				return QAT.widgets.Dropdown(container, "QAT_App_FDD_" .. fkey, 60, FONT_OPTS, 20)
			end)
			dd.onSelect = function(v)
				phase.look.fontSizes[fkey] = v
				commit(def)
			end
			dd:SetValue(phase.look.fontSizes[fkey] or FONT_DEFAULTS[fkey])
			dd:ClearAnchors()
			dd:SetAnchor(TOPLEFT, container, TOPLEFT, fx + 16, y)
			fx = fx + 16 + 60 + 14
		end
		y = y + ROW_H + GAP

		-- ===== Right column: Colors =====
		local colHeader = get("hColors", function()
			return QAT.widgets.SectionHeader(container, "QAT_App_hColors", "Colors")
		end)
		colHeader:ClearAnchors()
		colHeader:SetAnchor(TOPLEFT, container, TOPLEFT, COLX, PAD)
		local cy = PAD + ROW_H
		for _, f in ipairs(COLOR_SET[kind] or {}) do
			local key = f[1]
			local cap = get("cc_" .. key, function()
				return QAT.widgets.Label(container, "QAT_App_CC_" .. key, "")
			end)
			cap:SetText(f[2])
			cap:ClearAnchors()
			cap:SetAnchor(TOPLEFT, container, TOPLEFT, COLX, cy + 3)
			QAT.widgets.Tooltip(cap, f[2] .. " colour.")
			local sw = get("cs_" .. key, function()
				return QAT.widgets.ColorSwatch(container, "QAT_App_CS_" .. key, ROW_H, { 1, 1, 1, 1 })
			end)
			sw.onChange = function(c)
				phase.look.colors = phase.look.colors or {}
				phase.look.colors[key] = c
				commit(def)
			end
			sw:SetColor((phase.look.colors and phase.look.colors[key]) or DEFAULT_COLORS[key])
			sw:ClearAnchors()
			sw:SetAnchor(TOPLEFT, container, TOPLEFT, COLX + 110, cy)
			cy = cy + ROW_H + GAP
		end

		-- Vertical rule separating the two columns.
		local vdiv = get("vdiv", function()
			return QAT.widgets.Panel(container, "QAT_App_VDiv", { 0.30, 0.34, 0.42, 0.6 }, { 0, 0, 0, 0 })
		end)
		vdiv:ClearAnchors()
		vdiv:SetDimensions(1, math.max(y, cy) - PAD)
		vdiv:SetAnchor(TOPLEFT, container, TOPLEFT, COLX - 24, PAD)
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
