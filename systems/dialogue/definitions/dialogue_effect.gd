@tool
class_name DialogueEffect
extends Resource

## A single consequence fired when a dialogue Option or skill-check
## branch is taken. Same typed-vocabulary pattern as DialogueCondition
## and ModifierEntry: a closed `type` enum plus generic `target`/`value`
## fields whose meaning depends on the type.
##
## Effects fire the instant their branch is determined and are treated
## as committed (Section 5.2 of the design doc). Dialogue never mutates
## a CharacterSheet or shop inventory directly - it only fires the
## effect and lets the owning system (PartyManager, RelationsSystem,
## InventorySystem, etc.) act on it.
##
## Field meaning by type:
##   FACTION_REPUTATION_DELTA   target = faction_id   value = delta applied to reputation
##   REVEAL_ACTOR_NAME          target = actor_id (empty = current speaking actor)
##   MORALE_EVENT               target = MoraleEventInstance id/preset
##   GRANT_ITEM                 target = item_id      value = quantity
##   START_PRESET               target = preset id (e.g. "bartering")
##   TRIGGER_RECRUITMENT        target = actor_id (empty = current speaking actor)
##   CUSTOM                     custom_script.apply(actor, player_state) -> void
##                               Signature proposed in the design doc, not yet validated
##                               against a real implementation - confirm before relying on it.

enum Type {
	FACTION_REPUTATION_DELTA,
	REVEAL_ACTOR_NAME,
	MORALE_EVENT,
	GRANT_ITEM,
	START_PRESET,
	TRIGGER_RECRUITMENT,
	CUSTOM,
}

@export var type: Type = Type.REVEAL_ACTOR_NAME
@export var target: String = ""
@export var value: float = 0.0

## Only used when type == CUSTOM. Must implement:
##   apply(actor: ActorDefinition, player_state: Variant) -> void
@export var custom_script: Script = null
