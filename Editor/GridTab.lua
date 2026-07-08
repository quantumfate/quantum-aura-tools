-- Grid tab: the table-layout builder for a group. Arranges the group's member
-- trackers into rows × columns, assigns which member sits in each cell, styles the
-- drawn chrome (headers, cell backgrounds, borders), and toggles fake-growth fill.
-- Rendered into the shared load scroll container when a grid-enabled group has its
-- "Grid layout" tree row selected (scope "grid").

local WM = GetWindowManager()

-- Resolve a member tracker's representative icon (first phase that carries one).
local function memberIcon(kid)
	for _, p in ipairs(kid.phases or {}) do
		local ic = QAT.util.PhaseIcon(p)
		if ic then
			return ic
		end
	end
	return "/esoui/art/icons/icon_missing.dds"
end

local function cellKey(r, c)
	return "r" .. r .. "c" .. c
end

-- The non-folder children of a group, in tree order (its placeable members).
local function members(def)
	local out = {}
	for _, c in ipairs(def.children or {}) do
		if c.kind ~= "folder" then
			out[#out + 1] = c
		end
	end
	return out
end

local function memberById(def, id)
	for _, c in ipairs(members(def)) do
		if c.id == id then
			return c
		end
	end
	return nil
end

-- If `defId` is a dynamic tracker (kind="dynamic"), return its source name, so the
-- Behavior tab can offer the "Emitter" trigger/duration. Also checks folder-based
-- dynamic groups for backward compat (a template child's id).
function QAT.Editor_DynamicSourceFor(defId)
	local function scan(defs)
		for _, d in ipairs(defs or {}) do
			if d.kind == "dynamic" and d.id == defId then
				return d.source
			end
			if d.kind == "folder" then
				if d.grid and d.grid.dynamic and d.grid.dynamic.source then
					for _, c in ipairs(d.children or {}) do
						if c.kind ~= "folder" and c.id == defId then
							return d.grid.dynamic.source
						end
					end
				end
				local nested = scan(d.children)
				if nested then
					return nested
				end
			end
		end
		return nil
	end
	return scan(QAT.sv.trackers)
end

-- ===== Mutations (canonicalize + notify after each, so tree/HUD/inspector follow) =====

-- Ensure a grid block exists (enabling the group's table mode). Idempotent.
function QAT.Editor_GridEnsure(def)
	def.grid = def.grid or { enabled = false, cols = 2, rows = 2 }
	QAT.CanonicalizeGrid(def)
	return def.grid
end

local function commit(def)
	QAT.CanonicalizeGrid(def)
	QAT.widgets.NotifyTrackerChanged(def.id)
end

-- Turn table mode on/off for a group. Off leaves the group a plain logical folder
-- (and its "Grid layout" tree row disappears).
function QAT.Editor_GridSetEnabled(def, on)
	QAT.Editor_GridEnsure(def)
	def.grid.enabled = on and true or false
	QAT.editor.gridPlacing = nil
	commit(def)
	if on then
		if QAT.Editor_SelectGrid then
			QAT.Editor_SelectGrid(def.id)
		end
	else
		if QAT.Editor_SelectLoad then
			QAT.Editor_SelectLoad(def.id)
		end
	end
end

-- Nudge column/row count. Shrinking orphans dropped-cell assignments back to the
-- Unplaced tray (CanonicalizeGrid prunes them).
function QAT.Editor_GridSetDim(def, key, delta)
	local g = QAT.Editor_GridEnsure(def)
	g[key] = math.max(1, (g[key] or 2) + delta)
	commit(def)
end

function QAT.Editor_GridToggle(def, key)
	local g = QAT.Editor_GridEnsure(def)
	g[key] = not g[key]
	commit(def)
end

function QAT.Editor_GridSetFill(def, key, value)
	local g = QAT.Editor_GridEnsure(def)
	g.fill = g.fill or {}
	g.fill[key] = value
	commit(def)
end

-- Horizontal placement of members within their cells (left / center / right).
function QAT.Editor_GridSetAlign(def, value)
	local g = QAT.Editor_GridEnsure(def)
	g.align = value
	commit(def)
end

function QAT.Editor_GridSetLabel(def, which, index, text)
	local g = QAT.Editor_GridEnsure(def)
	local arr = which == "col" and g.colLabels or g.rowLabels
	arr[index] = text
	commit(def)
end

function QAT.Editor_GridSetStyle(def, key, value)
	local g = QAT.Editor_GridEnsure(def)
	g.style = g.style or {}
	g.style[key] = value
	commit(def)
end

-- Place the pending member (or a given id) into a cell; clears any previous cell of
-- that member so a tracker only ever occupies one cell.
function QAT.Editor_GridAssign(def, key, trackerId)
	local g = QAT.Editor_GridEnsure(def)
	for k, tid in pairs(g.cells) do
		if tid == trackerId then
			g.cells[k] = nil
		end
	end
	g.cells[key] = trackerId
	QAT.editor.gridPlacing = nil
	commit(def)
end

function QAT.Editor_GridUnassign(def, key)
	local g = QAT.Editor_GridEnsure(def)
	g.cells[key] = nil
	commit(def)
end

-- ===== Renderer =====

-- Editor-preview cell metrics (fixed; the live HUD uses per-column/row frozen sizing).
local CELL_W, CELL_H, RHDR_W, CHDR_H, CGAP = 150, 42, 96, 28, 6

-- A labelled −/n/+ stepper. Returns the next x after the control.
local function stepper(container, get, key, caption, x, y, valueText, onDelta)
	local lab = get("stepL" .. key, function()
		return QAT.widgets.Label(container, "QAT_Grid_StepL" .. key, "")
	end)
	lab:SetText(caption)
	lab:SetColor(0.62, 0.68, 0.78, 1)
	lab:ClearAnchors()
	lab:SetAnchor(TOPLEFT, container, TOPLEFT, x, y + 4)
	x = x + math.ceil(lab:GetTextWidth()) + 8

	local minus = get("stepM" .. key, function()
		return QAT.widgets.TextButton(container, "QAT_Grid_StepM" .. key, "−", nil)
	end)
	minus:SetHeight(24)
	minus:SetMinWidth(26)
	minus:ClearAnchors()
	minus:SetAnchor(TOPLEFT, container, TOPLEFT, x, y)
	minus.onClick = function()
		onDelta(-1)
	end
	x = x + minus:GetWidth() + 4

	local val = get("stepV" .. key, function()
		return QAT.widgets.Label(container, "QAT_Grid_StepV" .. key, "")
	end)
	val:SetText(valueText)
	val:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
	val:ClearAnchors()
	val:SetDimensions(24, 24)
	val:SetAnchor(TOPLEFT, container, TOPLEFT, x, y + 4)
	x = x + 26

	local plus = get("stepP" .. key, function()
		return QAT.widgets.TextButton(container, "QAT_Grid_StepP" .. key, "+", nil)
	end)
	plus:SetHeight(24)
	plus:SetMinWidth(26)
	plus:ClearAnchors()
	plus:SetAnchor(TOPLEFT, container, TOPLEFT, x, y)
	plus.onClick = function()
		onDelta(1)
	end
	return x + plus:GetWidth() + 18
end

-- A toggle button that reads selected/unselected from a boolean.
local function toggleButton(container, get, key, text, x, y, on, onClick)
	local b = get("tg" .. key, function()
		return QAT.widgets.TextButton(container, "QAT_Grid_Tg" .. key, "", nil)
	end)
	b:SetText(text)
	b:SetHeight(26)
	b:SetSelected(on)
	b:ClearAnchors()
	b:SetAnchor(TOPLEFT, container, TOPLEFT, x, y)
	b.onClick = onClick
	return x + b:GetWidth() + 8
end

-- One "caption + swatch" style row entry. Returns the next x.
local function styleSwatch(container, get, key, caption, x, y, color, onChange)
	local lab = get("swL" .. key, function()
		return QAT.widgets.Label(container, "QAT_Grid_SwL" .. key, "", "$(MEDIUM_FONT)|13|soft-shadow-thin")
	end)
	lab:SetText(caption)
	lab:SetColor(0.6, 0.66, 0.76, 1)
	lab:ClearAnchors()
	lab:SetAnchor(TOPLEFT, container, TOPLEFT, x, y)

	local sw = get("sw" .. key, function()
		return QAT.widgets.ColorSwatch(container, "QAT_Grid_Sw" .. key, 22, nil, nil)
	end)
	sw:SetColor(color)
	sw:ClearAnchors()
	sw:SetAnchor(TOPLEFT, container, TOPLEFT, x, y + 18)
	sw.onChange = onChange
	return x + 130
end

--- Render the grid builder for a group def into the shared load container.
---@param container table the scroll child to lay out against
---@param def table folder def (grid enabled)
function QAT.Editor_RenderGridCard(container, def)
	local pool = container.pool or QAT.widgets.NewPool()
	container.pool = pool
	QAT.widgets.PoolBegin(pool)
	local function get(k, f)
		return QAT.widgets.PoolGet(pool, k, f)
	end

	local g = QAT.Editor_GridEnsure(def)
	local cw = container.qatViewportW or container:GetWidth()
	if cw < 240 then
		cw = 900
	end
	local OUT = 16
	local y = OUT

	-- Row 1: dimensions + header/fill toggles.
	local x = stepper(container, get, "cols", "Columns", OUT, y, tostring(g.cols), function(d)
		QAT.Editor_GridSetDim(def, "cols", d)
	end)
	x = stepper(container, get, "rows", "Rows", x, y, tostring(g.rows), function(d)
		QAT.Editor_GridSetDim(def, "rows", d)
	end)
	x = x + 8
	x = toggleButton(container, get, "colH", "Column headers", x, y, g.colHeaders, function()
		QAT.Editor_GridToggle(def, "colHeaders")
	end)
	x = toggleButton(container, get, "rowH", "Row headers", x, y, g.rowHeaders, function()
		QAT.Editor_GridToggle(def, "rowHeaders")
	end)
	x = toggleButton(container, get, "fill", "Fill empty cells", x, y, g.fill and g.fill.enabled, function()
		QAT.Editor_GridSetFill(def, "enabled", not (g.fill and g.fill.enabled))
	end)
	y = y + 34

	-- Screen position of the whole table (its top-left origin; the grid moves as a unit).
	local pos = def.pos or { x = 400, y = 300 }
	local posLbl = get("posLbl", function()
		return QAT.widgets.Label(container, "QAT_Grid_PosLbl", "")
	end)
	posLbl:SetText("Screen position")
	posLbl:SetColor(0.62, 0.68, 0.78, 1)
	posLbl:ClearAnchors()
	posLbl:SetAnchor(TOPLEFT, container, TOPLEFT, OUT, y + 4)
	local px = OUT + math.ceil(posLbl:GetTextWidth()) + 12
	local function posBox(key, field, caption)
		local cap = get("posC" .. key, function()
			return QAT.widgets.Label(container, "QAT_Grid_PosC" .. key, "")
		end)
		cap:SetText(caption)
		cap:SetColor(0.5, 0.56, 0.66, 1)
		cap:ClearAnchors()
		cap:SetAnchor(TOPLEFT, container, TOPLEFT, px, y + 4)
		px = px + 14
		local box = get("posB" .. key, function()
			return QAT.widgets.EditBox(container, "QAT_Grid_PosB" .. key, 56, 24, "", nil)
		end)
		box:SetText(tostring(pos[field] or 0))
		box:ClearAnchors()
		box:SetAnchor(TOPLEFT, container, TOPLEFT, px, y)
		box.onChange = function(t)
			local n = tonumber(t)
			if n then
				def.pos = def.pos or {}
				def.pos[field] = math.floor(n)
				QAT.widgets.NotifyTrackerChanged(def.id)
			end
		end
		px = px + 64
	end
	posBox("x", "x", "X")
	posBox("y", "y", "Y")
	y = y + 34

	-- Fill sub-options (packing axis + growth side) — only meaningful while fill is on.
	if g.fill and g.fill.enabled then
		local fx = OUT
		fx = toggleButton(container, get, "faxR", "Rows", fx, y, g.fill.axis == "rows", function()
			QAT.Editor_GridSetFill(def, "axis", "rows")
		end)
		fx = toggleButton(container, get, "faxC", "Columns", fx, y, g.fill.axis == "cols", function()
			QAT.Editor_GridSetFill(def, "axis", "cols")
		end)
		fx = fx + 12
		fx = toggleButton(container, get, "fromL", "From left", fx, y, g.fill.from == "left", function()
			QAT.Editor_GridSetFill(def, "from", "left")
		end)
		fx = toggleButton(container, get, "fromR", "From right", fx, y, g.fill.from == "right", function()
			QAT.Editor_GridSetFill(def, "from", "right")
		end)
		y = y + 34
	end

	-- Cell alignment: where each member sits horizontally within its cell (vertical is
	-- always centered). Replaces per-member screen positioning inside a table.
	local alignLbl = get("alignLbl", function()
		return QAT.widgets.Label(container, "QAT_Grid_AlignLbl", "")
	end)
	alignLbl:SetText("Align in cell")
	alignLbl:SetColor(0.62, 0.68, 0.78, 1)
	alignLbl:ClearAnchors()
	alignLbl:SetAnchor(TOPLEFT, container, TOPLEFT, OUT, y + 4)
	local axx = OUT + math.ceil(alignLbl:GetTextWidth()) + 12
	for _, opt in ipairs({ { "left", "Left" }, { "center", "Center" }, { "right", "Right" } }) do
		axx = toggleButton(
			container,
			get,
			"align" .. opt[1],
			opt[2],
			axx,
			y,
			(g.align or "center") == opt[1],
			function()
				QAT.Editor_GridSetAlign(def, opt[1])
			end
		)
	end
	y = y + 34

	-- TABLE STYLE card.
	local s = g.style
	local styleCard = get("styleCard", function()
		return QAT.widgets.Card(container, "QAT_Grid_StyleCard", "Table style")
	end)
	styleCard:SetTitle("Table style")
	styleCard:ClearAnchors()
	styleCard:SetAnchor(TOPLEFT, container, TOPLEFT, OUT, y)
	local sPad = OUT + styleCard.padX
	local sy = y + styleCard.contentY
	local swx = sPad
	swx = styleSwatch(container, get, "hbg", "Header background", swx, sy, s.headerBg, function(c)
		QAT.Editor_GridSetStyle(def, "headerBg", c)
	end)
	swx = styleSwatch(container, get, "htx", "Header text", swx, sy, s.headerText, function(c)
		QAT.Editor_GridSetStyle(def, "headerText", c)
	end)
	swx = styleSwatch(container, get, "cbg", "Cell background", swx, sy, s.cellBg, function(c)
		QAT.Editor_GridSetStyle(def, "cellBg", c)
	end)
	swx = styleSwatch(container, get, "ctx", "Cell text", swx, sy, s.cellText, function(c)
		QAT.Editor_GridSetStyle(def, "cellText", c)
	end)
	swx = styleSwatch(container, get, "bdr", "Border colour", swx, sy, s.border, function(c)
		QAT.Editor_GridSetStyle(def, "border", c)
	end)
	sy = sy + 52

	-- Numeric style steppers + striped toggle, on a second row inside the card.
	local nx = sPad
	nx = stepper(container, get, "bw", "Border width", nx, sy, tostring(s.borderWidth), function(d)
		QAT.Editor_GridSetStyle(def, "borderWidth", math.max(0, s.borderWidth + d))
	end)
	nx = stepper(container, get, "cr", "Corner radius", nx, sy, tostring(s.corner), function(d)
		QAT.Editor_GridSetStyle(def, "corner", math.max(0, s.corner + d))
	end)
	nx = stepper(container, get, "cgap", "Cell gap", nx, sy, tostring(s.gap), function(d)
		QAT.Editor_GridSetStyle(def, "gap", math.max(0, s.gap + d))
	end)
	nx = nx + 8
	toggleButton(container, get, "strp", "Striped rows", nx, sy, s.striped, function()
		QAT.Editor_GridSetStyle(def, "striped", not s.striped)
	end)
	sy = sy + 34
	styleCard:SetDimensions(cw - OUT * 2, (sy - y) + 8)
	y = sy + 18

	-- Authored-cell assignment UI (legacy dynamic groups skip this).
	if not g.dynamic then
		-- Place-mode banner: while placing a member, cells become drop targets.
		local placingId = QAT.editor.gridPlacing
		local placing = placingId and memberById(def, placingId)
		if placing then
			local banner = get("banner", function()
				return QAT.widgets.Panel(container, "QAT_Grid_Banner", { 0.10, 0.14, 0.20, 1 }, { 0.24, 0.34, 0.48, 1 })
			end)
			banner:SetHidden(false)
			banner:ClearAnchors()
			banner:SetAnchor(TOPLEFT, container, TOPLEFT, OUT, y)
			banner:SetDimensions(cw - OUT * 2, 30)
			local bl = get("bannerL", function()
				return QAT.widgets.Label(container, "QAT_Grid_BannerL", "")
			end)
			bl:SetText("Placing " .. (placing.name or placing.id) .. " — click an empty cell")
			bl:SetColor(0.82, 0.88, 0.96, 1)
			bl:ClearAnchors()
			bl:SetAnchor(LEFT, banner, LEFT, 12, 0)
			local cancel = get("bannerX", function()
				return QAT.widgets.TextButton(container, "QAT_Grid_BannerX", "cancel", nil)
			end)
			cancel:SetHeight(22)
			cancel:ClearAnchors()
			cancel:SetAnchor(RIGHT, banner, RIGHT, -8, 0)
			cancel.onClick = function()
				QAT.editor.gridPlacing = nil
				QAT.Editor_Inspector_Refresh()
			end
			y = y + 38
		end

		-- ===== Assignment table =====
		-- Column header cells (skip the top-left corner spacer when both header kinds show).
		local gridLeft = OUT + (g.rowHeaders and (RHDR_W + CGAP) or 0)
		if g.colHeaders then
			for c = 1, g.cols do
				local hx = gridLeft + (c - 1) * (CELL_W + CGAP)
				local hc = get("chdr" .. c, function()
					return QAT.widgets.Panel(container, "QAT_Grid_CHdr" .. c, s.headerBg, s.border)
				end)
				hc:SetCenterColor(unpack(s.headerBg))
				hc:SetEdgeColor(unpack(s.border))
				hc:SetHidden(false)
				hc:SetDimensions(CELL_W, CHDR_H)
				hc:ClearAnchors()
				hc:SetAnchor(TOPLEFT, container, TOPLEFT, hx, y)
				local eb = get("chdrE" .. c, function()
					return QAT.widgets.EditBox(container, "QAT_Grid_CHdrE" .. c, CELL_W - 8, 22, "", nil)
				end)
				eb:SetHidden(false)
				eb:SetText(g.colLabels[c] or "")
				eb:ClearAnchors()
				eb:SetAnchor(CENTER, hc, CENTER, 0, 0)
				eb.onChange = function(t)
					QAT.Editor_GridSetLabel(def, "col", c, t)
				end
			end
			y = y + CHDR_H + CGAP
		end

		-- Body rows (with optional row-header cell on the left).
		for r = 1, g.rows do
			local ry = y + (r - 1) * (CELL_H + CGAP)
			if g.rowHeaders then
				local rh = get("rhdr" .. r, function()
					return QAT.widgets.Panel(container, "QAT_Grid_RHdr" .. r, s.headerBg, s.border)
				end)
				rh:SetCenterColor(unpack(s.headerBg))
				rh:SetEdgeColor(unpack(s.border))
				rh:SetHidden(false)
				rh:SetDimensions(RHDR_W, CELL_H)
				rh:ClearAnchors()
				rh:SetAnchor(TOPLEFT, container, TOPLEFT, OUT, ry)
				local eb = get("rhdrE" .. r, function()
					return QAT.widgets.EditBox(container, "QAT_Grid_RHdrE" .. r, RHDR_W - 8, 22, "", nil)
				end)
				eb:SetHidden(false)
				eb:SetText(g.rowLabels[r] or "")
				eb:ClearAnchors()
				eb:SetAnchor(CENTER, rh, CENTER, 0, 0)
				eb.onChange = function(t)
					QAT.Editor_GridSetLabel(def, "row", r, t)
				end
			end

			for c = 1, g.cols do
				local key = cellKey(r, c)
				local cx = gridLeft + (c - 1) * (CELL_W + CGAP)
				local tid = g.cells[key]
				local kid = tid and memberById(def, tid)
				local cell = get("cell" .. key, function()
					return QAT.widgets.Clickable(container, "QAT_Grid_Cell" .. key, s.cellBg)
				end)
				cell:SetHidden(false)
				cell.bg:SetCenterColor(unpack(kid and s.cellBg or { 0.05, 0.06, 0.08, 0.5 }))
				cell.bg:SetEdgeColor(unpack(kid and s.border or { 0.14, 0.18, 0.24, 1 }))
				cell.bg:SetEdgeTexture("", 1, 1, 1)
				cell:SetDimensions(CELL_W, CELL_H)
				cell:ClearAnchors()
				cell:SetAnchor(TOPLEFT, container, TOPLEFT, cx, ry)
				cell.onClickCell = function()
					if QAT.editor.gridPlacing then
						QAT.Editor_GridAssign(def, key, QAT.editor.gridPlacing)
					end
				end
				cell:SetHandler("OnMouseUp", function(self, button, upInside)
					if upInside and button == MOUSE_BUTTON_INDEX_LEFT and self.onClickCell then
						self.onClickCell()
					end
				end)

				local cIcon = get("cellIc" .. key, function()
					local t = WM:CreateControl("QAT_Grid_CellIc" .. key, container, CT_TEXTURE)
					t:SetDimensions(20, 20)
					return t
				end)
				local cLbl = get("cellLb" .. key, function()
					return QAT.widgets.Label(container, "QAT_Grid_CellLb" .. key, "")
				end)
				local cDel = get("cellX" .. key, function()
					return QAT.widgets.TextButton(container, "QAT_Grid_CellX" .. key, "×", nil)
				end)
				if kid then
					cIcon:SetHidden(false)
					cIcon:SetTexture(memberIcon(kid))
					cIcon:ClearAnchors()
					cIcon:SetAnchor(LEFT, cell, LEFT, 8, 0)
					cLbl:SetHidden(false)
					cLbl:SetText(kid.name or kid.id)
					cLbl:SetColor(unpack(s.cellText))
					cLbl:ClearAnchors()
					cLbl:SetAnchor(LEFT, cIcon, RIGHT, 8, 0)
					cLbl:SetAnchor(RIGHT, cell, RIGHT, -26, 0)
					cLbl:SetMaxLineCount(1)
					cDel:SetHidden(false)
					cDel:SetHeight(22)
					cDel:ClearAnchors()
					cDel:SetAnchor(RIGHT, cell, RIGHT, -4, 0)
					cDel.onClick = function()
						QAT.Editor_GridUnassign(def, key)
					end
				else
					cIcon:SetHidden(true)
					cDel:SetHidden(true)
					cLbl:SetHidden(false)
					cLbl:SetText(placing and "click to place" or "+ assign")
					cLbl:SetColor(0.45, 0.52, 0.62, 1)
					cLbl:ClearAnchors()
					cLbl:SetAnchor(CENTER, cell, CENTER, 0, 0)
					cLbl:SetMaxLineCount(1)
				end
			end
		end
		y = y + g.rows * (CELL_H + CGAP) + 12

		-- ===== Unplaced tray =====
		local unplaced = {}
		do
			local inCell = {}
			for _, tid in pairs(g.cells) do
				inCell[tid] = true
			end
			for _, kid in ipairs(members(def)) do
				if not inCell[kid.id] then
					unplaced[#unplaced + 1] = kid
				end
			end
		end
		local uHead = get("uHead", function()
			return QAT.widgets.Label(container, "QAT_Grid_UHead", "", "$(BOLD_FONT)|13|soft-shadow-thin")
		end)
		uHead:SetText("UNPLACED TRACKERS")
		uHead:SetColor(0.5, 0.57, 0.68, 1)
		uHead:ClearAnchors()
		uHead:SetAnchor(TOPLEFT, container, TOPLEFT, OUT, y)
		y = y + 22

		if #unplaced == 0 then
			local none = get("uNone", function()
				return QAT.widgets.Label(container, "QAT_Grid_UNone", "")
			end)
			none:SetHidden(false)
			none:SetText("All members placed.")
			none:SetColor(0.45, 0.52, 0.62, 1)
			none:ClearAnchors()
			none:SetAnchor(TOPLEFT, container, TOPLEFT, OUT, y)
			y = y + 28
		else
			local ux, uy = OUT, y
			for i, kid in ipairs(unplaced) do
				local chip = get("uChip" .. i, function()
					return QAT.widgets.Clickable(container, "QAT_Grid_UChip" .. i, { 0.10, 0.13, 0.18, 1 })
				end)
				chip:SetHidden(false)
				local selected = QAT.editor.gridPlacing == kid.id
				chip.bg:SetCenterColor(unpack(selected and { 0.14, 0.20, 0.30, 1 } or { 0.10, 0.13, 0.18, 1 }))
				chip.bg:SetEdgeColor(unpack(selected and { 0.30, 0.44, 0.62, 1 } or { 0.16, 0.22, 0.30, 1 }))
				chip.bg:SetEdgeTexture("", 1, 1, 1)
				chip:SetDimensions(150, 30)
				if ux + 150 > cw - OUT then
					ux = OUT
					uy = uy + 36
				end
				chip:ClearAnchors()
				chip:SetAnchor(TOPLEFT, container, TOPLEFT, ux, uy)
				chip.placeId = kid.id
				chip:SetHandler("OnMouseUp", function(self, button, upInside)
					if upInside and button == MOUSE_BUTTON_INDEX_LEFT then
						QAT.editor.gridPlacing = (QAT.editor.gridPlacing == self.placeId) and nil or self.placeId
						QAT.Editor_Inspector_Refresh()
					end
				end)
				local ci = get("uChipIc" .. i, function()
					local t = WM:CreateControl("QAT_Grid_UChipIc" .. i, container, CT_TEXTURE)
					t:SetDimensions(18, 18)
					return t
				end)
				ci:SetHidden(false)
				ci:SetTexture(memberIcon(kid))
				ci:ClearAnchors()
				ci:SetAnchor(LEFT, chip, LEFT, 8, 0)
				local cl = get("uChipL" .. i, function()
					return QAT.widgets.Label(container, "QAT_Grid_UChipL" .. i, "")
				end)
				cl:SetHidden(false)
				cl:SetText(kid.name or kid.id)
				cl:SetColor(0.88, 0.91, 0.95, 1)
				cl:ClearAnchors()
				cl:SetAnchor(LEFT, ci, RIGHT, 8, 0)
				cl:SetAnchor(RIGHT, chip, RIGHT, -6, 0)
				cl:SetMaxLineCount(1)
				ux = ux + 150 + 8
			end
			y = uy + 36 + 6
		end
	end -- end non-dynamic assignment UI

	-- Bottom padding so the scroll child fits everything.
	local spacer = get("spacer", function()
		return WM:CreateControl("QAT_Grid_Spacer", container, CT_CONTROL)
	end)
	spacer:SetDimensions(1, 1)
	spacer:ClearAnchors()
	spacer:SetAnchor(TOPLEFT, container, TOPLEFT, OUT, y + 8)

	QAT.widgets.PoolEnd(pool)

	-- First-open fixup: the horizontal layout chains on label/button text widths, which
	-- ESO reports as 0 on the frame a control is created — collapsing the top rows into
	-- an overlap. Re-lay once on the next frame, when the widths have measured. One-shot
	-- per container: on later opens the controls are pooled and already sized.
	if not container.qatGridMeasured then
		container.qatGridMeasured = true
		zo_callLater(function()
			if
				not container:IsHidden()
				and QAT.editor
				and QAT.editor.selectedScope == "grid"
				and QAT.editor.selectedId == def.id
			then
				QAT.Editor_RenderGridCard(container, def)
			end
		end, 0)
	end
end
