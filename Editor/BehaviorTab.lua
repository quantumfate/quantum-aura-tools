-- Behavior tab: the selected phase's timer and its outgoing transitions (the state
-- machine). The phase is chosen by the shared phase strip in the header.

local PAD = 12
local ROW_H = 26
local GAP = 8

local DURATION_OPTS = {
	{ label = "Follows effect", value = "effect" },
	{ label = "Fixed seconds", value = "fixed" },
	{ label = "None (static)", value = "none" },
}
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
-- The unit each effect is watched on. Per-effect, so one phase can watch self for
-- one trigger and the target for another.
local UNIT_OPTS = {
	{ label = "Self", value = "player" },
	{ label = "Target", value = "reticleover" },
}

local function triggerValue(when)
	if when.kind == "effect" then
		return when.result or "gained"
	end
	return when.kind
end

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
			return QAT.widgets.Label(container, "QAT_Beh_" .. key, "")
		end)
		l:SetText(text)
		l:ClearAnchors()
		l:SetAnchor(TOPLEFT, container, TOPLEFT, PAD, yy + 3)
		QAT.widgets.Tooltip(l, tip)
		return l
	end

	-- Duration (the timer that animates the phase and defines "Timer ends").
	fieldLabel(
		"lDur",
		"Duration",
		y,
		"The phase's timer: Follows effect (while the buff is on the unit; permanent buffs show static), Fixed seconds (e.g. a cooldown), or None."
	)
	local durDD = get("durDD", function()
		return QAT.widgets.Dropdown(container, "QAT_Beh_Dur", 180, DURATION_OPTS, "none")
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
			return QAT.widgets.EditBox(container, "QAT_Beh_Secs", 100, ROW_H)
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
		fieldLabel(
			"lDurIds",
			"Effect",
			y,
			"The unit this effect is on, and the ability id(s) to follow (comma-separated)."
		)
		local durUnitDD = get("durUnit", function()
			return QAT.widgets.Dropdown(container, "QAT_Beh_DurUnit", 90, UNIT_OPTS, "player")
		end)
		durUnitDD.onSelect = function(v)
			phase.duration.unit = v
			commit(def)
		end
		durUnitDD:SetValue(phase.duration.unit or def.unit or "player")
		durUnitDD:ClearAnchors()
		durUnitDD:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y)
		local durIdBox = get("durIdBox", function()
			return QAT.widgets.EditBox(container, "QAT_Beh_DurIds", 180, ROW_H)
		end)
		durIdBox.onChange = function(text)
			phase.duration.abilityIds = textToIds(text)
			commit(def)
		end
		durIdBox:SetText(idsToText(phase.duration.abilityIds))
		durIdBox:ClearAnchors()
		durIdBox:SetAnchor(TOPLEFT, container, TOPLEFT, LX + 96, y)
		y = y + ROW_H + GAP
	end

	-- Transitions: an ordered list of exits; the engine takes the FIRST whose
	-- trigger matches (mutually exclusive).
	fieldLabel(
		"lTrans",
		"Transitions",
		y,
		"Where this phase can go next. Checked top to bottom; the first matching trigger wins (only one ever fires). Add several to branch on different triggers."
	)
	y = y + ROW_H
	if #phase.transitions > 1 then
		local hint = get("trHint", function()
			return QAT.widgets.Label(container, "QAT_Beh_TrHint", "")
		end)
		hint:SetText("checked top to bottom — first match wins")
		hint:SetColor(0.6, 0.65, 0.72, 1)
		hint:ClearAnchors()
		hint:SetAnchor(TOPLEFT, container, TOPLEFT, PAD + 26, y)
		y = y + 20
	end

	for i, tr in ipairs(phase.transitions) do
		local idx = i
		local when = tr.when

		local numLbl = get("trNum" .. i, function()
			return QAT.widgets.Label(container, "QAT_Beh_TrNum" .. i, "")
		end)
		numLbl:SetText(i .. ".")
		numLbl:ClearAnchors()
		numLbl:SetAnchor(TOPLEFT, container, TOPLEFT, PAD, y + 3)

		local x = PAD + 26
		local trigDD = get("trTrig" .. i, function()
			return QAT.widgets.Dropdown(container, "QAT_Beh_TrTrig" .. i, 120, TRIGGER_OPTS, "gained")
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

		local unitDD = get("trUnit" .. i, function()
			return QAT.widgets.Dropdown(container, "QAT_Beh_TrUnit" .. i, 86, UNIT_OPTS, "player")
		end)
		local idsBox = get("trIds" .. i, function()
			return QAT.widgets.EditBox(container, "QAT_Beh_TrIds" .. i, 130, ROW_H)
		end)
		local opDD = get("trOp" .. i, function()
			return QAT.widgets.Dropdown(container, "QAT_Beh_TrOp" .. i, 54, OP_OPTS, ">=")
		end)
		local valBox = get("trVal" .. i, function()
			return QAT.widgets.EditBox(container, "QAT_Beh_TrVal" .. i, 56, ROW_H)
		end)
		if when.kind == "effect" then
			opDD:SetHidden(true)
			valBox:SetHidden(true)
			-- "<result> on <unit> of <ids>": who gained/faded it matters.
			unitDD:SetHidden(false)
			unitDD.onSelect = function(v)
				when.unit = v
				commit(def)
			end
			unitDD:SetValue(when.unit or def.unit or "player")
			unitDD:ClearAnchors()
			unitDD:SetAnchor(TOPLEFT, container, TOPLEFT, x, y)
			x = x + 92
			idsBox:SetHidden(false)
			idsBox.onChange = function(text)
				when.abilityIds = textToIds(text)
				commit(def)
			end
			idsBox:SetText(idsToText(when.abilityIds))
			idsBox:ClearAnchors()
			idsBox:SetAnchor(TOPLEFT, container, TOPLEFT, x, y)
			x = x + 136
		elseif when.kind == "stacks" or when.kind == "remaining" then
			unitDD:SetHidden(true)
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
		else
			unitDD:SetHidden(true)
			idsBox:SetHidden(true)
			opDD:SetHidden(true)
			valBox:SetHidden(true)
		end

		local arrow = get("trArrow" .. i, function()
			return QAT.widgets.Label(container, "QAT_Beh_TrArrow" .. i, "->")
		end)
		arrow:SetText("->")
		arrow:ClearAnchors()
		arrow:SetAnchor(TOPLEFT, container, TOPLEFT, x, y + 3)
		x = x + 24

		local toDD = get("trTo" .. i, function()
			return QAT.widgets.Dropdown(container, "QAT_Beh_TrTo" .. i, 110, {}, nil)
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
			return QAT.widgets.TextButton(container, "QAT_Beh_TrDel" .. i, "X", nil)
		end)
		del:SetDimensions(ROW_H, ROW_H)
		del:ClearAnchors()
		del:SetAnchor(TOPLEFT, container, TOPLEFT, x, y)
		QAT.widgets.Tooltip(del, "Remove this transition.")
		del.onClick = function()
			table.remove(phase.transitions, idx)
			commit(def)
			render(container, def)
		end

		y = y + ROW_H + GAP
	end

	local addTrans = get("addTrans", function()
		return QAT.widgets.TextButton(container, "QAT_Beh_AddTrans", "+ Transition", nil)
	end)
	addTrans:SetHeight(ROW_H)
	addTrans:ClearAnchors()
	addTrans:SetAnchor(TOPLEFT, container, TOPLEFT, PAD + 26, y)
	QAT.widgets.Tooltip(addTrans, "Add an outgoing transition to this phase.")
	addTrans.onClick = function()
		table.insert(phase.transitions, { when = { kind = "effect", result = "gained", abilityIds = {} }, to = nil })
		commit(def)
		render(container, def)
	end
	y = y + ROW_H + GAP

	QAT.widgets.PoolEnd(pool)
end

QAT.editor.tabRenderers = QAT.editor.tabRenderers or {}
QAT.editor.tabRenderers["Behavior"] = render
