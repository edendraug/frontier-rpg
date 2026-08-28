class_name DialoguePlayer
extends RefCounted

## The runtime graph walker (design doc Section 5.1). One instance per
## active conversation - holds the active tree, current node, the
## Preset call stack, and the "awaiting skill-check resolution" state.
## RefCounted rather than Node, matching SkillCheck/DiceResolver's
## pure-logic pattern rather than needing scene-tree placement.
##
## Presentation is a separate, later layer (Section 9) - this class
## only exposes the contract: signals for what's currently on screen,
## and advance()/select_option() for the UI to call. It does not know
## about buttons, portraits rendering, or dialogue boxes.
##
## WALKING-LOGIC REFACTOR (Dialogue Graph Node Restructure design doc,
## Section 9): this file now actually walks the new node structure -
## DialogueStructureNode fan-out, an optional DialogueConditionNode
## gating each choice, DialogueSkillCheckChoiceNode's four branches -
## rather than the earlier compile-fix pass's stubs. Also wires up
## default_return_id (Restructure follow-up addendum), which existed
## in the data model and the editor before this pass but was never
## actually consumed by anything at runtime until now.
##
## Three judgment calls made here, not settled anywhere else, flagged
## for visibility rather than buried as silent choices:
## 1. A dangling condition_node_id (points at a node_id that no longer
##    exists, or that isn't actually a DialogueConditionNode) is
##    treated as ungated - permissive-by-default, matching the missing-
##    reference convention everywhere else in this project
##    (CharacterSheet.get_modifier_entries()'s null-check-and-skip
##    pattern). A stricter "exclude on broken reference" reading is
##    equally defensible; this isn't a settled design decision.
## 2. A DialogueStructureNode output pointing at something that isn't a
##    Choice-family node (e.g. a Line) is warned and skipped - there's
##    no coherent meaning for "select this Line from a choice list."
## 3. select_option() only accepts an id that was part of the most
##    recently emitted choice_ready payload - stale UI state or a
##    caller passing something that was never actually offered is
##    rejected rather than trusted blindly.

signal line_ready(speaker_actor_id: String, text: String, portrait: Texture2D)
signal choice_ready(options: Array)  # Array[DialogueChoiceNode] (including the SkillCheckChoiceNode subtype) - the currently-available choices, already filtered by consume_once/condition
signal awaiting_skill_check_started()
signal skill_check_resolved(result: SkillCheckResult, branch: SkillCheckBranch)
signal recruitment_triggered(actor_id: String)
signal conversation_ended()

var _tree_registry: DialogueTreeRegistry
var _context: DialogueContext
var _rng: RandomNumberGenerator

var _actor_id: String = ""
var _current_tree: DialogueTree
var _current_node_id: String = ""
var _call_stack: Array = []  # [{tree: DialogueTree, return_node_id: String}, ...]
var _awaiting_resolution: bool = false
var _last_offered_ids: Array[String] = []  # the exact ids from the most recent choice_ready emission - see judgment call 3 above


func _init(tree_registry: DialogueTreeRegistry, context: DialogueContext) -> void:
	_tree_registry = tree_registry
	_context = context
	_rng = context.rng


func is_awaiting_resolution() -> bool:
	return _awaiting_resolution


## Whether this choice has been taken before, for the UI's "already
## picked" treatment on repeatable (non-consume_once) choices. Keyed
## by the same String id as before - just sourced from a
## DialogueChoiceNode's own node_id now instead of the retired
## option_id (Restructure doc Section 8). No ActorState changes needed
## either way, since it never cared where the key string came from.
func has_taken_option(option_id: String) -> bool:
	return RelationsSystem.get_actor_state(_actor_id).has_taken_option(option_id)


## The CharacterDataRegistry this conversation is resolving skill
## checks/HAS_TRAIT/HAS_SKILL_RANK_AT_LEAST against - exposed so the
## UI can look up TraitDefinition/SkillDefinition display names for
## its own presentation purposes (e.g. the condition-tag hint on an
## Option), without this window needing its own separate registry
## reference just for that.
func get_registry() -> CharacterDataRegistry:
	return _context.registry


## Read-only lookup for the UI's OWN presentation purposes (the
## condition-tag hint on a choice, in particular - a choice's
## condition_node_id is just an id string, and the UI has no other way
## to reach the actual DialogueConditionNode it points at). NOT used by
## this class's own walking logic, which already has _current_tree
## directly - this exists purely as a read-only window into it for
## external callers, same reasoning as get_registry() above. Returns
## null if id is empty, doesn't exist, or isn't actually a
## DialogueConditionNode - callers should treat all three the same way
## (nothing to show), matching this project's missing-reference-
## tolerant convention rather than distinguishing "broken" from
## "absent."
func get_condition_node(id: String) -> DialogueConditionNode:
	if id.is_empty() or _current_tree == null:
		return null
	return _current_tree.get_node(id) as DialogueConditionNode


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

func start_conversation(actor_id: String) -> void:
	var def := RelationsSystem.get_actor_definition(actor_id)
	if def == null:
		push_warning("DialoguePlayer: start_conversation() called for unknown actor_id '%s'" % actor_id)
		conversation_ended.emit()
		return
	if def.dialogue_tree_id.is_empty():
		push_warning("DialoguePlayer: Actor '%s' has no dialogue_tree_id (mute/flavor-only NPC)" % actor_id)
		conversation_ended.emit()
		return
	var tree: DialogueTree = _tree_registry.trees.get(def.dialogue_tree_id)
	if tree == null:
		push_warning("DialoguePlayer: dialogue_tree_id '%s' not found in registry" % def.dialogue_tree_id)
		conversation_ended.emit()
		return

	_actor_id = actor_id
	_current_tree = tree
	_call_stack.clear()
	_last_offered_ids.clear()
	_navigate_to(tree.start_node_id)


# ---------------------------------------------------------------------------
# UI-facing input
# ---------------------------------------------------------------------------

## Called by the UI when the player dismisses a currently-shown Line.
func advance() -> void:
	var node := _current_node()
	if not (node is DialogueLineNode):
		push_warning("DialoguePlayer: advance() called while not presenting a Line")
		return
	_navigate_to(_resolve_next(node.next, node.default_return_id))


## Pure, side-effect-free peek for the UI's own pacing decisions - e.g.
## whether to require an explicit advance() before showing what's next,
## or move straight on automatically. Only meaningful while a Line is
## currently being presented; returns false otherwise. Deliberately
## does NOT run the real walking logic (_present_structure/
## _offer_choices) to find out what would ultimately be reachable -
## just resolves the immediate next node_id (same next/
## default_return_id fallback advance() itself uses) and checks ITS
## type. Running the real logic here would risk duplicate or premature
## side effects (a Line's own variant-picking mutates ActorState the
## moment it's presented - see _present_line - which must only ever
## happen once, from the real advance(), not from a UI peek).
func next_is_another_line() -> bool:
	var node := _current_node()
	if not (node is DialogueLineNode):
		return false
	var next_id := _resolve_next(node.next, node.default_return_id)
	if next_id.is_empty():
		return false
	return _current_tree.get_node(next_id) is DialogueLineNode


## Called by the UI once the player picks one of the ids most recently
## offered via choice_ready (judgment call 3 - see file header).
func select_option(chosen_node_id: String) -> void:
	if not _last_offered_ids.has(chosen_node_id):
		push_warning("DialoguePlayer: select_option() called with '%s', which wasn't among the last-offered choices - ignoring" % chosen_node_id)
		return

	var node := _current_tree.get_node(chosen_node_id)
	if node == null or not (node is DialogueChoiceNode):
		push_warning("DialoguePlayer: select_option() target '%s' is missing or not a Choice-family node" % chosen_node_id)
		return

	var choice: DialogueChoiceNode = node
	_last_offered_ids.clear()
	RelationsSystem.get_actor_state(_actor_id).mark_option_taken(choice.node_id)

	if choice is DialogueSkillCheckChoiceNode:
		_resolve_skill_check_option(choice as DialogueSkillCheckChoiceNode)
	else:
		_fire_effects_and_navigate(choice.effects, _resolve_next(choice.next, choice.default_return_id))


# ---------------------------------------------------------------------------
# Node presentation
# ---------------------------------------------------------------------------

func _current_node() -> Resource:
	return _current_tree.get_node(_current_node_id)


func _enter_current_node() -> void:
	var node := _current_node()
	if node == null:
		push_warning("DialoguePlayer: node_id '%s' not found in tree '%s'" % [_current_node_id, _current_tree.tree_id])
		_conclude_current_tree()
		return

	if node is DialogueLineNode:
		_present_line(node)
	elif node is DialogueStructureNode:
		_present_structure(node)
	elif node is DialogueChoiceNode:
		# Reachable directly (without a wrapping DialogueStructureNode)
		# if some `next`/tree.start_node_id points straight at a single
		# choice - unusual, but the data model doesn't forbid it.
		# _present_choice reuses the exact same filtering as a real
		# Structure fan-out, just for a candidate list of one, rather
		# than this being a second, separately-maintained code path.
		_present_choice(node)
	elif node is DialogueConditionNode:
		# A ConditionNode should never be a navigation target in a
		# well-formed tree - it's meant to sit on a choice's condition
		# input, resolved while gathering available choices
		# (_offer_choices), never entered directly. The editor's own
		# ConditionNode has 0 inputs (no visible port to wire this way
		# normally), so this is reachable only via malformed/hand-
		# edited data - kept as a defensive, warn-and-conclude case.
		push_warning("DialoguePlayer: DialogueConditionNode is not a presentable node (node_id '%s')" % _current_node_id)
		_conclude_current_tree()
	else:
		push_warning("DialoguePlayer: unrecognized node type for node_id '%s'" % _current_node_id)
		_conclude_current_tree()


func _present_line(node: DialogueLineNode) -> void:
	var variant_index: int
	var portrait: Texture2D = null

	if node.speaker.is_empty():
		# Narration/group scene - no Actor identity, no memory, no portrait.
		variant_index = node.pick_variant_index(-1, _rng)
	else:
		var state := RelationsSystem.get_actor_state(node.speaker)
		variant_index = node.pick_variant_index(state.get_last_variant(node.node_id), _rng)
		state.set_last_variant(node.node_id, variant_index)

		var def := RelationsSystem.get_actor_definition(node.speaker)
		if def != null:
			portrait = def.get_portrait(node.emotion_tag)

	line_ready.emit(node.speaker, node.get_text(variant_index), portrait)


## Walks `node.outputs` in array order, resolving each target down to a
## candidate Choice-family node (judgment call 2 - see file header:
## anything that isn't one is warned and skipped), then hands the list
## to _offer_choices for the actual availability filtering.
func _present_structure(node: DialogueStructureNode) -> void:
	var candidates: Array = []

	for target_id in node.outputs:
		if target_id.is_empty():
			continue
		var target: DialogueGraphNode = _current_tree.get_node(target_id)
		if target == null:
			push_warning("DialoguePlayer: Structure node '%s' references missing node_id '%s'" % [node.node_id, target_id])
			continue
		if not (target is DialogueChoiceNode):
			push_warning("DialoguePlayer: Structure node '%s' output '%s' isn't a Choice-family node, skipping" % [node.node_id, target_id])
			continue
		candidates.append(target)

	_offer_choices(candidates)


## See _enter_current_node()'s own comment on when this path is reached.
func _present_choice(node: DialogueChoiceNode) -> void:
	_offer_choices([node])


## Filters `candidates` down to what's actually available right now -
## excluded if consume_once and already taken (Dialogue & Relations doc
## Section 4.5's "disappears entirely" rule), or if a wired
## DialogueConditionNode fails (Restructure doc Section 5/6, evaluated
## via DialogueConditionResolver.evaluate_condition_node, AND/OR mode
## included) - then emits choice_ready with the survivors, or
## concludes the tree if nothing survives (matching the pre-restructure
## empty-choice-list handling). Shared by _present_structure (a real
## fan-out) and _present_choice (a single choice reached directly).
func _offer_choices(candidates: Array) -> void:
	var state := RelationsSystem.get_actor_state(_actor_id)
	var available: Array = []

	for choice in candidates:
		if choice.consume_once and state.has_taken_option(choice.node_id):
			continue

		if not choice.condition_node_id.is_empty():
			var condition_node := _current_tree.get_node(choice.condition_node_id)
			if condition_node == null:
				# Judgment call 1 - see file header.
				push_warning("DialoguePlayer: '%s' references missing condition_node_id '%s' - treating as ungated" % [choice.node_id, choice.condition_node_id])
			elif condition_node is DialogueConditionNode:
				if not DialogueConditionResolver.evaluate_condition_node(condition_node, _actor_id, state, _context):
					continue
			else:
				push_warning("DialoguePlayer: '%s' condition_node_id '%s' isn't a DialogueConditionNode - treating as ungated" % [choice.node_id, choice.condition_node_id])

		available.append(choice)

	if available.is_empty():
		_last_offered_ids.clear()
		_conclude_current_tree()
		return

	_last_offered_ids.clear()
	for choice in available:
		_last_offered_ids.append(choice.node_id)
	choice_ready.emit(available)


# ---------------------------------------------------------------------------
# Navigation / tree & Preset lifecycle
# ---------------------------------------------------------------------------

## Resolves the node_id to actually navigate to, falling back to
## `default_return_id` when `next_value` is empty (Restructure follow-
## up addendum) - lets an authored ending like "go back to the hub I
## came from" not require an explicit wire on the canvas. Checked here,
## at each call site, rather than inside _navigate_to/
## _fire_effects_and_navigate - default_return_id belongs to the owning
## DialogueLineNode/DialogueChoiceNode, not to whichever specific
## field is being resolved (a DialogueSkillCheckChoiceNode's four
## branches all share ONE fallback on the choice itself, not four
## separate ones per branch).
func _resolve_next(next_value: String, default_return_id: String) -> String:
	return next_value if not next_value.is_empty() else default_return_id


func _navigate_to(node_id: String) -> void:
	if node_id.is_empty():
		_conclude_current_tree()
		return
	_current_node_id = node_id
	_enter_current_node()


## An empty `next` (after _resolve_next's fallback has already been
## applied) is treated as "this branch of the graph is exhausted" - the
## natural end-of-tree signal, since no distinct End node type exists
## in the data model. At the top level that ends the whole
## conversation; inside a Preset, it pops back to the caller.
func _conclude_current_tree() -> void:
	if _call_stack.is_empty():
		conversation_ended.emit()
		return
	var frame: Dictionary = _call_stack.pop_back()
	_current_tree = frame.tree
	_navigate_to(frame.return_node_id)


# ---------------------------------------------------------------------------
# Effects / skill checks / Presets
# ---------------------------------------------------------------------------

## Fires effects fired together (a Choice's plain effects, or one
## skill-check branch's effects), then navigates - handling START_PRESET
## specially, since it means next_node_id is a RETURN point rather than
## an immediate destination (Section 4.9: the call stack stores
## current tree + return point, pushed by the START_PRESET effect
## itself, rather than an explicit hand-wired return edge). Callers
## pass the ALREADY default_return_id-resolved next_node_id
## (_resolve_next) - this function itself has no opinion on that
## fallback, since it doesn't know which node the effects/next came
## from.
func _fire_effects_and_navigate(effects: Array, next_node_id: String) -> void:
	var preset_target: String = ""
	for effect in effects:
		if effect.type == DialogueEffect.Type.START_PRESET:
			preset_target = effect.target
		else:
			_fire_one_effect(effect)

	if preset_target.is_empty():
		_navigate_to(next_node_id)
	else:
		_enter_preset(preset_target, next_node_id)


func _fire_one_effect(effect: DialogueEffect) -> void:
	match effect.type:
		DialogueEffect.Type.TRIGGER_RECRUITMENT:
			# Dialogue only fires the signal - it never touches a
			# CharacterSheet itself (Section 3.1). PartyManager (or a
			# dedicated onboarding process) is expected to listen.
			var target_id: String = effect.target if not effect.target.is_empty() else _actor_id
			recruitment_triggered.emit(target_id)

		DialogueEffect.Type.MORALE_EVENT:
			# VitalsSystem/MoraleEventInstance's exact "add a morale
			# event to a CharacterSheet" API hasn't been reviewed in
			# this session - stubbed rather than guessed at.
			push_warning("DialoguePlayer: MORALE_EVENT effect fired but not yet wired to VitalsSystem")

		_:
			DialogueEffectResolver.apply(effect, _actor_id, _context)


func _enter_preset(preset_id: String, return_node_id: String) -> void:
	var preset_tree: DialogueTree = _tree_registry.presets.get(preset_id)
	if preset_tree == null:
		push_warning("DialoguePlayer: unknown preset id '%s', skipping and continuing normally" % preset_id)
		_navigate_to(return_node_id)
		return

	_call_stack.append({"tree": _current_tree, "return_node_id": return_node_id})
	_current_tree = preset_tree
	_navigate_to(preset_tree.start_node_id)


## Section 5.3's real pause: further input is disabled (UI checks
## is_awaiting_resolution()) until the visual roll finishes. Effects
## fire only once the outcome is known - per Section 5.2, a
## skill-check choice's effects live on the branch, never at selection
## time.
func _resolve_skill_check_option(choice: DialogueSkillCheckChoiceNode) -> void:
	_awaiting_resolution = true
	awaiting_skill_check_started.emit()

	var check := SkillCheck.new(_context.player_character, choice.skill_id, choice.get_dc(), _context.registry)
	var result := check.resolve()

	await DiceVisualizer.roll_and_show(result)

	_awaiting_resolution = false

	var branch: SkillCheckBranch
	match result.outcome:
		DiceResolver.Outcome.CRITICAL_SUCCESS:
			branch = choice.get_critical_success_branch()
		DiceResolver.Outcome.SUCCESS:
			branch = choice.success
		DiceResolver.Outcome.FAILURE:
			branch = choice.failure
		DiceResolver.Outcome.CRITICAL_FAILURE:
			branch = choice.get_critical_failure_branch()

	if branch == null:
		push_warning("DialoguePlayer: DialogueSkillCheckChoiceNode for skill '%s' has no branch authored for outcome %s" % [choice.skill_id, DiceResolver.Outcome.keys()[result.outcome]])
		skill_check_resolved.emit(result, null)
		_conclude_current_tree()
		return

	skill_check_resolved.emit(result, branch)
	_fire_effects_and_navigate(branch.effects, _resolve_next(branch.next, choice.default_return_id))
