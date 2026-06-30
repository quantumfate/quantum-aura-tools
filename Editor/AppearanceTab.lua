-- Appearance tab: how the selected phase draws. The phase is chosen by the shared
-- phase strip in the header. Laid out as grouped cards (Source / Colors / Text &
-- Timer); only the fields and cards relevant to the chosen Kind are shown.

local ROW_H = 28
local RH = 32 -- row pitch inside a card

local KIND_OPTS = {
	{ label = "Bar", value = "bar" },
	{ label = "Icon", value = "icon" },
	{ label = "Text", value = "text" },
	{ label = "None (hidden)", value = "none" },
	{ label = "Audio Cue", value = "audio" },
}
local FONT_DEFAULTS = { label = 20, time = 20, stacks = 16 }
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
local DEFAULT_COLORS = {
	background = { 0, 0, 0, 0.55 },
	bar = { 0.20, 0.80, 0.35, 1 },
	border = { 0, 0, 0, 1 },
	stacks = { 1, 0.82, 0.20, 1 },
	text = { 1, 1, 1, 1 },
	timer = { 1, 1, 1, 1 },
}
-- Which colour elements each Kind exposes. Icon has no bar/background/text label;
-- Text has no bar fill or stacks.
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
	local look = phase.look
	look.colors = look.colors or {}
	look.fontSizes = look.fontSizes or {}
	local kind = look.display or "bar"
	local isVisual = kind == "bar" or kind == "icon" or kind == "text"
	local canLabel = kind == "bar" or kind == "text"

	local cw = container:GetWidth()
	if cw < 240 then
		cw = 900
	end
	local OUT, CGAP, LW = 14, 16, 84
	local topW = math.floor((cw - OUT * 2 - CGAP) / 2)

	-- Small builders that parent a control to a card and return it (pooled by key).
	local function cardOf(key, title)
		local c = get(key, function()
			return QAT.widgets.Card(container, "QAT_App_" .. key, title)
		end)
		c:SetTitle(title)
		return c
	end
	local function rowLabel(card, key, text, yy)
		local l = get("L" .. key, function()
			return QAT.widgets.Label(card, "QAT_App_L" .. key, "")
		end)
		l:SetText(text)
		l:ClearAnchors()
		l:SetAnchor(TOPLEFT, card, TOPLEFT, card.padX, yy + 5)
		return l
	end

	-- ===== SOURCE card =====
	local src = cardOf("cSrc", "Source")
	src:ClearAnchors()
	src:SetAnchor(TOPLEFT, container, TOPLEFT, OUT, OUT)
	local sLX = src.padX + LW
	local sFieldW = topW - sLX - src.padX
	local sy = src.contentY

	rowLabel(src, "Id", "Phase id", sy)
	local idBox = get("idBox", function()
		return QAT.widgets.EditBox(src, "QAT_App_IdBox", 100, ROW_H)
	end)
	idBox.onChange = function(text)
		text = zo_strtrim(text)
		if text ~= "" then
			local was = phase.id
			phase.id = text
			if def.initial == was then
				def.initial = text
			end
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
	idBox:SetDimensions(sFieldW, ROW_H)
	idBox:SetText(phase.id)
	idBox:ClearAnchors()
	idBox:SetAnchor(TOPLEFT, src, TOPLEFT, sLX, sy)
	sy = sy + RH

	rowLabel(src, "Kind", "Kind", sy)
	local kindDD = get("kindDD", function()
		return QAT.widgets.Dropdown(src, "QAT_App_Kind", 180, KIND_OPTS, "bar")
	end)
	kindDD.onSelect = function(v)
		look.display = v
		commit(def)
		render(container, def)
	end
	kindDD:SetValue(kind)
	kindDD:SetDimensions(sFieldW, 24)
	kindDD:ClearAnchors()
	kindDD:SetAnchor(TOPLEFT, src, TOPLEFT, sLX, sy)
	sy = sy + RH

	if kind == "icon" then
		rowLabel(src, "Icon", "Icon", sy)
		local iconBox = get("iconBox", function()
			return QAT.widgets.EditBox(src, "QAT_App_IconBox", 100, ROW_H)
		end)
		iconBox.onChange = function(text)
			text = zo_strtrim(text or "")
			look.icon = (text ~= "" and text) or nil
			commit(def)
			render(container, def)
		end
		iconBox:SetDimensions(sFieldW - ROW_H - 8, ROW_H)
		iconBox:SetText(look.icon or "")
		iconBox:ClearAnchors()
		iconBox:SetAnchor(TOPLEFT, src, TOPLEFT, sLX, sy)
		local prev = get("iconPreview", function()
			return QAT.widgets.IconWell(src, "QAT_App_IconPreview", ROW_H)
		end)
		prev:SetTexture(QAT.util.PhaseIcon(phase) or "/esoui/art/icons/icon_missing.dds")
		prev:ClearAnchors()
		prev:SetAnchor(LEFT, iconBox, RIGHT, 8, 0)
		sy = sy + RH
	elseif canLabel then
		rowLabel(src, "Name", "Label text", sy)
		local nameBox = get("nameBox", function()
			return QAT.widgets.EditBox(src, "QAT_App_NameBox", 100, ROW_H)
		end)
		nameBox.onChange = function(text)
			look.name = text
			commit(def)
		end
		nameBox:SetDimensions(sFieldW, ROW_H)
		nameBox:SetText(look.name or "")
		nameBox:ClearAnchors()
		nameBox:SetAnchor(TOPLEFT, src, TOPLEFT, sLX, sy)
		sy = sy + RH
	elseif kind == "audio" then
		phase.cues = phase.cues or {}
		rowLabel(src, "Snd", "Sound", sy)
		local soundBox = get("soundBox", function()
			return QAT.widgets.EditBox(src, "QAT_App_Sound", 100, ROW_H)
		end)
		soundBox.onChange = function(text)
			text = zo_strtrim(text or "")
			phase.cues.sound = (text ~= "" and text) or nil
			commit(def)
		end
		soundBox:SetDimensions(sFieldW - 60, ROW_H)
		soundBox:SetText(phase.cues.sound or "")
		soundBox:ClearAnchors()
		soundBox:SetAnchor(TOPLEFT, src, TOPLEFT, sLX, sy)
		local testBtn = get("soundTest", function()
			return QAT.widgets.TextButton(src, "QAT_App_SoundTest", "Test", nil)
		end)
		testBtn:SetHeight(ROW_H)
		testBtn:ClearAnchors()
		testBtn:SetAnchor(LEFT, soundBox, RIGHT, 8, 0)
		testBtn.onClick = function()
			QAT.FireCues({ sound = phase.cues.sound })
		end
		sy = sy + RH
	end
	local srcH = sy + 6

	-- ===== COLORS card (visual kinds) =====
	local topH = srcH
	if isVisual then
		local col = cardOf("cCol", "Colors")
		col:ClearAnchors()
		col:SetAnchor(TOPLEFT, container, TOPLEFT, OUT + topW + CGAP, OUT)
		local fields = COLOR_SET[kind] or {}
		local colX = { col.padX, math.floor(topW / 2) + 6 }
		local cy = col.contentY
		for i, f in ipairs(fields) do
			local key = f[1]
			local cidx = (i - 1) % 2
			local fx = colX[cidx + 1]
			local cap = get("cc_" .. key, function()
				return QAT.widgets.Label(col, "QAT_App_CC_" .. key, "")
			end)
			cap:SetText(f[2])
			cap:ClearAnchors()
			cap:SetAnchor(TOPLEFT, col, TOPLEFT, fx, cy + 5)
			QAT.widgets.Tooltip(cap, f[2] .. " colour.")
			local sw = get("cs_" .. key, function()
				return QAT.widgets.ColorSwatch(col, "QAT_App_CS_" .. key, ROW_H, { 1, 1, 1, 1 })
			end)
			sw.onChange = function(c)
				look.colors[key] = c
				commit(def)
			end
			sw:SetColor(look.colors[key] or DEFAULT_COLORS[key])
			sw:ClearAnchors()
			sw:SetAnchor(TOPLEFT, col, TOPLEFT, fx + 78, cy)
			if cidx == 1 then
				cy = cy + RH
			end
		end
		if #fields % 2 == 1 then
			cy = cy + RH
		end

		rowLabel(col, "BW", "Border width", cy)
		local btDD = get("btDD", function()
			return QAT.widgets.Dropdown(col, "QAT_App_BorderT", 70, BORDER_OPTS, 1)
		end)
		btDD.onSelect = function(v)
			look.borderThickness = v
			commit(def)
		end
		btDD:SetValue(look.borderThickness or 1)
		btDD:ClearAnchors()
		btDD:SetAnchor(TOPLEFT, col, TOPLEFT, col.padX + 96, cy)
		cy = cy + RH

		topH = math.max(srcH, cy + 6)
		col:SetDimensions(topW, topH)
	end
	src:SetDimensions(topW, topH)

	-- ===== TEXT & TIMER card (visual kinds), full width below =====
	if isVisual then
		local tt = cardOf("cTT", "Text & Timer")
		tt:ClearAnchors()
		tt:SetAnchor(TOPLEFT, container, TOPLEFT, OUT, OUT + topH + CGAP)
		local ty = tt.contentY

		-- Row 1: Show time | Decimals | Font size (T / S / L per kind).
		rowLabel(tt, "ShowTime", "Show time", ty)
		local timeChk = get("timeChk", function()
			return QAT.widgets.Checkbox(tt, "QAT_App_ShowTime", true)
		end)
		timeChk:SetChecked(look.showTime ~= false)
		timeChk.onToggle = function(v)
			look.showTime = v
			commit(def)
		end
		timeChk:ClearAnchors()
		timeChk:SetAnchor(TOPLEFT, tt, TOPLEFT, tt.padX + LW, ty + 4)

		local decCap = get("LDec", function()
			return QAT.widgets.Label(tt, "QAT_App_LDec", "Decimals")
		end)
		decCap:SetText("Decimals")
		decCap:ClearAnchors()
		decCap:SetAnchor(TOPLEFT, tt, TOPLEFT, tt.padX + 200, ty + 5)
		local decDD = get("decDD", function()
			return QAT.widgets.Dropdown(tt, "QAT_App_Dec", 60, DECIMAL_OPTS, 1)
		end)
		decDD.onSelect = function(v)
			look.decimals = v
			commit(def)
		end
		decDD:SetValue(look.decimals or 1)
		decDD:ClearAnchors()
		decDD:SetAnchor(TOPLEFT, tt, TOPLEFT, tt.padX + 270, ty)

		local fontCap = get("LFont", function()
			return QAT.widgets.Label(tt, "QAT_App_LFont", "Font size")
		end)
		fontCap:SetText("Font size")
		fontCap:ClearAnchors()
		fontCap:SetAnchor(TOPLEFT, tt, TOPLEFT, tt.padX + 360, ty + 5)
		local fkeys = { "label", "time", "stacks" }
		if kind == "icon" then
			fkeys = { "time", "stacks" }
		elseif kind == "text" then
			fkeys = { "label", "time" }
		end
		local fx = tt.padX + 440
		for _, key in ipairs(fkeys) do
			local fk = key
			local letter = get("fcap_" .. fk, function()
				return QAT.widgets.Label(tt, "QAT_App_FCap_" .. fk, "")
			end)
			letter:SetText(fk:sub(1, 1):upper())
			letter:ClearAnchors()
			letter:SetAnchor(TOPLEFT, tt, TOPLEFT, fx, ty + 5)
			QAT.widgets.Tooltip(letter, fk:gsub("^%l", string.upper) .. " font size")
			local dd = get("fdd_" .. fk, function()
				return QAT.widgets.Dropdown(tt, "QAT_App_FDD_" .. fk, 56, FONT_OPTS, 20)
			end)
			dd.onSelect = function(v)
				look.fontSizes[fk] = v
				commit(def)
			end
			dd:SetValue(look.fontSizes[fk] or FONT_DEFAULTS[fk])
			dd:ClearAnchors()
			dd:SetAnchor(TOPLEFT, tt, TOPLEFT, fx + 16, ty)
			fx = fx + 16 + 56 + 12
		end
		ty = ty + RH

		-- Row 2: Show stacks (bar/icon only).
		if kind ~= "text" then
			rowLabel(tt, "ShowStacks", "Show stacks", ty)
			local stacksChk = get("stacksChk", function()
				return QAT.widgets.Checkbox(tt, "QAT_App_ShowStacks", false)
			end)
			stacksChk:SetChecked(look.showStacks or false)
			stacksChk.onToggle = function(v)
				look.showStacks = v or nil
				commit(def)
			end
			stacksChk:ClearAnchors()
			stacksChk:SetAnchor(TOPLEFT, tt, TOPLEFT, tt.padX + LW, ty + 4)
			ty = ty + RH
		end

		tt:SetDimensions(cw - OUT * 2, ty + 6)
	end

	QAT.widgets.PoolEnd(pool)
end

QAT.editor.tabRenderers = QAT.editor.tabRenderers or {}
QAT.editor.tabRenderers["Appearance"] = render
