-- Conditions tab (Stage-A interim).
--
-- Runtime conditions now live per-phase (phase.runtime) and are applied ephemerally
-- by the engine. The per-phase editor (stat -> Set X Color / Show Proc) arrives with
-- the Stage-B IA. This interim view summarizes the conditions already on each phase
-- read-only; existing conditions still run on the HUD.

local PAD = 12
local ROW_H = 26

local function actionText(c)
	if c.action == "showProc" then
		return "Show Proc"
	end
	local map = {
		setBackgroundColor = "Set Background Color",
		setBarColor = "Set Bar Color",
		setBorderColor = "Set Border Color",
		setStacksColor = "Set Stacks Color",
		setTextColor = "Set Text Color",
		setTimerColor = "Set Timer Color",
	}
	return map[c.action] or tostring(c.action)
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
	local y = PAD

	local header = get("hdr", function()
		return QAT.widgets.SectionHeader(container, "QAT_Cond_Hdr", "Runtime conditions (per phase)")
	end)
	header:ClearAnchors()
	header:SetAnchor(TOPLEFT, container, TOPLEFT, PAD, y)
	y = y + ROW_H

	local note = get("note", function()
		return QAT.widgets.Label(container, "QAT_Cond_Note", "")
	end)
	note:SetText("Conditions are per-phase and run on the HUD now; the editor arrives with the Stage-B Conditions tab.")
	note:ClearAnchors()
	note:SetAnchor(TOPLEFT, container, TOPLEFT, PAD, y + 3)
	y = y + ROW_H + 6

	for _, phase in ipairs(def.phases) do
		local ph = get("ph_" .. phase.id, function()
			return QAT.widgets.Label(container, "QAT_Cond_Ph_" .. phase.id, "", "$(BOLD_FONT)|18|soft-shadow-thin")
		end)
		ph:SetText(phase.id .. ":")
		ph:ClearAnchors()
		ph:SetAnchor(TOPLEFT, container, TOPLEFT, PAD, y + 3)
		y = y + ROW_H

		if #(phase.runtime or {}) == 0 then
			local row = get("c_none_" .. phase.id, function()
				return QAT.widgets.Label(container, "QAT_Cond_None_" .. phase.id, "")
			end)
			row:SetText("  (none)")
			row:ClearAnchors()
			row:SetAnchor(TOPLEFT, container, TOPLEFT, PAD + 12, y + 3)
			y = y + ROW_H
		else
			for i, c in ipairs(phase.runtime) do
				local row = get("c_" .. phase.id .. "_" .. i, function()
					return QAT.widgets.Label(container, "QAT_Cond_Row_" .. phase.id .. "_" .. i, "")
				end)
				row:SetText(
					"  IF "
						.. (c.stat or "remaining")
						.. " "
						.. (c.op or "<")
						.. " "
						.. tostring(c.value or 0)
						.. "  ->  "
						.. actionText(c)
				)
				row:ClearAnchors()
				row:SetAnchor(TOPLEFT, container, TOPLEFT, PAD + 12, y + 3)
				y = y + ROW_H
			end
		end
	end

	QAT.widgets.PoolEnd(pool)
end

QAT.editor.tabRenderers = QAT.editor.tabRenderers or {}
QAT.editor.tabRenderers["Conditions"] = render
