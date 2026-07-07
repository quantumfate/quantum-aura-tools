-- Runtime: owns all live trackers, the filtered effect subscriptions that drive
-- their phase transitions, and the single render tick that animates them.
--
-- Design principle (DESIGN.md): transitions come from filtered
-- EVENT_EFFECT_CHANGED (one registration per tracked ability id); the render
-- tick only advances/draws trackers that are in a timed phase. Idle and static
-- phases early-return in Tracker:Tick, so the per-frame cost scales with what's
-- actually counting down.

QAT.runtime = {
	trackers = {}, -- id -> Tracker
	list = {}, -- array of Trackers (tick order)
	byAbilityId = {}, -- abilityId -> { Tracker, ... }
}

local TICK_MS = 50 -- ~20 Hz

local function OnEffectChanged(
	_,
	changeType,
	_,
	_,
	unitTag,
	beginTime,
	endTime,
	stackCount,
	_,
	_,
	_,
	_,
	_,
	_,
	_,
	abilityId
)
	local listeners = QAT.runtime.byAbilityId[abilityId]
	if not listeners then
		return
	end
	QAT.log.runtime:Verbose(
		"effect %d on %s change=%d (%d listener(s))",
		abilityId,
		tostring(unitTag),
		changeType,
		#listeners
	)
	for _, tracker in ipairs(listeners) do
		tracker:OnEffect(unitTag, abilityId, changeType, beginTime, endTime, stackCount)
	end
end

local function OnUpdate()
	local now = GetFrameTimeSeconds()
	for _, tracker in ipairs(QAT.runtime.list) do
		tracker:Tick(now)
	end
	-- After trackers have updated (so member visibility is current), lay out any grid
	-- groups: position placed members into cells and redraw the table chrome.
	if QAT.GridLayout_Update then
		QAT.GridLayout_Update()
	end
end

-- The distinct unit tags any loaded tracker watches (player, reticleover, ...).
local function unitsOfInterest()
	local set = {}
	for _, tracker in ipairs(QAT.runtime.list) do
		for _, phase in pairs(tracker.phases) do
			for _, tr in ipairs(phase.transitions) do
				if tr.when.kind == "effect" and tr.when.unit then
					set[tr.when.unit] = true
				end
			end
			if phase.duration.type == "effect" and phase.duration.unit then
				set[phase.duration.unit] = true
			end
		end
	end
	return set
end

-- Seed already-active effects. EVENT_EFFECT_CHANGED only fires on change, so a buff
-- that is already up when a tracker loads (after /reloadui, zone-in, slotting a
-- skill, or acquiring a target) would otherwise never be seen — the gap that left
-- permanent/passive buffs untrackable. We enumerate current buffs and feed matching
-- ones in as synthetic "gained" events.
function QAT.Runtime_ScanBuffs()
	-- Record which tracked effects are live on each unit while seeding "gained", so a
	-- phase held up by an effect that vanished without a "faded" event can be ended.
	local present = {}
	for unit in pairs(unitsOfInterest()) do
		present[unit] = {}
		if DoesUnitExist(unit) then
			for i = 1, GetNumBuffs(unit) do
				local _, started, ending, _, stackCount, _, _, _, _, _, abilityId = GetUnitBuffInfo(unit, i)
				local listeners = abilityId and QAT.runtime.byAbilityId[abilityId]
				if listeners then
					present[unit][abilityId] = true
					for _, tracker in ipairs(listeners) do
						tracker:OnEffect(unit, abilityId, EFFECT_RESULT_GAINED, started, ending, stackCount)
					end
				end
			end
		end
	end
	for _, tracker in ipairs(QAT.runtime.list) do
		tracker:ReconcilePresence(present)
	end
end

-- One filtered EVENT_EFFECT_CHANGED per distinct tracked ability id.
local function RegisterEffectFilters()
	for abilityId in pairs(QAT.runtime.byAbilityId) do
		local evName = QAT.name .. "_eff_" .. abilityId
		EVENT_MANAGER:UnregisterForEvent(evName, EVENT_EFFECT_CHANGED)
		EVENT_MANAGER:RegisterForEvent(evName, EVENT_EFFECT_CHANGED, OnEffectChanged)
		EVENT_MANAGER:AddFilterForEvent(evName, EVENT_EFFECT_CHANGED, REGISTER_FILTER_ABILITY_ID, abilityId)
	end
end

-- Build Tracker objects from a list of defs. Folders are pass-through containers
-- (no display) that carry a screen anchor; their members are positioned relative to
-- it, and their load defs cascade to children via the loadChain.
local function BuildTrackers(defs, parentLoads, anchor)
	anchor = anchor or { x = 0, y = 0 }
	for _, def in ipairs(defs or {}) do
		if def.enabled == false then
			-- A disabled tracker or folder is skipped entirely (a disabled folder
			-- disables its whole subtree). Its controls were hidden before rebuild.
		elseif def.kind == "folder" then
			local childLoads = QAT.util.DeepCopy(parentLoads)
			if def.load then
				table.insert(childLoads, def.load)
			end
			-- A group's own anchor is its position relative to its parent; children
			-- inherit the accumulated absolute anchor.
			local gp = def.pos or { x = 0, y = 0 }
			local childAnchor = { x = anchor.x + (gp.x or 0), y = anchor.y + (gp.y or 0) }
			-- A group arranged as a table registers its grid so the layout pass can draw
			-- the chrome and place members. The same chain gates the whole table; the
			-- anchor gives the table its absolute screen origin.
			local isDynamic = def.grid and def.grid.enabled and def.grid.dynamic and def.grid.dynamic.source
			if def.grid and def.grid.enabled and QAT.GridLayout_Register then
				QAT.GridLayout_Register(def, childLoads, anchor)
			end
			-- A dynamic group's children are its template, not independent trackers: the
			-- layout pass instances the template per live target, so don't build them here.
			if not isDynamic then
				BuildTrackers(def.children, childLoads, childAnchor)
			end
		else
			local chain = QAT.util.DeepCopy(parentLoads)
			if def.load then
				table.insert(chain, def.load)
			end

			local tracker = QAT.Tracker.New(def, chain, anchor)
			QAT.runtime.trackers[def.id] = tracker
			table.insert(QAT.runtime.list, tracker)
			for id in pairs(tracker:AbilityIds()) do
				QAT.runtime.byAbilityId[id] = QAT.runtime.byAbilityId[id] or {}
				table.insert(QAT.runtime.byAbilityId[id], tracker)
			end
		end
	end
end

-- Is a tracker a member of a grid-enabled group? Grid members are positioned by the
-- layout pass, so they are never hand-draggable.
local function isGridMember(id)
	local function scan(defs, inGrid)
		for _, def in ipairs(defs or {}) do
			if def.kind == "folder" then
				if scan(def.children, inGrid or (def.grid and def.grid.enabled)) then
					return true
				end
			elseif def.id == id then
				return inGrid or false
			end
		end
		return false
	end
	return scan(QAT.sv.trackers, false)
end
QAT.Runtime_IsGridMember = isGridMember

-- Only the tree-selected node is draggable on the HUD, so a stray click never moves
-- the wrong tracker. This arms exactly the selected tracker's controls (or none, when
-- a group / grid member / nothing is selected — a selected group is dragged via its
-- editor outline handle instead; see Display/GroupOutline).
function QAT.Runtime_ApplyDragSelection()
	local movable = QAT.trackersMovable
	local selId = movable and QAT.editor and QAT.editor.selectedId or nil
	local selScope = QAT.editor and QAT.editor.selectedScope
	-- A tracker is grabbable only when it (not a phase-sibling) is the selected node and
	-- it is not laid out by a grid.
	local dragId = nil
	if selId and QAT.runtime.trackers[selId] and not isGridMember(selId) then
		dragId = selId
	end
	for id, tracker in pairs(QAT.runtime.trackers) do
		local on = movable and id == dragId
		for _, phase in pairs(tracker.phases) do
			phase.control.tlw:SetMouseEnabled(on)
		end
	end
	-- Show the drag outline for a selected group (folder), hide it otherwise.
	if QAT.GroupOutline_Show then
		local groupId = (movable and selScope ~= nil and selId and not QAT.runtime.trackers[selId]) and selId or nil
		QAT.GroupOutline_Show(groupId)
	end
end

-- Enable/disable on-HUD dragging, driven by the editor's open/closed state so
-- trackers don't eat the mouse during play. Actual per-control arming is delegated to
-- the selection (only the selected node is movable).
function QAT.Runtime_SetTrackersMovable(on)
	QAT.trackersMovable = on and true or false
	QAT.Runtime_ApplyDragSelection()
end

-- Move a tracker's live controls to a new position RELATIVE to its parent group
-- anchor, without a rebuild (used by the editor's position fields and the on-HUD
-- drag). Top-level trackers have a zero anchor, so this is their absolute position.
function QAT.Runtime_RepositionTracker(id, x, y)
	local tracker = QAT.runtime.trackers[id]
	if not tracker then
		return
	end
	tracker:SetRelativePosition(x, y)
end

-- Place a tracker's live controls at an absolute screen position, bypassing the
-- anchor/offset math. Used by the grid layout pass (cell positions are screen-space).
function QAT.Runtime_PlaceTrackerAbsolute(id, x, y)
	local tracker = QAT.runtime.trackers[id]
	if tracker then
		tracker:PlaceAbsolute(x, y)
	end
end

-- Recompute every live tracker's parent anchor from the current def tree and re-place
-- it. Called after a group's position changes so all its members follow as one unit.
local function reanchor(defs, ax, ay)
	for _, def in ipairs(defs or {}) do
		if def.enabled ~= false then
			if def.kind == "folder" then
				local p = def.pos or { x = 0, y = 0 }
				reanchor(def.children, ax + (p.x or 0), ay + (p.y or 0))
			else
				local t = QAT.runtime.trackers[def.id]
				if t then
					t:SetAnchor(ax, ay)
				end
			end
		end
	end
end

function QAT.Runtime_ReanchorAll()
	reanchor(QAT.sv.trackers, 0, 0)
end

-- Pull every top-level group back on screen if it (or its members) drifted off. Only
-- top-level groups need clamping — their box encloses any nested content. Called once
-- after the initial build so a group saved off-screen becomes reachable again.
function QAT.Runtime_ClampAllGroups()
	if not QAT.GroupOutline_ClampToScreen then
		return
	end
	local moved = false
	for _, def in ipairs(QAT.sv.trackers or {}) do
		if def.kind == "folder" and QAT.GroupOutline_ClampToScreen(def.id) then
			moved = true
		end
	end
	if moved then
		QAT.Runtime_ReanchorAll()
	end
end

-- Move a group to a new position relative to its parent (its members follow). The
-- def is updated by the caller; this just re-places the live controls.
function QAT.Runtime_RepositionGroup(_, _, _)
	QAT.Runtime_ReanchorAll()
end

-- Re-evaluate every tracker's load conditions.
function QAT.Runtime_RefreshLoad()
	for _, tracker in ipairs(QAT.runtime.list) do
		tracker:RefreshLoad()
	end
end

-- Load conditions are checked on the events that can change them (not polled).
-- A short debounce coalesces bursts (e.g. swapping a full gear set).
local loadCheckPending = false
local function RequestLoadRecompute()
	if loadCheckPending then
		return
	end
	loadCheckPending = true
	zo_callLater(function()
		loadCheckPending = false
		QAT.log.runtime:Debug("load recompute (debounced)")
		QAT.Runtime_RefreshLoad()
		QAT.Runtime_ScanBuffs() -- catch passives that became relevant (e.g. skill slotted)
	end, 100)
end

-- A target changed: re-seed target-unit effects (debuffs already on the new target).
local function OnTargetChanged()
	QAT.Safe("scan buffs (target)", QAT.Runtime_ScanBuffs)
end

local function RegisterLoadEvents()
	local events = {
		EVENT_SKILLS_FULL_UPDATE,
		EVENT_ACTION_SLOTS_ALL_HOTBARS_UPDATED, -- skill slotted in/out
		EVENT_ACTIVE_WEAPON_PAIR_CHANGED, -- bar swap (current-bar set mode)
		EVENT_INVENTORY_SINGLE_SLOT_UPDATE, -- gear changes
		EVENT_PLAYER_ACTIVATED, -- zone load
		EVENT_BOSSES_CHANGED, -- boss conditions
		EVENT_PLAYER_COMBAT_STATE, -- in-combat conditions
	}
	for _, ev in ipairs(events) do
		EVENT_MANAGER:RegisterForEvent(QAT.name .. "_load", ev, RequestLoadRecompute)
	end
	EVENT_MANAGER:RegisterForEvent(QAT.name .. "_target", EVENT_RETICLE_TARGET_CHANGED, OnTargetChanged)
	EVENT_MANAGER:AddFilterForEvent(
		QAT.name .. "_load",
		EVENT_INVENTORY_SINGLE_SLOT_UPDATE,
		REGISTER_FILTER_INVENTORY_UPDATE_REASON,
		INVENTORY_UPDATE_REASON_DEFAULT
	)
end

function QAT.Runtime_Init()
	if QAT.GridLayout_Reset then
		QAT.GridLayout_Reset()
	end
	BuildTrackers(QAT.sv.trackers, {})

	RegisterEffectFilters()
	RegisterLoadEvents()

	for _, tracker in ipairs(QAT.runtime.list) do
		tracker:Start() -- evaluates load conditions, enters initial phase if loaded
	end
	QAT.Runtime_ScanBuffs() -- seed already-active effects
	QAT.Runtime_ClampAllGroups() -- pull any off-screen group back into view

	EVENT_MANAGER:UnregisterForUpdate(QAT.name .. "_tick")
	EVENT_MANAGER:RegisterForUpdate(QAT.name .. "_tick", TICK_MS, OnUpdate)

	QAT.log.runtime:Info(
		"runtime up: %d tracker(s), %d ability filter(s)",
		#QAT.runtime.list,
		NonContiguousCount(QAT.runtime.byAbilityId)
	)
end

-- Rebuild all live trackers from the current saved defs. Used when the editor
-- changes a def, so the on-screen trackers update without a reload. Display
-- controls are reused by name (see Display.Create), so this neither leaks nor
-- collides; it only swaps the in-memory Tracker objects and event filters.
local function rebuildAll()
	-- Suppress on-enter cues for the duration of the rebuild: Start()/ScanBuffs()
	-- below re-enter each tracker's live phase to restore state, which must not
	-- replay sounds/flashes. Real transitions fire later via events.
	QAT.runtime.suppressCues = true

	-- Hide every current phase control so removed trackers/phases don't linger.
	for _, tracker in ipairs(QAT.runtime.list) do
		for _, phase in pairs(tracker.phases) do
			phase.control:SetState(false)
		end
	end

	-- Drop the per-ability effect subscriptions before rebuilding the index.
	for abilityId in pairs(QAT.runtime.byAbilityId) do
		EVENT_MANAGER:UnregisterForEvent(QAT.name .. "_eff_" .. abilityId, EVENT_EFFECT_CHANGED)
	end

	QAT.runtime.trackers = {}
	QAT.runtime.list = {}
	QAT.runtime.byAbilityId = {}
	if QAT.GridLayout_Reset then
		QAT.GridLayout_Reset()
	end

	BuildTrackers(QAT.sv.trackers, {})
	RegisterEffectFilters()
	for _, tracker in ipairs(QAT.runtime.list) do
		tracker:Start()
	end
	QAT.Runtime_ScanBuffs()
	QAT.runtime.suppressCues = false
	QAT.Runtime_ApplyDragSelection() -- re-arm dragging for the selected node
	QAT.log.runtime:Debug("runtime rebuilt: %d tracker(s)", #QAT.runtime.list)
end

-- Coalesce rapid edits (e.g. typing) into one rebuild.
local rebuildPending = false
function QAT.Runtime_RequestRebuild()
	if rebuildPending then
		return
	end
	rebuildPending = true
	zo_callLater(function()
		rebuildPending = false
		QAT.Safe("runtime rebuild", rebuildAll)
	end, 80)
end

-- A def changed in the editor: rebuild the affected runtime. (A full rebuild is
-- simple and cheap at these counts; per-tracker rebuild can come later.)
CALLBACK_MANAGER:RegisterCallback("QAT_TrackerChanged", function()
	if QAT.runtime then
		QAT.Runtime_RequestRebuild()
	end
end)
