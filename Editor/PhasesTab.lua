-- Phases tab (Stage-A interim).
--
-- The full editor IA (header Load, phase selector, and separate Appearance /
-- Behavior / Conditions tabs with the transitions editor and per-element colors)
-- lands in Stage B. This interim view keeps live editing working against the new
-- schema: appearance basics + duration are editable, and a phase's transitions are
-- shown read-only so the new state machine is visible while it is being tested.

local WM = GetWindowManager()
local PAD = 12
local ROW_H = 26
local GAP = 8

local DISPLAY_OPTS = {
	{ label = "Bar", value = "bar" },
	{ label = "Icon", value = "icon" },
	{ label = "Text", value = "text" },
	{ label = "None (hidden)", value = "none" },
}
local DURATION_OPTS = {
	{ label = "Follows effect", value = "effect" },
	{ label = "Fixed seconds", value = "fixed" },
	{ label = "None (static)", value = "none" },
}
-- A transition's trigger, flattened for the dropdown (effect result is folded in).
local TRIGGER_OPTS = {
	{ label = "Effect gained", value = "gained" },
	{ label = "Effect faded", value = "faded" },
	{ label = "Stacks", value = "stacks" },
	{ label = "Time left", value = "remaining" },
	{ label = "Timer ends", value = "expire" },
}
local OP_OPTS = {
	{ label = "<", value = "<" },
	{ label = "<=", value = "<=" },
	{ label = "==", value = "==" },
	{ label = "~=", value = "~=" },
	{ label = ">=", value = ">=" },
	{ label = ">", value = ">" },
}

-- The flattened trigger value for an existing `when`.
local function triggerValue(when)
	if when.kind == "effect" then
		return when.result or "gained"
	end
	return when.kind
end

-- Reshape a `when` in place for a newly chosen trigger value, keeping fields valid.
local function setTriggerKind(when, v)
	if v == "gained" or v == "faded" then
		when.kind = "effect"
		when.result = v
		when.abilityIds = when.abilityIds or {}
	elseif v == "stacks" or v == "remaining" then
		when.kind = v
		when.op = when.op or ">="
		when.value = when.value or 0
	else
		when.kind = "expire"
	end
end

local function idsToText(ids)
	return table.concat(ids or {}, ", ")
end
local function textToIds(text)
	local ids = {}
	for token in tostring(text or ""):gmatch("%d+") do
		table.insert(ids, tonumber(token))
	end
	return ids
end

local function selectedPhase(def)
	local id = QAT.editor.selectedPhaseId
	for _, p in ipairs(def.phases) do
		if p.id == id then
			return p
		end
	end
	return def.phases[1]
end

-- Target options for a transition: every phase, plus "(hidden)" = nil.
local function phaseOptions(def)
	local opts = { { label = "(hidden)", value = nil } }
	for _, p in ipairs(def.phases) do
		table.insert(opts, { label = p.id, value = p.id })
	end
	return opts
end

local function commit(def)
	QAT.CanonicalizeDef(def)
	QAT.widgets.NotifyTrackerChanged(def.id)
end

local function flowText(def)
	local parts = {}
	for _, p in ipairs(def.phases) do
		local marker = (p.id == def.initial) and ("[" .. p.id .. "]") or p.id
		table.insert(parts, marker)
	end
	return "Phases:  " .. table.concat(parts, "    ")
end

local function render(container, def)
	local pool = container.pool or QAT.widgets.NewPool()
	container.pool = pool
	QAT.widgets.PoolBegin(pool)

	local function get(key, factory)
		return QAT.widgets.PoolGet(pool, key, factory)
	end

	if def.kind == "folder" then
		local note = get("folderNote", function()
			return QAT.widgets.Label(container, "QAT_Ph_FolderNote", "")
		end)
		note:SetText("Groups have no phases. Use the Load tab for shared conditions.")
		note:ClearAnchors()
		note:SetAnchor(TOPLEFT, container, TOPLEFT, PAD, PAD)
		QAT.widgets.PoolEnd(pool)
		return
	end

	QAT.CanonicalizeDef(def)
	if not selectedPhase(def) then
		QAT.editor.selectedPhaseId = def.phases[1] and def.phases[1].id
	end

	local y = PAD

	local flow = get("flow", function()
		return QAT.widgets.Label(container, "QAT_Ph_Flow", "")
	end)
	flow:SetText(flowText(def))
	flow:ClearAnchors()
	flow:SetAnchor(TOPLEFT, container, TOPLEFT, PAD, y)
	y = y + ROW_H

	-- Phase chips.
	local x = PAD
	for i, p in ipairs(def.phases) do
		local pid = p.id
		local chip = get("chip" .. i, function()
			return QAT.widgets.TextButton(container, "QAT_Ph_Chip" .. i, "", nil)
		end)
		chip:SetSelected(pid == QAT.editor.selectedPhaseId)
		chip.label:SetText(pid)
		chip:SetDimensions(96, ROW_H)
		chip:ClearAnchors()
		chip:SetAnchor(TOPLEFT, container, TOPLEFT, x, y)
		chip.onClick = function()
			QAT.editor.selectedPhaseId = pid
			render(container, def)
		end
		x = x + 96 + 8
	end

	local addBtn = get("add", function()
		return QAT.widgets.TextButton(container, "QAT_Ph_Add", "+ Phase", nil)
	end)
	addBtn:SetDimensions(80, ROW_H)
	addBtn:ClearAnchors()
	addBtn:SetAnchor(TOPLEFT, container, TOPLEFT, x, y)
	addBtn.onClick = function()
		local n = #def.phases + 1
		table.insert(
			def.phases,
			{ id = "phase" .. n, look = { display = "bar" }, duration = { type = "none" }, transitions = {} }
		)
		QAT.editor.selectedPhaseId = "phase" .. n
		commit(def)
		render(container, def)
	end
	y = y + ROW_H + GAP

	local phase = selectedPhase(def)
	if not phase then
		QAT.widgets.PoolEnd(pool)
		return
	end

	local LX = PAD + 110

	local function fieldLabel(key, text, yy, tip)
		local l = get(key, function()
			return QAT.widgets.Label(container, "QAT_Ph_" .. key, "")
		end)
		l:SetText(text)
		l:ClearAnchors()
		l:SetAnchor(TOPLEFT, container, TOPLEFT, PAD, yy + 3)
		QAT.widgets.Tooltip(l, tip)
		return l
	end

	local function sectionHeader(key, text, yy)
		local h = get(key, function()
			return QAT.widgets.SectionHeader(container, "QAT_Ph_" .. key, "")
		end)
		h:SetText(text)
		h:ClearAnchors()
		h:SetAnchor(TOPLEFT, container, TOPLEFT, PAD, yy)
		return h
	end

	-- Phase id.
	fieldLabel(
		"lId",
		"Phase id",
		y,
		"Internal name for this phase (e.g. Idle, Active, Cooldown). Transitions target phases by this name."
	)
	local idBox = get("idBox", function()
		return QAT.widgets.EditBox(container, "QAT_Ph_IdBox", 180, ROW_H)
	end)
	idBox.onChange = function(text)
		text = zo_strtrim(text)
		if text ~= "" then
			phase.id = text
			if def.initial == QAT.editor.selectedPhaseId then
				def.initial = text
			end
			QAT.editor.selectedPhaseId = text
			commit(def)
		end
	end
	idBox:SetText(phase.id)
	idBox:ClearAnchors()
	idBox:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y)
	y = y + ROW_H + GAP

	-- ===== Appearance =====
	sectionHeader("hAppear", "Appearance", y)
	y = y + ROW_H

	fieldLabel(
		"lDisp",
		"Display",
		y,
		"How this phase draws: Bar, Icon, Text, or None (hidden - used for an idle phase)."
	)
	local dispDD = get("dispDD", function()
		return QAT.widgets.Dropdown(container, "QAT_Ph_Disp", 180, DISPLAY_OPTS, "bar")
	end)
	dispDD.onSelect = function(v)
		phase.look.display = v
		commit(def)
		render(container, def)
	end
	dispDD:SetValue(phase.look.display or "bar")
	dispDD:ClearAnchors()
	dispDD:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y)
	y = y + ROW_H + GAP

	-- Icon override (icon display only).
	local iconBox = get("iconBox", function()
		return QAT.widgets.EditBox(container, "QAT_Ph_IconBox", 260, ROW_H)
	end)
	local iconLabel = get("lIcon", function()
		return QAT.widgets.Label(container, "QAT_Ph_lIcon", "Icon")
	end)
	local iconPreview = get("iconPreview", function()
		return WM:CreateControl("QAT_Ph_IconPreview", container, CT_TEXTURE)
	end)
	if phase.look.display == "icon" then
		iconLabel:SetHidden(false)
		iconLabel:SetText("Icon")
		iconLabel:ClearAnchors()
		iconLabel:SetAnchor(TOPLEFT, container, TOPLEFT, PAD, y + 3)
		QAT.widgets.Tooltip(
			iconLabel,
			"Texture path for the icon. Leave empty to use the tracked ability's own icon automatically."
		)
		iconBox:SetHidden(false)
		iconBox.onChange = function(text)
			text = zo_strtrim(text or "")
			phase.look.icon = (text ~= "" and text) or nil
			commit(def)
			render(container, def)
		end
		iconBox:SetText(phase.look.icon or "")
		iconBox:ClearAnchors()
		iconBox:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y)
		iconPreview:SetHidden(false)
		iconPreview:SetDimensions(ROW_H, ROW_H)
		iconPreview:SetTexture(QAT.util.PhaseIcon(phase) or "/esoui/art/icons/icon_missing.dds")
		iconPreview:ClearAnchors()
		iconPreview:SetAnchor(LEFT, iconBox, RIGHT, 8, 0)
		y = y + ROW_H + GAP
	else
		iconLabel:SetHidden(true)
		iconBox:SetHidden(true)
		iconPreview:SetHidden(true)
	end

	-- Label text.
	fieldLabel(
		"lName",
		"Label text",
		y,
		"Text drawn next to the bar / on icons. Leave empty to use the tracker's name."
	)
	local nameBox = get("nameBox", function()
		return QAT.widgets.EditBox(container, "QAT_Ph_NameBox", 220, ROW_H)
	end)
	nameBox.onChange = function(text)
		phase.look.name = text
		commit(def)
	end
	nameBox:SetText(phase.look.name or "")
	nameBox:ClearAnchors()
	nameBox:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y)
	y = y + ROW_H + GAP

	-- Primary (bar / fill) color + Decimals. (Full per-element colors come in Stage B.)
	fieldLabel("lColor", "Color", y, "Primary fill / bar colour. Per-element colours arrive with the Appearance tab.")
	local colorSw = get("colorSw", function()
		return QAT.widgets.ColorSwatch(container, "QAT_Ph_Color", ROW_H, { 1, 1, 1, 1 })
	end)
	colorSw.onChange = function(c)
		phase.look.colors = phase.look.colors or {}
		phase.look.colors.bar = c
		commit(def)
	end
	colorSw:SetColor((phase.look.colors and phase.look.colors.bar) or { 0.2, 0.8, 0.35, 1 })
	colorSw:ClearAnchors()
	colorSw:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y)

	local decLabel = get("lDec", function()
		return QAT.widgets.Label(container, "QAT_Ph_lDec", "Decimals")
	end)
	decLabel:SetText("Decimals")
	decLabel:ClearAnchors()
	decLabel:SetAnchor(TOPLEFT, container, TOPLEFT, LX + 44, y + 3)
	QAT.widgets.Tooltip(decLabel, "Decimal places on the time readout.")
	local decBox = get("decBox", function()
		return QAT.widgets.EditBox(container, "QAT_Ph_Dec", 50, ROW_H)
	end)
	decBox.onChange = function(text)
		phase.look.decimals = tonumber(text) or 0
		commit(def)
	end
	decBox:SetText(tostring(phase.look.decimals or 1))
	decBox:ClearAnchors()
	decBox:SetAnchor(TOPLEFT, container, TOPLEFT, LX + 120, y)
	y = y + ROW_H + GAP

	-- Show stacks.
	fieldLabel(
		"lShowStacks",
		"Show stacks",
		y,
		"This effect has stacks - show the stack number when the game reports stacks."
	)
	local stacksChk = get("stacksChk", function()
		return QAT.widgets.Checkbox(container, "QAT_Ph_ShowStacks", false)
	end)
	stacksChk:SetChecked(phase.look.showStacks or false)
	stacksChk.onToggle = function(v)
		phase.look.showStacks = v or nil
		commit(def)
	end
	stacksChk:ClearAnchors()
	stacksChk:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y + 2)
	y = y + ROW_H + GAP

	-- ===== Behavior =====
	sectionHeader("hBehavior", "Behavior", y)
	y = y + ROW_H

	fieldLabel(
		"lDur",
		"Duration",
		y,
		"The phase's timer: Follows effect (while the buff is on the unit; permanent buffs show static), Fixed seconds (e.g. a cooldown), or None."
	)
	local durDD = get("durDD", function()
		return QAT.widgets.Dropdown(container, "QAT_Ph_Dur", 180, DURATION_OPTS, "none")
	end)
	durDD.onSelect = function(v)
		phase.duration.type = v
		commit(def)
		render(container, def)
	end
	durDD:SetValue(phase.duration.type or "none")
	durDD:ClearAnchors()
	durDD:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y)
	y = y + ROW_H + GAP

	if phase.duration.type == "fixed" then
		fieldLabel("lSecs", "Seconds", y, "Length of the fixed timer, in seconds.")
		local secsBox = get("secsBox", function()
			return QAT.widgets.EditBox(container, "QAT_Ph_Secs", 100, ROW_H)
		end)
		secsBox.onChange = function(text)
			phase.duration.seconds = tonumber(text) or 0
			commit(def)
		end
		secsBox:SetText(tostring(phase.duration.seconds or 0))
		secsBox:ClearAnchors()
		secsBox:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y)
		y = y + ROW_H + GAP
	elseif phase.duration.type == "effect" then
		fieldLabel("lDurIds", "Effect ids", y, "Ability id(s) this phase follows. Comma-separated.")
		local durIdBox = get("durIdBox", function()
			return QAT.widgets.EditBox(container, "QAT_Ph_DurIds", 220, ROW_H)
		end)
		durIdBox.onChange = function(text)
			phase.duration.abilityIds = textToIds(text)
			commit(def)
		end
		durIdBox:SetText(idsToText(phase.duration.abilityIds))
		durIdBox:ClearAnchors()
		durIdBox:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y)
		y = y + ROW_H + GAP
	end

	-- Transitions editor: each row is "IF <trigger> -> <target phase>".
	fieldLabel(
		"lTrans",
		"Transitions",
		y,
		"When does this phase hand off, and to which phase. Effect = a buff gained/faded; Stacks/Time left = a live threshold; Timer ends = the duration ran out."
	)
	y = y + ROW_H

	for i, tr in ipairs(phase.transitions) do
		local idx = i
		local when = tr.when
		local x = PAD + 12

		local trigDD = get("trTrig" .. i, function()
			return QAT.widgets.Dropdown(container, "QAT_Ph_TrTrig" .. i, 120, TRIGGER_OPTS, "gained")
		end)
		trigDD.onSelect = function(v)
			setTriggerKind(when, v)
			commit(def)
			render(container, def)
		end
		trigDD:SetValue(triggerValue(when))
		trigDD:ClearAnchors()
		trigDD:SetAnchor(TOPLEFT, container, TOPLEFT, x, y)
		x = x + 126

		local idsBox = get("trIds" .. i, function()
			return QAT.widgets.EditBox(container, "QAT_Ph_TrIds" .. i, 150, ROW_H)
		end)
		local opDD = get("trOp" .. i, function()
			return QAT.widgets.Dropdown(container, "QAT_Ph_TrOp" .. i, 54, OP_OPTS, ">=")
		end)
		local valBox = get("trVal" .. i, function()
			return QAT.widgets.EditBox(container, "QAT_Ph_TrVal" .. i, 56, ROW_H)
		end)
		if when.kind == "effect" then
			opDD:SetHidden(true)
			valBox:SetHidden(true)
			idsBox:SetHidden(false)
			idsBox.onChange = function(text)
				when.abilityIds = textToIds(text)
				commit(def)
			end
			idsBox:SetText(idsToText(when.abilityIds))
			idsBox:ClearAnchors()
			idsBox:SetAnchor(TOPLEFT, container, TOPLEFT, x, y)
			x = x + 156
		elseif when.kind == "stacks" or when.kind == "remaining" then
			idsBox:SetHidden(true)
			opDD:SetHidden(false)
			opDD.onSelect = function(v)
				when.op = v
				commit(def)
			end
			opDD:SetValue(when.op or ">=")
			opDD:ClearAnchors()
			opDD:SetAnchor(TOPLEFT, container, TOPLEFT, x, y)
			valBox:SetHidden(false)
			valBox.onChange = function(text)
				when.value = tonumber(text) or 0
				commit(def)
			end
			valBox:SetText(tostring(when.value or 0))
			valBox:ClearAnchors()
			valBox:SetAnchor(TOPLEFT, container, TOPLEFT, x + 60, y)
			x = x + 122
		else -- expire: no parameter
			idsBox:SetHidden(true)
			opDD:SetHidden(true)
			valBox:SetHidden(true)
		end

		local arrow = get("trArrow" .. i, function()
			return QAT.widgets.Label(container, "QAT_Ph_TrArrow" .. i, "->")
		end)
		arrow:SetText("->")
		arrow:ClearAnchors()
		arrow:SetAnchor(TOPLEFT, container, TOPLEFT, x, y + 3)
		x = x + 24

		local toDD = get("trTo" .. i, function()
			return QAT.widgets.Dropdown(container, "QAT_Ph_TrTo" .. i, 110, {}, nil)
		end)
		toDD:SetOptions(phaseOptions(def))
		toDD.onSelect = function(v)
			tr.to = v
			commit(def)
		end
		toDD:SetValue(tr.to)
		toDD:ClearAnchors()
		toDD:SetAnchor(TOPLEFT, container, TOPLEFT, x, y)
		x = x + 116

		local del = get("trDel" .. i, function()
			return QAT.widgets.TextButton(container, "QAT_Ph_TrDel" .. i, "X", nil)
		end)
		del:SetDimensions(ROW_H, ROW_H)
		del:ClearAnchors()
		del:SetAnchor(TOPLEFT, container, TOPLEFT, x, y)
		del.onClick = function()
			table.remove(phase.transitions, idx)
			commit(def)
			render(container, def)
		end

		y = y + ROW_H + GAP
	end

	local addTrans = get("addTrans", function()
		return QAT.widgets.TextButton(container, "QAT_Ph_AddTrans", "+ Transition", nil)
	end)
	addTrans:SetDimensions(110, ROW_H)
	addTrans:ClearAnchors()
	addTrans:SetAnchor(TOPLEFT, container, TOPLEFT, PAD + 12, y)
	addTrans.onClick = function()
		table.insert(phase.transitions, { when = { kind = "effect", result = "gained", abilityIds = {} }, to = nil })
		commit(def)
		render(container, def)
	end
	y = y + ROW_H + GAP

	-- Set-initial / delete phase.
	local initBtn = get("initBtn", function()
		return QAT.widgets.TextButton(container, "QAT_Ph_Init", "Set as initial", nil)
	end)
	initBtn:SetDimensions(120, ROW_H)
	initBtn:ClearAnchors()
	initBtn:SetAnchor(TOPLEFT, container, TOPLEFT, PAD, y)
	initBtn.onClick = function()
		def.initial = phase.id
		commit(def)
		render(container, def)
	end

	local delBtn = get("delBtn", function()
		return QAT.widgets.TextButton(container, "QAT_Ph_Del", "Delete phase", nil)
	end)
	delBtn:SetDimensions(120, ROW_H)
	delBtn:ClearAnchors()
	delBtn:SetAnchor(TOPLEFT, container, TOPLEFT, PAD + 140, y)
	delBtn.onClick = function()
		if #def.phases <= 1 then
			return
		end
		for i, p in ipairs(def.phases) do
			if p.id == phase.id then
				table.remove(def.phases, i)
				break
			end
		end
		QAT.editor.selectedPhaseId = def.phases[1].id
		commit(def)
		render(container, def)
	end

	QAT.widgets.PoolEnd(pool)
end

QAT.editor.tabRenderers = QAT.editor.tabRenderers or {}
QAT.editor.tabRenderers["Phases"] = render
