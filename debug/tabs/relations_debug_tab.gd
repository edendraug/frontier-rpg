class_name RelationsDebugTab
extends DebugTab

## Manual controls for RelationsSystem (design doc Section 6): set/
## inspect player Faction Reputation, and inspect/reset a single
## Actor's live state. Built specifically to unblock testing
## reputation-gated dialogue content (FACTION_REPUTATION_AT_LEAST, a
## ConditionSet built on one, etc.) without needing to actually earn
## reputation through play first - see set_faction_reputation() on
## RelationsSystem, which exists for exactly this.

var _faction_id_input: LineEdit
var _faction_value_input: SpinBox
var _faction_list: VBoxContainer

var _actor_id_input: LineEdit
var _actor_known_label: Label


func _ready() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	root.add_child(_make_label("Faction Reputation", 16))

	var faction_row := HBoxContainer.new()

	_faction_id_input = LineEdit.new()
	_faction_id_input.placeholder_text = "faction id (e.g. settler)"
	_faction_id_input.custom_minimum_size = Vector2(160, 0)
	faction_row.add_child(_faction_id_input)

	_faction_value_input = SpinBox.new()
	_faction_value_input.min_value = -100
	_faction_value_input.max_value = 100
	_faction_value_input.step = 1
	_faction_value_input.value = 0
	faction_row.add_child(_faction_value_input)

	var set_button := Button.new()
	set_button.text = "Set"
	set_button.pressed.connect(_on_set_reputation_pressed)
	faction_row.add_child(set_button)

	root.add_child(faction_row)

	# Reserved up front for the same reason DialogueDebugTab's
	# _choice_box is: DebugTab's minimum-size forwarding only reliably
	# covers the FIRST layout pass, and this list is empty at that
	# point (nothing's been set yet) - without reserving space now,
	# entries added later would get silently clipped by the wrapping
	# ScrollContainer instead of scrolled to.
	_faction_list = VBoxContainer.new()
	_faction_list.custom_minimum_size = Vector2(0, 120)
	root.add_child(_faction_list)

	root.add_child(_make_label("Actor State", 16))

	var actor_row := HBoxContainer.new()

	_actor_id_input = LineEdit.new()
	_actor_id_input.placeholder_text = "actor id (e.g. silas_cobb)"
	_actor_id_input.text = "silas_cobb"
	_actor_id_input.custom_minimum_size = Vector2(160, 0)
	actor_row.add_child(_actor_id_input)

	var reveal_button := Button.new()
	reveal_button.text = "Reveal Name"
	reveal_button.pressed.connect(_on_reveal_name_pressed)
	actor_row.add_child(reveal_button)

	var reset_button := Button.new()
	reset_button.text = "Reset State"
	reset_button.pressed.connect(_on_reset_actor_pressed)
	actor_row.add_child(reset_button)

	root.add_child(actor_row)

	_actor_known_label = _make_label("")
	root.add_child(_actor_known_label)


func refresh() -> void:
	_refresh_faction_list()
	_refresh_actor_label()


func get_tab_title() -> String:
	return "Relations"


# ---------------------------------------------------------------------------
# Faction Reputation
# ---------------------------------------------------------------------------

func _on_set_reputation_pressed() -> void:
	var faction_id := _faction_id_input.text.strip_edges()
	if faction_id.is_empty():
		return
	RelationsSystem.set_faction_reputation(faction_id, _faction_value_input.value)
	_refresh_faction_list()


func _refresh_faction_list() -> void:
	for child in _faction_list.get_children():
		child.queue_free()

	var snapshot := RelationsSystem.get_faction_reputation_snapshot()
	if snapshot.is_empty():
		_faction_list.add_child(_make_label("(no reputation set yet)"))
		return

	for faction_id in snapshot:
		_faction_list.add_child(_make_label("%s: %s" % [faction_id, snapshot[faction_id]]))


# ---------------------------------------------------------------------------
# Actor State
# ---------------------------------------------------------------------------

func _on_reveal_name_pressed() -> void:
	var actor_id := _actor_id_input.text.strip_edges()
	if actor_id.is_empty():
		return
	RelationsSystem.reveal_actor_name(actor_id)
	_refresh_actor_label()


func _on_reset_actor_pressed() -> void:
	var actor_id := _actor_id_input.text.strip_edges()
	if actor_id.is_empty():
		return
	RelationsSystem.reset_actor_state(actor_id)
	_refresh_actor_label()


func _refresh_actor_label() -> void:
	var actor_id := _actor_id_input.text.strip_edges()
	if actor_id.is_empty():
		_actor_known_label.text = ""
		return
	_actor_known_label.text = "Known: %s" % RelationsSystem.is_actor_known(actor_id)
