class_name InteractionBehavior
extends Resource

## Base for a small, reusable, Inspector-assignable "what happens when
## a WorldInteractable is interacted with" behavior. Write a small
## script extending this, override execute(), save it as a .tres, and
## drag it into any WorldInteractable's custom_behaviors array.
##
## Deliberately kept single-purpose per subclass rather than one
## bloated behavior with a field for every possible effect -- several
## small behaviors compose on one interactable (e.g. an entry added to
## the journal AND an event triggered from the same signpost) without
## needing a combined "does both" class. The same @export-parameterized
## reuse this project already gets from Skill/Trait/Occupation
## Definitions, applied here to behavior instead of static data: one
## TriggerEventBehavior TYPE, many different .tres instances (one per
## event_id), not one class per event.

func execute(_character: CharacterController, _interactable: WorldInteractable) -> void:
	pass
