class_name PartyDebugTab
extends DebugTab

var _member_option: OptionButton
var _hunger_spin: SpinBox
var _fatigue_spin: SpinBox
var _morale_spin: SpinBox
var _readout: Label


func get_tab_title() -> String:
	return "Party"


func _ready() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	_member_option = _build_member_option()
	_member_option.item_selected.connect(func(_i): _load_selected_member())
	root.add_child(_member_option)

	root.add_child(HSeparator.new())

	_hunger_spin = _build_stat_row(root, "Hunger (100 = fed):")
	_fatigue_spin = _build_stat_row(root, "Fatigue (0 = rested):")
	_morale_spin = _build_stat_row(root, "Morale:")

	var apply_button := Button.new()
	apply_button.text = "Apply"
	apply_button.pressed.connect(_on_apply_pressed)
	root.add_child(apply_button)

	root.add_child(HSeparator.new())
	_readout = _make_label("")
	root.add_child(_readout)

	refresh()


func _build_stat_row(root: VBoxContainer, label_text: String) -> SpinBox:
	var row := HBoxContainer.new()
	row.add_child(_make_label(label_text, 12))
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = 100
	spin.value = 100
	row.add_child(spin)
	root.add_child(row)
	return spin


func refresh() -> void:
	if _member_option == null:
		return
	_refresh_member_option(_member_option)
	_load_selected_member()


func _load_selected_member() -> void:
	var sheet := _selected_member(_member_option)
	if sheet == null:
		_readout.text = "(no party members)"
		return
	_hunger_spin.set_value_no_signal(sheet.hunger)
	_fatigue_spin.set_value_no_signal(sheet.fatigue)
	_morale_spin.set_value_no_signal(sheet.morale)
	_update_readout(sheet)


func _on_apply_pressed() -> void:
	var sheet := _selected_member(_member_option)
	if sheet == null:
		return
	sheet.hunger = _hunger_spin.value
	sheet.fatigue = _fatigue_spin.value
	sheet.morale = _morale_spin.value
	_update_readout(sheet)
	PartyManager.notify_roster_changed()


func _update_readout(sheet: CharacterSheet) -> void:
	_readout.text = "Condition: %s\nMorale Tier: %s" % [
		CharacterSheet.ConditionTier.keys()[sheet.get_condition_tier()],
		CharacterSheet.MoraleTier.keys()[sheet.get_morale_tier()],
	]
