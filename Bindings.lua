-- Keybind handlers (native ZOS keybinds; see Bindings.xml).

--- Show or hide the tracker editor window.
function QAT_ToggleEditor()
	if QAT.Editor_Toggle then
		QAT.Editor_Toggle()
	else
		d(QAT.displayName .. ": editor unavailable.")
	end
end

--- Show or hide the effect aggregator window.
function QAT_ToggleAggregator()
	if QAT.Aggregator_Toggle then
		QAT.Aggregator_Toggle()
	else
		d(QAT.displayName .. ": aggregator unavailable.")
	end
end
