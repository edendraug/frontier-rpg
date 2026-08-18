class_name ActorState
extends RefCounted

## Per-playthrough live state for a single Actor - kept structurally
## separate from ActorDefinition (Section 4.3), same reasoning as every
## other Definition/Instance split in this project: authored content
## and save data have different lifecycles and shouldn't be
## intermingled in one Resource. Owned by RelationsSystem, keyed by
## actor_id.
##
## RefCounted rather than Resource for now, since this has no file
## backing of its own - it only ever exists inside RelationsSystem's
## save data. to_dict()/from_dict() are provided so SaveManager can
## fold this into GameSaveData however that system already serializes
## everything else. That integration hasn't been reviewed yet, so
## treat this shape as a starting point, not final - flag it if
## SaveManager's actual convention wants something else.

var actor_id: String = ""
var is_known: bool = false

## option_id -> true. Presence means "has been taken at least once".
## Used both for consume_once removal and the repeatable
## already-picked treatment (Section 4.5).
var options_taken: Dictionary = {}

## node_id -> int index into that Line's variants array. Absent means
## "never shown" - relevant for sticky vs. reroll variant_mode
## (Section 4.4).
var last_shown_variant: Dictionary = {}


func _init(p_actor_id: String = "") -> void:
	actor_id = p_actor_id


func mark_known() -> void:
	is_known = true


func has_taken_option(option_id: String) -> bool:
	return options_taken.get(option_id, false)


func mark_option_taken(option_id: String) -> void:
	options_taken[option_id] = true


func get_last_variant(node_id: String) -> int:
	return last_shown_variant.get(node_id, -1)


func set_last_variant(node_id: String, variant_index: int) -> void:
	last_shown_variant[node_id] = variant_index


func to_dict() -> Dictionary:
	return {
		"actor_id": actor_id,
		"is_known": is_known,
		"options_taken": options_taken.duplicate(),
		"last_shown_variant": last_shown_variant.duplicate(),
	}


static func from_dict(data: Dictionary) -> ActorState:
	var state := ActorState.new(data.get("actor_id", ""))
	state.is_known = data.get("is_known", false)
	state.options_taken = data.get("options_taken", {}).duplicate()
	state.last_shown_variant = data.get("last_shown_variant", {}).duplicate()
	return state
