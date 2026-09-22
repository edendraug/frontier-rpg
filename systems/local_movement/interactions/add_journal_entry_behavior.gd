class_name AddJournalEntryBehavior
extends InteractionBehavior

## Adds a named entry to the player's journal by id. STUBBED: no
## Journal system exists yet, so this just warns rather than silently
## no-oping -- same posture as TriggerEventBehavior's own stub. Wire
## the real journal write in once that system exists; nothing about
## WorldInteractable or this class's own shape (one type, parameterized
## by entry_id, reusable across many .tres instances) should need to
## change when it does.

@export var entry_id: String = ""


func execute(_character: CharacterController, interactable: WorldInteractable) -> void:
	if entry_id.is_empty():
		push_warning("AddJournalEntryBehavior on '%s' has no entry_id set" % interactable.name)
		return
	push_warning("AddJournalEntryBehavior: would add journal entry '%s' -- not yet wired to a Journal system" % entry_id)
