class_name ActorDefinition
extends Resource

## Authored template data for a single NPC that dialogue owns: a
## shopkeeper, a trail encounter, a recruitable companion. Actor is
## explicitly NOT CharacterSheet - see design doc Section 3.1. A
## recruitable Actor only gets paired with a real CharacterSheet at
## the moment of recruitment, owned by PartyManager/onboarding, not by
## Dialogue.
##
## Discovered the same way SkillDefinition/TraitDefinition/
## OccupationDefinition already are: scanned from a known content
## folder by a registry, rather than hand-enumerated in code. See
## RelationsSystem, built to mirror CharacterDataRegistry's DirAccess
## scan pattern.
##
## Definition vs. Instance: this is the shared, regeneratable template.
## Per-playthrough state (known/unknown, per-Option memory) lives
## separately in ActorState, owned by RelationsSystem - see that file.

@export var actor_id: String = ""
@export var unknown_name: String = ""
@export var known_name: String = ""

## faction_id -> int (-1 opposed, 0 neutral/unassigned, 1 aligned).
## Sparse - a faction with no entry here is implicitly neutral (0), so
## "unassigned" and "neutral" collapse into one state.
##
## This is a static fact about this specific NPC ("this shopkeeper
## personally leans Settler"), authored once. It is NOT the same thing
## as player Faction Reputation, which lives on RelationsSystem and
## changes dynamically during play - do not conflate the two.
@export var faction_alignment: Dictionary = {}

## Which dialogue tree this Actor owns. May be empty for a mute or
## flavor-only NPC.
@export var dialogue_tree_id: String = ""

## emotion_tag -> Texture2D. Optional - an Actor may have zero entries.
## Convention: the "default" key covers the no-tag case.
@export var portraits: Dictionary = {}

## Reference only. Actual shop contents are owned externally (wherever
## the Bartering preset's data lives), not by Actor.
@export var shop_inventory_id: String = ""


func get_alignment(faction_id: String) -> int:
	return faction_alignment.get(faction_id, 0)


## Implements the Line Node portrait-resolution rules from Section 4.4:
## no portraits authored at all -> nothing, silently. No tag on the
## Line -> "default" if present, else nothing, silently. A tag not
## found on this Actor -> warn, then fall back to "default" if
## present, else nothing.
func get_portrait(emotion_tag: String = "") -> Texture2D:
	if portraits.is_empty():
		return null
	if emotion_tag.is_empty():
		return portraits.get("default", null)
	if portraits.has(emotion_tag):
		return portraits[emotion_tag]
	push_warning("ActorDefinition '%s': no portrait for emotion_tag '%s', falling back to default" % [actor_id, emotion_tag])
	return portraits.get("default", null)
