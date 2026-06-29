-- Keybind handlers (native ZOS keybinds; see Bindings.xml).

-- Toggles the tracker editor window. The editor itself arrives in M4; for now
-- this is a discoverable stub so the keybind exists and is rebindable.
function QAT_ToggleEditor()
	if QAT.Editor_Toggle then
		QAT.Editor_Toggle()
	else
		d(QAT.displayName .. ": the editor is not implemented yet (coming in a later milestone).")
	end
end
