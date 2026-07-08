-- Behavior tab: the selected phase's timer and its outgoing transitions (the state
-- machine). The phase is chosen by the shared phase strip in the header.

local PAD = 12
local ROW_H = 26
local GAP = 8

local DURATION_OPTS = {
	{ label = "Follows effect", value = "effect" },
	{ label = "Fixed seconds", value = "fixed" },
	{ label = "None (static)", value = "none" },
}
local TRIGGER_OPTS = {
	{ label = "Effect gained", value = "gained" },
	{ label = "Effect faded", value = "faded" },
	{ label = "Stacks", value = "stacks" },
	{ label = "Time left", value = "remaining" },
	{ label = "Timer ends", value = "expire" },
}
local OP_OPTS = {
	{ label = "<", value = "<" },
	{ label = "<=", value = "<=" },
	{ label = "==", value = "==" },
	{ label = "~=", value = "~=" },
	{ label = ">=", value = ">=" },
	{ label = ">", value = ">" },
}
-- The unit each effect is watched on. Per-effect, so one phase can watch self for
-- one trigger and the target for another.
local UNIT_OPTS = {
	{ label = "Self", value = "player" },
	{ label = "Target", value = "reticleover" },
}

local function triggerValue(when)
	if when.kind == "effect" then
		return when.result or "gained"
	elseif when.kind == "source" then
		return (when.result == "faded") and "source_faded" or "source_gained"
	end
	return when.kind
end

local function setTriggerKind(when, v)
	if v == "gained" or v == "faded" then
		when.kind = "effect"
		when.result = v
		when.abilityIds = when.abilityIds or {}
	elseif v == "source_gained" or v == "source_faded" then
		when.kind = "source"
		when.result = (v == "source_faded") and "faded" or "gained"
		when.abilityIds = nil
	elseif v == "stacks" or v == "remaining" then
		when.kind = v
		when.op = when.op or ">="
		when.value = when.value or 0
	else
		when.kind = "expire"
	end
end

local function idsToText(ids)
	return table.concat(ids or {}, ", ")
end
local function textToIds(text)
	local ids = {}
	for token in tostring(text or ""):gmatch("%d+") do
		table.insert(ids, tonumber(token))
	end
	return ids
end

local function selectedPhase(def)
	local id = QAT.editor.selectedPhaseId
	for _, p in ipairs(def.phases) do
		if p.id == id then
			return p
		end
	end
	return def.phases[1]
end

local function phaseOptions(def, sourcePhase)
	local layer = sourcePhase and (sourcePhase.layer or 0) or 0
	local opts = { { label = "(hidden)", value = nil } }
	for _, p in ipairs(def.phases) do
		if p ~= sourcePhase and (p.layer or 0) == layer then
			table.insert(opts, { label = p.id, value = p.id })
		end
	end
	return opts
end

local function commit(def)
	QAT.CanonicalizeDef(def)
	QAT.widgets.NotifyTrackerChanged(def.id)
end

-- Plain-language helpers for the read-only "How this phase works" card, which
-- narrates a phase without exposing ability ids or the state-machine jargon.
local function onUnit(unit)
	if unit == "reticleover" then
		return "on your target"
	elseif unit and unit ~= "player" then
		return "on the boss"
	end
	return "on you"
end
local function fromUnit(unit)
	if unit == "reticleover" then
		return "from your target"
	elseif unit and unit ~= "player" then
		return "from the boss"
	end
	return "from you"
end
local function stacksPhrase(op, v)
	v = v or 0
	if op == ">=" or op == ">" then
		return "reaches " .. v .. " stacks"
	elseif op == "<=" or op == "<" then
		return "drops below " .. v .. " stacks"
	elseif op == "==" then
		return "hits exactly " .. v .. " stacks"
	end
	return "stacks " .. (op or ">=") .. " " .. v
end
local function remainingPhrase(op, v)
	v = v or 0
	if op == "<" or op == "<=" then
		return "under " .. v .. "s remain"
	elseif op == ">" or op == ">=" then
		return "over " .. v .. "s left"
	end
	return "time left " .. (op or "<=") .. " " .. v .. "s"
end
-- The phase's own id (the string shown in the tree), not its display label — so the
-- card names phases the way the user navigates them.
local function phaseName(def, id)
	if not id then
		return "(hidden)"
	end
	return tostring(id)
end
local SLATE = { 0.55, 0.62, 0.72 }
-- A phase's own bar color, so a target badge reads with the color the user set.
local function phaseColor(def, id)
	for _, p in ipairs(def.phases or {}) do
		if p.id == id then
			local c = p.look and p.look.colors and p.look.colors.bar
			if c then
				return { c[1], c[2], c[3] }
			end
		end
	end
	return SLATE
end

local function render(container, def)
	local pool = container.pool or QAT.widgets.NewPool()
	container.pool = pool
	QAT.widgets.PoolBegin(pool)
	local function get(key, factory)
		return QAT.widgets.PoolGet(pool, key, factory)
	end

	QAT.CanonicalizeDef(def)
	local phase = selectedPhase(def)
	if not phase then
		QAT.widgets.PoolEnd(pool)
		return
	end

	-- When this tracker is the template of a dynamic group, its phases can subscribe to
	-- the group's emitter (source) as a duration / transition trigger. Offer those extra
	-- options only then.
	local dynSource = QAT.Editor_DynamicSourceFor and QAT.Editor_DynamicSourceFor(def.id)
	local durOpts, trigOpts = DURATION_OPTS, TRIGGER_OPTS
	if dynSource then
		durOpts = { { label = "Emitter (" .. dynSource .. ")", value = "source" } }
		for _, o in ipairs(DURATION_OPTS) do
			durOpts[#durOpts + 1] = o
		end
		trigOpts = {
			{ label = "Emitter appears", value = "source_gained" },
			{ label = "Emitter fades", value = "source_faded" },
		}
		for _, o in ipairs(TRIGGER_OPTS) do
			trigOpts[#trigOpts + 1] = o
		end
	end

	-- Wrap the content in a titled card (created first, so it draws behind).
	local cw = container.qatViewportW or container:GetWidth()
	if cw < 240 then
		cw = 900
	end
	local OUT = 14
	local card = get("card", function()
		return QAT.widgets.Card(container, "QAT_Beh_Card", "Behavior")
	end)
	card:SetTitle("Behavior")
	card:ClearAnchors()
	card:SetAnchor(TOPLEFT, container, TOPLEFT, OUT, OUT)
	local PAD = OUT + card.padX
	local LX = PAD + 100
	local y = OUT + card.contentY

	local function fieldLabel(key, text, yy, tip)
		local l = get(key, function()
			return QAT.widgets.Label(container, "QAT_Beh_" .. key, "")
		end)
		l:SetText(text)
		l:ClearAnchors()
		l:SetAnchor(TOPLEFT, container, TOPLEFT, PAD, yy + 3)
		QAT.widgets.Tooltip(l, tip)
		return l
	end

	-- Duration (the timer that animates the phase and defines "Timer ends").
	fieldLabel(
		"lDur",
		"Duration",
		y,
		"The phase's timer: Follows effect (while the buff is on the unit; permanent buffs show static), Fixed seconds (e.g. a cooldown), or None."
	)
	local durDD = get("durDD", function()
		return QAT.widgets.Dropdown(container, "QAT_Beh_Dur", 180, DURATION_OPTS, "none")
	end)
	durDD:SetOptions(durOpts)
	durDD.onSelect = function(v)
		phase.duration.type = v
		commit(def)
	end
	durDD:SetValue(phase.duration.type or "none")
	durDD:ClearAnchors()
	durDD:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y)
	y = y + ROW_H + GAP

	if phase.duration.type == "fixed" then
		fieldLabel("lSecs", "Seconds", y, "Length of the fixed timer, in seconds.")
		local secsBox = get("secsBox", function()
			return QAT.widgets.EditBox(container, "QAT_Beh_Secs", 100, ROW_H)
		end)
		secsBox.onChange = function(text)
			phase.duration.seconds = tonumber(text) or 0
			commit(def)
		end
		secsBox:SetText(tostring(phase.duration.seconds or 0))
		secsBox:ClearAnchors()
		secsBox:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y)
		y = y + ROW_H + GAP
	elseif phase.duration.type == "effect" then
		fieldLabel(
			"lDurIds",
			"Effect",
			y,
			"The unit this effect is on, and the ability id(s) to follow (comma-separated)."
		)
		local durUnitDD = get("durUnit", function()
			return QAT.widgets.Dropdown(container, "QAT_Beh_DurUnit", 90, UNIT_OPTS, "player")
		end)
		durUnitDD.onSelect = function(v)
			phase.duration.unit = v
			commit(def)
		end
		durUnitDD:SetValue(phase.duration.unit or def.unit or "player")
		durUnitDD:ClearAnchors()
		durUnitDD:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y)
		local durIdBox = get("durIdBox", function()
			return QAT.widgets.EditBox(container, "QAT_Beh_DurIds", 180, ROW_H)
		end)
		durIdBox.onChange = function(text)
			phase.duration.abilityIds = textToIds(text)
			commit(def)
		end
		durIdBox:SetText(idsToText(phase.duration.abilityIds))
		durIdBox:ClearAnchors()
		durIdBox:SetAnchor(TOPLEFT, container, TOPLEFT, LX + 96, y)
		y = y + ROW_H + GAP

		-- Target debuffs vanish the instant the reticle leaves the target. Opt in to
		-- keep the phase on screen (running out on its own timer), updating only when a
		-- new target is acquired. Aura-wide, so it shows on any target-following phase.
		if (phase.duration.unit or def.unit) == "reticleover" then
			fieldLabel(
				"lSticky",
				"On target loss",
				y,
				"Keep this tracker on screen after your reticle leaves the target, letting it run out on its own timer. It updates only when you select a new target. Applies to the whole aura."
			)
			local stickyBox = get("stickyBox", function()
				return QAT.widgets.Checkbox(container, "QAT_Beh_Sticky", false, nil)
			end)
			stickyBox.onToggle = function(v)
				def.stickyTarget = v
				commit(def)
			end
			stickyBox:SetChecked(def.stickyTarget and true or false)
			stickyBox:ClearAnchors()
			stickyBox:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y)
			local hint = get("stickyHint", function()
				return QAT.widgets.Label(container, "QAT_Beh_StickyHint", "")
			end)
			hint:SetText("keep showing & run out")
			hint:SetColor(0.6, 0.65, 0.72, 1)
			hint:ClearAnchors()
			hint:SetAnchor(LEFT, stickyBox, RIGHT, 8, 0)
			y = y + ROW_H + GAP
		end
	elseif phase.duration.type == "source" then
		fieldLabel(
			"lDurSrc",
			"Emitter",
			y,
			"This phase is timed by the group's emitter: each emitted element's own timing drives one instance of this tracker."
		)
		local srcHint = get("durSrcHint", function()
			return QAT.widgets.Label(container, "QAT_Beh_DurSrcHint", "")
		end)
		srcHint:SetText("timed by " .. (dynSource or "the source") .. " (per emitted element)")
		srcHint:SetColor(0.6, 0.72, 0.66, 1)
		srcHint:ClearAnchors()
		srcHint:SetAnchor(TOPLEFT, container, TOPLEFT, LX, y + 3)
		y = y + ROW_H + GAP
	end

	-- Transitions: an ordered list of exits; the engine takes the FIRST whose
	-- trigger matches (mutually exclusive).
	fieldLabel(
		"lTrans",
		"Transitions",
		y,
		"Where this phase can go next. Checked top to bottom; the first matching trigger wins (only one ever fires). Add several to branch on different triggers."
	)
	y = y + ROW_H
	if #phase.transitions > 1 then
		local hint = get("trHint", function()
			return QAT.widgets.Label(container, "QAT_Beh_TrHint", "")
		end)
		hint:SetText("checked top to bottom — first match wins")
		hint:SetColor(0.6, 0.65, 0.72, 1)
		hint:ClearAnchors()
		hint:SetAnchor(TOPLEFT, container, TOPLEFT, PAD + 26, y)
		y = y + 20
	end

	for i, tr in ipairs(phase.transitions) do
		local idx = i
		local when = tr.when

		local numLbl = get("trNum" .. i, function()
			return QAT.widgets.Label(container, "QAT_Beh_TrNum" .. i, "")
		end)
		numLbl:SetText(i .. ".")
		numLbl:ClearAnchors()
		numLbl:SetAnchor(TOPLEFT, container, TOPLEFT, PAD, y + 3)

		local x = PAD + 26
		local trigDD = get("trTrig" .. i, function()
			return QAT.widgets.Dropdown(container, "QAT_Beh_TrTrig" .. i, 170, TRIGGER_OPTS, "gained")
		end)
		trigDD:SetOptions(trigOpts)
		trigDD.onSelect = function(v)
			setTriggerKind(when, v)
			commit(def)
		end
		trigDD:SetValue(triggerValue(when))
		trigDD:ClearAnchors()
		trigDD:SetAnchor(TOPLEFT, container, TOPLEFT, x, y)
		x = x + 176

		local unitDD = get("trUnit" .. i, function()
			return QAT.widgets.Dropdown(container, "QAT_Beh_TrUnit" .. i, 86, UNIT_OPTS, "player")
		end)
		local idsBox = get("trIds" .. i, function()
			return QAT.widgets.EditBox(container, "QAT_Beh_TrIds" .. i, 130, ROW_H)
		end)
		local opDD = get("trOp" .. i, function()
			return QAT.widgets.Dropdown(container, "QAT_Beh_TrOp" .. i, 54, OP_OPTS, ">=")
		end)
		local valBox = get("trVal" .. i, function()
			return QAT.widgets.EditBox(container, "QAT_Beh_TrVal" .. i, 56, ROW_H)
		end)
		if when.kind == "effect" then
			opDD:SetHidden(true)
			valBox:SetHidden(true)
			-- "<result> on <unit> of <ids>": who gained/faded it matters.
			unitDD:SetHidden(false)
			unitDD.onSelect = function(v)
				when.unit = v
				commit(def)
			end
			unitDD:SetValue(when.unit or def.unit or "player")
			unitDD:ClearAnchors()
			unitDD:SetAnchor(TOPLEFT, container, TOPLEFT, x, y)
			x = x + 92
			idsBox:SetHidden(false)
			idsBox.onChange = function(text)
				when.abilityIds = textToIds(text)
				commit(def)
			end
			idsBox:SetText(idsToText(when.abilityIds))
			idsBox:ClearAnchors()
			idsBox:SetAnchor(TOPLEFT, container, TOPLEFT, x, y)
			x = x + 136
		elseif when.kind == "stacks" or when.kind == "remaining" then
			unitDD:SetHidden(true)
			idsBox:SetHidden(true)
			opDD:SetHidden(false)
			opDD.onSelect = function(v)
				when.op = v
				commit(def)
			end
			opDD:SetValue(when.op or ">=")
			opDD:ClearAnchors()
			opDD:SetAnchor(TOPLEFT, container, TOPLEFT, x, y)
			valBox:SetHidden(false)
			valBox.onChange = function(text)
				when.value = tonumber(text) or 0
				commit(def)
			end
			valBox:SetText(tostring(when.value or 0))
			valBox:ClearAnchors()
			valBox:SetAnchor(TOPLEFT, container, TOPLEFT, x + 60, y)
			x = x + 122
		else
			unitDD:SetHidden(true)
			idsBox:SetHidden(true)
			opDD:SetHidden(true)
			valBox:SetHidden(true)
		end

		local arrow = get("trArrow" .. i, function()
			return QAT.widgets.Label(container, "QAT_Beh_TrArrow" .. i, "->")
		end)
		arrow:SetText("->")
		arrow:ClearAnchors()
		arrow:SetAnchor(TOPLEFT, container, TOPLEFT, x, y + 3)
		x = x + 24

		local toDD = get("trTo" .. i, function()
			return QAT.widgets.Dropdown(container, "QAT_Beh_TrTo" .. i, 110, {}, nil)
		end)
		toDD:SetOptions(phaseOptions(def, phase))
		toDD.onSelect = function(v)
			tr.to = v
			commit(def)
		end
		toDD:SetValue(tr.to)
		toDD:ClearAnchors()
		toDD:SetAnchor(TOPLEFT, container, TOPLEFT, x, y)
		x = x + 116

		local del = get("trDel" .. i, function()
			return QAT.widgets.TextButton(container, "QAT_Beh_TrDel" .. i, "X", nil)
		end)
		del:SetDimensions(ROW_H, ROW_H)
		del:ClearAnchors()
		del:SetAnchor(TOPLEFT, container, TOPLEFT, x, y)
		QAT.widgets.Tooltip(del, "Remove this transition.")
		del.onClick = function()
			table.remove(phase.transitions, idx)
			commit(def)
		end

		y = y + ROW_H + GAP
	end

	local addTrans = get("addTrans", function()
		return QAT.widgets.TextButton(container, "QAT_Beh_AddTrans", "+ Transition", nil)
	end)
	addTrans:SetHeight(ROW_H)
	addTrans:ClearAnchors()
	addTrans:SetAnchor(TOPLEFT, container, TOPLEFT, PAD + 26, y)
	QAT.widgets.Tooltip(addTrans, "Add an outgoing transition to this phase.")
	addTrans.onClick = function()
		table.insert(phase.transitions, { when = { kind = "effect", result = "gained", abilityIds = {} }, to = nil })
		commit(def)
	end
	y = y + ROW_H + GAP

	card:SetDimensions(cw - OUT * 2, y - OUT + 8)

	-- Read-only "How this phase works" card: narrates the phase as a state map —
	-- what shows it, each outgoing branch, and the natural fall-through — with ability
	-- ids rendered as icon+name chips (the "state-flow" layout). Purely descriptive:
	-- it reads the same fields edited above and never writes.
	do
		local W = QAT.widgets
		local ci, bi, li = 0, 0, 0
		local function chip()
			ci = ci + 1
			local c = get("expC" .. ci, function()
				return W.AbilityChip(container, "QAT_Beh_ExpC" .. ci)
			end)
			c:SetHidden(false)
			return c
		end
		local function badge()
			bi = bi + 1
			local b = get("expB" .. bi, function()
				return W.Badge(container, "QAT_Beh_ExpB" .. bi, "", SLATE)
			end)
			b:SetHidden(false)
			return b
		end
		local BODY = "$(MEDIUM_FONT)|16|soft-shadow-thin"
		local function text(font)
			li = li + 1
			local l = get("expL" .. li, function()
				return W.Label(container, "QAT_Beh_ExpL" .. li, "", BODY)
			end)
			l:SetHidden(false)
			l:SetFont(font or BODY) -- font can differ per use; a pooled label is re-fonted
			return l
		end

		local INK = { 0.74, 0.80, 0.88, 1 }
		local MUTED = { 0.55, 0.6, 0.68, 1 }
		-- Lay a sequence of text / ability-chip / phase-badge segments left to right.
		local function inlineRow(x0, yy, segs)
			local x = x0
			for _, s in ipairs(segs) do
				if s.t then
					local l = text(s.font)
					l:SetText(s.t)
					l:SetColor(unpack(s.color or INK))
					l:ClearAnchors()
					l:SetAnchor(TOPLEFT, container, TOPLEFT, x, yy + (s.dy or 5))
					x = x + math.ceil(l:GetTextWidth()) + (s.pad or 5)
				elseif s.chip ~= nil then
					local c = chip()
					c:SetAbility(s.chip)
					c:ClearAnchors()
					c:SetAnchor(TOPLEFT, container, TOPLEFT, x, yy)
					x = x + c:GetWidth() + 6
				elseif s.badge then
					local b = badge()
					b:SetColorRGB(s.color or SLATE)
					b:SetText(s.badge)
					b:ClearAnchors()
					b:SetAnchor(TOPLEFT, container, TOPLEFT, x, yy + 4)
					x = x + b:GetWidth() + 6
				end
			end
			return x
		end

		local expTop = y + 22
		local expCard = get("expCard", function()
			return W.Card(container, "QAT_Beh_ExpCard", "How this phase works")
		end)
		expCard:SetTitle("How this phase works")
		expCard:ClearAnchors()
		expCard:SetAnchor(TOPLEFT, container, TOPLEFT, OUT, expTop)
		local P2 = OUT + expCard.padX
		local innerW = cw - OUT * 2 - expCard.padX * 2
		local y2 = expTop + expCard.contentY

		local nt = #phase.transitions
		local cnt = text("$(MEDIUM_FONT)|14|soft-shadow-thin")
		cnt:SetText(nt .. " transition" .. (nt == 1 and "" or "s"))
		cnt:SetColor(0.5, 0.56, 0.64, 1)
		cnt:ClearAnchors()
		cnt:SetAnchor(TOPRIGHT, expCard, TOPRIGHT, -expCard.padX, 8)

		-- THIS PHASE box: the current phase and what puts the tracker in it.
		local panel = get("expThis", function()
			return W.Panel(container, "QAT_Beh_ExpThis", { 0.06, 0.09, 0.13, 1 }, { 0.12, 0.17, 0.22, 1 })
		end)
		panel:SetHidden(false)
		panel:ClearAnchors()
		panel:SetAnchor(TOPLEFT, container, TOPLEFT, P2, y2)
		panel:SetDimensions(innerW, 74)

		local hdr = text("$(BOLD_FONT)|14|soft-shadow-thin")
		hdr:SetText("THIS PHASE")
		hdr:SetColor(0.5, 0.56, 0.64, 1)
		hdr:ClearAnchors()
		hdr:SetAnchor(TOPLEFT, container, TOPLEFT, P2 + 12, y2 + 8)
		local pb = badge()
		pb:SetColorRGB(phaseColor(def, phase.id))
		pb:SetText(phaseName(def, phase.id))
		pb:ClearAnchors()
		pb:SetAnchor(TOPLEFT, container, TOPLEFT, P2 + 12, y2 + 25)

		local d = phase.duration
		local durSegs
		if d.type == "effect" then
			durSegs = { { t = "Shown while", color = MUTED } }
			local ids = d.abilityIds or {}
			if #ids == 0 then
				durSegs[#durSegs + 1] = { t = "its effect", color = INK }
			else
				if #ids > 1 then
					durSegs[#durSegs + 1] = { t = "any of", color = MUTED }
				end
				for _, id in ipairs(ids) do
					durSegs[#durSegs + 1] = { chip = id }
				end
			end
			durSegs[#durSegs + 1] = { t = "is " .. onUnit(d.unit) .. ".", color = MUTED }
		elseif d.type == "fixed" then
			durSegs = { { t = "Shown for " .. (d.seconds or 0) .. " seconds.", color = INK } }
		elseif d.type == "source" then
			durSegs = { { t = "Shown while the emitter's element is live (one per emitted element).", color = INK } }
		else
			durSegs = { { t = "Static — shown while this phase is active.", color = MUTED } }
		end
		inlineRow(P2 + 12, y2 + 44, durSegs)
		y2 = y2 + 74 + 12

		-- Each outgoing branch: "when <trigger> -> <target phase>".
		for _, tr in ipairs(phase.transitions) do
			local w = tr.when
			local segs = { { t = "when", color = MUTED } }
			if w.kind == "effect" then
				local ids = w.abilityIds or {}
				if #ids == 0 then
					segs[#segs + 1] = { t = "its effect", color = INK }
				end
				for _, id in ipairs(ids) do
					segs[#segs + 1] = { chip = id }
				end
				segs[#segs + 1] = {
					t = (w.result == "faded") and ("drops " .. fromUnit(w.unit)) or ("appears " .. onUnit(w.unit)),
					color = MUTED,
				}
			elseif w.kind == "source" then
				segs[#segs + 1] = {
					t = (w.result == "faded") and "the emitter drops an element" or "the emitter emits an element",
					color = MUTED,
				}
			elseif w.kind == "stacks" then
				segs[#segs + 1] = { t = stacksPhrase(w.op, w.value), color = MUTED }
			elseif w.kind == "remaining" then
				segs[#segs + 1] = { t = remainingPhrase(w.op, w.value), color = MUTED }
			else
				segs[#segs + 1] = { t = "the timer runs out", color = MUTED }
			end
			segs[#segs + 1] = { t = "→", color = MUTED, pad = 6 }
			segs[#segs + 1] = { badge = phaseName(def, tr.to), color = phaseColor(def, tr.to) }
			inlineRow(P2 + 6, y2, segs)
			y2 = y2 + 28
		end

		-- The natural fall-through the engine takes when nothing above matches, unless
		-- the user already wrote it as an explicit transition.
		local hasExpire, hasFadedDur = false, false
		for _, tr in ipairs(phase.transitions) do
			if tr.when.kind == "expire" then
				hasExpire = true
			elseif tr.when.kind == "effect" and tr.when.result == "faded" then
				for _, id in ipairs(tr.when.abilityIds or {}) do
					for _, did in ipairs(d.abilityIds or {}) do
						if id == did then
							hasFadedDur = true
						end
					end
				end
			end
		end
		local fbName, fbColor = phaseName(def, def.initial), phaseColor(def, def.initial)
		local fbSegs
		if d.type == "fixed" and not hasExpire then
			fbSegs = {
				{ t = "Fallback — when the timer runs out", color = MUTED },
				{ t = "→", color = MUTED, pad = 6 },
				{ badge = fbName, color = fbColor },
			}
		elseif d.type == "effect" and not hasFadedDur then
			fbSegs = { { t = "Fallback — if", color = MUTED } }
			for _, id in ipairs(d.abilityIds or {}) do
				fbSegs[#fbSegs + 1] = { chip = id }
			end
			fbSegs[#fbSegs + 1] = { t = "drops", color = MUTED }
			fbSegs[#fbSegs + 1] = { t = "→", color = MUTED, pad = 6 }
			fbSegs[#fbSegs + 1] = { badge = fbName, color = fbColor }
		elseif d.type == "none" and nt == 0 then
			fbSegs = { { t = "No outgoing transitions — this phase only ends on its own.", color = MUTED } }
		end
		if fbSegs then
			local div = get("expDiv", function()
				return W.Divider(container, "QAT_Beh_ExpDiv")
			end)
			div:SetHidden(false)
			div:ClearAnchors()
			div:SetAnchor(TOPLEFT, container, TOPLEFT, P2, y2 + 2)
			div:SetWidth(innerW)
			y2 = y2 + 10
			inlineRow(P2 + 6, y2, fbSegs)
			y2 = y2 + 28
		end

		expCard:SetDimensions(cw - OUT * 2, (y2 - expTop) + 10)
	end

	QAT.widgets.PoolEnd(pool)
end

QAT.editor.tabRenderers = QAT.editor.tabRenderers or {}
QAT.editor.tabRenderers["Behavior"] = render
