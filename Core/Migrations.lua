-- Versioned schema migrations.
--
-- Each step migrates the saved data from version N to N+1. On load,
-- QAT.RunMigrations applies every step whose index >= the stored schemaVersion,
-- in order, then stamps the data with QAT.schemaVersion.
--
--   QAT.migrations[1] = function(sv) ... end  -- migrate schema 1 -> 2
--   QAT.migrations[2] = function(sv) ... end  -- migrate schema 2 -> 3

QAT.migrations = {
	-- No migrations yet; v0.1.0 ships at schema 1.
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
