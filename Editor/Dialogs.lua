-- Editor dialogs: a first-run hint when adding a tracker, and a delete confirm.
-- Dialogs are registered lazily on first use (the dialog system is ready by then)
-- and read their per-fire data from dialog.data.

local ADD_HINT = "QAT_AddTrackerHint"
local DELETE_CONFIRM = "QAT_DeleteConfirm"

local registered = false
local function ensureRegistered()
	if registered then
		return
	end
	registered = true

	ZO_Dialogs_RegisterCustomDialog(ADD_HINT, {
		title = { text = QAT.displayName },
		mainText = {
			text = "Trackers are hidden until their effect is gained — a new tracker starts on a hidden 'idle' phase and only shows once it triggers.\n\nIf you want a tracker to be visible at all times, delete its 'idle' phase.",
		},
		buttons = {
			{
				text = "Okay",
				callback = function() end,
			},
			{
				text = "Okay, don't show again",
				callback = function()
					QAT.sv.account.addTrackerHintSeen = true
				end,
			},
		},
	})

	ZO_Dialogs_RegisterCustomDialog(DELETE_CONFIRM, {
		title = { text = "Delete" },
		mainText = { text = 'Delete "<<1>>"? This cannot be undone.' },
		buttons = {
			{
				text = "Delete",
				callback = function(dialog)
					if dialog.data and dialog.data.onConfirm then
						dialog.data.onConfirm()
					end
				end,
			},
			{
				text = "Cancel",
				callback = function() end,
			},
		},
	})
end

-- Show the "trackers start hidden" hint once (until the user dismisses it for good).
function QAT.Editor_ShowAddTrackerHint()
	if QAT.sv and QAT.sv.account.addTrackerHintSeen then
		return
	end
	ensureRegistered()
	ZO_Dialogs_ShowDialog(ADD_HINT)
end

-- Confirm deletion of a named node; runs onConfirm only if the user confirms.
function QAT.Editor_ConfirmDelete(name, onConfirm)
	ensureRegistered()
	ZO_Dialogs_ShowDialog(DELETE_CONFIRM, { onConfirm = onConfirm }, { mainTextParams = { name } })
end
