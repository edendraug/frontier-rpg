class_name DialogueWindow
extends Control

## Drives the hand-built dialogue scene: RichTextLabel.visible_characters
## reveal tween, ChoicesScroll open/close tween, OptionRow instancing,
## and all DialoguePlayer signal wiring. Holds the only real logic in
## this UI - the scene itself is static, hand-placed, and just gets
## fed data/tween targets.
##
## Two states exist here that DialoguePlayer has no concept of at all
## (REVEALING, LINE_SHOWN/"waiting to auto-advance") - reveal animation
## and read-pacing are pure presentation concerns, so this window keeps
## its own small state machine on top of whatever DialoguePlayer itself
## is doing, rather than trying to read state off DialoguePlayer.

enum State { IDLE, REVEALING, LINE_SHOWN, CHOICES_SHOWN, AWAITING_SKILL_CHECK, ENDED }

## Swap for your actual InputMap action if "ui_accept" (Godot's
## built-in Enter/Space/gamepad-A) isn't what this project uses to
## confirm/interact.
const ACCEPT_ACTION := "ui_accept"

const OPTION_ROW_SCENE := preload("res://ui/dialogue_window/option_row.tscn")

const MAX_VISIBLE_OPTIONS := 4

# --- Tunable placeholders - none of these are considered final ---
const REVEAL_CHARS_PER_SECOND := 45.0
const POST_LINE_PAUSE := 0.2
const CHOICES_TWEEN_DURATION := 0.4

@onready var speaker_label: Label = %SpeakerLabel
@onready var line_text_label: RichTextLabel = %LineText
@onready var line_row: VBoxContainer = %LineRow
@onready var choices_scroll: ScrollContainer = %ChoicesScroll
@onready var choices_list: VBoxContainer = %ChoicesList
@onready var portrait_display: PortraitDisplay = %PortraitDisplay

var _player: DialoguePlayer
var _state: State = State.IDLE
var _reveal_tween: Tween
var _choices_tween: Tween


func _ready() -> void:
	visible = false
	line_row.gui_input.connect(_on_line_row_gui_input)
	# Lets anything outside this scene's hand-built tree (DialogueDebugTab,
	# in particular) find this instance without depending on %UniqueName
	# resolution across a runtime-added-child boundary, which is murky
	# for programmatically instantiated nodes without an explicit owner.
	add_to_group("dialogue_window")


## Entry point - whatever triggers a conversation (an NPC interaction,
## a scripted event) calls this with a freshly-built DialoguePlayer and
## the actor to talk to. This window doesn't construct DialoguePlayer
## itself, same reasoning as the debug tab: which CharacterSheet/
## registries to use is the caller's decision, not this window's.
func open(player: DialoguePlayer, actor_id: String) -> void:
	_player = player
	_player.line_ready.connect(_on_line_ready)
	_player.choice_ready.connect(_on_choice_ready)
	_player.awaiting_skill_check_started.connect(_on_awaiting_skill_check_started)
	_player.skill_check_resolved.connect(_on_skill_check_resolved)
	_player.conversation_ended.connect(_on_conversation_ended)

	_close_choices_instant()
	visible = true
	_player.start_conversation(actor_id)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if not event.is_action_pressed(ACCEPT_ACTION):
		return
	if _try_progress():
		get_viewport().set_input_as_handled()


func _on_line_row_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_try_progress()


## Single entry point for both the skip-reveal and advance-past-a-
## finished-line interactions, since they're the same physical input
## (accept press or a click on the line) just handled differently
## depending on _state.
func _try_progress() -> bool:
	if _state == State.REVEALING:
		_skip_reveal()
		return true
	if _state == State.LINE_SHOWN:
		_advance_from_line()
		return true
	return false


# ---------------------------------------------------------------------------
# DialoguePlayer signal handlers
# ---------------------------------------------------------------------------

func _on_line_ready(speaker_actor_id: String, text: String, portrait: Texture2D) -> void:
	speaker_label.text = RelationsSystem.get_display_name(speaker_actor_id) if not speaker_actor_id.is_empty() else ""
	portrait_display.set_portrait(portrait)
	_reveal_line(text)


func _on_choice_ready(options: Array) -> void:
	_state = State.CHOICES_SHOWN
	_build_choices(options)


func _on_awaiting_skill_check_started() -> void:
	_state = State.AWAITING_SKILL_CHECK
	# Tray presentation itself is out of scope here - this window just
	# needs to stop reacting to dialogue input until skill_check_resolved,
	# which the _state guards throughout this file already enforce.


func _on_skill_check_resolved(_result: SkillCheckResult, _branch: SkillCheckBranch) -> void:
	# DialoguePlayer has already moved on to the branch's next node by
	# the time this fires - the line_ready/choice_ready/conversation_ended
	# that follows immediately after will set _state correctly. Nothing
	# to do here for now.
	pass


func _on_conversation_ended() -> void:
	_state = State.ENDED
	_close_choices_instant()
	_player.line_ready.disconnect(_on_line_ready)
	_player.choice_ready.disconnect(_on_choice_ready)
	_player.awaiting_skill_check_started.disconnect(_on_awaiting_skill_check_started)
	_player.skill_check_resolved.disconnect(_on_skill_check_resolved)
	_player.conversation_ended.disconnect(_on_conversation_ended)
	_player = null
	visible = false


# ---------------------------------------------------------------------------
# Line reveal
# ---------------------------------------------------------------------------

func _reveal_line(text: String) -> void:
	_state = State.REVEALING
	line_text_label.text = text
	line_text_label.visible_characters = 0

	var total_chars := line_text_label.get_total_character_count()
	var duration: float = total_chars / REVEAL_CHARS_PER_SECOND

	if _reveal_tween:
		_reveal_tween.kill()
	_reveal_tween = create_tween()
	_reveal_tween.tween_property(line_text_label, "visible_characters", total_chars, duration)
	_reveal_tween.finished.connect(_on_reveal_finished, CONNECT_ONE_SHOT)


func _skip_reveal() -> void:
	if _reveal_tween:
		_reveal_tween.kill()
	line_text_label.visible_characters = line_text_label.get_total_character_count()
	_on_reveal_finished()


func _on_reveal_finished() -> void:
	_state = State.LINE_SHOWN
	# Deliberately does NOT clear/collapse choices_list here, even
	# though a Line is now being shown "on top of" whatever choices
	# were visible before. Any previously-picked choice was already
	# locked (disabled) by _on_option_selected() the instant it was
	# clicked - what's showing here is a correctly-disabled leftover,
	# not a live one, and it should stay visible/stable through however
	# many Lines this branch strings together, only actually getting
	# replaced once _build_choices() (called from _on_choice_ready)
	# has a real new set to show. Clearing it here instead - what an
	# earlier version of this function did - wiped it out the moment
	# the very FIRST of those Lines finished revealing, well before any
	# replacement existed, and collapsed/reopened the panel on every
	# single Line in between for no reason.
	#
	# An explicit confirm (ui_accept, or clicking the line - see
	# _try_progress()) is only required when this Line leads straight
	# into ANOTHER Line - that's the one transition with no other
	# signal that the player has actually finished reading. Advancing
	# into a choice screen (or the conversation ending) still gets a
	# brief, tunable pause (POST_LINE_PAUSE) rather than snapping
	# instantly, but no explicit confirm of its own - the player's next
	# action already IS the choice itself, so requiring a press first
	# would just be a redundant extra step.
	if not _player.next_is_another_line():
		get_tree().create_timer(POST_LINE_PAUSE).timeout.connect(_advance_from_line, CONNECT_ONE_SHOT)


func _advance_from_line() -> void:
	if _state != State.LINE_SHOWN:
		return  # defensive guard against a double-call (e.g. two rapid ui_accept presses, or a click landing during POST_LINE_PAUSE's own brief window before the timer also fires) - not expected to matter in normal use, just cheap to keep correct
	_state = State.IDLE
	_player.advance()


# ---------------------------------------------------------------------------
# Choices
# ---------------------------------------------------------------------------

## Builds one OptionRow per currently-available choice, in the order
## DialoguePlayer offered them (already filtered by consume_once/
## condition - nothing further to check here). node_id replaces the
## retired option_id as both the display-memory key
## (has_taken_option) and what gets passed back to select_option().
func _build_choices(options: Array) -> void:
	_clear_choices()

	var registry := _player.get_registry()
	var row_height := 0.0
	for raw_choice in options:
		var choice: DialogueChoiceNode = raw_choice
		var row: OptionRow = OPTION_ROW_SCENE.instantiate()
		choices_list.add_child(row)
		row.setup(choice.node_id, choice.text, _derive_condition_tag(choice, registry), _player.has_taken_option(choice.node_id))
		row.option_selected.connect(_on_option_selected)
		row_height = row.custom_minimum_size.y

	var visible_rows: int = min(options.size(), MAX_VISIBLE_OPTIONS)
	_tween_choices_height(row_height * visible_rows)


## Surfaces a short bracketed hint on a choice, in priority order:
## 1. A skill check, if this is a DialogueSkillCheckChoiceNode -
##    "[Medicine check]". Takes priority over any condition-based tag,
##    since a skill check is the more decision-relevant thing for a
##    player to know about before choosing it.
## 2. The first HAS_TRAIT/HAS_SKILL_RANK_AT_LEAST condition found in
##    the wired DialogueConditionNode's own list, if one is attached
##    via condition_node_id (including inside any ConditionSet
##    references) - "[Natural Hunter]". Every other condition type
##    stays invisible flow-control, same as before the restructure.
## Returns "" (no tag shown) if neither applies.
func _derive_condition_tag(choice: DialogueChoiceNode, registry: CharacterDataRegistry) -> String:
	if choice is DialogueSkillCheckChoiceNode:
		var skill_check := choice as DialogueSkillCheckChoiceNode
		var skill_def: SkillDefinition = registry.skills.get(skill_check.skill_id)
		var skill_name: String = skill_def.display_name if skill_def != null else skill_check.skill_id
		return "[%s check]" % skill_name

	if choice.condition_node_id.is_empty():
		return ""
	var condition_node := _player.get_condition_node(choice.condition_node_id)
	if condition_node == null:
		return ""

	var raw_tag := _find_tag_in(condition_node.conditions, registry)
	if raw_tag.is_empty():
		return ""
	return "[%s]" % raw_tag


func _find_tag_in(entries: Array, registry: CharacterDataRegistry) -> String:
	for entry in entries:
		var tag := ""
		if entry is ConditionSet:
			tag = _find_tag_in(entry.conditions, registry)
		elif entry is DialogueCondition:
			tag = _tag_for_condition(entry, registry)
		if not tag.is_empty():
			return tag
	return ""


## Falls back to the raw id if the definition can't be found, matching
## the missing-reference-tolerant convention used elsewhere in this
## project rather than crashing or showing nothing.
func _tag_for_condition(condition: DialogueCondition, registry: CharacterDataRegistry) -> String:
	match condition.type:
		DialogueCondition.Type.HAS_TRAIT:
			var trait_def: TraitDefinition = registry.traits.get(condition.target)
			return trait_def.display_name if trait_def != null else condition.target
		DialogueCondition.Type.HAS_SKILL_RANK_AT_LEAST:
			var skill_def: SkillDefinition = registry.skills.get(condition.target)
			return skill_def.display_name if skill_def != null else condition.target
		_:
			return ""


func _on_option_selected(option_id: String) -> void:
	if _state != State.CHOICES_SHOWN:
		return
	_state = State.IDLE
	for row in choices_list.get_children():
		if row is OptionRow:
			row.lock()
	_player.select_option(option_id)


func _clear_choices() -> void:
	for child in choices_list.get_children():
		child.queue_free()


func _tween_choices_height(target_height: float) -> void:
	if _choices_tween:
		_choices_tween.kill()
	_choices_tween = create_tween()
	_choices_tween.tween_property(choices_scroll, "custom_minimum_size:y", target_height, CHOICES_TWEEN_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _close_choices_instant() -> void:
	if _choices_tween:
		_choices_tween.kill()
	_clear_choices()
	choices_scroll.custom_minimum_size.y = 0
