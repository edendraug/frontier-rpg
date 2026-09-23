class_name LeaveLocationBehavior
extends InteractionBehavior

## Assign this as one of a bespoke scene's "Leave" WorldInteractable's
## custom_behaviors. Continues whatever arrival-prompt sequence is
## still pending at this hex (further locations, or resuming Travel
## once none remain) -- or, for a debug-tab-triggered visit, reloads
## whichever ambient scene matches Travel's current state directly.
## See ExpeditionSceneRouter.leave_current_location()'s own comment for
## the full behavior.
##
## Pair with WorldInteractable.blocks_movement = false on the same
## node -- a doorway/exit marker should be walked ONTO, not stopped
## short of like a solid obstacle (Cameron's confirmed model).

func execute(_character: CharacterController, _interactable: WorldInteractable) -> void:
	ExpeditionSceneRouter.leave_current_location()
