class_name DialogueEffectResolver
extends RefCounted

## Applies the DialogueEffect types that map onto a clear, already-
## reviewed system call. START_PRESET, TRIGGER_RECRUITMENT, and
## MORALE_EVENT are deliberately NOT handled here - see
## DialoguePlayer._fire_one_effect(). START_PRESET needs the runner's
## own Preset call stack; TRIGGER_RECRUITMENT and MORALE_EVENT depend
## on PartyManager/VitalsSystem APIs not yet reviewed in this session.

## actor_id: the Actor this effect fired in relation to (the current
## speaker) - default target for effects whose own `target` is empty.
static func apply(effect: DialogueEffect, actor_id: String, context: DialogueContext) -> void:
	match effect.type:
		DialogueEffect.Type.FACTION_REPUTATION_DELTA:
			RelationsSystem.apply_faction_reputation_delta(effect.target, effect.value)

		DialogueEffect.Type.REVEAL_ACTOR_NAME:
			var target_id: String = effect.target if not effect.target.is_empty() else actor_id
			RelationsSystem.reveal_actor_name(target_id)

		DialogueEffect.Type.GRANT_ITEM:
			InventorySystem.add_item(effect.target, int(effect.value))

		DialogueEffect.Type.CUSTOM:
			if effect.custom_script == null:
				push_warning("DialogueEffectResolver: CUSTOM effect with no custom_script, ignoring")
				return
			var instance: Object = effect.custom_script.new()
			instance.apply(RelationsSystem.get_actor_definition(actor_id), context)

		DialogueEffect.Type.MORALE_EVENT, DialogueEffect.Type.TRIGGER_RECRUITMENT, DialogueEffect.Type.START_PRESET:
			push_warning("DialogueEffectResolver: %s must be routed through DialoguePlayer, not this resolver" % DialogueEffect.Type.keys()[effect.type])
