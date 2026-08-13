class_name HealthDebugTab
extends DebugTab

## Injury and Disease are deliberately NOT unified into one shared
## form -- InjuryInstance has `treated`, DiseaseInstance has
## `contagious`/`virulence` instead. Forcing a common shape here would
## hide that real difference rather than reflect it.

var _member_option: OptionButton
var _condition_readout: Label

var _injury_name_edit: LineEdit
var _injury_severity_option: OptionButton
var _injury_list: VBoxContainer

var _disease_name_edit: LineEdit
var _disease_severity_option: OptionButton
var _disease_contagious_check: CheckBox
var _disease_list: VBoxContainer


func get_tab_title() -> String:
	return "Health"


func _ready() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	_member_option = _build_member_option()
	_member_option.item_selected.connect(func(_i): _refresh_for_member())
	root.add_child(_member_option)

	_condition_readout = _make_label("")
	root.add_child(_condition_readout)

	root.add_child(HSeparator.new())

	_build_injury_section(root)
	root.add_child(HSeparator.new())
	_build_disease_section(root)

	refresh()


func _build_injury_section(root: VBoxContainer) -> void:
	root.add_child(_make_label("Injuries", 14))

	var form := HBoxContainer.new()
	_injury_name_edit = LineEdit.new()
	_injury_name_edit.placeholder_text = "Injury name"
	_injury_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(_injury_name_edit)

	_injury_severity_option = OptionButton.new()
	for key in InjuryInstance.Severity.keys():
		_injury_severity_option.add_item(key.capitalize())
	form.add_child(_injury_severity_option)

	var inflict_button := Button.new()
	inflict_button.text = "Inflict"
	inflict_button.pressed.connect(_on_inflict_injury_pressed)
	form.add_child(inflict_button)
	root.add_child(form)

	_injury_list = VBoxContainer.new()
	root.add_child(_injury_list)


func _build_disease_section(root: VBoxContainer) -> void:
	root.add_child(_make_label("Diseases", 14))

	var form := HBoxContainer.new()
	_disease_name_edit = LineEdit.new()
	_disease_name_edit.placeholder_text = "Disease name"
	_disease_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(_disease_name_edit)

	_disease_severity_option = OptionButton.new()
	for key in DiseaseInstance.Severity.keys():
		_disease_severity_option.add_item(key.capitalize())
	form.add_child(_disease_severity_option)

	_disease_contagious_check = CheckBox.new()
	_disease_contagious_check.text = "Contagious"
	form.add_child(_disease_contagious_check)

	var inflict_button := Button.new()
	inflict_button.text = "Inflict"
	inflict_button.pressed.connect(_on_inflict_disease_pressed)
	form.add_child(inflict_button)
	root.add_child(form)

	_disease_list = VBoxContainer.new()
	root.add_child(_disease_list)


func refresh() -> void:
	if _member_option == null:
		return
	_refresh_member_option(_member_option)
	_refresh_for_member()


func _refresh_for_member() -> void:
	var sheet := _selected_member(_member_option)
	if sheet == null:
		_condition_readout.text = "(no party members)"
		_clear_list(_injury_list)
		_clear_list(_disease_list)
		return

	_condition_readout.text = "Condition: %s" % CharacterSheet.ConditionTier.keys()[sheet.get_condition_tier()]
	_rebuild_injury_list(sheet)
	_rebuild_disease_list(sheet)


func _clear_list(container: VBoxContainer) -> void:
	for child in container.get_children():
		child.queue_free()


func _on_inflict_injury_pressed() -> void:
	var sheet := _selected_member(_member_option)
	if sheet == null:
		return

	var injury := InjuryInstance.new()
	injury.injury_name = _injury_name_edit.text if _injury_name_edit.text != "" else "Unnamed Injury"
	injury.severity = _injury_severity_option.selected as InjuryInstance.Severity
	injury.day_acquired = TimeSystem.get_current_day()
	sheet.injuries.append(injury)

	_injury_name_edit.text = ""
	_refresh_for_member()
	PartyManager.notify_roster_changed()


func _on_inflict_disease_pressed() -> void:
	var sheet := _selected_member(_member_option)
	if sheet == null:
		return

	var disease := DiseaseInstance.new()
	disease.disease_name = _disease_name_edit.text if _disease_name_edit.text != "" else "Unnamed Disease"
	disease.severity = _disease_severity_option.selected as DiseaseInstance.Severity
	disease.contagious = _disease_contagious_check.button_pressed
	disease.day_contracted = TimeSystem.get_current_day()
	sheet.diseases.append(disease)

	_disease_name_edit.text = ""
	_refresh_for_member()
	PartyManager.notify_roster_changed()


func _rebuild_injury_list(sheet: CharacterSheet) -> void:
	_clear_list(_injury_list)
	for injury in sheet.injuries:
		var row := HBoxContainer.new()

		var label := _make_label(
			"%s (%s)" % [injury.injury_name, InjuryInstance.Severity.keys()[injury.severity]], 12
		)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		var treated_check := CheckBox.new()
		treated_check.text = "Treated"
		treated_check.button_pressed = injury.treated
		treated_check.toggled.connect(func(pressed):
			injury.treated = pressed
			PartyManager.notify_roster_changed()
		)
		row.add_child(treated_check)

		var remove_button := Button.new()
		remove_button.text = "Remove"
		remove_button.pressed.connect(func():
			sheet.injuries.erase(injury)
			_refresh_for_member()
			PartyManager.notify_roster_changed()
		)
		row.add_child(remove_button)

		_injury_list.add_child(row)


func _rebuild_disease_list(sheet: CharacterSheet) -> void:
	_clear_list(_disease_list)
	for disease in sheet.diseases:
		var row := HBoxContainer.new()

		var contagious_tag := "  [contagious]" if disease.contagious else ""
		var label := _make_label(
			"%s (%s)%s" % [disease.disease_name, DiseaseInstance.Severity.keys()[disease.severity], contagious_tag], 12
		)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		var remove_button := Button.new()
		remove_button.text = "Remove"
		remove_button.pressed.connect(func():
			sheet.diseases.erase(disease)
			_refresh_for_member()
			PartyManager.notify_roster_changed()
		)
		row.add_child(remove_button)

		_disease_list.add_child(row)
