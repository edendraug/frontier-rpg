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

signal line_ready(speaker_actor_id: String, text: String, portrait: Texture2D)
signal choice_ready(options: Array)  # Array[DialogueOption], currently available
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


func _init(tree_registry: DialogueTreeRegistry, context: DialogueContext) -> void:
	_tree_registry = tree_registry
	_context = context
	_rng = context.rng


func is_awaiting_resolution() -> bool:
	return _awaiting_resolution


## Whether this option has been taken before, for the UI's "already
## picked" treatment on repeatable (non-consume_once) options.
func has_taken_option(option_id: String) -> bool:
	return RelationsSystem.get_actor_state(_actor_id).has_taken_option(option_id)


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
	_navigate_to(node.next)


## Called by the UI when the player picks an option on the
## currently-shown Choice. Re-validates option_id belongs to the
## current node rather than trusting the caller blindly.
func select_option(option_id: String) -> void:
	var node := _current_node()
	if not (node is DialogueChoiceNode):
		push_warning("DialoguePlayer: select_option() called while not presenting a Choice")
		return

	var option: DialogueOption = null
	for o in node.options:
		if o.option_id == option_id:
			option = o
			break
	if option == null:
		push_warning("DialoguePlayer: option_id '%s' not found on current Choice node" % option_id)
		return

	# Marked taken on SELECTION, not on skill-check success - "has this
	# Option been taken" (Section 4.5) reads as "did the player pick
	# it," independent of pass/fail. This means a consume_once option
	## with a skill check disappears after one attempt even if it was
	# failed. Flag if a retry-until-success behavior was intended
	# instead - that would need marking taken only on success/crit.
	RelationsSystem.get_actor_state(_actor_id).mark_option_taken(option_id)

	if option.has_skill_check():
		_resolve_skill_check_option(option)
	else:
		_fire_effects_and_navigate(option.effects, option.next)


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
	elif node is DialogueChoiceNode:
		_present_choice(node)
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


func _present_choice(node: DialogueChoiceNode) -> void:
	var state := RelationsSystem.get_actor_state(_actor_id)

	if not DialogueConditionResolver.evaluate_all(node.conditions, _actor_id, state, _context):
		# Whole topic gated off. The design doc doesn't specify a
		# fallback beyond "unavailable" - treating a hidden Choice node
		# the same as an exhausted branch (pop the Preset stack, or end
		# the conversation at top level) seemed the closest reasonable
		# default. Flag if a specific fallback node was intended instead.
		_conclude_current_tree()
		return

	var available: Array = []
	for option in node.options:
		if option.consume_once and state.has_taken_option(option.option_id):
			continue
		if not DialogueConditionResolver.evaluate_all(option.conditions, _actor_id, state, _context):
			continue
		available.append(option)

	if available.is_empty():
		_conclude_current_tree()
		return

	choice_ready.emit(available)


# ---------------------------------------------------------------------------
# Navigation / tree & Preset lifecycle
# ---------------------------------------------------------------------------

func _navigate_to(node_id: String) -> void:
	if node_id.is_empty():
		_conclude_current_tree()
		return
	_current_node_id = node_id
	_enter_current_node()


## An empty `next` is treated as "this branch of the graph is
## exhausted" - the natural end-of-tree signal, since no distinct End
## node type exists in the data model. At the top level that ends the
## whole conversation; inside a Preset, it pops back to the caller.
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

## Fires effects fired together (an Option's plain effects, or one
## skill-check branch's effects), then navigates - handling START_PRESET
## specially, since it means next_node_id is a RETURN point rather than
## an immediate destination (Section 4.9: the call stack stores
## current tree + return point, pushed by the START_PRESET effect
## itself, rather than an explicit hand-wired return edge).
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
## skill-check Option's effects live on the branch, never at selection
## time.
func _resolve_skill_check_option(option: DialogueOption) -> void:
	_awaiting_resolution = true
	awaiting_skill_check_started.emit()

	var gate := option.skill_check
	var check := SkillCheck.new(_context.player_character, gate.skill_id, gate.get_dc(), _context.registry)
	var result := check.resolve()

	await DiceVisualizer.roll_and_show(result)

	_awaiting_resolution = false

	var branch: SkillCheckBranch
	match result.outcome:
		DiceResolver.Outcome.CRITICAL_SUCCESS:
			branch = gate.get_critical_success_branch()
		DiceResolver.Outcome.SUCCESS:
			branch = gate.success
		DiceResolver.Outcome.FAILURE:
			branch = gate.failure
		DiceResolver.Outcome.CRITICAL_FAILURE:
			branch = gate.get_critical_failure_branch()

	if branch == null:
		push_warning("DialoguePlayer: SkillCheckGate for skill '%s' has no branch authored for outcome %s" % [gate.skill_id, DiceResolver.Outcome.keys()[result.outcome]])
		skill_check_resolved.emit(result, null)
		_conclude_current_tree()
		return

	skill_check_resolved.emit(result, branch)
	_fire_effects_and_navigate(branch.effects, branch.next)
