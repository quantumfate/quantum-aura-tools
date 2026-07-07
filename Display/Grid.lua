-- Group grid chrome: the drawn table frame (header cells, cell backgrounds and
-- borders) that sits behind a grid-group's member trackers on the HUD. One full-
-- screen top-level window per group holds pooled backdrops/labels, positioned in
-- screen space by the layout pass (Engine/GridLayout). Members are separate top-level
-- windows drawn above this (DT_LOW keeps the chrome behind them).
--
-- The engine computes geometry and issues Cell/Header calls between Begin and End;
-- End hides any pooled control not touched this pass (so shrinking the grid or
-- collapsing cells under fill leaves nothing stranded).

QAT.gridDisplay = {}

local WM = GetWindowManager()
local groups = {} -- groupId -> { tlw, cache = { name -> control }, used = {}, n = <counter> }

-- Backdrop edge thickness must be a power of two; snap the authored border width to
-- the nearest valid step (0 = borderless).
local function snapBorder(w)
	w = tonumber(w) or 1
	if w <= 0 then
		return 0
	end
	for _, v in ipairs({ 16, 8, 4, 2, 1 }) do
		if w >= v then
			return v
		end
	end
	return 1
end

local function ensure(groupId)
	local e = groups[groupId]
	if not e then
		local tlw = WM:CreateTopLevelWindow("QAT_GridChrome_" .. tostring(groupId))
		tlw:SetDrawTier(DT_LOW) -- behind member trackers (default medium tier)
		tlw:ClearAnchors()
		tlw:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, 0, 0)
		tlw:SetDimensions(GuiRoot:GetWidth(), GuiRoot:GetHeight())
		e = { tlw = tlw, cache = {}, used = {}, n = 0 }
		groups[groupId] = e
	end
	return e
end

local function getControl(e, name, factory)
	local c = e.cache[name]
	if not c then
		c = factory()
		e.cache[name] = c
	end
	e.used[name] = true
	c:SetHidden(false)
	return c
end

-- Begin a redraw pass: show the container and reset the per-pass usage set.
function QAT.gridDisplay.Begin(groupId)
	local e = ensure(groupId)
	e.tlw:SetHidden(false)
	e.used = {}
	e.n = 0
end

-- A cell background: a filled, bordered box at a screen-space rect.
function QAT.gridDisplay.Cell(groupId, x, y, w, h, bg, border, borderW)
	local e = ensure(groupId)
	e.n = e.n + 1
	local name = "QAT_GridChrome_" .. groupId .. "_Cell" .. e.n
	local box = getControl(e, name, function()
		return QAT.widgets.Panel(e.tlw, name, bg, border)
	end)
	-- Size first, then (re)assert the edge: a CT_BACKDROP's edge textures don't reliably
	-- redraw when a pooled control is resized unless the edge is set after SetDimensions.
	box:SetDimensions(w, h)
	box:SetCenterColor(unpack(bg))
	local bw = snapBorder(borderW)
	if bw == 0 then
		box:SetEdgeColor(0, 0, 0, 0)
		box:SetEdgeTexture("", 1, 1, 1)
	else
		box:SetEdgeColor(unpack(border))
		box:SetEdgeTexture("", bw, bw, bw)
	end
	box:ClearAnchors()
	box:SetAnchor(TOPLEFT, e.tlw, TOPLEFT, x, y)
end

-- A header cell: a filled box with centered text.
function QAT.gridDisplay.Header(groupId, x, y, w, h, text, bg, border, borderW, textColor)
	local e = ensure(groupId)
	e.n = e.n + 1
	local name = "QAT_GridChrome_" .. groupId .. "_Hdr" .. e.n
	local box = getControl(e, name, function()
		return QAT.widgets.Panel(e.tlw, name, bg, border)
	end)
	-- Size first, then (re)assert the edge (see Cell: backdrop edges don't redraw on a
	-- resize otherwise).
	box:SetDimensions(w, h)
	box:SetCenterColor(unpack(bg))
	local bw = snapBorder(borderW)
	if bw == 0 then
		box:SetEdgeColor(0, 0, 0, 0)
		box:SetEdgeTexture("", 1, 1, 1)
	else
		box:SetEdgeColor(unpack(border))
		box:SetEdgeTexture("", bw, bw, bw)
	end
	box:ClearAnchors()
	box:SetAnchor(TOPLEFT, e.tlw, TOPLEFT, x, y)

	local lname = name .. "_L"
	local lbl = getControl(e, lname, function()
		return QAT.widgets.Label(box, lname, "", "$(BOLD_FONT)|16|soft-shadow-thick")
	end)
	lbl:SetText(text or "")
	lbl:SetColor(unpack(textColor))
	lbl:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
	lbl:ClearAnchors()
	lbl:SetAnchor(CENTER, box, CENTER, 0, 0)
end

-- Finish a pass: hide every pooled control that was not (re)used this time.
function QAT.gridDisplay.End(groupId)
	local e = groups[groupId]
	if not e then
		return
	end
	for name, c in pairs(e.cache) do
		if not e.used[name] then
			c:SetHidden(true)
		end
	end
end

-- Hide a group's chrome entirely (grid disabled or group unloaded).
function QAT.gridDisplay.Hide(groupId)
	local e = groups[groupId]
	if e then
		e.tlw:SetHidden(true)
	end
end
