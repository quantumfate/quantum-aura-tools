-- Phases tab: the per-phase state-machine editor.
--
-- Top: a flow summary plus a strip of selectable phase chips (with add / delete /
-- set-initial). Below: the detail editor for the selected phase — its look,
-- duration source, enter trigger and on-expire transition.

local PAD = 12
local ROW_H = 26
local GAP = 8

local DISPLAY_OPTS = {
	{ label = "Bar", value = "bar" },
	{ label = "Icon", value = "icon" },
	{ label = "Text", value = "text" },
	{ label = "None (cue only)", value = "none" },
}
local DURATION_OPTS = {
	{ label = "Follows effect", value = "effect" },
	{ label = "Fixed seconds", value = "fixed" },
	{ label = "None (static)", value = "none" },
}
local RESULT_OPTS = {
	{ label = "gained", value = "gained" },
	{ label = "faded", value = "faded" },
}

-- Comma-separated ability id string <-> array of numbers.
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

local function phaseOptions(def, includeNone)
	local opts = {}
	if includeNone then
		table.insert(opts, { label = "(idle)", value = nil })
	end
	for _, p in ipairs(def.phases) do
		table.insert(opts, { label = p.id, value = p.id })
	end
	return opts
end

local function commit(def)
	QAT.CanonicalizeDef(def)
	QAT.widgets.NotifyTrackerChanged(def.id)
end

-- A readable one-line summary of the state flow, e.g. "Ready -> Active -> Cooldown".
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

	-- Defensive: guarantee a canonical (phased) def so the editor never renders a
	-- flat shorthand from an import or older data.
	QAT.CanonicalizeDef(def)

	-- Ensure a valid selected phase.
	if not selectedPhase(def) then
		QAT.editor.selectedPhaseId = def.phases[1] and def.phases[1].id
	end

	local y = PAD

	-- Flow summary line.
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

	-- Add phase.
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
			{ id = "phase" .. n, look = { display = "bar" }, duration = { type = "none" }, enter = {} }
		)
		QAT.editor.selectedPhaseId = "phase" .. n
		commit(def)
		render(container, def)
	end
	y = y + ROW_H + GAP

	-- Detail editor for the selected phase.
	local phase = selectedPhase(def)
	if not phase then
		QAT.widgets.PoolEnd(pool)
		return
	end
	local trig = phase.enter[1] or { kind = "effect", abilityIds = {}, result = "gained" }
	phase.enter[1] = trig

	local function fieldLabel(key, text, yy)
		local l = get(key, function()
			return QAT.widgets.Label(container, "QAT_Ph_" .. key, "")
		end)
		l:SetText(text)
		l:ClearAnchors()
		l:SetAnchor(TOPLEFT, container, TOPLEFT, PAD, yy + 3)
		return l
	end

	local LX = PAD + 110 -- control column

	-- Phase id.
	fieldLabel("lId", "Phase id", y)
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

	-- Display kind.
	fieldLabel("lDisp", "Display", y)
	local dispDD = get("dispDD", function()
		return QAT.widgets.Dropdown(container, "QAT_Ph_Disp", 180, DISPLAY_OPTS, "bar")
	end)
	dispDD.onSelect = function(v)
		phase.look.display = v
		commit(def)
	end
	dispDD:SetValue(phase.look.display or "bar")
	dispDD:ClearAnchors()
	dispDD:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y)
	y = y + ROW_H + GAP

	-- Display name.
	fieldLabel("lName", "Label text", y)
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

	-- Color.
	fieldLabel("lColor", "Color", y)
	local colorSw = get("colorSw", function()
		return QAT.widgets.ColorSwatch(container, "QAT_Ph_Color", ROW_H, { 1, 1, 1, 1 })
	end)
	colorSw.onChange = function(c)
		phase.look.color = c
		commit(def)
	end
	colorSw:SetColor(phase.look.color or { 1, 1, 1, 1 })
	colorSw:ClearAnchors()
	colorSw:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y)
	y = y + ROW_H + GAP

	-- Duration type.
	fieldLabel("lDur", "Duration", y)
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

	-- Duration parameter (seconds for fixed, ability ids for effect).
	if phase.duration.type == "fixed" then
		fieldLabel("lSecs", "Seconds", y)
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
		fieldLabel("lDurIds", "Effect ids", y)
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

	-- Enter trigger (single, common case): result + ability ids.
	fieldLabel("lEnter", "Enter on", y)
	local resDD = get("resDD", function()
		return QAT.widgets.Dropdown(container, "QAT_Ph_Res", 110, RESULT_OPTS, "gained")
	end)
	resDD.onSelect = function(v)
		trig.result = v
		commit(def)
	end
	resDD:SetValue(trig.result or "gained")
	resDD:ClearAnchors()
	resDD:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y)

	local enterIdBox = get("enterIdBox", function()
		return QAT.widgets.EditBox(container, "QAT_Ph_EnterIds", 200, ROW_H)
	end)
	enterIdBox.onChange = function(text)
		trig.abilityIds = textToIds(text)
		commit(def)
	end
	enterIdBox:SetText(idsToText(trig.abilityIds))
	enterIdBox:ClearAnchors()
	enterIdBox:SetAnchor(TOPLEFT, container, TOPLEFT, LX + 120, y)
	y = y + ROW_H + GAP

	-- On-expire transition. Options are rebuilt each render (the phase list changes).
	fieldLabel("lExpire", "On expire", y)
	local expireDD = get("expireDD", function()
		return QAT.widgets.Dropdown(container, "QAT_Ph_Expire", 180, {}, nil)
	end)
	expireDD:SetOptions(phaseOptions(def, true))
	expireDD.onSelect = function(v)
		phase.onExpire = v
		commit(def)
	end
	expireDD:SetValue(phase.onExpire)
	expireDD:ClearAnchors()
	expireDD:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y)
	y = y + ROW_H + GAP

	-- Set-initial / delete buttons for the selected phase.
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
