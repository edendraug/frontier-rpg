extends RefCounted

## Minimal example CUSTOM DialogueEffect script. Exists purely to
## validate the proposed-but-unconfirmed signature from design doc
## Section 4.8:
##
##   apply(actor: ActorDefinition, player_state: Variant) -> void
##
## Just prints, to confirm DialogueEffectResolver actually reaches and
## calls this rather than demonstrating a real gameplay effect.

func apply(actor: ActorDefinition, player_state) -> void:
	var actor_label := actor.actor_id if actor != null else "<none>"
	print("[CUSTOM effect] fired for actor '%s'" % actor_label)
