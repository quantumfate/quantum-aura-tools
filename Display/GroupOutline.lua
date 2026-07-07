-- Group drag outline: an editor-only overlay that visualizes a selected group's
-- bounds and acts as its drag handle. A group has no drawn HUD presence of its own
-- (it's a logical anchor); this outline appears only while the editor is open and the
-- group is the selected tree node, so the whole group can be moved as one unit without
-- risking an accidental drag of a member tracker.
--
-- Dragging updates the group's def.pos (its anchor) and re-anchors every member via
-- QAT.Runtime_ReanchorAll, so members follow rigidly.

QAT.groupOutline = {}

local WM = GetWindowManager()
local MARGIN = 6 -- breathing room drawn around the member bounds
local MINW, MINH = 60, 28 -- floor for an empty group so there's something to grab

local outline -- lazily-created overlay { tlw, border, label }

-- Absolute screen anchor of a folder's children (parent anchor + the folder's own
-- pos), found by walking the tree. Returns nil if the id isn't a folder.
local function folderAnchor(defs, id, ax, ay)
	for _, def in ipairs(defs or {}) do
		if def.kind == "folder" then
			local p = def.pos or { x = 0, y = 0 }
			local cx, cy = ax + (p.x or 0), ay + (p.y or 0)
			if def.id == id then
				return cx, cy, def
			end
			local rx, ry, found = folderAnchor(def.children, id, cx, cy)
			if found then
				return rx, ry, found
			end
		end
	end
	return nil
end

-- Grow bounds `b` to cover every member of `def`, whose children sit at absolute
-- anchor (ax, ay). Square kinds (icon/border/gradient) are height-wide.
local function accumBounds(def, ax, ay, b)
	for _, c in ipairs(def.children or {}) do
		if c.kind == "folder" then
			local p = c.pos or { x = 0, y = 0 }
			accumBounds(c, ax + (p.x or 0), ay + (p.y or 0), b)
		else
			local p = c.pos or {}
			local h = p.height or 30
			local w = p.width or 220
			local squareOnly = true
			for _, ph in ipairs(c.phases or {}) do
				local d = ph.look and ph.look.display
				if d == "bar" or d == "text" then
					squareOnly = false
				end
			end
			if squareOnly then
				w = h
			end
			local x, y = ax + (p.x or 0), ay + (p.y or 0)
			b.minx = math.min(b.minx, x)
			b.miny = math.min(b.miny, y)
			b.maxx = math.max(b.maxx, x + w)
			b.maxy = math.max(b.maxy, y + h)
			b.any = true
		end
	end
end

-- Screen rect (x, y, w, h) of a group and its member-covering bounds, plus the group
-- def. Falls back to a small box at the anchor when the group is empty.
local function groupRect(id)
	local ax, ay, def = folderAnchor(QAT.sv.trackers, id, 0, 0)
	if not def then
		return nil
	end
	local b = { minx = math.huge, miny = math.huge, maxx = -math.huge, maxy = -math.huge, any = false }
	accumBounds(def, ax, ay, b)
	if not b.any then
		return ax, ay, MINW, MINH, def
	end
	local x = b.minx - MARGIN
	local y = b.miny - MARGIN
	return x, y, math.max(MINW, b.maxx - b.minx + MARGIN * 2), math.max(MINH, b.maxy - b.miny + MARGIN * 2), def
end

-- Absolute screen rect { x, y, w, h } covering a group's members (nil if not a group).
-- Used by the inspector's Center action to bring the whole group into view.
function QAT.GroupOutline_Rect(id)
	local x, y, w, h = groupRect(id)
	if not x then
		return nil
	end
	return x, y, w, h
end

-- Nudge a group's anchor so its member-bounding box stays fully on screen. Mutates the
-- folder's def.pos; the caller re-places members (ReanchorAll). Returns true if moved.
function QAT.GroupOutline_ClampToScreen(id)
	local x, y, w, h, def = groupRect(id)
	if not def then
		return false
	end
	local sw, sh = GuiRoot:GetWidth(), GuiRoot:GetHeight()
	local nx = zo_clamp(x, 0, math.max(0, sw - w))
	local ny = zo_clamp(y, 0, math.max(0, sh - h))
	if nx == x and ny == y then
		return false
	end
	def.pos = def.pos or { x = 0, y = 0 }
	def.pos.x = def.pos.x + (nx - x)
	def.pos.y = def.pos.y + (ny - y)
	return true
end

local function ensure()
	if outline then
		return outline
	end
	local tlw = WM:CreateTopLevelWindow("QAT_GroupOutline")
	tlw:SetDrawTier(DT_HIGH) -- above members so it always reads as the handle
	tlw:SetMouseEnabled(true)
	tlw:SetHidden(true)

	local border = WM:CreateControl("QAT_GroupOutline_Border", tlw, CT_BACKDROP)
	border:SetAnchorFill()
	border:SetCenterColor(0, 0, 0, 0) -- border only; never a fill (would read as a background)
	border:SetEdgeColor(0.45, 0.62, 0.95, 0.95)
	border:SetEdgeTexture("", 2, 2, 2)

	local label = WM:CreateControl("QAT_GroupOutline_Label", tlw, CT_LABEL)
	label:SetFont("$(BOLD_FONT)|15|soft-shadow-thick")
	label:SetColor(0.75, 0.85, 1, 1)
	label:SetAnchor(BOTTOMLEFT, tlw, TOPLEFT, 2, -2)

	-- Drag: move the group's anchor by the mouse delta, re-anchoring members live.
	tlw:SetHandler("OnMouseDown", function(self, button)
		if button ~= MOUSE_BUTTON_INDEX_LEFT then
			return
		end
		local mx, my = GetUIMousePosition()
		self.grabX, self.grabY = mx, my
		local def = self.groupDef
		self.startX = (def and def.pos and def.pos.x) or 0
		self.startY = (def and def.pos and def.pos.y) or 0
		self.dragging = true
	end)
	tlw:SetHandler("OnMouseUp", function(self)
		self.dragging = false
	end)
	tlw:SetHandler("OnUpdate", function(self)
		if not self.dragging then
			return
		end
		local mx, my = GetUIMousePosition()
		local def = self.groupDef
		if not def then
			return
		end
		def.pos = def.pos or { x = 0, y = 0 }
		def.pos.x = self.startX + (mx - self.grabX)
		def.pos.y = self.startY + (my - self.grabY)
		QAT.GroupOutline_ClampToScreen(self.groupId) -- keep the whole group on screen
		if QAT.Runtime_ReanchorAll then
			QAT.Runtime_ReanchorAll()
		end
		QAT.groupOutline.Reposition()
		if QAT.Editor_SetGroupPosLive then
			QAT.Editor_SetGroupPosLive(self.groupId, def.pos.x, def.pos.y)
		end
	end)

	outline = { tlw = tlw, border = border, label = label }
	return outline
end

-- Reposition the outline over its current group's bounds (called on show and each
-- drag frame).
function QAT.groupOutline.Reposition()
	local o = outline
	if not o or not o.tlw.groupId then
		return
	end
	local x, y, w, h, def = groupRect(o.tlw.groupId)
	if not x then
		o.tlw:SetHidden(true)
		return
	end
	o.tlw.groupDef = def
	o.tlw:ClearAnchors()
	o.tlw:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, x, y)
	o.tlw:SetDimensions(w, h)
	o.label:SetText((def.name or "Group") .. "  (drag to move group)")
end

-- Show the outline for a group id, or hide it when id is nil.
function QAT.GroupOutline_Show(id)
	local o = ensure()
	if not id then
		o.tlw.groupId = nil
		o.tlw.dragging = false
		o.tlw:SetHidden(true)
		return
	end
	o.tlw.groupId = id
	o.tlw:SetHidden(false)
	QAT.groupOutline.Reposition()
end
