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
