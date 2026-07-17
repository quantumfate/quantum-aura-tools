-- Versioned schema migrations.
--
-- Each step migrates the saved data from version N to N+1. On load,
-- QAT.RunMigrations applies every step whose index >= the stored schemaVersion,
-- in order, then stamps the data with QAT.schemaVersion.
--
--   QAT.migrations[1] = function(sv) ... end  -- migrate schema 1 -> 2
--   QAT.migrations[2] = function(sv) ... end  -- migrate schema 2 -> 3

QAT.migrations = {
	-- schema 1 -> 2: add editor window geometry.
	[1] = function(sv)
		sv.editor = sv.editor or {
			x = 200,
			y = 200,
			width = 900,
			height = 560,
			treeWidth = 410,
		}
	end,

	-- schema 2 -> 3: rewrite stored trackers into the canonical phased shape so
	-- flat single-phase defs are no longer kept alongside phased ones.
	[2] = function(sv)
		QAT.CanonicalizeTree(sv.trackers)
	end,

	-- schema 3 -> 4: phase model overhaul. enter[]/onExpire collapse into
	-- source-attached transitions, idle becomes a real phase, look gains per-element
	-- colors + showStacks (value/maxStacks removed), and tracker-level runtime
	-- conditions move onto the phases. CanonicalizeDef performs all of it.
	[3] = function(sv)
		QAT.CanonicalizeTree(sv.trackers)
	end,

	-- schema 4 -> 5: positions switch from centre-relative to a top-left origin.
	-- Convert each stored offset (control centre from screen centre) to the control's
	-- top-left corner from the screen's top-left, using the current screen size.
	[4] = function(sv)
		local w, h = GuiRoot:GetWidth(), GuiRoot:GetHeight()
		local function convert(defs)
			for _, def in ipairs(defs or {}) do
				if def.kind == "folder" then
					convert(def.children)
				elseif def.pos then
					local p = def.pos
					p.x = math.floor(w / 2 + (p.x or 0) - (p.width or 220) / 2)
					p.y = math.floor(h / 2 + (p.y or 0) - (p.height or 30) / 2)
				end
			end
		end
		convert(sv.trackers)
	end,

	-- schema 5 -> 6: add the effect-aggregator persistence bucket (pinned records +
	-- ignored ability ids). The live session catch is transient and never stored.
	[5] = function(sv)
		sv.capture = sv.capture or { pinned = {}, ignored = {} }
		sv.capture.pinned = sv.capture.pinned or {}
		sv.capture.ignored = sv.capture.ignored or {}
	end,

	-- schema 6 -> 7: "pin" becomes "favourite" (a pure display concept, distinct from
	-- the new build-selection). Rename the persisted bucket, preserving saved records.
	[6] = function(sv)
		sv.capture = sv.capture or {}
		sv.capture.favourites = sv.capture.favourites or sv.capture.pinned or {}
		sv.capture.pinned = nil
		for _, rec in pairs(sv.capture.favourites) do
			if type(rec) == "table" then
				rec.favourited = rec.favourited or rec.pinned or true
				rec.pinned = nil
			end
		end
	end,

	-- schema 7 -> 8: retire per-layer x/y offsets (layers now stack at the shared
	-- origin with a 9-point alignment instead — the offset trick was only ever used to
	-- fake tables, which the new group grid layout replaces). Grid blocks are optional
	-- and initialized lazily by CanonicalizeGrid, so nothing to seed here.
	[7] = function(sv)
		local function walk(defs)
			for _, def in ipairs(defs or {}) do
				if def.kind == "folder" then
					walk(def.children)
				elseif def.layerSettings then
					for _, s in pairs(def.layerSettings) do
						if type(s) == "table" then
							s.xOffset, s.yOffset = nil, nil
							s.align = s.align or "topleft"
						end
					end
				end
			end
		end
		walk(sv.trackers)
	end,

	-- schema 8 -> 9: captured effects now persist by default (the standing library),
	-- not just favourites. Add the records bucket and the opt-out account flag.
	[8] = function(sv)
		sv.capture = sv.capture or {}
		sv.capture.records = sv.capture.records or {}
		sv.account = sv.account or {}
		if sv.account.persistCapture == nil then
			sv.account.persistCapture = true
		end
	end,

	-- schema 9 -> 10: the icon is now a single per-phase concept with one unified
	-- "show icon" gate; the border kind's old `iconBehind` flag folds into it. Preserve
	-- the prior look: a border phase only showed its icon when iconBehind was set, so
	-- carry that across; every other kind keeps the new default-on showIcon.
	[9] = function(sv)
		local function walk(defs)
			for _, def in ipairs(defs or {}) do
				if def.kind == "folder" then
					walk(def.children)
				elseif def.phases then
					for _, p in ipairs(def.phases) do
						local look = p.look
						if type(look) == "table" then
							if look.display == "border" then
								look.showIcon = look.iconBehind == true
							end
							look.iconBehind = nil
						end
					end
				end
			end
		end
		walk(sv.trackers)
	end,

	-- schema 10 -> 11: groups gain a screen anchor and members become RELATIVE to it
	-- (so moving a group moves its members as one unit). Existing member coordinates are
	-- absolute; convert them: a folder's anchor becomes the top-left of its contents
	-- (or its grid origin), and every child's position is rebased to that anchor.
	-- Processed bottom-up so a nested folder's computed anchor is treated as its absolute
	-- position by its parent. Top-level trackers are unchanged (their anchor is 0,0).
	[10] = function(sv)
		local function migrate(folder)
			local children = folder.children or {}
			for _, c in ipairs(children) do
				if c.kind == "folder" then
					migrate(c)
				end
			end
			-- Anchor: a grid keeps its drawn origin; a plain folder takes the top-left of
			-- its contents' absolute positions. (Ignore any 0,0 injected by an earlier build
			-- of this feature — recompute the real top-left for non-grid folders.)
			local ax, ay
			if folder.grid and folder.grid.enabled and folder.pos and folder.pos.x then
				ax, ay = folder.pos.x, folder.pos.y
			else
				ax, ay = math.huge, math.huge
				for _, c in ipairs(children) do
					local p = c.pos
					if p and p.x then
						ax, ay = math.min(ax, p.x), math.min(ay, p.y)
					end
				end
				if ax == math.huge then
					ax, ay = 0, 0
				end
			end
			for _, c in ipairs(children) do
				c.pos = c.pos or { x = 0, y = 0 }
				c.pos.x = (c.pos.x or 0) - ax
				c.pos.y = (c.pos.y or 0) - ay
			end
			folder.pos = { x = ax, y = ay }
		end
		for _, def in ipairs(sv.trackers or {}) do
			if def.kind == "folder" then
				migrate(def)
			end
		end
	end,
}

function QAT.RunMigrations(sv)
	local from = sv.schemaVersion or 1
	local to = QAT.schemaVersion

	for v = from, to - 1 do
		local step = QAT.migrations[v]
		if step then
			step(sv)
			if QAT.Log then
				QAT.Log("migrated schema %d -> %d", v, v + 1)
			end
		end
	end

	sv.schemaVersion = to
end
