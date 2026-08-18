extends RefCounted

## Minimal example CUSTOM DialogueCondition script. Exists purely to
## validate the proposed-but-unconfirmed signature from design doc
## Section 4.8:
##
##   evaluate(actor: ActorDefinition, player_state: Variant) -> bool
##
## Always returns true - this proves DialogueConditionResolver can
## instantiate and call an external script correctly, not a real
## gameplay condition. player_state arrives as the full DialogueContext
## (see DialogueConditionResolver's CUSTOM case), not just a
## CharacterSheet, so a real CUSTOM condition can reach
## player_character/registry/rng if it needs to.

func evaluate(actor: ActorDefinition, player_state) -> bool:
	var actor_label := actor.actor_id if actor != null else "<none>"
	print("[CUSTOM condition] evaluated for actor '%s' -> true" % actor_label)
	return true
