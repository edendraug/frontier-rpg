class_name DialogueCondition
extends Resource

## A single gating check for a dialogue Option or Choice node.
##
## Mirrors the typed-vocabulary pattern already used by ModifierEntry:
## a closed `type` enum plus generic `target`/`threshold` fields whose
## meaning depends on which type is selected. Combined into an AND-list
## by whatever holds them (DialogueOption.conditions, a Choice node's
## own gate list) or reused across many trees via ConditionSet.
##
## Field meaning by type:
##   FACTION_REPUTATION_AT_LEAST   target = faction_id       threshold = minimum reputation
##   ACTOR_ALIGNMENT_IS            target = faction_id       threshold = required alignment (-1/0/1)
##                                  (checked against the actor currently being spoken to)
##   ACTOR_KNOWN                   target = actor_id (empty = current speaking actor)
##   HAS_TRAIT                     target = trait_id
##   HAS_ITEM                      target = item_id          threshold = minimum quantity (default 1)
##   PREVIOUS_OPTION_TAKEN         target = option_id
##   CUSTOM                        custom_script.evaluate(actor, player_state) -> bool
##                                  Signature proposed in the design doc, not yet validated
##                                  against a real implementation - confirm before relying on it.

enum Type {
	FACTION_REPUTATION_AT_LEAST,
	ACTOR_ALIGNMENT_IS,
	ACTOR_KNOWN,
	HAS_TRAIT,
	HAS_ITEM,
	PREVIOUS_OPTION_TAKEN,
	CUSTOM,
}

@export var type: Type = Type.HAS_TRAIT
@export var target: String = ""
@export var threshold: float = 0.0

## Only used when type == CUSTOM. Must implement:
##   evaluate(actor: ActorDefinition, player_state: Variant) -> bool
@export var custom_script: Script = null
