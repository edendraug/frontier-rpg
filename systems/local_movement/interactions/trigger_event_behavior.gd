class_name TriggerEventBehavior
extends InteractionBehavior

## Triggers a named event by id. STUBBED: no Event/Encounter system
## exists yet to actually consume event_id, so this just warns rather
## than silently no-oping -- same posture as DialogueEffectResolver's
## own MORALE_EVENT stub. Wire the real lookup/dispatch in once that
## system exists; nothing about WorldInteractable or this class's own
## shape (one type, parameterized by event_id, reusable across many
## .tres instances) should need to change when it does.

@export var event_id: String = ""


func execute(_character: CharacterController, interactable: WorldInteractable) -> void:
	if event_id.is_empty():
		push_warning("TriggerEventBehavior on '%s' has no event_id set" % interactable.name)
		return
	push_warning("TriggerEventBehavior: would trigger event '%s' -- not yet wired to an Event system" % event_id)
