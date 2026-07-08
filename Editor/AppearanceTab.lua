-- Appearance tab: how the selected phase draws. The phase is chosen by the shared
-- phase strip in the header. Laid out as grouped cards (Source / Colors / Text &
-- Timer / Font size); only the cards and fields relevant to the chosen Kind show.

local ROW_H, DD_H, SW = 28, 26, 24
local RH = 34 -- row pitch inside a card

local KIND_OPTS = {
	{ label = "Bar", value = "bar" },
	{ label = "Icon", value = "icon" },
	{ label = "Border", value = "border" },
	{ label = "Gradient sweep", value = "gradient" },
	{ label = "Graphic", value = "graphic" },
	{ label = "Text", value = "text" },
	{ label = "None (hidden)", value = "none" },
	{ label = "Audio Cue", value = "audio" },
}
local BAR_ANCHOR_OPTS =
	{ { label = "Top", value = "top" }, { label = "Middle", value = "middle" }, { label = "Bottom", value = "bottom" } }
local BAR_HEIGHT_OPTS =
	{ { label = "Thin", value = "thin" }, { label = "Half", value = "half" }, { label = "Full", value = "full" } }
local SWEEP_DIR_OPTS = {
	{ label = "Right → Left", value = "rtl" },
	{ label = "Left → Right", value = "ltr" },
	{ label = "Top → Bottom", value = "ttb" },
	{ label = "Bottom → Top", value = "btt" },
}
local BORDER_STYLE_OPTS = { { label = "Drain", value = "drain" }, { label = "Fill", value = "fill" } }
local FONT_DEFAULTS = { label = 20, time = 20, stacks = 16 }
local FONT_LABEL = { label = "Text", time = "Timer", stacks = "Stacks" } -- match Colors naming
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

-- Common ESO cue sounds for audio phases. Keys are SOUNDS.* names; only those the
-- running client actually defines are offered (validated when options are built),
-- and a hand-authored value that isn't in the list is preserved.
local CUE_SOUNDS = {
	{ label = "Notification", key = "NEW_NOTIFICATION" },
	{ label = "Alert / Error", key = "GENERAL_ALERT_ERROR" },
	{ label = "Duel Start", key = "DUEL_START" },
	{ label = "Duel Invite", key = "DUEL_INVITE_RECEIVED" },
	{ label = "Quest Complete", key = "QUEST_COMPLETED" },
	{ label = "Objective Complete", key = "OBJECTIVE_COMPLETED" },
	{ label = "Achievement", key = "ACHIEVEMENT_AWARDED" },
	{ label = "Level Up", key = "LEVEL_UP" },
	{ label = "Champion Point", key = "CHAMPION_POINTS_COMMITTED" },
	{ label = "Enlightened", key = "ENLIGHTENED_STATE_GAINED" },
	{ label = "Countdown Tick", key = "BATTLEGROUND_COUNTDOWN_TICK" },
	{ label = "Countdown Finish", key = "BATTLEGROUND_COUNTDOWN_FINISH" },
	{ label = "Group Join", key = "GROUP_JOIN" },
	{ label = "Group Leave", key = "GROUP_LEAVE" },
	{ label = "Accept", key = "DIALOG_ACCEPT" },
	{ label = "Decline", key = "DIALOG_DECLINE" },
	{ label = "Negative", key = "NEGATIVE_CLICK" },
	{ label = "Trial Complete", key = "RAID_TRIAL_COMPLETED" },
	{ label = "Trial Failed", key = "RAID_TRIAL_FAILED" },
	{ label = "Justice KOS", key = "JUSTICE_NOW_KOS" },
}
-- Font family options from LibMediaProvider; "(default)" plus a preserved custom.
local function fontFamilyOptions(current)
	local opts, have = { { label = "(default)", value = nil } }, {}
	for _, name in ipairs(QAT.util.FontList()) do
		opts[#opts + 1] = { label = name, value = name }
		have[name] = true
	end
	if current and current ~= "" and not have[current] then
		opts[#opts + 1] = { label = tostring(current), value = current }
	end
	return opts
end

local function soundOptions(current)
	local opts, have = { { label = "(none)", value = nil } }, {}
	for _, s in ipairs(CUE_SOUNDS) do
		if SOUNDS and SOUNDS[s.key] and SOUNDS[s.key] ~= "" then
			opts[#opts + 1] = { label = s.label, value = s.key }
			have[s.key] = true
		end
	end
	if current and current ~= "" and not have[current] then
		opts[#opts + 1] = { label = tostring(current) .. " (custom)", value = current }
	end
	return opts
end
local DEFAULT_COLORS = {
	background = { 0, 0, 0, 0.55 },
	bar = { 0.20, 0.80, 0.35, 1 },
	border = { 0, 0, 0, 1 },
	stacks = { 1, 0.82, 0.20, 1 },
	text = { 1, 1, 1, 1 },
	timer = { 1, 1, 1, 1 },
}
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
	border = { { "bar", "Frame" }, { "timer", "Timer" }, { "stacks", "Stacks" } },
	gradient = { { "timer", "Timer" }, { "stacks", "Stacks" } },
	graphic = { { "timer", "Timer" }, { "stacks", "Stacks" } },
}
-- Stat + operator options for the graphic kind's state-driven texture rules.
local GRAPHIC_STAT_OPTS = { { label = "Time left", value = "remaining" }, { label = "Stacks", value = "stacks" } }
local GRAPHIC_OP_OPTS = {
	{ label = "≤", value = "<=" },
	{ label = "<", value = "<" },
	{ label = "≥", value = ">=" },
	{ label = ">", value = ">" },
	{ label = "=", value = "==" },
}
-- Curated-texture dropdown options from the shared catalog, plus a preserved custom.
local function textureOptions(current)
	local opts, have = {}, {}
	for _, t in ipairs(QAT.AllTextures()) do
		opts[#opts + 1] = { label = t.label, value = t.path, icon = t.path }
		have[t.path] = true
	end
	if current and current ~= "" and not have[current] then
		opts[#opts + 1] = { label = "(custom)", value = current, icon = current }
	end
	return opts
end
local GRAPHIC_ALIGN_OPTS =
	{ { label = "Center", value = "center" }, { label = "Left", value = "left" }, { label = "Right", value = "right" } }

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

-- Vertical offset to centre a control of height h within a row of pitch RH.
local function vy(yy, h)
	return yy + math.floor((RH - h) / 2)
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
	local isVisual = kind == "bar"
		or kind == "icon"
		or kind == "text"
		or kind == "border"
		or kind == "gradient"
		or kind == "graphic"
	local isDynamic = def.kind == "dynamic"

	local cw = container.qatViewportW or container:GetWidth()
	if cw < 240 then
		cw = 900
	end
	local OUT, CGAP, LW = 14, 16, 104
	local topW = math.floor((cw - OUT * 2 - CGAP) / 2)

	local function cardOf(key, title)
		local c = get(key, function()
			return QAT.widgets.Card(container, "QAT_App_" .. key, title)
		end)
		c:SetTitle(title)
		return c
	end
	-- A field label inside a card, vertically centred on its row.
	local function rowLabel(card, key, text, yy, x)
		local l = get("L" .. key, function()
			return QAT.widgets.Label(card, "QAT_App_L" .. key, "")
		end)
		l:SetText(text)
		l:ClearAnchors()
		l:SetAnchor(TOPLEFT, card, TOPLEFT, x or card.padX, vy(yy, 18))
		return l
	end

	-- ===== SOURCE =====
	local src = cardOf("cSrc", "Source")
	src:ClearAnchors()
	src:SetAnchor(TOPLEFT, container, TOPLEFT, OUT, OUT)
	local sLX = src.padX + LW
	local sFieldW = topW - sLX - src.padX
	local sy = src.contentY

	-- Low-time warning row (shared by Border and Bar-beside kinds): below this many
	-- seconds the fill switches to the low colour and optionally pulses. Blank = off.
	local function lowTimeFields(yy)
		rowLabel(src, "Low", "Low at (s)", yy)
		local lowBox = get("lowBox", function()
			return QAT.widgets.EditBox(src, "QAT_App_LowBox", 60, ROW_H)
		end)
		lowBox.onChange = function(text)
			local n = tonumber(zo_strtrim(text or ""))
			phase.look.lowThreshold = (n and n > 0) and n or nil
			commit(def)
		end
		lowBox:SetDimensions(60, ROW_H)
		lowBox:SetText(look.lowThreshold and tostring(look.lowThreshold) or "")
		lowBox:ClearAnchors()
		lowBox:SetAnchor(TOPLEFT, src, TOPLEFT, sLX, vy(yy, ROW_H))
		local lowSw = get("lowSw", function()
			return QAT.widgets.ColorSwatch(src, "QAT_App_LowSw", SW, { 0.9, 0.2, 0.2, 1 })
		end)
		lowSw.onChange = function(c)
			phase.look.lowColor = c
			commit(def)
		end
		lowSw:SetColor(look.lowColor or { 0.9, 0.2, 0.2, 1 })
		lowSw:ClearAnchors()
		lowSw:SetAnchor(LEFT, lowBox, RIGHT, 8, 0)
		local pulseChk = get("pulseChk", function()
			return QAT.widgets.Checkbox(src, "QAT_App_LowPulse", false)
		end)
		pulseChk:SetChecked(look.lowPulse or false)
		pulseChk.onToggle = function(v)
			phase.look.lowPulse = v or nil
			commit(def)
		end
		pulseChk:ClearAnchors()
		pulseChk:SetAnchor(LEFT, lowSw, RIGHT, 10, 0)
		local pulseLbl = get("pulseLbl", function()
			return QAT.widgets.Label(src, "QAT_App_LowPulseLbl", "pulse")
		end)
		pulseLbl:SetText("pulse")
		pulseLbl:ClearAnchors()
		pulseLbl:SetAnchor(LEFT, pulseChk, RIGHT, 6, 0)
		return yy + RH
	end

	-- Graphic kind: a curated (or custom) default texture, plus ordered rules that swap
	-- it while a stat threshold holds. Handlers re-fetch phase.look.graphic at call time
	-- because commit's canonicalize replaces the table.
	local function graphicFields(yy)
		phase.look.graphic = phase.look.graphic or { rules = {} }
		local g = phase.look.graphic
		g.rules = g.rules or {}

		rowLabel(src, "GfxTex", "Texture", yy)
		local texDD = get("gfxTexDD", function()
			return QAT.widgets.Dropdown(src, "QAT_App_GfxTex", sFieldW - ROW_H - 8, {}, nil, nil)
		end)
		texDD:SetOptions(textureOptions(g.default))
		texDD:SetValue(g.default)
		texDD.onSelect = function(v)
			phase.look.graphic.default = v
			commit(def)
		end
		texDD:ClearAnchors()
		texDD:SetAnchor(TOPLEFT, src, TOPLEFT, sLX, vy(yy, DD_H))
		local texPrev = get("gfxTexPrev", function()
			return QAT.widgets.IconWell(src, "QAT_App_GfxTexPrev", ROW_H)
		end)
		texPrev:SetTexture(g.default or "/esoui/art/icons/icon_missing.dds")
		texPrev:ClearAnchors()
		texPrev:SetAnchor(LEFT, texDD, RIGHT, 8, 0)
		yy = yy + RH

		-- Custom path override for textures outside the catalog.
		rowLabel(src, "GfxCustom", "Custom .dds", yy)
		local customBox = get("gfxCustom", function()
			return QAT.widgets.EditBox(src, "QAT_App_GfxCustom", 100, ROW_H)
		end)
		customBox:SetDimensions(sFieldW, ROW_H)
		customBox:SetText(g.default or "")
		customBox.onChange = function(text)
			text = zo_strtrim(text or "")
			phase.look.graphic.default = (text ~= "" and text) or nil
			commit(def)
		end
		customBox:ClearAnchors()
		customBox:SetAnchor(TOPLEFT, src, TOPLEFT, sLX, vy(yy, ROW_H))
		yy = yy + RH

		-- Horizontal placement of the aspect-kept texture within the tracker box.
		rowLabel(src, "GfxAlign", "Align", yy)
		local alignDD = get("gfxAlign", function()
			return QAT.widgets.Dropdown(src, "QAT_App_GfxAlign", 110, GRAPHIC_ALIGN_OPTS, "center")
		end)
		alignDD:SetValue(g.align or "center")
		alignDD.onSelect = function(v)
			phase.look.graphic.align = v
			commit(def)
		end
		alignDD:ClearAnchors()
		alignDD:SetAnchor(TOPLEFT, src, TOPLEFT, sLX, vy(yy, DD_H))
		yy = yy + RH

		rowLabel(src, "GfxRules", "When", yy)
		for i, rule in ipairs(g.rules) do
			local statDD = get("gfxStat" .. i, function()
				return QAT.widgets.Dropdown(src, "QAT_App_GfxStat" .. i, 90, GRAPHIC_STAT_OPTS, "remaining")
			end)
			statDD:SetValue(rule.stat or "remaining")
			statDD.onSelect = function(v)
				phase.look.graphic.rules[i].stat = v
				commit(def)
			end
			statDD:ClearAnchors()
			statDD:SetAnchor(TOPLEFT, src, TOPLEFT, sLX, vy(yy, DD_H))
			local opDD = get("gfxOp" .. i, function()
				return QAT.widgets.Dropdown(src, "QAT_App_GfxOp" .. i, 46, GRAPHIC_OP_OPTS, "<=")
			end)
			opDD:SetValue(rule.op or "<=")
			opDD.onSelect = function(v)
				phase.look.graphic.rules[i].op = v
				commit(def)
			end
			opDD:ClearAnchors()
			opDD:SetAnchor(LEFT, statDD, RIGHT, 4, 0)
			local valBox = get("gfxVal" .. i, function()
				return QAT.widgets.EditBox(src, "QAT_App_GfxVal" .. i, 44, ROW_H)
			end)
			valBox:SetDimensions(44, ROW_H)
			valBox:SetText(tostring(rule.value or 0))
			valBox.onChange = function(text)
				phase.look.graphic.rules[i].value = tonumber(zo_strtrim(text or "")) or 0
				commit(def)
			end
			valBox:ClearAnchors()
			valBox:SetAnchor(LEFT, opDD, RIGHT, 4, 0)
			local ruleTexDD = get("gfxRuleTex" .. i, function()
				return QAT.widgets.Dropdown(src, "QAT_App_GfxRuleTex" .. i, 120, {}, nil, nil)
			end)
			ruleTexDD:SetOptions(textureOptions(rule.texture))
			ruleTexDD:SetValue(rule.texture)
			ruleTexDD.onSelect = function(v)
				phase.look.graphic.rules[i].texture = v
				commit(def)
			end
			ruleTexDD:ClearAnchors()
			ruleTexDD:SetAnchor(LEFT, valBox, RIGHT, 6, 0)
			local delBtn = get("gfxDel" .. i, function()
				return QAT.widgets.TextButton(src, "QAT_App_GfxDel" .. i, "X", nil)
			end)
			delBtn:SetHeight(ROW_H)
			delBtn.onClick = function()
				table.remove(phase.look.graphic.rules, i)
				commit(def)
			end
			delBtn:ClearAnchors()
			delBtn:SetAnchor(LEFT, ruleTexDD, RIGHT, 6, 0)
			yy = yy + RH
		end
		local addBtn = get("gfxAdd", function()
			return QAT.widgets.TextButton(src, "QAT_App_GfxAdd", "+ Rule", nil)
		end)
		addBtn:SetHeight(ROW_H)
		addBtn.onClick = function()
			table.insert(
				phase.look.graphic.rules,
				{ stat = "remaining", op = "<=", value = 3, texture = (QAT.textures[1] and QAT.textures[1].path) }
			)
			commit(def)
		end
		addBtn:ClearAnchors()
		addBtn:SetAnchor(TOPLEFT, src, TOPLEFT, sLX, vy(yy, ROW_H))
		return yy + RH
	end

	rowLabel(src, "Id", "Phase id", sy)
	local idBox = get("idBox", function()
		return QAT.widgets.EditBox(src, "QAT_App_IdBox", 100, ROW_H)
	end)
	idBox.onChange = function(text)
		text = zo_strtrim(text)
		if text ~= "" and text ~= phase.id then
			for _, p in ipairs(def.phases) do
				if p.id == text then
					idBox:SetText(phase.id)
					return
				end
			end
			local was = phase.id
			phase.id = text
			if def.initial == was then
				def.initial = text
			end
			if def.layerInitial then
				for layer, id in pairs(def.layerInitial) do
					if id == was then
						def.layerInitial[layer] = text
					end
				end
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
	idBox:SetAnchor(TOPLEFT, src, TOPLEFT, sLX, vy(sy, ROW_H))
	sy = sy + RH

	rowLabel(src, "Kind", "Kind", sy)
	local kindDD = get("kindDD", function()
		return QAT.widgets.Dropdown(src, "QAT_App_Kind", 180, KIND_OPTS, "bar")
	end)
	kindDD.onSelect = function(v)
		phase.look.display = v -- write the live look; commit's canonicalize replaces the table
		commit(def) -- re-renders this tab via the TrackerChanged callback
	end
	kindDD:SetValue(kind)
	kindDD:SetDimensions(sFieldW, DD_H)
	kindDD:ClearAnchors()
	kindDD:SetAnchor(TOPLEFT, src, TOPLEFT, sLX, vy(sy, DD_H))
	sy = sy + RH

	-- A "Show icon" checkbox bound to the unified look.showIcon gate, plus the phase's
	-- resolved icon preview. Shared by every icon-capable kind; the icon itself is set
	-- on the Behavior tab (auto from the tracked ability, or an override there).
	-- The phase's icon override + live preview. The icon auto-derives from the tracked
	-- ability; the box overrides it (blank = auto). Handlers re-fetch phase.look at call
	-- time (commit's canonicalize replaces the table).
	local function iconOverrideRow(yy, boxKey, prevKey)
		rowLabel(src, "Icon", "Icon", yy)
		-- The "Follow effect" button is always shown so the auto behaviour is discoverable.
		local resetW = 108
		local box = get(boxKey, function()
			return QAT.widgets.EditBox(src, "QAT_App_" .. boxKey, 100, ROW_H)
		end)
		box:SetDimensions(sFieldW - ROW_H - 8 - resetW - 8, ROW_H)
		box:SetText(look.icon or "")
		box.onChange = function(text)
			text = zo_strtrim(text or "")
			phase.look.icon = (text ~= "" and text) or nil
			commit(def)
		end
		box:ClearAnchors()
		box:SetAnchor(TOPLEFT, src, TOPLEFT, sLX, vy(yy, ROW_H))
		local prev = get(prevKey, function()
			return QAT.widgets.IconWell(src, "QAT_App_" .. prevKey, ROW_H)
		end)
		prev:SetTexture(QAT.util.PhaseIcon(phase, def) or "/esoui/art/icons/icon_missing.dds")
		prev:ClearAnchors()
		prev:SetAnchor(LEFT, box, RIGHT, 8, 0)
		-- Clear the override back to the tracked ability's icon (follow effect id).
		local reset = get(boxKey .. "Reset", function()
			return QAT.widgets.TextButton(src, "QAT_App_" .. boxKey .. "Reset", "Follow effect", nil)
		end)
		reset:SetHeight(ROW_H)
		reset:SetMinWidth(resetW)
		reset:SetTooltip("Use the tracked ability's icon (follow effect id) instead of an override.")
		reset.onClick = function()
			phase.look.icon = nil
			commit(def)
		end
		reset:ClearAnchors()
		reset:SetAnchor(LEFT, prev, RIGHT, 8, 0)
		return yy + RH
	end

	-- "Show icon" gate (bar/border/gradient) followed by the shared icon override row.
	local function showIconRow(yy, chkKey, boxKey, prevKey)
		rowLabel(src, "ShowIcon", "Show icon", yy)
		local chk = get(chkKey, function()
			return QAT.widgets.Checkbox(src, "QAT_App_" .. chkKey, true)
		end)
		chk:SetChecked(look.showIcon ~= false)
		chk.onToggle = function(v)
			-- Store false explicitly when off: nil would canonicalize back to the
			-- default (on) via `showIcon ~= false`, making the box impossible to untick.
			phase.look.showIcon = v and true or false
			commit(def)
		end
		chk:ClearAnchors()
		chk:SetAnchor(TOPLEFT, src, TOPLEFT, sLX, vy(yy, 20))
		yy = yy + RH
		if look.showIcon ~= false then
			yy = iconOverrideRow(yy, boxKey, prevKey)
		end
		return yy
	end

	if kind == "icon" then
		-- The icon kind IS the icon; set/override it right here.
		sy = iconOverrideRow(sy, "iconBox", "iconPreview")
	elseif kind == "bar" or kind == "text" then
		-- Label text: hidden for dynamic trackers (source supplies the instance name).
		if not isDynamic then
			rowLabel(src, "Name", "Label text", sy)
			local nameBox = get("nameBox", function()
				return QAT.widgets.EditBox(src, "QAT_App_NameBox", 100, ROW_H)
			end)
			nameBox.onChange = function(text)
				phase.look.name = text
				commit(def)
			end
			nameBox:SetDimensions(sFieldW, ROW_H)
			nameBox:SetText(look.name or "")
			nameBox:ClearAnchors()
			nameBox:SetAnchor(TOPLEFT, src, TOPLEFT, sLX, vy(sy, ROW_H))
			sy = sy + RH
		end

		if kind == "bar" then
			sy = showIconRow(sy, "siChk", "barIconBox", "barIconPrev")

			rowLabel(src, "BarAnchor", "Bar anchor", sy)
			local anchDD = get("bsAnchDD", function()
				return QAT.widgets.Dropdown(src, "QAT_App_BsAnchor", 110, BAR_ANCHOR_OPTS, "middle")
			end)
			anchDD.onSelect = function(v)
				phase.look.barAnchor = v
				commit(def)
			end
			anchDD:SetValue(look.barAnchor or "middle")
			anchDD:ClearAnchors()
			anchDD:SetAnchor(TOPLEFT, src, TOPLEFT, sLX, vy(sy, DD_H))
			sy = sy + RH

			rowLabel(src, "BarHeight", "Bar height", sy)
			local bhDD = get("bsHDD", function()
				return QAT.widgets.Dropdown(src, "QAT_App_BsHeight", 110, BAR_HEIGHT_OPTS, "full")
			end)
			bhDD.onSelect = function(v)
				phase.look.barHeight = v
				commit(def)
			end
			bhDD:SetValue(look.barHeight or "full")
			bhDD:ClearAnchors()
			bhDD:SetAnchor(TOPLEFT, src, TOPLEFT, sLX, vy(sy, DD_H))
			sy = sy + RH

			sy = lowTimeFields(sy)
		end
	elseif kind == "border" then
		-- Drain (empties as time runs out) vs Fill (grows as it progresses).
		rowLabel(src, "BdStyle", "Style", sy)
		local styleDD = get("bdStyleDD", function()
			return QAT.widgets.Dropdown(src, "QAT_App_BdStyle", 110, BORDER_STYLE_OPTS, "drain")
		end)
		styleDD.onSelect = function(v)
			phase.look.borderStyle = v
			commit(def)
		end
		styleDD:SetValue(look.borderStyle or "drain")
		styleDD:ClearAnchors()
		styleDD:SetAnchor(TOPLEFT, src, TOPLEFT, sLX, vy(sy, DD_H))
		sy = sy + RH

		-- The frame is transparent, so the icon behind it is optional; toggle it with the
		-- unified gate (a bare frame overlays another phase cleanly when off).
		sy = showIconRow(sy, "ibChk", "borderIconBox", "borderIconPrev")

		sy = lowTimeFields(sy)
	elseif kind == "gradient" then
		-- Sweep direction + optional colour, and the icon it sweeps over. The fill
		-- always maps to remaining time; only the direction it drains from is chosen.
		rowLabel(src, "Sweep", "Direction", sy)
		local swDD = get("grSweepDD", function()
			return QAT.widgets.Dropdown(src, "QAT_App_GrSweep", 130, SWEEP_DIR_OPTS, "rtl")
		end)
		swDD.onSelect = function(v)
			phase.look.sweepDir = v
			commit(def)
		end
		swDD:SetValue(look.sweepDir or "rtl")
		swDD:ClearAnchors()
		swDD:SetAnchor(TOPLEFT, src, TOPLEFT, sLX, vy(sy, DD_H))
		local swSw = get("grSweepSw", function()
			return QAT.widgets.ColorSwatch(src, "QAT_App_GrSweepSw", SW, { 1, 1, 1, 0.85 })
		end)
		swSw.onChange = function(c)
			phase.look.sweepColor = c
			commit(def)
		end
		swSw:SetColor(look.sweepColor or { 1, 1, 1, 0.85 })
		swSw:ClearAnchors()
		swSw:SetAnchor(LEFT, swDD, RIGHT, 8, 0)
		local swLbl = get("grSweepLbl", function()
			return QAT.widgets.Label(src, "QAT_App_GrSweepLbl", "band")
		end)
		swLbl:SetText("band")
		swLbl:ClearAnchors()
		swLbl:SetAnchor(LEFT, swSw, RIGHT, 6, 0)
		sy = sy + RH

		sy = showIconRow(sy, "grShowIcon", "grIconBox", "grIconPrev")
	elseif kind == "graphic" then
		sy = graphicFields(sy)
	elseif kind == "audio" then
		phase.cues = phase.cues or {}
		rowLabel(src, "Snd", "Sound", sy)
		local soundDD = get("soundDD", function()
			return QAT.widgets.Dropdown(src, "QAT_App_Sound", sFieldW - 60, {}, nil, nil)
		end)
		soundDD:SetOptions(soundOptions(phase.cues.sound))
		soundDD:SetValue(phase.cues.sound)
		soundDD.onSelect = function(v)
			phase.cues.sound = v
			commit(def)
			if v then
				QAT.FireCues({ sound = v }) -- preview the pick
			end
		end
		soundDD:ClearAnchors()
		soundDD:SetAnchor(TOPLEFT, src, TOPLEFT, sLX, vy(sy, DD_H))
		local testBtn = get("soundTest", function()
			return QAT.widgets.TextButton(src, "QAT_App_SoundTest", "Test", nil)
		end)
		testBtn:SetHeight(ROW_H)
		testBtn:ClearAnchors()
		testBtn:SetAnchor(LEFT, soundDD, RIGHT, 8, 0)
		testBtn.onClick = function()
			QAT.FireCues({ sound = phase.cues.sound })
		end
		sy = sy + RH
	end

	local srcH = sy + 8

	-- ===== COLORS =====
	local topH = srcH
	if isVisual then
		local col = cardOf("cCol", "Colors")
		col:ClearAnchors()
		col:SetAnchor(TOPLEFT, container, TOPLEFT, OUT + topW + CGAP, OUT)
		local fields = COLOR_SET[kind] or {}
		-- Two columns; the swatch sits at a fixed x in each so long labels (e.g.
		-- "Background") never overlap it.
		local colX = { col.padX, math.floor(topW / 2) + 4 }
		local swDX = math.floor(topW / 2) - col.padX - SW - 10
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
			cap:SetAnchor(TOPLEFT, col, TOPLEFT, fx, vy(cy, 18))
			QAT.widgets.Tooltip(cap, f[2] .. " colour.")
			local sw = get("cs_" .. key, function()
				return QAT.widgets.ColorSwatch(col, "QAT_App_CS_" .. key, SW, { 1, 1, 1, 1 })
			end)
			sw.onChange = function(c)
				phase.look.colors[key] = c
				commit(def)
			end
			sw:SetColor(look.colors[key] or DEFAULT_COLORS[key])
			sw:ClearAnchors()
			sw:SetAnchor(TOPLEFT, col, TOPLEFT, fx + swDX, vy(cy, SW))
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
			phase.look.borderThickness = v
			commit(def)
		end
		btDD:SetValue(look.borderThickness or 1)
		btDD:ClearAnchors()
		btDD:SetAnchor(TOPLEFT, col, TOPLEFT, col.padX + 100, vy(cy, DD_H))
		cy = cy + RH

		topH = math.max(srcH, cy + 8)
		col:SetDimensions(topW, topH)
	end
	src:SetDimensions(topW, topH)

	if not isVisual then
		QAT.widgets.PoolEnd(pool)
		return
	end

	-- ===== TEXT & TIMER (bottom-left) =====
	local y2 = OUT + topH + CGAP
	local tt = cardOf("cTT", "Text & Timer")
	tt:ClearAnchors()
	tt:SetAnchor(TOPLEFT, container, TOPLEFT, OUT, y2)
	local ttLX = tt.padX + LW
	local ty = tt.contentY

	rowLabel(tt, "ShowTime", "Show time", ty)
	local timeChk = get("timeChk", function()
		return QAT.widgets.Checkbox(tt, "QAT_App_ShowTime", true)
	end)
	timeChk:SetChecked(look.showTime ~= false)
	timeChk.onToggle = function(v)
		phase.look.showTime = v
		commit(def)
	end
	timeChk:ClearAnchors()
	timeChk:SetAnchor(TOPLEFT, tt, TOPLEFT, ttLX + 12, vy(ty, 20))
	ty = ty + RH

	if kind ~= "text" then
		rowLabel(tt, "ShowStacks", "Show stacks", ty)
		local stacksChk = get("stacksChk", function()
			return QAT.widgets.Checkbox(tt, "QAT_App_ShowStacks", false)
		end)
		stacksChk:SetChecked(look.showStacks or false)
		stacksChk.onToggle = function(v)
			phase.look.showStacks = v or nil
			commit(def)
		end
		stacksChk:ClearAnchors()
		stacksChk:SetAnchor(TOPLEFT, tt, TOPLEFT, ttLX + 12, vy(ty, 20))
		ty = ty + RH
	end

	rowLabel(tt, "Dec", "Decimals", ty)
	local decDD = get("decDD", function()
		return QAT.widgets.Dropdown(tt, "QAT_App_Dec", 60, DECIMAL_OPTS, 1)
	end)
	decDD.onSelect = function(v)
		phase.look.decimals = v
		commit(def)
	end
	decDD:SetValue(look.decimals or 1)
	decDD:ClearAnchors()
	decDD:SetAnchor(TOPLEFT, tt, TOPLEFT, ttLX, vy(ty, DD_H))
	ty = ty + RH
	tt:SetDimensions(topW, ty + 8)

	-- ===== FONT (bottom-right) =====
	local font = cardOf("cFont", "Font")
	font:ClearAnchors()
	font:SetAnchor(TOPLEFT, container, TOPLEFT, OUT + topW + CGAP, y2)
	local fLX = font.padX + LW
	local fkeys = { "label", "time", "stacks" }
	if kind == "icon" or kind == "graphic" then
		fkeys = { "time", "stacks" }
	elseif kind == "text" then
		fkeys = { "label", "time" }
	end
	local fy = font.contentY

	-- Font family (applies to every readout of this phase).
	rowLabel(font, "FFam", "Family", fy)
	local famDD = get("ffam", function()
		return QAT.widgets.Dropdown(font, "QAT_App_FFam", topW - fLX - font.padX, {}, nil, nil)
	end)
	famDD:SetOptions(fontFamilyOptions(look.font))
	famDD:SetValue(look.font)
	famDD.onSelect = function(v)
		phase.look.font = v
		commit(def)
	end
	famDD:ClearAnchors()
	famDD:SetAnchor(TOPLEFT, font, TOPLEFT, fLX, vy(fy, DD_H))
	fy = fy + RH
	for _, key in ipairs(fkeys) do
		local fk = key
		rowLabel(font, "F" .. fk, FONT_LABEL[fk], fy)
		local dd = get("fdd_" .. fk, function()
			return QAT.widgets.Dropdown(font, "QAT_App_FDD_" .. fk, 64, FONT_OPTS, 20)
		end)
		dd.onSelect = function(v)
			phase.look.fontSizes[fk] = v
			commit(def)
		end
		dd:SetValue(look.fontSizes[fk] or FONT_DEFAULTS[fk])
		dd:ClearAnchors()
		dd:SetAnchor(TOPLEFT, font, TOPLEFT, fLX, vy(fy, DD_H))
		fy = fy + RH
	end
	font:SetDimensions(topW, fy + 8)

	QAT.widgets.PoolEnd(pool)
end

QAT.editor.tabRenderers = QAT.editor.tabRenderers or {}
QAT.editor.tabRenderers["Appearance"] = render
