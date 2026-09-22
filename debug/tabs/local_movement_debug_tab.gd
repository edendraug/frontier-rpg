class_name LocalMovementDebugTab
extends DebugTab

## Debug-menu-exposed character switching (Local Movement Design Doc,
## Section 3.8: "a straightforward, character-sheet-driven API... that
## a debug menu entry calls directly, ahead of any real player-facing
## switching UI"). Finds whichever PlayerController is live in the
## CURRENTLY LOADED scene via the "player_controller" group -- this
## tab has no scene of its own, unlike DialogueDebugTab, since there's
## no independent way to test movement without the actual scene's
## painted TileMapLayers.

var _character_option: OptionButton
var _lock_checkbox: CheckBox
var _readout: Label
var _player_controller: PlayerController

## Tracks which PlayerController instance we've already registered our
## synthetic lock check with, so refresh() -- called every time this
## tab becomes active -- doesn't pile up duplicate registrations on
## the same instance. Reset naturally whenever a different (or newly
## reloaded) scene's PlayerController is found instead.
var _lock_registered_on: PlayerController = null
var _simulated_lock_active: bool = false

var _scene_path_edit: LineEdit
var _load_status_label: Label


func get_tab_title() -> String:
	return "Local Movement"


func _ready() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	root.add_child(_make_label("Active Character", 16))
	root.add_child(_make_label(
		"Requires a scene with a PlayerController present (e.g. the Local Movement whitebox room).",
		11
	))

	_character_option = OptionButton.new()
	_character_option.item_selected.connect(_on_character_selected)
	root.add_child(_character_option)

	root.add_child(HSeparator.new())
	root.add_child(_make_label(
		"Phase 3c: a synthetic stand-in for a real modal lock (e.g. mid-dialogue) --"
		+ " proves PlayerController.register_control_lock() actually blocks movement, interaction, and switching.",
		11
	))
	_lock_checkbox = CheckBox.new()
	_lock_checkbox.text = "Simulate modal lock (block movement/interact/switching)"
	_lock_checkbox.toggled.connect(func(pressed): _simulated_lock_active = pressed)
	root.add_child(_lock_checkbox)

	_readout = _make_label("")
	root.add_child(_readout)

	root.add_child(HSeparator.new())
	root.add_child(_make_label(
		"Load a local scene into Expedition Hub's content viewport via LocalSceneManager --"
		+ " nothing real (Travel, an Encounter) triggers this yet, so this is the manual stand-in.",
		11
	))
	var load_row := HBoxContainer.new()
	_scene_path_edit = LineEdit.new()
	_scene_path_edit.placeholder_text = "res://path/to/scene.tscn"
	_scene_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_row.add_child(_scene_path_edit)
	var load_button := Button.new()
	load_button.text = "Load"
	load_button.pressed.connect(_on_load_scene_pressed)
	load_row.add_child(load_button)
	root.add_child(load_row)
	_load_status_label = _make_label("")
	root.add_child(_load_status_label)

	refresh()


## Re-finds the current scene's PlayerController every time this tab
## becomes active or the menu reopens -- matters since which scene is
## loaded (and whether it has one at all) can change between opens.
## Also (re-)registers the synthetic lock check exactly once per
## PlayerController instance found.
func refresh() -> void:
	_player_controller = get_tree().get_first_node_in_group("player_controller")
	if _player_controller != null and _player_controller != _lock_registered_on:
		_player_controller.register_control_lock(func(): return _simulated_lock_active)
		_lock_registered_on = _player_controller
	_rebuild_character_option()


func _rebuild_character_option() -> void:
	_character_option.clear()

	if _player_controller == null:
		_readout.text = "(no PlayerController in the current scene)"
		return

	var present := _player_controller.get_present_characters()
	if present.is_empty():
		_readout.text = "(no characters registered)"
		return

	var active := _player_controller.get_active_character()
	for i in present.size():
		var sheet: CharacterSheet = present[i]
		_character_option.add_item(sheet.character_name if sheet != null else "(unnamed)")
		if sheet == active:
			_character_option.select(i)

	_readout.text = "Future clicks in the scene move whichever character is selected above."


func _on_character_selected(index: int) -> void:
	if _player_controller == null:
		return
	var present := _player_controller.get_present_characters()
	if index < 0 or index >= present.size():
		return

	var target: CharacterSheet = present[index]
	if _player_controller.set_active_character(target):
		_readout.text = "Switched -- future clicks move %s." % target.character_name
	else:
		var still_active := _player_controller.get_active_character()
		_readout.text = "Switch blocked (modal lock active) -- still on %s." % (still_active.character_name if still_active != null else "?")
		# The switch didn't happen -- snap the dropdown back to
		# whichever character is actually active, so it doesn't lie
		# about what just got picked.
		_rebuild_character_option()


func _on_load_scene_pressed() -> void:
	var path := _scene_path_edit.text.strip_edges()
	if path == "":
		_load_status_label.text = "Enter a scene path first."
		return

	if LocalSceneManager.load_local_scene(path):
		_load_status_label.text = "Loaded '%s'." % path
		# The scene that just loaded has its own fresh PlayerController --
		# re-find it so the Active Character section above reflects it
		# instead of whatever was there before (or nothing).
		refresh()
	else:
		_load_status_label.text = "Failed to load '%s' -- check the Output panel." % path
