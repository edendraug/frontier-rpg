class_name DialogueConditionResolver
extends RefCounted

## Evaluates a DialogueCondition/ConditionSet AND-list (design doc
## Section 4.7 - AND-list only, no first-class OR/NOT) against the
## systems Dialogue is allowed to ask: RelationsSystem, InventorySystem,
## CharacterSheet. Never reimplements what those systems already know.

## entries: the mixed Array from DialogueOption.conditions or
## DialogueChoiceNode.conditions - each element is either a
## DialogueCondition or a ConditionSet.
## actor_id: the Actor currently being spoken to - default target for
## ACTOR_ALIGNMENT_IS/ACTOR_KNOWN when a condition's own target is left
## empty.
## state: that Actor's ActorState (for PREVIOUS_OPTION_TAKEN).
static func evaluate_all(entries: Array, actor_id: String, state: ActorState, context: DialogueContext) -> bool:
	for entry in entries:
		if entry is ConditionSet:
			if not evaluate_all(entry.conditions, actor_id, state, context):
				return false
		elif entry is DialogueCondition:
			if not _evaluate_one(entry, actor_id, state, context):
				return false
		else:
			push_warning("DialogueConditionResolver: unexpected entry type in condition list, skipping")
	return true


static func _evaluate_one(condition: DialogueCondition, actor_id: String, state: ActorState, context: DialogueContext) -> bool:
	match condition.type:
		DialogueCondition.Type.FACTION_REPUTATION_AT_LEAST:
			return RelationsSystem.get_faction_reputation(condition.target) >= condition.threshold

		DialogueCondition.Type.ACTOR_ALIGNMENT_IS:
			var def := RelationsSystem.get_actor_definition(actor_id)
			if def == null:
				return false
			return def.get_alignment(condition.target) == int(condition.threshold)

		DialogueCondition.Type.ACTOR_KNOWN:
			var target_id: String = condition.target if not condition.target.is_empty() else actor_id
			return RelationsSystem.is_actor_known(target_id)

		DialogueCondition.Type.HAS_TRAIT:
			return context.player_character != null and context.player_character.has_trait(condition.target)

		DialogueCondition.Type.HAS_SKILL_RANK_AT_LEAST:
			if context.player_character == null:
				return false
			var progress: SkillProgress = context.player_character.get_skill(condition.target)
			# No SkillProgress at all means the character has never
			# touched this skill - equivalent to the lowest rank
			# (UNSKILLED), not a missing-reference case worth warning
			# about, so this just fails the threshold normally rather
			# than treating it as an error.
			if progress == null:
				return false
			return progress.get_rank() >= int(condition.threshold)

		DialogueCondition.Type.HAS_ITEM:
			var qty: int = int(condition.threshold) if condition.threshold > 0 else 1
			return InventorySystem.has_item(condition.target, qty)

		DialogueCondition.Type.PREVIOUS_OPTION_TAKEN:
			return state != null and state.has_taken_option(condition.target)

		DialogueCondition.Type.CUSTOM:
			if condition.custom_script == null:
				push_warning("DialogueConditionResolver: CUSTOM condition with no custom_script, treating as false")
				return false
			var instance: Object = condition.custom_script.new()
			return instance.evaluate(RelationsSystem.get_actor_definition(actor_id), context)

	return false
