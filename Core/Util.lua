-- Small shared helpers.

QAT.util = {}

-- Deep copy a plain-data table (no metatables / no cycles — fine for tracker defs).
function QAT.util.DeepCopy(t)
	if type(t) ~= "table" then
		return t
	end
	local out = {}
	for k, v in pairs(t) do
		out[k] = QAT.util.DeepCopy(v)
	end
	return out
end

-- Resolve a phase's icon: an explicit look.icon override, else the game icon of
-- the first tracked ability id (duration or an effect transition), else nil.
function QAT.util.PhaseIcon(phase)
	if phase.look and phase.look.icon and phase.look.icon ~= "" then
		return phase.look.icon
	end
	local sources = { phase.duration and phase.duration.abilityIds }
	for _, tr in ipairs(phase.transitions or {}) do
		if tr.when and tr.when.kind == "effect" then
			table.insert(sources, tr.when.abilityIds)
		end
	end
	for _, ids in ipairs(sources) do
		for _, id in ipairs(ids or {}) do
			local ic = GetAbilityIcon(id)
			if ic and ic ~= "" then
				return ic
			end
		end
	end
	return nil
end

-- Resolve an ability id to a display name and icon for the editor. Ids are
-- meaningless to users, so anywhere one is shown it should be paired with these.
-- Falls back gracefully: a 0/nil id reads as "(none)", an unknown id keeps its
-- number so a mistyped id is still identifiable.
---@param id number|nil ability id
---@return string name, string icon
function QAT.util.AbilityInfo(id)
	if not id or id == 0 then
		return "(none)", "/esoui/art/icons/icon_missing.dds"
	end
	local name = GetAbilityName(id)
	if not name or name == "" then
		name = "#" .. id
	end
	local icon = GetAbilityIcon(id)
	if not icon or icon == "" then
		icon = "/esoui/art/icons/icon_missing.dds"
	end
	return name, icon
end

-- Build a lookup set { [value] = true } from an array.
function QAT.util.ToSet(arr)
	local set = {}
	for _, v in ipairs(arr or {}) do
		set[v] = true
	end
	return set
end

-- LibMediaProvider access (optional dep). Fonts registered by the user's media
-- addons become selectable per phase; everything degrades gracefully if the lib or
-- a font is missing.
local function getLMP()
	if LibMediaProvider then
		return LibMediaProvider
	end
	if LibStub then
		local ok, lib = pcall(LibStub, "LibMediaProvider-1.0", true)
		if ok then
			return lib
		end
	end
	return nil
end

--- The list of registered font family names (sorted by the lib), or {} if none.
function QAT.util.FontList()
	local lmp = getLMP()
	if lmp and lmp.List then
		local ok, list = pcall(lmp.List, lmp, "font")
		if ok and list then
			return list
		end
	end
	return {}
end

--- Resolve a font family name to a usable font face path, or nil for the default.
function QAT.util.FontFace(name)
	if not name or name == "" then
		return nil
	end
	local lmp = getLMP()
	if lmp and lmp.Fetch then
		local ok, path = pcall(lmp.Fetch, lmp, "font", name)
		if ok and path and path ~= "" then
			return path
		end
	end
	return nil
end

-- Collect the distinct ability ids referenced by a list of tracker defs
-- (folders recurse into children). Returns { [abilityId] = { def, def, ... } }.
function QAT.util.IndexByAbilityId(defs, index)
	index = index or {}
	for _, def in ipairs(defs or {}) do
		if def.kind == "folder" then
			QAT.util.IndexByAbilityId(def.children, index)
		else
			for _, id in ipairs(def.abilityIds or {}) do
				index[id] = index[id] or {}
				table.insert(index[id], def)
			end
		end
	end
	return index
end
