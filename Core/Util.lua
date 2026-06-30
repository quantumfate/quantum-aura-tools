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

-- Build a lookup set { [value] = true } from an array.
function QAT.util.ToSet(arr)
	local set = {}
	for _, v in ipairs(arr or {}) do
		set[v] = true
	end
	return set
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
