-- Conditions tab: per-phase runtime conditions. Each row is
--   IF [stat] [op] [value]  ->  [action] (+ colour)
-- and applies ephemerally on the HUD (never written back to the saved look).
-- The phase strip mirrors the Phases tab and shares QAT.editor.selectedPhaseId, so
-- conditions are edited for the same phase you set up there.

local PAD = 12
local ROW_H = 26
local GAP = 6

local STAT_OPTS = {
	{ label = "Time left", value = "remaining" },
	{ label = "Stacks", value = "stacks" },
}
local OP_OPTS = {
	{ label = "<", value = "<" },
	{ label = "<=", value = "<=" },
	{ label = "==", value = "==" },
	{ label = "~=", value = "~=" },
	{ label = ">=", value = ">=" },
	{ label = ">", value = ">" },
}
local ACTION_OPTS = {
	{ label = "Set Background Color", value = "setBackgroundColor" },
	{ label = "Set Bar Color", value = "setBarColor" },
	{ label = "Set Border Color", value = "setBorderColor" },
	{ label = "Set Stacks Color", value = "setStacksColor" },
	{ label = "Set Text Color", value = "setTextColor" },
	{ label = "Set Timer Color", value = "setTimerColor" },
	{ label = "Show Proc", value = "showProc" },
}

local function commit(def)
	QAT.CanonicalizeDef(def)
	QAT.widgets.NotifyTrackerChanged(def.id)
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

local function render(container, def)
	local pool = container.pool or QAT.widgets.NewPool()
	container.pool = pool
	QAT.widgets.PoolBegin(pool)
	local function get(key, factory)
		return QAT.widgets.PoolGet(pool, key, factory)
	end

	if def.kind == "folder" then
		local note = get("folderNote", function()
			return QAT.widgets.Label(container, "QAT_Cond_FolderNote", "")
		end)
		note:SetText("Groups have no runtime conditions. Use the Load tab for shared load conditions.")
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

	-- Phase strip (shared selection with the Phases tab).
	local strip = get("strip", function()
		return QAT.widgets.Label(container, "QAT_Cond_Strip", "Phase:")
	end)
	strip:SetText("Phase:")
	strip:ClearAnchors()
	strip:SetAnchor(TOPLEFT, container, TOPLEFT, PAD, y + 3)
	local x = PAD + 56
	for i, p in ipairs(def.phases) do
		local pid = p.id
		local chip = get("chip" .. i, function()
			return QAT.widgets.TextButton(container, "QAT_Cond_Chip" .. i, "", nil)
		end)
		chip:SetSelected(pid == QAT.editor.selectedPhaseId)
		chip.label:SetText(pid)
		chip:SetDimensions(90, ROW_H)
		chip:ClearAnchors()
		chip:SetAnchor(TOPLEFT, container, TOPLEFT, x, y)
		chip.onClick = function()
			QAT.editor.selectedPhaseId = pid
			render(container, def)
		end
		x = x + 96
	end
	y = y + ROW_H + GAP

	local phase = selectedPhase(def)
	if not phase then
		QAT.widgets.PoolEnd(pool)
		return
	end
	phase.runtime = phase.runtime or {}

	local header = get("hdr", function()
		return QAT.widgets.SectionHeader(container, "QAT_Cond_Hdr", "")
	end)
	header:SetText("Runtime conditions — phase: " .. phase.id)
	header:ClearAnchors()
	header:SetAnchor(TOPLEFT, container, TOPLEFT, PAD, y)
	y = y + ROW_H + GAP

	for i, cond in ipairs(phase.runtime) do
		local idx = i
		local cx = PAD

		local statDD = get("stat" .. i, function()
			return QAT.widgets.Dropdown(container, "QAT_Cond_Stat" .. i, 100, STAT_OPTS, "remaining")
		end)
		statDD.onSelect = function(v)
			cond.stat = v
			commit(def)
		end
		statDD:SetValue(cond.stat or "remaining")
		statDD:ClearAnchors()
		statDD:SetAnchor(TOPLEFT, container, TOPLEFT, cx, y)
		cx = cx + 106

		local opDD = get("op" .. i, function()
			return QAT.widgets.Dropdown(container, "QAT_Cond_Op" .. i, 54, OP_OPTS, "<")
		end)
		opDD.onSelect = function(v)
			cond.op = v
			commit(def)
		end
		opDD:SetValue(cond.op or "<")
		opDD:ClearAnchors()
		opDD:SetAnchor(TOPLEFT, container, TOPLEFT, cx, y)
		cx = cx + 60

		local valBox = get("val" .. i, function()
			return QAT.widgets.EditBox(container, "QAT_Cond_Val" .. i, 56, ROW_H)
		end)
		valBox.onChange = function(text)
			cond.value = tonumber(text) or 0
			commit(def)
		end
		valBox:SetText(tostring(cond.value or 0))
		valBox:ClearAnchors()
		valBox:SetAnchor(TOPLEFT, container, TOPLEFT, cx, y)
		cx = cx + 62

		local arrow = get("arr" .. i, function()
			return QAT.widgets.Label(container, "QAT_Cond_Arr" .. i, "->")
		end)
		arrow:SetText("->")
		arrow:ClearAnchors()
		arrow:SetAnchor(TOPLEFT, container, TOPLEFT, cx, y + 3)
		cx = cx + 22

		local actDD = get("act" .. i, function()
			return QAT.widgets.Dropdown(container, "QAT_Cond_Act" .. i, 168, ACTION_OPTS, "setBarColor")
		end)
		actDD.onSelect = function(v)
			cond.action = v
			commit(def)
			render(container, def)
		end
		actDD:SetValue(cond.action or "setBarColor")
		actDD:ClearAnchors()
		actDD:SetAnchor(TOPLEFT, container, TOPLEFT, cx, y)
		cx = cx + 174

		-- Colour swatch for the Set-X-Color actions (not Show Proc).
		local sw = get("col" .. i, function()
			return QAT.widgets.ColorSwatch(container, "QAT_Cond_Col" .. i, ROW_H, { 1, 0, 0, 1 })
		end)
		if cond.action ~= "showProc" then
			sw.onChange = function(c)
				cond.color = c
				commit(def)
			end
			sw:SetColor(cond.color or { 1, 0, 0, 1 })
			sw:SetHidden(false)
			sw:ClearAnchors()
			sw:SetAnchor(TOPLEFT, container, TOPLEFT, cx, y)
			cx = cx + ROW_H + 6
		else
			sw:SetHidden(true)
		end

		local del = get("del" .. i, function()
			return QAT.widgets.TextButton(container, "QAT_Cond_Del" .. i, "X", nil)
		end)
		del:SetDimensions(ROW_H, ROW_H)
		del:ClearAnchors()
		del:SetAnchor(TOPLEFT, container, TOPLEFT, cx, y)
		del.onClick = function()
			table.remove(phase.runtime, idx)
			commit(def)
			render(container, def)
		end

		y = y + ROW_H + GAP
	end

	local addBtn = get("add", function()
		return QAT.widgets.TextButton(container, "QAT_Cond_Add", "+ Condition", nil)
	end)
	addBtn:SetDimensions(110, ROW_H)
	addBtn:ClearAnchors()
	addBtn:SetAnchor(TOPLEFT, container, TOPLEFT, PAD, y + GAP)
	addBtn.onClick = function()
		table.insert(
			phase.runtime,
			{ stat = "remaining", op = "<", value = 3, action = "setBarColor", color = { 1, 0, 0, 1 } }
		)
		commit(def)
		render(container, def)
	end

	QAT.widgets.PoolEnd(pool)
end

QAT.editor.tabRenderers = QAT.editor.tabRenderers or {}
QAT.editor.tabRenderers["Conditions"] = render
