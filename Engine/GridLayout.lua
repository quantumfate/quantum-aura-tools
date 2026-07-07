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

-- Dynamic groups own a pool of full template-tracker INSTANCES (one per cell), each a
-- clone of the group's template, driven per-target by a Targeting source instead of the
-- global event bus. Kept module-level so instance controls persist (reused by name)
-- across runtime rebuilds.
local dynSlots = {} -- groupId -> { instances = { Tracker, ... }, slotW, slotH, ability }

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
	-- Absolute screen origin: the parent anchor (nested groups) plus this group's pos.
	local anchor = entry.anchor or { x = 0, y = 0 }
	local ox, oy = (anchor.x or 0) + (origin.x or 400), (anchor.y or 0) + (origin.y or 300)

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
				-- Horizontal placement within the cell follows the grid's align setting;
				-- vertical is always centered.
				local slackX = colW[c] - w
				local ox2 = (g.align == "left") and 0 or (g.align == "right") and slackX or math.floor(slackX / 2)
				local mx = colX[c] + ox2
				local my = rowY[r] + math.floor((rowH[r] - h) / 2)
				QAT.Runtime_PlaceTrackerAbsolute(tid, mx, my)
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

-- The group's single non-folder child is its template tracker (authored like any
-- tracker); nil = use a synthesized default.
local function templateChild(def)
	for _, c in ipairs(def.children or {}) do
		if c.kind ~= "folder" then
			return c
		end
	end
	return nil
end

-- Default template when a dynamic group has no authored one: hidden idle plus a bar
-- shown while the source effect is live (name + remaining). Reproduces the pre-template
-- behaviour so an empty dynamic group still renders.
local function defaultTemplate(slotW, slotH)
	return {
		kind = "tracker",
		unit = QAT.DYN_UNIT,
		phases = {
			{
				id = "idle",
				look = { display = "none" },
				duration = { type = "none" },
				transitions = { { when = { kind = "source", result = "gained" }, to = "active" } },
			},
			{
				id = "active",
				look = { display = "bar", showTime = true },
				duration = { type = "source" },
				transitions = {},
			},
		},
		initial = "idle",
		pos = { width = slotW, height = slotH },
	}
end

-- Clone the template into one pooled instance def, resolving its explicit `source`
-- subscriptions (a `source` duration or transition trigger) into a concrete effect on
-- the reserved dynamic unit + ability — so the source can drive the phase machine
-- directly (a real EVENT_EFFECT_CHANGED never fires for these). Everything else
-- (appearance, real-effect phases the author wrote, transitions) is left untouched.
local function instanceDef(template, groupId, i, srcAbilityId, slotW, slotH)
	local def = QAT.util.DeepCopy(template)
	def.id = groupId .. "_slot" .. i
	def.kind = "tracker"
	def.enabled = true
	def.load = nil -- the group's load chain gates the whole grid, not each instance
	def.pos = {
		x = 0,
		y = 0,
		width = (template.pos and template.pos.width) or slotW,
		height = (template.pos and template.pos.height) or slotH,
	}
	for _, p in ipairs(def.phases or {}) do
		if p.duration and p.duration.type == "source" then
			p.duration = { type = "effect", abilityIds = { srcAbilityId }, unit = QAT.DYN_UNIT }
		end
		for _, tr in ipairs(p.transitions or {}) do
			if tr.when and tr.when.kind == "source" then
				tr.when = {
					kind = "effect",
					result = tr.when.result or "gained",
					abilityIds = { srcAbilityId },
					unit = QAT.DYN_UNIT,
				}
			end
		end
	end
	QAT.CanonicalizeDef(def)
	return def
end

-- (Re)build a dynamic group's instance pool: rows*cols full template-tracker instances,
-- each a clone of the template with a stable per-slot id (so Display controls are reused
-- by name across rebuilds). Instances are driven by the source, not the global event bus.
local function buildPool(def, anchor)
	local g = def.grid
	local cap = g.rows * g.cols
	local srcAbilityId = QAT.Targeting.PrimaryAbilityId(g.dynamic.source)
	local slotW, slotH = g.dynamic.slot.width, g.dynamic.slot.height
	local template = templateChild(def) or defaultTemplate(slotW, slotH)
	local fw = (template.pos and template.pos.width) or slotW
	local fh = (template.pos and template.pos.height) or slotH

	local pool = { instances = {}, slotW = fw, slotH = fh, ability = srcAbilityId }
	dynSlots[def.id] = pool
	for i = 1, cap do
		local idef = instanceDef(template, def.id, i, srcAbilityId, slotW, slotH)
		local inst = QAT.Tracker.New(idef, {}, anchor or { x = 0, y = 0 })
		inst.dynAbilityId = srcAbilityId
		inst.loaded = true
		inst:ResetDynamic() -- start every lane in its hidden initial phase
		pool.instances[i] = inst
	end
	return pool
end
QAT.GridLayout_BuildDynamicPool = buildPool

-- Hide every instance control of every dynamic pool (rebuild / disable).
local function hideAllSlots()
	for _, pool in pairs(dynSlots) do
		for _, inst in ipairs(pool.instances or {}) do
			for _, phase in pairs(inst.phases) do
				phase.control:SetState(false)
			end
		end
	end
end

-- Is an instance drawing anything right now (any phase control visible)?
local function instPresent(inst)
	for _, phase in pairs(inst.phases) do
		if phase.control.tlw and not phase.control.tlw:IsHidden() then
			return true
		end
	end
	return false
end

-- Lay out one dynamic group: bind the source's live targets to pooled template
-- instances (stable per key so a re-sorted snapshot doesn't churn the machines), tick
-- each machine, then pack the visible ones into cells sorted soonest-expiry-first — so
-- the table grows and shrinks with the live set. `entry` is { def, loadChain, anchor }.
local function layoutDynamic(entry)
	local def = entry.def
	local g = def.grid
	local id = def.id
	local pool = dynSlots[id]
	if not (g and g.enabled and g.dynamic and pool) then
		QAT.gridDisplay.Hide(id)
		return
	end
	local now = GetFrameTimeSeconds()
	if entry.loadChain and not QAT.conditions.EvaluateLoad(entry.loadChain) then
		QAT.gridDisplay.Hide(id)
		for _, inst in ipairs(pool.instances) do
			for _, phase in pairs(inst.phases) do
				phase.control:SetState(false)
			end
		end
		return
	end

	local snap = QAT.Targeting.Snapshot(g.dynamic.source, now)
	local cap = g.rows * g.cols
	local insts = pool.instances

	-- Release instances whose bound target left the set (lets the fade phase play out).
	local current = {}
	for _, b in ipairs(snap) do
		current[b.key] = b
	end
	for i = 1, cap do
		local inst = insts[i]
		if inst.boundKey and not current[inst.boundKey] then
			inst:FeedDynamic(false)
			inst.boundKey, inst.boundEnd = nil, nil
		end
	end
	-- Assign each live target to an instance (refresh if already bound, else a free slot).
	for _, b in ipairs(snap) do
		local bound
		for i = 1, cap do
			if insts[i].boundKey == b.key then
				bound = insts[i]
				break
			end
		end
		if bound then
			if bound.boundEnd ~= b.endTime then
				bound:FeedDynamic(true, b.beginTime, b.endTime, b.stacks) -- re-applied (e.g. re-taunt)
				bound.boundEnd = b.endTime
			end
		else
			for i = 1, cap do
				local inst = insts[i]
				if not inst.boundKey then
					inst:ResetDynamic()
					inst:SetDisplayName(b.name)
					inst:FeedDynamic(true, b.beginTime, b.endTime, b.stacks)
					inst.boundKey, inst.boundEnd = b.key, b.endTime
					break
				end
			end
		end
	end
	-- Advance every machine (bound counts down; released ones finish their fade).
	for i = 1, #insts do
		insts[i]:Tick(now)
	end

	-- Pack the visible instances, soonest-expiry-first.
	local s = g.style
	local gap = s.gap
	local slotW, slotH = pool.slotW, pool.slotH
	local origin = def.pos or { x = 400, y = 300 }
	local anchor = entry.anchor or { x = 0, y = 0 }
	local ox, oy = (anchor.x or 0) + (origin.x or 400), (anchor.y or 0) + (origin.y or 300)
	local byCols = g.fill and g.fill.axis == "cols"

	local present = {}
	for i = 1, cap do
		if instPresent(insts[i]) then
			present[#present + 1] = insts[i]
		end
	end
	table.sort(present, function(a, b)
		return (a.boundEnd or math.huge) < (b.boundEnd or math.huge)
	end)

	-- No cell chrome: the template instance owns its own background/border, so a dynamic
	-- group draws only the instances (Begin/End still clears any stale pooled chrome).
	QAT.gridDisplay.Begin(id)
	for idx, inst in ipairs(present) do
		local n = idx - 1
		local r, c
		if byCols then
			r, c = (n % g.rows) + 1, math.floor(n / g.rows) + 1
		else
			r, c = math.floor(n / g.cols) + 1, (n % g.cols) + 1
		end
		local x = ox + (c - 1) * (slotW + gap)
		local y = oy + (r - 1) * (slotH + gap)
		inst:PlaceAbsolute(x, y)
	end
	QAT.gridDisplay.End(id)
end

-- Reposition + redraw every live grid group. Called each render tick after trackers
-- have ticked (so member visibility is current).
function QAT.GridLayout_Update()
	for _, entry in ipairs(QAT.runtime.grids) do
		QAT.Safe("grid layout " .. tostring(entry.def.id), function()
			if entry.def.grid and entry.def.grid.dynamic then
				layoutDynamic(entry)
			else
				layoutGroup(entry)
			end
		end)
	end
end

-- Forget all live grids and hide their chrome (called before a runtime rebuild).
function QAT.GridLayout_Reset()
	for _, entry in ipairs(QAT.runtime.grids) do
		QAT.gridDisplay.Hide(entry.def.id)
	end
	hideAllSlots() -- dynamic-grid slot controls (persist by name; just hide them)
	QAT.runtime.grids = {}
end

-- Register a grid group discovered during BuildTrackers. `anchor` is the parent's
-- absolute screen anchor (the group's own pos is added on top in layoutGroup). A dynamic
-- group also builds its template-instance pool here.
function QAT.GridLayout_Register(def, loadChain, anchor)
	QAT.runtime.grids[#QAT.runtime.grids + 1] = { def = def, loadChain = loadChain, anchor = anchor }
	if def.grid and def.grid.dynamic and def.grid.dynamic.source then
		QAT.Safe("build dynamic pool " .. tostring(def.id), function()
			buildPool(def, anchor)
		end)
	end
end
