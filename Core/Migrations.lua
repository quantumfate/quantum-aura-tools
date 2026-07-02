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
			treeWidth = 260,
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
