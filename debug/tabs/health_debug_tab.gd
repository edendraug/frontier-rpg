class_name HealthDebugTab
extends DebugTab

## Injury and Disease are deliberately NOT unified into one shared
## form -- InjuryInstance has `treated`, DiseaseInstance has
## `contagious`/`virulence` instead. Forcing a common shape here would
## hide that real difference rather than reflect it.
##
## Both DO share an identical need, though: a way to actually attach
## a ModifierEntry penalty when inflicting one. `penalties` has
## existed on both instances since day one and already flows through
## CharacterSheet.get_modifier_entries() into SkillCheck -- nothing
## has ever populated it from here. _build_penalty_subform()/
## _read_penalty_entry() below are that missing authoring step,
## shared between both sections since the ModifierEntry shape itself
## doesn't differ between an Injury's penalty and a Disease's.

var _member_option: OptionButton
var _condition_readout: Label

var _injury_name_edit: LineEdit
var _injury_severity_option: OptionButton
var _injury_list: VBoxContainer
var _injury_penalty_controls: Dictionary

var _disease_name_edit: LineEdit
var _disease_severity_option: OptionButton
var _disease_contagious_check: CheckBox
var _disease_list: VBoxContainer
var _disease_penalty_controls: Dictionary


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

	_injury_penalty_controls = _build_penalty_subform(root)

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

	_disease_penalty_controls = _build_penalty_subform(root)

	_disease_list = VBoxContainer.new()
	root.add_child(_disease_list)


## ============================================================
## PENALTY SUBFORM (shared by Injury + Disease sections)
## ============================================================
## Builds one instance of the penalty-authoring widget and returns
## its controls keyed by name. Called twice (once per section) so
## Injury and Disease each get their own independent set of fields --
## only the WIDGET SHAPE is shared, not any state.
func _build_penalty_subform(root: VBoxContainer) -> Dictionary:
	var controls := {}

	var enabled_check := CheckBox.new()
	enabled_check.text = "Attach penalty (ModifierEntry) on inflict"
	root.add_child(enabled_check)
	controls["enabled"] = enabled_check

	var target_row := HBoxContainer.new()
	var skill_edit := LineEdit.new()
	skill_edit.placeholder_text = "target skill id(s), comma-separated (e.g. craft, marksmanship)"
	skill_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_row.add_child(skill_edit)
	controls["skill_ids"] = skill_edit

	var stat_option := OptionButton.new()
	stat_option.add_item("(no stat target)")
	for key in CharacterSheet.Stat.keys():
		stat_option.add_item(key.capitalize())
	target_row.add_child(stat_option)
	controls["stat_option"] = stat_option
	root.add_child(target_row)

	var effect_row := HBoxContainer.new()
	var type_option := OptionButton.new()
	type_option.add_item("Additive Penalty (stat/skill total)")
	type_option.add_item("Suppress Bonus Dice")
	effect_row.add_child(type_option)
	controls["type_option"] = type_option

	var value_spin := SpinBox.new()
	value_spin.min_value = -10
	value_spin.max_value = 10
	value_spin.step = 1
	value_spin.value = -1
	value_spin.tooltip_text = "Additive: amount added to the check total.\nSuppress: bonus dice removed (ignored if Full below is checked)."
	effect_row.add_child(value_spin)
	controls["value_spin"] = value_spin

	var full_suppress_check := CheckBox.new()
	full_suppress_check.text = "Full (treat as Unskilled)"
	full_suppress_check.tooltip_text = "Only applies when type is Suppress Bonus Dice. Ignores the value above -- bonus dice go to 0 outright."
	effect_row.add_child(full_suppress_check)
	controls["full_suppress"] = full_suppress_check
	root.add_child(effect_row)

	return controls


## Builds a single ModifierEntry from a penalty subform's current
## state, or null if the subform is unchecked or has no targets --
## callers should skip attaching in either case. One entry with
## potentially several targets, matching the shared-scope decision:
## a "Broken Hand" style penalty naming both Craft and Marksmanship
## here is still ONE ModifierEntry, ONE source_label, not two.
func _read_penalty_entry(controls: Dictionary, default_source_label: String) -> ModifierEntry:
	if not controls["enabled"].button_pressed:
		return null

	var targets: Array[String] = []
	for raw_id in (controls["skill_ids"] as LineEdit).text.split(","):
		var id := raw_id.strip_edges()
		if id != "":
			targets.append(ModifierResolver.target_for_skill(id))

	var stat_index: int = controls["stat_option"].selected
	if stat_index > 0:
		targets.append(ModifierResolver.target_for_stat((stat_index - 1) as CharacterSheet.Stat))

	if targets.is_empty():
		return null

	var m := ModifierEntry.new()
	m.targets = targets
	m.source_label = default_source_label

	if controls["type_option"].selected == 1:
		m.type = ModifierEntry.Type.SUPPRESS_BONUS_DICE
		m.full_suppression = controls["full_suppress"].button_pressed
		m.value = controls["value_spin"].value
	else:
		m.type = ModifierEntry.Type.ADDITIVE
		m.value = controls["value_spin"].value

	return m


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

	var penalty := _read_penalty_entry(_injury_penalty_controls, injury.injury_name)
	if penalty != null:
		injury.penalties.append(penalty)

	sheet.injuries.append(injury)
	VitalsSystem.apply_injury_morale_hit(sheet, injury.severity)

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

	var penalty := _read_penalty_entry(_disease_penalty_controls, disease.disease_name)
	if penalty != null:
		disease.penalties.append(penalty)

	sheet.diseases.append(disease)
	VitalsSystem.apply_disease_morale_hit(sheet, disease.severity)

	_disease_name_edit.text = ""
	_refresh_for_member()
	PartyManager.notify_roster_changed()


func _rebuild_injury_list(sheet: CharacterSheet) -> void:
	_clear_list(_injury_list)
	for injury in sheet.injuries:
		var row := HBoxContainer.new()

		var label := _make_label(
			"%s (%s)%s" % [injury.injury_name, InjuryInstance.Severity.keys()[injury.severity], _penalty_suffix(injury.penalties)], 12
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
		var contagious_tag := "  [contagious]" if disease.contagious else ""
		var row := HBoxContainer.new()

		var label := _make_label(
			"%s (%s)%s%s" % [disease.disease_name, DiseaseInstance.Severity.keys()[disease.severity], contagious_tag, _penalty_suffix(disease.penalties)], 12
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


## Terse "(-2 skill:craft)" / "(Suppress skill:craft, skill:marksmanship)"
## style summary so an attached penalty is at least visible in the
## list without building a full breakdown UI yet -- crude but
## functional, matching the project's usual first pass.
func _penalty_suffix(penalties: Array) -> String:
	if penalties.is_empty():
		return ""
	var parts: Array[String] = []
	for p in penalties:
		var entry := p as ModifierEntry
		var target_list := ", ".join(entry.targets)
		if entry.type == ModifierEntry.Type.SUPPRESS_BONUS_DICE:
			var desc := "Full" if entry.full_suppression else "-%d" % int(entry.value)
			parts.append("%s dice: %s" % [desc, target_list])
		else:
			parts.append("%+d: %s" % [int(entry.value), target_list])
	return "  [%s]" % "; ".join(parts)
