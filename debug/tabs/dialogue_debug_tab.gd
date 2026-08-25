class_name DialogueDebugTab
extends DebugTab

## Minimal proof-of-runtime tab for the Dialogue & Relations design
## doc's Phase 1 (Section 8): no dialogue-box presentation, just a
## text log plus dynamically-built buttons - enough to drive a real
## DialoguePlayer against the sample content from
## dev/generate_dialogue_sample_data.gd and watch every Phase 1 piece
## actually fire: Line variants, gated/consume_once Options, a
## SkillCheckGate resolving through the real pipeline (including the
## DiceVisualizer pause), a Preset call-stack round trip, and the
## CUSTOM Condition/Effect scripts.
##
## Rebuilds CharacterDataRegistry/DialogueTreeRegistry fresh every time
## "Start Conversation" is pressed, rather than caching them once -
## costs a bit of extra work per conversation, but means freshly
## re-run sample data (or hand-edited .tres content) gets picked up
## without reopening the Debug Menu. A real game scene starting actual
## conversations would want to build these once and hold onto them
## instead.

const TEST_ACTOR_ID := "silas_cobb"  # must match generate_dialogue_sample_data.gd's ACTOR_ID

var _member_option: OptionButton
var _log: RichTextLabel
var _choice_box: VBoxContainer
var _advance_button: Button
var _start_button: Button
var _real_ui_button: Button

var _player: DialoguePlayer


func _ready() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	root.add_child(_make_label("Dialogue", 16))
	root.add_child(_make_label("Talks to '%s' - run dev/generate_dialogue_sample_data.gd first if this errors." % TEST_ACTOR_ID))

	_member_option = _build_member_option()
	root.add_child(_member_option)

	_start_button = Button.new()
	_start_button.text = "Start Conversation (log)"
	_start_button.pressed.connect(_on_start_pressed)
	root.add_child(_start_button)

	_real_ui_button = Button.new()
	_real_ui_button.text = "Start Conversation (real UI)"
	_real_ui_button.pressed.connect(_on_start_real_ui_pressed)
	root.add_child(_real_ui_button)

	_log = RichTextLabel.new()
	_log.custom_minimum_size = Vector2(0, 220)
	_log.bbcode_enabled = true
	_log.scroll_following = true
	root.add_child(_log)

	_advance_button = Button.new()
	_advance_button.text = "Continue"
	_advance_button.visible = false
	_advance_button.pressed.connect(_on_advance_pressed)
	root.add_child(_advance_button)

	_choice_box = VBoxContainer.new()
	# Reserved up front rather than left to grow dynamically: DebugTab's
	# _get_minimum_size() forwards root's combined minimum size to the
	# wrapping ScrollContainer, but that forwarding only happens
	# reliably on the FIRST layout pass. root/_choice_box (real
	# Containers) correctly resize themselves as buttons are added
	# later at runtime, but DialogueDebugTab itself is a plain Control,
	# not a Container, so nothing automatically tells the ScrollContainer
	# to re-measure when a deeply-nested descendant's size changes after
	# the fact - buttons added post-_ready() were getting silently
	# clipped rather than scrolled to. Reserving space here means the
	# very first (correctly-forwarded) measurement already accounts for
	# a full set of options. Sized for ~8 buttons at default theme
	# height; bump this if a tree ever offers more choices at once.
	_choice_box.custom_minimum_size = Vector2(0, 280)
	root.add_child(_choice_box)


func refresh() -> void:
	_refresh_member_option(_member_option)


func get_tab_title() -> String:
	return "Dialogue"


func on_deactivated() -> void:
	# No partial-conversation persistence exists (or is planned) at
	# this layer, so switching away mid-conversation just drops it -
	# nothing meaningful to pause/resume. Still worth hiding the tray
	# in case a roll was mid-flight when the tab lost focus.
	DiceVisualizer.hide_tray()
	_player = null


# ---------------------------------------------------------------------------
# Starting a conversation
# ---------------------------------------------------------------------------

func _on_start_pressed() -> void:
	var character := _selected_member(_member_option)
	if character == null:
		_append_log("[color=orange]No party member selected/available - add one via the Party tab first.[/color]")
		return

	_log.clear()
	_clear_choice_buttons()
	_advance_button.visible = false

	var registry := CharacterDataRegistry.new()
	var tree_registry := DialogueTreeRegistry.new()
	var context := DialogueContext.new(character, registry)

	_player = DialoguePlayer.new(tree_registry, context)
	_player.line_ready.connect(_on_line_ready)
	_player.choice_ready.connect(_on_choice_ready)
	_player.awaiting_skill_check_started.connect(_on_awaiting_skill_check_started)
	_player.skill_check_resolved.connect(_on_skill_check_resolved)
	_player.recruitment_triggered.connect(_on_recruitment_triggered)
	_player.conversation_ended.connect(_on_conversation_ended)

	_append_log("[b]Starting conversation with %s as %s...[/b]" % [TEST_ACTOR_ID, character.character_name])
	_player.start_conversation(TEST_ACTOR_ID)


## Separate from _on_start_pressed() rather than a shared helper with a
## branch in it - the two paths build the same DialoguePlayer but do
## completely different things with it afterward (wire signals to this
## tab's own log/buttons vs. hand it to a scene that already knows how
## to drive itself), so a shared function would mostly be an if/else
## with nothing else in common.
func _on_start_real_ui_pressed() -> void:
	var character := _selected_member(_member_option)
	if character == null:
		_append_log("[color=orange]No party member selected/available - add one via the Party tab first.[/color]")
		return

	var dialogue_window := get_tree().get_first_node_in_group("dialogue_window") as DialogueWindow
	if dialogue_window == null:
		_append_log("[color=orange]No DialogueWindow found in the scene (group 'dialogue_window') - is one instanced in the current scene?[/color]")
		return

	var registry := CharacterDataRegistry.new()
	var tree_registry := DialogueTreeRegistry.new()
	var context := DialogueContext.new(character, registry)
	var player := DialoguePlayer.new(tree_registry, context)

	_append_log("[b]Opening real dialogue window with %s as %s...[/b]" % [TEST_ACTOR_ID, character.character_name])
	dialogue_window.open(player, TEST_ACTOR_ID)


# ---------------------------------------------------------------------------
# DialoguePlayer signal handlers
# ---------------------------------------------------------------------------

func _on_line_ready(speaker_actor_id: String, text: String, _portrait: Texture2D) -> void:
	var speaker_label := RelationsSystem.get_display_name(speaker_actor_id) if not speaker_actor_id.is_empty() else "Narration"
	_append_log("[b]%s:[/b] %s" % [speaker_label, text])
	_clear_choice_buttons()
	_advance_button.visible = true


func _on_choice_ready(options: Array) -> void:
	_advance_button.visible = false
	_clear_choice_buttons()

	for raw_option in options:
		var option: DialogueOption = raw_option
		var label: String = option.text
		if not option.consume_once and _player.has_taken_option(option.option_id):
			label += "  [already asked]"
		var button := Button.new()
		button.text = label
		button.pressed.connect(_on_option_pressed.bind(option.option_id))
		_choice_box.add_child(button)


func _on_option_pressed(option_id: String) -> void:
	_clear_choice_buttons()
	_player.select_option(option_id)


func _on_awaiting_skill_check_started() -> void:
	_append_log("[i]Rolling...[/i]")
	_advance_button.visible = false


func _on_skill_check_resolved(result: SkillCheckResult, branch: SkillCheckBranch) -> void:
	var outcome_label: String = DiceResolver.Outcome.keys()[result.outcome]
	if branch == null:
		_append_log("[color=orange]Skill check result: %s (total %d vs DC %d) - no branch was authored for this outcome.[/color]" % [outcome_label, result.total, result.difficulty])
	else:
		_append_log("Skill check result: [b]%s[/b] (total %d vs DC %d)" % [outcome_label, result.total, result.difficulty])


func _on_recruitment_triggered(actor_id: String) -> void:
	_append_log("[color=green]TRIGGER_RECRUITMENT fired for '%s' - no PartyManager hookup exists yet, so nothing further happens.[/color]" % actor_id)


func _on_conversation_ended() -> void:
	_append_log("[i]-- conversation ended --[/i]")
	_clear_choice_buttons()
	_advance_button.visible = false


# ---------------------------------------------------------------------------
# UI-facing input passthrough
# ---------------------------------------------------------------------------

func _on_advance_pressed() -> void:
	_advance_button.visible = false
	_player.advance()


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

func _append_log(bbcode_line: String) -> void:
	_log.append_text(bbcode_line + "\n")


func _clear_choice_buttons() -> void:
	for child in _choice_box.get_children():
		child.queue_free()
