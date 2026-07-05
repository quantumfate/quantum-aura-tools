-- Grid layout pass: positions a grid-group's member trackers into table cells and
-- drives the drawn chrome (Display/Grid). Runs each render tick for every enabled
-- grid group. Cell sizes are frozen to the maximum footprint of ALL members assigned
-- to a column/row (present or not), so the table stays rigid and never pops as buffs
-- come and go. "Fill" collapses absent members and packs the rest toward one side of
-- the row/column to fake a growing bar.

-- Live grid groups discovered during a runtime build: each carries the folder def and
-- the load chain that gates the whole table.
QAT.runtime.grids = QAT.runtime.grids or {}

-- HUD header extents (the drawn label track around the cells).
local HHDR_ROW, HHDR_COL = 24, 90
local DEFAULT_W, DEFAULT_H = 150, 34

-- A member tracker's footprint on the HUD. Square-only trackers (icon/border/gradient
-- with no bar/text phase) are height-wide; anything with a bar/text phase uses the
-- authored box width.
local function footprint(kid)
	local pos = kid.pos or {}
	local w, h = pos.width or 220, pos.height or 30
	local squareOnly = true
	for _, p in ipairs(kid.phases or {}) do
		local d = p.look and p.look.display
		if d == "bar" or d == "text" then
			squareOnly = false
		end
	end
	return (squareOnly and h or w), h
end

local function memberDef(def, id)
	for _, c in ipairs(def.children or {}) do
		if c.id == id then
			return c
		end
	end
	return nil
end

-- Is a member currently drawing something (loaded and in a visible phase)? Absent
-- members (unloaded or idle) collapse under fill and leave their cell empty.
local function isPresent(id)
	local tracker = QAT.runtime.trackers[id]
	if not tracker or not tracker.loaded then
		return false
	end
	for _, phase in pairs(tracker.phases) do
		if phase.control and phase.control.tlw and not phase.control.tlw:IsHidden() then
			return true
		end
	end
	return false
end

-- Slightly darkened background for striped alternate rows.
local function striped(bg)
	return { bg[1] * 0.7, bg[2] * 0.7, bg[3] * 0.7, bg[4] or 1 }
end

-- Lay out one grid group: compute frozen column/row sizes, draw chrome, and reposition
-- (or leave hidden) each member. `entry` is { def, loadChain }.
local function layoutGroup(entry)
	local def = entry.def
	local g = def.grid
	local id = def.id
	if not g or not g.enabled then
		QAT.gridDisplay.Hide(id)
		return
	end
	-- Gate the whole table on the group's load conditions (cascaded to members anyway).
	if entry.loadChain and not QAT.conditions.EvaluateLoad(entry.loadChain) then
		QAT.gridDisplay.Hide(id)
		return
	end

	local s = g.style
	local gap = s.gap
	local origin = def.pos or { x = 400, y = 300 }
	local ox, oy = origin.x or 400, origin.y or 300

	-- Frozen sizes: column width = widest assigned member in the column; row height =
	-- tallest in the row. Empty columns/rows fall back to a default so the frame reads.
	local colW, rowH = {}, {}
	for c = 1, g.cols do
		colW[c] = DEFAULT_W
	end
	for r = 1, g.rows do
		rowH[r] = DEFAULT_H
	end
	for key, tid in pairs(g.cells) do
		local r, c = tostring(key):match("^r(%d+)c(%d+)$")
		r, c = tonumber(r), tonumber(c)
		local kid = memberDef(def, tid)
		if kid and r and c and r <= g.rows and c <= g.cols then
			local w, h = footprint(kid)
			if w > colW[c] then
				colW[c] = w
			end
			if h > rowH[r] then
				rowH[r] = h
			end
		end
	end

	-- Cumulative top-left of each column/row (body area, after the header tracks).
	local bodyLeft = ox + (g.rowHeaders and (HHDR_COL + gap) or 0)
	local bodyTop = oy + (g.colHeaders and (HHDR_ROW + gap) or 0)
	local colX, rowY = {}, {}
	local acc = bodyLeft
	for c = 1, g.cols do
		colX[c] = acc
		acc = acc + colW[c] + gap
	end
	acc = bodyTop
	for r = 1, g.rows do
		rowY[r] = acc
		acc = acc + rowH[r] + gap
	end

	QAT.gridDisplay.Begin(id)

	-- Header tracks.
	if g.colHeaders then
		for c = 1, g.cols do
			QAT.gridDisplay.Header(
				id,
				colX[c],
				oy,
				colW[c],
				HHDR_ROW,
				g.colLabels[c] or "",
				s.headerBg,
				s.border,
				s.borderWidth,
				s.headerText
			)
		end
	end
	if g.rowHeaders then
		for r = 1, g.rows do
			QAT.gridDisplay.Header(
				id,
				ox,
				rowY[r],
				HHDR_COL,
				rowH[r],
				g.rowLabels[r] or "",
				s.headerBg,
				s.border,
				s.borderWidth,
				s.headerText
			)
		end
	end

	-- Place a member centered in a cell rect and draw that cell's background.
	local function placeCell(r, c, tid, drawBg)
		if drawBg then
			local bg = (s.striped and (r % 2 == 0)) and striped(s.cellBg) or s.cellBg
			QAT.gridDisplay.Cell(id, colX[c], rowY[r], colW[c], rowH[r], bg, s.border, s.borderWidth)
		end
		if tid then
			local kid = memberDef(def, tid)
			if kid then
				local w, h = footprint(kid)
				local mx = colX[c] + math.floor((colW[c] - w) / 2)
				local my = rowY[r] + math.floor((rowH[r] - h) / 2)
				QAT.Runtime_RepositionTracker(tid, mx, my)
			end
		end
	end

	if not (g.fill and g.fill.enabled) then
		-- Static grid: every cell drawn; each present, assigned member sits in its cell.
		for r = 1, g.rows do
			for c = 1, g.cols do
				local tid = g.cells[("r%dc%d"):format(r, c)]
				local place = tid and isPresent(tid) and tid or nil
				placeCell(r, c, place, true)
			end
		end
	elseif g.fill.axis == "rows" then
		-- Pack each row's present members across its columns, growing from one side.
		for r = 1, g.rows do
			local present = {}
			for c = 1, g.cols do
				local tid = g.cells[("r%dc%d"):format(r, c)]
				if tid and isPresent(tid) then
					present[#present + 1] = tid
				end
			end
			for i, tid in ipairs(present) do
				local c = (g.fill.from == "left") and i or (g.cols - #present + i)
				placeCell(r, c, tid, true)
			end
		end
	else
		-- axis == "cols": pack each column's present members down (or up) its rows.
		for c = 1, g.cols do
			local present = {}
			for r = 1, g.rows do
				local tid = g.cells[("r%dc%d"):format(r, c)]
				if tid and isPresent(tid) then
					present[#present + 1] = tid
				end
			end
			for i, tid in ipairs(present) do
				local r = (g.fill.from == "left") and i or (g.rows - #present + i)
				placeCell(r, c, tid, true)
			end
		end
	end

	QAT.gridDisplay.End(id)
end

-- Reposition + redraw every live grid group. Called each render tick after trackers
-- have ticked (so member visibility is current).
function QAT.GridLayout_Update()
	for _, entry in ipairs(QAT.runtime.grids) do
		QAT.Safe("grid layout " .. tostring(entry.def.id), function()
			layoutGroup(entry)
		end)
	end
end

-- Forget all live grids and hide their chrome (called before a runtime rebuild).
function QAT.GridLayout_Reset()
	for _, entry in ipairs(QAT.runtime.grids) do
		QAT.gridDisplay.Hide(entry.def.id)
	end
	QAT.runtime.grids = {}
end

-- Register a grid group discovered during BuildTrackers.
function QAT.GridLayout_Register(def, loadChain)
	QAT.runtime.grids[#QAT.runtime.grids + 1] = { def = def, loadChain = loadChain }
end
