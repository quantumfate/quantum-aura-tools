-- Curated catalog of textures for the "graphic" display kind, so authors pick from a
-- thumbnailed menu instead of hunting .dds paths. Each entry is
-- { path=<esoui texture>, label=<short name> }; the picker previews `path` directly.
-- Authors who need a texture outside this list can type a raw path in the graphic
-- picker's custom field (or, for proc/stack art, follow an ability icon on the Icon
-- kind, or bundle custom .dds art with the addon).
--
-- Only paths verified to resolve in-game live here; add new ones once confirmed via the
-- thumbnailed picker (a blank thumbnail means the path is wrong).

QAT.textures = {
	{ path = "/esoui/art/icons/mapkey/mapkey_groupboss.dds", label = "Boss skull" },
	{ path = "/esoui/art/icons/mapkey/mapkey_groupmember.dds", label = "Group dot" },
	{ path = "/esoui/art/icons/mapkey/mapkey_crafting.dds", label = "Crafting" },
	{ path = "EsoUI/Art/ActionBar/abilityHighlightAnimation.dds", label = "Proc glow" },
}

-- User-added textures (managed in the settings panel) extend the picker. Each entry is
-- { label, path }; stored on the account SavedVars so they persist per install.
function QAT.CustomTextures_List()
	return (QAT.sv and QAT.sv.account.customTextures) or {}
end

-- The full picker list: built-in catalog followed by the user's own entries.
function QAT.AllTextures()
	local all = {}
	for _, t in ipairs(QAT.textures) do
		all[#all + 1] = t
	end
	for _, t in ipairs(QAT.CustomTextures_List()) do
		if t.path and t.path ~= "" then
			all[#all + 1] = { path = t.path, label = (t.label ~= nil and t.label ~= "") and t.label or t.path }
		end
	end
	return all
end

-- Serialize the user list for the settings editbox: one "Label = path" per line.
function QAT.CustomTextures_Serialize()
	local lines = {}
	for _, t in ipairs(QAT.CustomTextures_List()) do
		lines[#lines + 1] = string.format("%s = %s", t.label or "", t.path or "")
	end
	return table.concat(lines, "\n")
end

-- Parse the settings editbox back into the user list. Each non-empty line is
-- "Label = path"; a line with no "=" is treated as a bare path (label = path).
function QAT.CustomTextures_Parse(text)
	local list = {}
	for line in tostring(text or ""):gmatch("[^\r\n]+") do
		local label, path = line:match("^%s*(.-)%s*=%s*(.-)%s*$")
		if not path then
			label, path = nil, line:match("^%s*(.-)%s*$")
		end
		if path and path ~= "" then
			list[#list + 1] = { label = (label ~= nil and label ~= "") and label or path, path = path }
		end
	end
	if QAT.sv then
		QAT.sv.account.customTextures = list
	end
	return list
end
