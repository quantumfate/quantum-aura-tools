-- Keybind handlers (native ZOS keybinds; see Bindings.xml).

--- Show or hide the tracker editor window.
function QAT_ToggleEditor()
	if QAT.Editor_Toggle then
		QAT.Editor_Toggle()
	else
		d(QAT.displayName .. ": editor unavailable.")
	end
end
