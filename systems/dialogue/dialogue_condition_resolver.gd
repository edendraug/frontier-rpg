class_name DialogueConditionResolver
extends RefCounted

## Evaluates a DialogueCondition/ConditionSet list against the systems
## Dialogue is allowed to ask: RelationsSystem, InventorySystem,
## CharacterSheet. Never reimplements what those systems already know.
##
## AND/OR support (Dialogue Graph Node Restructure follow-up addendum,
## Section 5): the TOP-LEVEL list passed to evaluate_all() combines
## under whichever `mode` the caller supplies (AND by default, matching
## every call site from before this support existed). A ConditionSet
## entry's OWN internal list, however, is ALWAYS AND - that's
## ConditionSet's own definition, not something the wrapping mode
## should override, so the recursive call for one always passes
## DialogueConditionNode.Mode.AND explicitly regardless of the outer
## mode. Reuses DialogueConditionNode's own Mode enum rather than
## defining a second, parallel one.

## entries: the mixed Array from a DialogueConditionNode's own
## `conditions` (or, recursively, a ConditionSet's) - each element is
## either a DialogueCondition or a ConditionSet.
## actor_id: the Actor currently being spoken to - default target for
## ACTOR_ALIGNMENT_IS/ACTOR_KNOWN when a condition's own target is left
## empty.
## state: that Actor's ActorState (for PREVIOUS_OPTION_TAKEN).
static func evaluate_all(entries: Array, actor_id: String, state: ActorState, context: DialogueContext, mode: DialogueConditionNode.Mode = DialogueConditionNode.Mode.AND) -> bool:
	for entry in entries:
		var passed: bool
		if entry is ConditionSet:
			passed = evaluate_all(entry.conditions, actor_id, state, context, DialogueConditionNode.Mode.AND)
		elif entry is DialogueCondition:
			passed = _evaluate_one(entry, actor_id, state, context)
		else:
			push_warning("DialogueConditionResolver: unexpected entry type in condition list, skipping")
			continue   # never votes either way, under EITHER mode

		if mode == DialogueConditionNode.Mode.AND and not passed:
			return false
		if mode == DialogueConditionNode.Mode.OR and passed:
			return true

	# AND: nothing failed (including an empty or fully-skipped list) -
	# vacuously true, unchanged from every call site that predates
	# `mode` existing at all.
	# OR: nothing passed (including an empty or fully-skipped list) -
	# vacuously FALSE, the opposite default. An OR with nothing in it
	# that could be true isn't "satisfied by default" the way an AND
	# with nothing that could fail is - a ConditionNode that's had no
	# conditions authored into it yet shouldn't silently gate as
	# "always available" just because its mode happens to be OR.
	return mode == DialogueConditionNode.Mode.AND


## Convenience for evaluating a whole DialogueConditionNode directly -
## the shape DialoguePlayer's still-deferred choice-availability check
## will actually want (a choice's condition_node_id either empty -
## always available - or pointing at exactly one ConditionNode to
## evaluate), rather than every caller manually unpacking
## node.conditions/node.mode itself.
static func evaluate_condition_node(node: DialogueConditionNode, actor_id: String, state: ActorState, context: DialogueContext) -> bool:
	return evaluate_all(node.conditions, actor_id, state, context, node.mode)


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
