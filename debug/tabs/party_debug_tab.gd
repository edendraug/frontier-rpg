class_name PartyDebugTab
extends DebugTab

var _member_option: OptionButton
var _hunger_spin: SpinBox
var _fatigue_spin: SpinBox
var _apply_vitals_button: Button

var _event_label_edit: LineEdit
var _event_magnitude_spin: SpinBox
var _event_decay_spin: SpinBox

var _readout: Label
var _events_list: VBoxContainer


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

	root.add_child(_make_label("Hunger / Fatigue", 14))
	_hunger_spin = _build_stat_row(root, "Hunger (100 = fed):")
	_fatigue_spin = _build_stat_row(root, "Fatigue (0 = rested):")

	_apply_vitals_button = Button.new()
	_apply_vitals_button.text = "Apply"
	_apply_vitals_button.pressed.connect(_on_apply_vitals_pressed)
	root.add_child(_apply_vitals_button)

	root.add_child(HSeparator.new())

	# Morale has no direct override here -- it's derived by VitalsSystem
	# from whatever morale_events are currently active (see
	# VitalsSystem._recompute_morale). Setting it directly would just
	# get overwritten on the next hourly tick. This adds a real
	# (decaying) test event instead, the same way any real trigger
	# (an injury, eventually Food/Encounters) would.
	root.add_child(_make_label("Add Test Morale Event", 14))

	var event_row := HBoxContainer.new()
	_event_label_edit = LineEdit.new()
	_event_label_edit.placeholder_text = "Source label"
	_event_label_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	event_row.add_child(_event_label_edit)

	_event_magnitude_spin = SpinBox.new()
	_event_magnitude_spin.min_value = -50
	_event_magnitude_spin.max_value = 50
	_event_magnitude_spin.value = -5
	event_row.add_child(_event_magnitude_spin)
	root.add_child(event_row)

	var decay_row := HBoxContainer.new()
	decay_row.add_child(_make_label("Fade over (hours):", 12))
	_event_decay_spin = SpinBox.new()
	_event_decay_spin.min_value = 1
	_event_decay_spin.max_value = 500
	_event_decay_spin.value = 24
	decay_row.add_child(_event_decay_spin)
	root.add_child(decay_row)

	var apply_event_button := Button.new()
	apply_event_button.text = "Apply Event"
	apply_event_button.pressed.connect(_on_apply_event_pressed)
	root.add_child(apply_event_button)

	root.add_child(HSeparator.new())
	_readout = _make_label("")
	root.add_child(_readout)

	_events_list = VBoxContainer.new()
	root.add_child(_events_list)

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
		_clear_events_list()
		return
	_hunger_spin.set_value_no_signal(sheet.hunger)
	_fatigue_spin.set_value_no_signal(sheet.fatigue)
	_update_readout(sheet)
	_rebuild_events_list(sheet)


func _on_apply_vitals_pressed() -> void:
	var sheet := _selected_member(_member_option)
	if sheet == null:
		return
	sheet.hunger = _hunger_spin.value
	sheet.fatigue = _fatigue_spin.value
	_update_readout(sheet)
	PartyManager.notify_roster_changed()


func _on_apply_event_pressed() -> void:
	var sheet := _selected_member(_member_option)
	if sheet == null:
		return

	var label := _event_label_edit.text if _event_label_edit.text != "" else "Debug Event"
	var magnitude: float = _event_magnitude_spin.value
	var fade_hours: float = _event_decay_spin.value

	VitalsSystem.apply_morale_event(sheet, label, magnitude, absf(magnitude) / fade_hours)

	_event_label_edit.text = ""
	_update_readout(sheet)
	_rebuild_events_list(sheet)


func _update_readout(sheet: CharacterSheet) -> void:
	_readout.text = "Condition: %s\nMorale: %.1f / 100 — %s\nVitals modifier: %.1f (continuous, from current Hunger/Fatigue/Injury/Disease)" % [
		CharacterSheet.ConditionTier.keys()[sheet.get_condition_tier()],
		sheet.morale,
		CharacterSheet.MoraleTier.keys()[sheet.get_morale_tier()],
		VitalsSystem.get_vitals_morale_modifier(sheet),
	]


func _clear_events_list() -> void:
	for child in _events_list.get_children():
		child.queue_free()


func _rebuild_events_list(sheet: CharacterSheet) -> void:
	_clear_events_list()
	if sheet.morale_events.is_empty():
		_events_list.add_child(_make_label("(no active morale events)", 11))
		return

	_events_list.add_child(_make_label("Active Morale Events:", 12))
	for event in sheet.morale_events:
		var sign_str := ("+%.1f" % event.magnitude) if event.magnitude >= 0 else ("%.1f" % event.magnitude)
		_events_list.add_child(_make_label(
			"  %s: %s (fading %.2f/hr)" % [event.source_label, sign_str, event.decay_per_hour],
			11
		))
