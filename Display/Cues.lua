-- Additive on-enter cues: a momentary sound and/or screen flash played when a
-- phase is entered. Cues are independent of a phase's display kind, so a phase
-- can be a bar that also flashes and beeps, or a "none" phase that is cue-only.

local flashControl

local function ensureFlash()
	if flashControl then
		return flashControl
	end
	local c = GetWindowManager():CreateTopLevelWindow("QAT_CueFlash")
	c:SetAnchorFill(GuiRoot)
	c:SetDrawLayer(DL_OVERLAY)
	c:SetMouseEnabled(false)
	c:SetHidden(true)
	-- A backdrop's center color fills without depending on a texture path.
	local fill = GetWindowManager():CreateControl("QAT_CueFlash_Fill", c, CT_BACKDROP)
	fill:SetAnchorFill()
	fill:SetEdgeColor(0, 0, 0, 0)
	c.fill = fill
	flashControl = c
	return c
end

--- Play a phase's cues.
---@param cues table|nil { sound = <SOUNDS name string>, flash = { color = {r,g,b,a}, duration = <ms> } | true }
function QAT.FireCues(cues)
	if not cues then
		return
	end

	if cues.sound then
		-- Accept either a SOUNDS key ("NEW_NOTIFICATION") or a raw sound id.
		-- pcall: an invalid/removed sound name should never break a transition.
		local sound = (SOUNDS and SOUNDS[cues.sound]) or cues.sound
		pcall(PlaySound, sound)
	end

	if cues.flash then
		local flash = cues.flash
		local color = (type(flash) == "table" and flash.color) or { 1, 0.2, 0.2, 0.5 }
		local duration = (type(flash) == "table" and flash.duration) or 300
		local c = ensureFlash()
		c.fill:SetCenterColor(unpack(color))
		c:SetHidden(false)
		zo_callLater(function()
			c:SetHidden(true)
		end, duration)
	end
end
