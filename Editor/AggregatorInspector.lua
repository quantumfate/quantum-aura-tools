-- Effect Aggregator — Tracker builder (middle pane).
--
-- The build surface shown while building: multi-select (B) or a single collapsed-merge
-- pick (A). It turns the current selection into an ordered list of PHASES — one row per
-- built phase — and owns the Build / Add-to-existing actions. Each phase row states, in
-- plain terms, that one item equals one phase (a merged item shows "K IDs → 1 phase"),
-- so the collapse-on and collapse-off cases read the same. Per-effect data and the
-- leading-card picker live in the right context pane (AggregatorContext.lua); clicking a
-- phase row here focuses it there.

local WM = GetWindowManager()
local W = QAT.widgets

local PAD = 12
local INNER_W = 330 -- BUILDER_W (372) minus side padding and the scrollbar gutter

local WARN_COL = { 0.878, 0.686, 0.196 }
local ARROW_UP = "EsoUI/Art/Miscellaneous/list_sortUp.dds"
local ARROW_DOWN = "EsoUI/Art/Miscellaneous/list_sortDown.dds"

-- One PHASES row: number badge, icon, name, a "what this builds" subtitle, reorder
-- (up/down) and remove. Highlighted when it is the focused context target.
local function makePhaseRow(parent, name)
	local p = W.Clickable(parent, name, { 0.05, 0.08, 0.11, 1 })
	p.bg:SetEdgeColor(0.11, 0.16, 0.21, 1)
	p.bg:SetEdgeTexture("", 1, 1, 1)
	p:SetHeight(46)

	local num = W.Badge(p, name .. "_N", "1", { 0.55, 0.62, 0.72 })
	num:SetAnchor(TOPLEFT, p, TOPLEFT, 8, 7)
	local icon = WM:CreateControl(name .. "_Ic", p, CT_TEXTURE)
	icon:SetDimensions(22, 22)
	icon:SetAnchor(LEFT, num, RIGHT, 8, 0)
	local nm = W.Label(p, name .. "_Nm", "", "$(MEDIUM_FONT)|16|soft-shadow-thin")
	nm:SetAnchor(TOPLEFT, icon, TOPRIGHT, 8, -1)

	local del = W.CloseButton(p, name .. "_X", nil)
	del:SetDimensions(22, 22)
	del:SetAnchor(TOPRIGHT, p, TOPRIGHT, -4, 6)
	local down = W.IconButton(p, name .. "_Dn", ARROW_DOWN, 15, nil)
	down:SetAnchor(RIGHT, del, LEFT, -4, 0)
	local up = W.IconButton(p, name .. "_Up", ARROW_UP, 15, nil)
	up:SetAnchor(RIGHT, down, LEFT, -3, 0)

	-- Subtitle: "single id · You → Boss" or "K IDs → 1 phase · <dir | mixed dir>".
	local sub = W.Label(p, name .. "_Sub", "", "$(MEDIUM_FONT)|13|soft-shadow-thin")
	sub:SetColor(0.5, 0.58, 0.68, 1)
	sub:SetAnchor(BOTTOMLEFT, icon, BOTTOMRIGHT, 8, 16)

	p:SetHandler("OnMouseEnter", function(self)
		if not self.active then
			self.bg:SetCenterColor(0.07, 0.11, 0.15, 1)
		end
	end)
	p:SetHandler("OnMouseExit", function(self)
		if not self.active then
			self.bg:SetCenterColor(0.05, 0.08, 0.11, 1)
		end
	end)
	p:SetHandler("OnMouseUp", function(self, b, inside)
		if inside and b == MOUSE_BUTTON_INDEX_LEFT and self.onFocus then
			self.onFocus()
		end
	end)

	function p:Bind(index, item, cb)
		num:SetText(tostring(index))
		icon:SetTexture(item.icon)
		nm:SetText(item.name or "?")
		local dir = item.mixed and "mixed dir" or (item.dir or "")
		if item.merged then
			sub:SetText(item.idCount .. " IDs → 1 phase" .. (dir ~= "" and ("  ·  " .. dir) or ""))
		else
			sub:SetText("single id" .. (dir ~= "" and ("  ·  " .. dir) or ""))
		end
		sub:SetColor(
			item.mixed and WARN_COL[1] or 0.5,
			item.mixed and WARN_COL[2] or 0.58,
			item.mixed and WARN_COL[3] or 0.68,
			1
		)

		up.onClick, down.onClick = cb.onUp, cb.onDown
		up:SetHidden(cb.onUp == nil)
		down:SetHidden(cb.onDown == nil)
		del.onClick = cb.onRemove
		self.onFocus = cb.onFocus

		self.active = cb.active
		self.bg:SetCenterColor(cb.active and 0.12 or 0.05, cb.active and 0.20 or 0.08, cb.active and 0.30 or 0.11, 1)
		self:SetHidden(false)
	end
	return p
end

-- ---------------------------------------------------------------------------
-- Build (once)
-- ---------------------------------------------------------------------------

function QAT.Aggregator_Inspector_Build(pane)
	local I = {}
	QAT.aggregator.insp = I

	local sc = WM:CreateControlFromVirtual("QAT_AggBld_Scroll", pane, "ZO_ScrollContainer")
	sc:SetAnchor(TOPLEFT, pane, TOPLEFT, 0, 0)
	sc:SetAnchor(BOTTOMRIGHT, pane, BOTTOMRIGHT, 0, 0)
	local body = GetControl(sc, "ScrollChild")
	body:SetResizeToFitDescendents(true)
	body:SetResizeToFitPadding(0, 12)
	I.body = body

	-- Header: title + Done.
	local icon = WM:CreateControl("QAT_AggBld_Ic", body, CT_TEXTURE)
	icon:SetTexture("EsoUI/Art/Journal/journal_tabIcon_lore_up.dds")
	icon:SetDimensions(22, 22)
	icon:SetColor(0.6, 0.68, 0.78, 1)
	icon:SetAnchor(TOPLEFT, body, TOPLEFT, PAD, PAD)
	I.title = W.Label(body, "QAT_AggBld_Title", "Tracker builder", "$(BOLD_FONT)|20|soft-shadow-thin")
	I.title:SetAnchor(LEFT, icon, RIGHT, 8, 0)

	I.done = W.TextButton(body, "QAT_AggBld_Done", "Done", function()
		QAT.Aggregator_ExitBuild()
	end)
	I.done:SetHeight(28)
	I.done:SetAnchor(TOPRIGHT, body, TOPLEFT, PAD + INNER_W, PAD - 2)

	I.sub = W.Label(body, "QAT_AggBld_Sub", "", "$(MEDIUM_FONT)|14|soft-shadow-thin")
	I.sub:SetColor(0.55, 0.62, 0.72, 1)
	I.sub:SetAnchor(TOPLEFT, icon, BOTTOMLEFT, 0, 8)

	I.build = W.TextButton(body, "QAT_AggBld_Build", "Build Tracker", function()
		QAT.Aggregator_BuildFromSelection()
	end)
	I.build:SetSelected(true)
	I.build:SetHeight(32)
	I.build:SetMinWidth(INNER_W)
	I.build:SetAnchor(TOPLEFT, I.sub, BOTTOMLEFT, 0, 12)

	I.addLayer = W.TextButton(body, "QAT_AggBld_AddLayer", "Add to existing tracker…", function()
		QAT.Aggregator_AddSelectionToLayer()
	end)
	I.addLayer:SetHeight(28)
	I.addLayer:SetMinWidth(INNER_W)
	I.addLayer:SetAnchor(TOPLEFT, I.build, BOTTOMLEFT, 0, 8)

	-- "What this builds" info card.
	I.info = W.Card(body, "QAT_AggBld_Info", "Builds a simple tracker")
	I.info:SetWidth(INNER_W)
	I.info:SetAnchor(TOPLEFT, I.addLayer, BOTTOMLEFT, 0, 12)
	I.infoText = W.Label(I.info, "QAT_AggBld_InfoT", "", "$(MEDIUM_FONT)|14|soft-shadow-thin")
	I.infoText:SetColor(0.68, 0.75, 0.83, 1)
	I.infoText:SetAnchor(TOPLEFT, I.info, TOPLEFT, PAD, I.info.contentY)
	I.infoText:SetWidth(INNER_W - PAD * 2)
	I.infoText:SetVerticalAlignment(TEXT_ALIGN_TOP)

	-- Manual opt-out (switch trackers only).
	I.manualChk = W.Checkbox(body, "QAT_AggBld_Manual", false, function(v)
		QAT.aggregator.builderManual = v
		QAT.Aggregator_Inspector_RenderBuilder()
	end)
	I.manualLbl = W.Label(body, "QAT_AggBld_ManualL", "Wire the switching myself", "$(MEDIUM_FONT)|14|soft-shadow-thin")
	I.manualLbl:SetColor(0.68, 0.75, 0.83, 1)
	QAT.widgets.Tooltip(
		I.manualLbl,
		"Build one phase per effect plus a hidden idle, with no transitions — you add the switching rules yourself in the editor."
	)

	I.phasesHdr = W.Label(body, "QAT_AggBld_PhHdr", "PHASES", "$(BOLD_FONT)|13|soft-shadow-thin")
	I.phasesHdr:SetColor(0.5, 0.57, 0.66, 1)
	I.phasesHint =
		W.Label(body, "QAT_AggBld_PhHint", "order = sequence · phase 0 is idle", "$(MEDIUM_FONT)|12|soft-shadow-thin")
	I.phasesHint:SetColor(0.42, 0.48, 0.56, 1)

	I.pool = W.NewPool()
	QAT.Aggregator_Inspector_RenderBuilder()
end

-- ---------------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------------

function QAT.Aggregator_Inspector_RenderBuilder()
	local I = QAT.aggregator.insp
	if not I then
		return
	end
	local a = QAT.aggregator

	local items = QAT.Aggregator_GroupedSelection()
	local n = #items
	local switch = n >= 2

	I.sub:SetText(
		n == 0 and "select effects to build"
			or (n .. " phase" .. (n == 1 and "" or "s") .. " + idle = " .. (n + 1) .. " total")
	)

	if n == 0 then
		I.info:SetTitle("Nothing selected yet")
		I.infoText:SetText(
			"Tick effects in the list on the left. One becomes a simple tracker; two or more become a switch tracker."
		)
	elseif switch and a.builderManual then
		I.info:SetTitle("Builds phases only")
		I.infoText:SetText(
			"One phase per item plus a hidden idle, with no transitions — you wire the switching yourself in the editor."
		)
	elseif switch then
		I.info:SetTitle("Builds a switch tracker")
		I.infoText:SetText(
			"One aura cycling "
				.. n
				.. " phases (plus idle phase 0). Each row below is exactly one phase — a merged row still counts as one phase, matching any of its IDs."
		)
	else
		I.info:SetTitle("Builds a simple tracker")
		I.infoText:SetText("One aura for this single phase. Add another effect to make it a switch tracker.")
	end
	local th = I.infoText:GetTextHeight() or 40
	I.info:SetHeight(I.info.contentY + math.max(28, th) + 12)
	I.build:SetMouseEnabled(n > 0)
	I.addLayer:SetMouseEnabled(n > 0)

	-- Flowing section beneath the info card: manual checkbox (switch only), then the
	-- PHASES header + rows.
	local infoBottomGap = 14
	I.manualChk:SetChecked(a.builderManual)
	if switch then
		I.manualChk:SetHidden(false)
		I.manualLbl:SetHidden(false)
		I.manualChk:ClearAnchors()
		I.manualChk:SetAnchor(TOPLEFT, I.info, BOTTOMLEFT, 0, infoBottomGap)
		I.manualLbl:ClearAnchors()
		I.manualLbl:SetAnchor(LEFT, I.manualChk, RIGHT, 8, 0)
		I.phasesHdr:ClearAnchors()
		I.phasesHdr:SetAnchor(TOPLEFT, I.manualChk, BOTTOMLEFT, 0, 12)
	else
		I.manualChk:SetHidden(true)
		I.manualLbl:SetHidden(true)
		I.phasesHdr:ClearAnchors()
		I.phasesHdr:SetAnchor(TOPLEFT, I.info, BOTTOMLEFT, 0, infoBottomGap)
	end
	I.phasesHint:ClearAnchors()
	I.phasesHint:SetAnchor(LEFT, I.phasesHdr, RIGHT, 8, 1)

	-- Phase rows.
	local ct = a.contextTarget
	W.PoolBegin(I.pool)
	local prev = I.phasesHdr
	if n == 0 then
		local e = W.PoolGet(I.pool, "empty", function()
			return W.Label(I.body, "QAT_AggBld_Empty", "", "$(MEDIUM_FONT)|14|soft-shadow-thin")
		end)
		e:SetHidden(false)
		e:SetColor(0.5, 0.55, 0.62, 1)
		e:SetText("No effects ticked yet.")
		e:ClearAnchors()
		e:SetAnchor(TOPLEFT, I.phasesHdr, BOTTOMLEFT, 0, 10)
	else
		for i, it in ipairs(items) do
			local rows = {}
			for _, k in ipairs(it.keys) do
				local r = QAT.capture.store[k]
				if r then
					rows[#rows + 1] = r
				end
			end
			local ids, seen = {}, {}
			for _, r in ipairs(rows) do
				if not seen[r.abilityId] then
					seen[r.abilityId] = true
					ids[#ids + 1] = r.abilityId
				end
			end
			local dir = QAT.Aggregator_StackDirection(rows)
			local lead = rows[1]
			local pr = W.PoolGet(I.pool, "ph" .. i, function()
				return makePhaseRow(I.body, "QAT_AggBld_Ph" .. i)
			end)
			pr:ClearAnchors()
			pr:SetAnchor(TOPLEFT, prev, BOTTOMLEFT, (prev == I.phasesHdr) and 0 or 0, (prev == I.phasesHdr) and 10 or 6)
			pr:SetWidth(INNER_W)
			local active = ct and ct.keys[1] == it.keys[1] or false
			pr:Bind(i, {
				name = lead and lead.name or "?",
				icon = lead and lead.icon,
				idCount = #ids,
				merged = #ids > 1,
				dir = dir,
				mixed = (#rows > 1 and dir == nil),
			}, {
				active = active,
				onFocus = function()
					local gk = it.nameKey or it.keys[1]
					QAT.Aggregator_SetContextTarget(
						it.keys,
						lead and lead.name,
						lead and lead.icon,
						a.leadIndex[gk] or 1,
						gk
					)
					QAT.Aggregator_Inspector_RenderBuilder()
				end,
				onRemove = function()
					for _, k in ipairs(it.keys) do
						QAT.Aggregator_RemoveSelected(k)
					end
				end,
				onUp = (i > 1) and function()
					QAT.Aggregator_MovePhaseItem(i, -1)
				end or nil,
				onDown = (i < n) and function()
					QAT.Aggregator_MovePhaseItem(i, 1)
				end or nil,
			})
			prev = pr
		end
	end
	W.PoolEnd(I.pool)
end
