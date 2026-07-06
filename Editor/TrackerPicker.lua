-- A lightweight modal picker for choosing an existing tracker. Used by the aggregator's
-- "add to an existing tracker's layer" action. Lazily built once, re-populated on show;
-- folders render as dim headers, trackers as clickable rows. Picking hides the popup and
-- fires the caller's callback with the chosen def.

local WM = GetWindowManager()
local W = QAT.widgets

local ROW_H = 26
local PANEL_W, PANEL_H = 380, 460

local picker -- lazily created top-level window + parts
local rows = {} -- pooled list rows, reused across shows

-- Depth-first walk of the tracker tree, calling visit(def, depth) for every node.
local function walk(defs, depth, visit)
	for _, def in ipairs(defs or {}) do
		visit(def, depth)
		if def.kind == "folder" then
			walk(def.children, depth + 1, visit)
		end
	end
end

local function ensurePicker()
	if picker then
		return picker
	end
	-- Full-screen dimmer/catcher above the editor; a click outside the panel closes it.
	local tlw = WM:CreateTopLevelWindow("QAT_TrackerPicker")
	tlw:SetAnchorFill(GuiRoot)
	tlw:SetDrawTier(DT_HIGH)
	tlw:SetHidden(true)
	tlw:SetMouseEnabled(true)
	local dim = W.Clickable(tlw, "QAT_TrackerPicker_Dim", { 0, 0, 0, 0.55 })
	dim:SetAnchorFill()
	dim:SetHandler("OnMouseUp", function(_, button, upInside)
		if upInside and button == MOUSE_BUTTON_INDEX_LEFT then
			tlw:SetHidden(true)
		end
	end)

	local panel = W.Panel(tlw, "QAT_TrackerPicker_Panel", { 0.10, 0.11, 0.14, 1 }, { 0.30, 0.40, 0.58, 1 })
	panel:SetDimensions(PANEL_W, PANEL_H)
	panel:SetAnchor(CENTER, GuiRoot, CENTER, 0, 0)
	panel:SetMouseEnabled(true) -- swallow clicks so they don't hit the dimmer

	local title = W.Label(panel, "QAT_TrackerPicker_Title", "Add to which tracker?", "$(BOLD_FONT)|20|soft-shadow-thin")
	title:SetAnchor(TOPLEFT, panel, TOPLEFT, 14, 12)

	local close = W.CloseButton(panel, "QAT_TrackerPicker_Close", function()
		tlw:SetHidden(true)
	end)
	close:SetDimensions(24, 24)
	close:SetAnchor(TOPRIGHT, panel, TOPRIGHT, -8, 8)

	local sc = WM:CreateControlFromVirtual("QAT_TrackerPicker_Scroll", panel, "ZO_ScrollContainer")
	sc:SetAnchor(TOPLEFT, panel, TOPLEFT, 10, 46)
	sc:SetAnchor(BOTTOMRIGHT, panel, BOTTOMRIGHT, -10, -12)
	local content = GetControl(sc, "ScrollChild")
	content:SetResizeToFitDescendents(true)

	picker = { tlw = tlw, title = title, content = content, onPick = nil }
	return picker
end

-- Populate the list from the current tracker tree.
local function populate()
	local p = picker
	local content = p.content
	local y, i = 0, 0
	walk(QAT.sv.trackers, 0, function(def, depth)
		i = i + 1
		local row = rows[i]
		if not row then
			row = W.Clickable(content, "QAT_TrackerPicker_Row" .. i, { 0, 0, 0, 0 })
			row.icon = WM:CreateControl("QAT_TrackerPicker_Row" .. i .. "_I", row, CT_TEXTURE)
			row.icon:SetDimensions(18, 18)
			row.label = W.Label(row, "QAT_TrackerPicker_Row" .. i .. "_L", "")
			row:SetHandler("OnMouseEnter", function(self2)
				self2.bg:SetCenterColor(0.20, 0.24, 0.30, 1)
			end)
			row:SetHandler("OnMouseExit", function(self2)
				self2.bg:SetCenterColor(0, 0, 0, 0)
			end)
			rows[i] = row
		end
		row:SetHidden(false)
		row:SetDimensions(PANEL_W - 24, ROW_H)
		row:ClearAnchors()
		row:SetAnchor(TOPLEFT, content, TOPLEFT, 0, y)
		local indent = 8 + depth * 16
		local isFolder = def.kind == "folder"

		row.icon:ClearAnchors()
		row.label:ClearAnchors()
		if isFolder then
			row.icon:SetHidden(true)
			row.label:SetText(def.name or def.id)
			row.label:SetColor(0.6, 0.66, 0.76, 1)
			row.label:SetAnchor(LEFT, row, LEFT, indent, 0)
			row:SetMouseEnabled(false) -- headers aren't pickable
			row.bg:SetCenterColor(0, 0, 0, 0)
		else
			row.icon:SetHidden(false)
			row.icon:SetTexture(QAT.util.PhaseIcon(def.phases and def.phases[1]) or "/esoui/art/icons/icon_missing.dds")
			row.icon:SetAnchor(LEFT, row, LEFT, indent, 0)
			row.label:SetText(def.name or def.id)
			row.label:SetColor(0.9, 0.92, 0.95, 1)
			row.label:SetAnchor(LEFT, row.icon, RIGHT, 8, 0)
			row:SetMouseEnabled(true)
			row:SetHandler("OnMouseUp", function(_, button, upInside)
				if upInside and button == MOUSE_BUTTON_INDEX_LEFT then
					local cb, target = p.onPick, def
					p.tlw:SetHidden(true)
					if cb then
						cb(target)
					end
				end
			end)
		end
		y = y + ROW_H
	end)
	for j = i + 1, #rows do
		rows[j]:SetHidden(true)
	end
	content:SetHeight(math.max(1, y))
end

-- Show the picker; `onPick(def)` fires with the chosen tracker (folders excluded).
function QAT.ShowTrackerPicker(title, onPick)
	local p = ensurePicker()
	p.onPick = onPick
	p.title:SetText(title or "Add to which tracker?")
	populate()
	p.tlw:SetHidden(false)
end
