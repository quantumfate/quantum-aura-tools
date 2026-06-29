-- Logging layer over LibDebugLogger (optional dependency).
--
-- Sub-loggers per subsystem so the in-game LibDebugLogger viewer can filter by
-- area. Everything degrades to a no-op when LibDebugLogger isn't installed, so
-- call sites never need to nil-check.
--
-- Use for iterative troubleshooting: set the logger's min level in LibDebugLogger,
-- reproduce, then export the log and hand it back for analysis.

local function noop() end
-- Any method access on NULL returns a no-op function.
local NULL = setmetatable({}, {
	__index = function()
		return noop
	end,
})

QAT.log = {
	root = NULL,
	engine = NULL,
	editor = NULL,
	conditions = NULL,
	runtime = NULL,
	capture = NULL,
}

function QAT.SetupLogging()
	if not LibDebugLogger then
		return
	end
	-- LibDebugLogger has shipped both LibDebugLogger.Create(name) and the callable
	-- form LibDebugLogger(name); support either, and never let logging break load.
	local ok, root = pcall(function()
		return (LibDebugLogger.Create and LibDebugLogger.Create(QAT.name)) or LibDebugLogger(QAT.name)
	end)
	if not ok or not root then
		return
	end

	local function sub(name)
		local ok2, logger = pcall(function()
			return root:Create(name)
		end)
		return (ok2 and logger) or root
	end

	QAT.log.root = root
	QAT.log.engine = sub("Engine")
	QAT.log.editor = sub("Editor")
	QAT.log.conditions = sub("Conditions")
	QAT.log.runtime = sub("Runtime")
	QAT.log.capture = sub("Capture")
end

-- Backwards-compatible top-level info logger used by early code/migrations.
function QAT.Log(...)
	QAT.log.root:Info(...)
end

-- Run fn under pcall; on error, log it (with subsystem context) and surface a
-- short chat note instead of bricking addon load. Returns ok, result.
function QAT.Safe(label, fn)
	local ok, err = pcall(fn)
	if not ok then
		QAT.log.root:Error("%s failed: %s", label, tostring(err))
		d(QAT.displayName .. " error in " .. label .. ": " .. tostring(err))
	end
	return ok, err
end
