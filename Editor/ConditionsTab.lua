-- Conditions tab: runtime conditions that change a tracker's look in response to
-- its live state. Each row is: when [stat] [op] [value] then [action] (+ color).

local PAD = 12
local ROW_H = 26
local GAP = 6

local STAT_OPTS = {
	{ label = "Remaining", value = "remaining" },
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
	{ label = "Recolor", value = "color" },
	{ label = "Hide", value = "hide" },
}

local function commit(def)
	QAT.widgets.NotifyTrackerChanged(def.id)
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

	def.runtime = def.runtime or {}
	local y = PAD

	local header = get("hdr", function()
		return QAT.widgets.SectionHeader(container, "QAT_Cond_Hdr", "Runtime conditions")
	end)
	header:ClearAnchors()
	header:SetAnchor(TOPLEFT, container, TOPLEFT, PAD, y)
	y = y + ROW_H + GAP

	for i, cond in ipairs(def.runtime) do
		local x = PAD

		local statDD = get("stat" .. i, function()
			return QAT.widgets.Dropdown(container, "QAT_Cond_Stat" .. i, 110, STAT_OPTS, "remaining", function(v)
				cond.stat = v
				commit(def)
			end)
		end)
		statDD:SetValue(cond.stat or "remaining")
		statDD:ClearAnchors()
		statDD:SetAnchor(TOPLEFT, container, TOPLEFT, x, y)
		x = x + 116

		local opDD = get("op" .. i, function()
			return QAT.widgets.Dropdown(container, "QAT_Cond_Op" .. i, 60, OP_OPTS, "<", function(v)
				cond.op = v
				commit(def)
			end)
		end)
		opDD:SetValue(cond.op or "<")
		opDD:ClearAnchors()
		opDD:SetAnchor(TOPLEFT, container, TOPLEFT, x, y)
		x = x + 66

		local valBox = get("val" .. i, function()
			return QAT.widgets.EditBox(container, "QAT_Cond_Val" .. i, 70, ROW_H, "", function(text)
				cond.value = tonumber(text) or 0
				commit(def)
			end)
		end)
		valBox:SetText(tostring(cond.value or 0))
		valBox:ClearAnchors()
		valBox:SetAnchor(TOPLEFT, container, TOPLEFT, x, y)
		x = x + 80

		local actDD = get("act" .. i, function()
			return QAT.widgets.Dropdown(container, "QAT_Cond_Act" .. i, 100, ACTION_OPTS, "color", function(v)
				cond.action = v
				commit(def)
				render(container, def)
			end)
		end)
		actDD:SetValue(cond.action or "color")
		actDD:ClearAnchors()
		actDD:SetAnchor(TOPLEFT, container, TOPLEFT, x, y)
		x = x + 106

		if cond.action == "color" then
			local sw = get("col" .. i, function()
				return QAT.widgets.ColorSwatch(container, "QAT_Cond_Col" .. i, ROW_H, { 1, 0, 0, 1 }, function(c)
					cond.color = c
					commit(def)
				end)
			end)
			sw:SetColor(cond.color or { 1, 0, 0, 1 })
			sw:ClearAnchors()
			sw:SetAnchor(TOPLEFT, container, TOPLEFT, x, y)
			x = x + ROW_H + 6
		end

		local del = get("del" .. i, function()
			return QAT.widgets.TextButton(container, "QAT_Cond_Del" .. i, "X", function()
				table.remove(def.runtime, i)
				commit(def)
				render(container, def)
			end)
		end)
		del:SetDimensions(ROW_H, ROW_H)
		del:ClearAnchors()
		del:SetAnchor(TOPLEFT, container, TOPLEFT, x, y)

		y = y + ROW_H + GAP
	end

	local addBtn = get("add", function()
		return QAT.widgets.TextButton(container, "QAT_Cond_Add", "+ Condition", function()
			table.insert(
				def.runtime,
				{ stat = "remaining", op = "<", value = 3, action = "color", color = { 1, 0, 0, 1 } }
			)
			commit(def)
			render(container, def)
		end)
	end)
	addBtn:SetDimensions(110, ROW_H)
	addBtn:ClearAnchors()
	addBtn:SetAnchor(TOPLEFT, container, TOPLEFT, PAD, y + GAP)

	QAT.widgets.PoolEnd(pool)
end

QAT.editor.tabRenderers = QAT.editor.tabRenderers or {}
QAT.editor.tabRenderers["Conditions"] = render
