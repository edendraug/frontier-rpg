class_name PartyCharacterCard
extends Control

## Reworked from the original single-character prototype creator
## (character_creator.gd). Removed: the Main/NPC mode dropdown
## (PartyManager now stamps is_main_character from slot position —
## see party_manager.gd) and the "Save to .tres" button (party
## creation is in-memory only until the Save/Load system exists).
## Point buy, presets, skills, and occupation preview are carried
## over essentially unchanged.
##
## Meant to be instantiated as a child by party_creator.gd, not run
## as a standalone scene. Call configure() every time a slot is
## opened — for a fresh character (existing_sheet = null) or to edit
## one already in the roster (existing_sheet = that CharacterSheet).

signal confirmed(sheet: CharacterSheet)
signal cancelled()

const MAIN_CHARACTER_SKILL_COUNT := 2
const NPC_SKILL_COUNT := 1

const STAT_INFO := [
	{"key": "brawn", "stat": CharacterSheet.Stat.BRAWN, "label": "Brawn"},
	{"key": "agility", "stat": CharacterSheet.Stat.AGILITY, "label": "Agility"},
	{"key": "grit", "stat": CharacterSheet.Stat.GRIT, "label": "Grit"},
	{"key": "wits", "stat": CharacterSheet.Stat.WITS, "label": "Wits"},
	{"key": "knowledge", "stat": CharacterSheet.Stat.KNOWLEDGE, "label": "Knowledge"},
	{"key": "presence", "stat": CharacterSheet.Stat.PRESENCE, "label": "Presence"},
]

var registry: CharacterDataRegistry

var free_skill_count: int = MAIN_CHARACTER_SKILL_COUNT

## The sheet currently being edited, or null if this configure() call
## is for a brand-new character. Passed straight through to
## PartyManager on confirm rather than always building a new
## CharacterSheet, so edits modify the existing object in place —
## anything the card doesn't touch (Hunger, Fatigue, Injuries,
## Diseases, Morale, Relationships) is left exactly as it was.
var _editing_sheet: CharacterSheet = null

var name_edit: LineEdit
var stat_spinboxes: Dictionary = {}      # key -> SpinBox
var stat_mod_labels: Dictionary = {}     # key -> Label
var occ_bonus_labels: Dictionary = {}    # key -> Label ("+2 from Blacksmith")
var points_label: Label
var _last_valid_scores: Dictionary = {}  # key -> int, for reverting overspends

var preset_option: OptionButton
var _preset_ids: Array = []              # index 0 is always "" (Custom/Point Buy)

var skill_checkboxes: Dictionary = {}    # skill_id -> CheckBox
var skill_selection_label: Label
var _selected_skill_ids: Array = []

var occupation_option: OptionButton
var occupation_preview: RichTextLabel
var _occupation_ids: Array = []

var confirm_button: Button
var status_label: RichTextLabel


func _ready() -> void:
	registry = PartyManager.get_registry()
	_build_ui()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 12)
	add_child(root)

	var name_row := HBoxContainer.new()
	name_row.add_child(_make_label("Name", 14))
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Character name"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_edit)
	root.add_child(name_row)

	_build_stat_section(root)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)

	var skills_column := VBoxContainer.new()
	skills_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_skill_section(skills_column)
	columns.add_child(skills_column)

	var occupation_column := VBoxContainer.new()
	occupation_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_occupation_section(occupation_column)
	columns.add_child(occupation_column)

	root.add_child(columns)

	_update_stat_displays()

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 12)

	confirm_button = Button.new()
	confirm_button.text = "Add to Party"
	confirm_button.pressed.connect(_on_confirm_pressed)
	button_row.add_child(confirm_button)

	var cancel_button := Button.new()
	cancel_button.text = "Cancel"
	cancel_button.pressed.connect(func(): cancelled.emit())
	button_row.add_child(cancel_button)

	root.add_child(button_row)

	status_label = RichTextLabel.new()
	status_label.custom_minimum_size = Vector2(0, 40)
	status_label.bbcode_enabled = true
	status_label.fit_content = true
	root.add_child(status_label)


func _make_label(text: String, font_size: int = 14) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	return l


## ============================================================
## CONFIGURE / LOAD — called by party_creator.gd each time a slot
## is opened, whether for a new character or to edit an existing one.
## ============================================================

func configure(is_main: bool, existing_sheet: CharacterSheet = null) -> void:
	free_skill_count = MAIN_CHARACTER_SKILL_COUNT if is_main else NPC_SKILL_COUNT
	_editing_sheet = existing_sheet
	status_label.text = ""

	# Reset disabled state up front, regardless of path below — a box
	# left disabled from a PREVIOUS configure() call on this same
	# (reused) card instance must never carry over. The final
	# _update_skill_checkbox_states() call below re-derives the
	# correct disabled state fresh either way.
	for skill_id in skill_checkboxes:
		skill_checkboxes[skill_id].disabled = false

	if existing_sheet == null:
		confirm_button.text = "Add to Party"
		_reset_to_blank()
	else:
		confirm_button.text = "Save Changes"
		_load_sheet(existing_sheet)

	_update_skill_selection_label()
	_update_skill_checkbox_states()
	_update_points_label()
	_update_stat_displays()


func _reset_to_blank() -> void:
	name_edit.text = ""

	for key in stat_spinboxes:
		stat_spinboxes[key].set_value_no_signal(PointBuyRules.BASELINE_SCORE)
		_last_valid_scores[key] = PointBuyRules.BASELINE_SCORE
	if preset_option != null:
		preset_option.select(0)

	_selected_skill_ids.clear()
	for skill_id in skill_checkboxes:
		skill_checkboxes[skill_id].set_pressed_no_signal(false)

	if not _occupation_ids.is_empty():
		occupation_option.select(0)


## Reconstructs the point-buy BASE score by subtracting the
## previously-applied Occupation's bonus back out of the sheet's
## stored (base + bonus) score — CharacterSheet only ever keeps the
## final combined value, so this is the only way to recover what the
## spinbox should show. Assumes the same Occupation is still
## selected; if the player picks a different one mid-edit, the bonus
## preview simply recalculates against the new selection like it
## always does, and Save Changes rebuilds the sheet correctly either way.
func _load_sheet(sheet: CharacterSheet) -> void:
	name_edit.text = sheet.character_name

	var occ_index: int = _occupation_ids.find(sheet.occupation_id)
	var old_occupation: OccupationDefinition = registry.occupations.get(sheet.occupation_id)
	if occ_index != -1:
		occupation_option.select(occ_index)

	for info in STAT_INFO:
		var final_score: int = sheet.get(info.key)
		var old_bonus: int = 0
		if old_occupation != null:
			old_bonus = int(old_occupation.stat_modifiers.get(info.stat, 0))
		var base_score: int = final_score - old_bonus
		stat_spinboxes[info.key].set_value_no_signal(base_score)
		_last_valid_scores[info.key] = base_score

	# Editing always starts from "Custom" — there's no record of
	# which preset (if any) originally produced these values.
	if preset_option != null:
		preset_option.select(0)

	_selected_skill_ids.clear()
	for progress in sheet.skills:
		var proficient: bool = progress.get_rank() != SkillProgress.Rank.UNSKILLED
		var cb: CheckBox = skill_checkboxes.get(progress.skill_id)
		if cb != null:
			cb.set_pressed_no_signal(proficient)
		if proficient:
			_selected_skill_ids.append(progress.skill_id)


## ============================================================
## STAT POINT BUY (unchanged from the original creator)
## ============================================================
func _build_stat_section(parent: VBoxContainer) -> void:
	parent.add_child(_make_label(
		"Stats — Point Buy (%d points, cap %d)" % [PointBuyRules.POINT_POOL, PointBuyRules.MAX_SCORE],
		16
	))

	var preset_row := HBoxContainer.new()
	preset_row.add_child(_make_label("Preset Spread:", 12))
	preset_option = OptionButton.new()
	preset_option.add_item("(Custom — Point Buy)")
	_preset_ids.append("")
	for preset_id in registry.stat_presets.keys():
		_preset_ids.append(preset_id)
		var preset: StatSpreadPreset = registry.stat_presets[preset_id]
		preset_option.add_item(preset.display_name)
	preset_option.item_selected.connect(_on_preset_selected)
	preset_row.add_child(preset_option)
	parent.add_child(preset_row)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	for info in STAT_INFO:
		var card := VBoxContainer.new()
		card.custom_minimum_size = Vector2(90, 0)

		var label := _make_label(info.label, 13)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(label)

		var spin := SpinBox.new()
		spin.min_value = PointBuyRules.MIN_SCORE
		spin.max_value = PointBuyRules.MAX_SCORE
		spin.step = 1
		spin.value = PointBuyRules.BASELINE_SCORE
		spin.value_changed.connect(_on_stat_changed.bind(info.key))
		stat_spinboxes[info.key] = spin
		_last_valid_scores[info.key] = PointBuyRules.BASELINE_SCORE
		card.add_child(spin)

		var bonus_label := _make_label("", 10)
		bonus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bonus_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		occ_bonus_labels[info.key] = bonus_label
		card.add_child(bonus_label)

		var mod_label := _make_label("+0", 12)
		mod_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stat_mod_labels[info.key] = mod_label
		card.add_child(mod_label)

		row.add_child(card)

	parent.add_child(row)

	points_label = Label.new()
	parent.add_child(points_label)

	_update_points_label()
	_update_stat_displays()


func _current_scores() -> Dictionary:
	var scores := {}
	for key in stat_spinboxes:
		scores[key] = int(stat_spinboxes[key].value)
	return scores


func _on_stat_changed(new_value: float, key: String) -> void:
	var scores := _current_scores()
	if PointBuyRules.points_remaining(scores) < 0:
		var spin: SpinBox = stat_spinboxes[key]
		spin.set_value_no_signal(_last_valid_scores[key])
	else:
		_last_valid_scores[key] = int(new_value)

	if preset_option != null and preset_option.selected != 0:
		preset_option.select(0)

	_update_points_label()
	_update_stat_displays()


func _update_points_label() -> void:
	var remaining := PointBuyRules.points_remaining(_current_scores())
	points_label.text = "Points remaining: %d" % remaining
	if remaining == 0:
		points_label.add_theme_color_override("font_color", Color.ORANGE)
	elif remaining < 0:
		points_label.add_theme_color_override("font_color", Color.RED)
	else:
		points_label.remove_theme_color_override("font_color")


func _on_preset_selected(index: int) -> void:
	var preset_id: String = _preset_ids[index]
	if preset_id == "":
		return
	_apply_preset(registry.stat_presets[preset_id])


func _apply_preset(preset: StatSpreadPreset) -> void:
	for key in stat_spinboxes:
		var value: int = int(preset.scores.get(key, PointBuyRules.BASELINE_SCORE))
		stat_spinboxes[key].set_value_no_signal(value)
		_last_valid_scores[key] = value

	_update_points_label()
	_update_stat_displays()


func _current_occupation() -> OccupationDefinition:
	if occupation_option == null or _occupation_ids.is_empty():
		return null
	var occ_id: String = _occupation_ids[occupation_option.selected]
	return registry.occupations[occ_id]


func _stat_enum_for_key(key: String) -> CharacterSheet.Stat:
	for info in STAT_INFO:
		if info.key == key:
			return info.stat
	return CharacterSheet.Stat.BRAWN


func _occupation_bonus_for(key: String) -> int:
	var occ := _current_occupation()
	if occ == null:
		return 0
	var stat_enum: CharacterSheet.Stat = _stat_enum_for_key(key)
	return int(occ.stat_modifiers.get(stat_enum, 0))


func _update_stat_displays() -> void:
	var occ := _current_occupation()
	for key in stat_spinboxes:
		var base_score: int = int(stat_spinboxes[key].value)
		var bonus: int = _occupation_bonus_for(key)
		var effective_score: int = base_score + bonus
		var mod: int = CharacterSheet.score_to_modifier(effective_score)

		stat_mod_labels[key].text = ("+%d" % mod) if mod >= 0 else str(mod)

		var bonus_label: Label = occ_bonus_labels[key]
		if bonus != 0 and occ != null:
			var sign_str: String = ("+%d" % bonus) if bonus > 0 else str(bonus)
			bonus_label.text = "%s from %s" % [sign_str, occ.display_name]
			bonus_label.add_theme_color_override(
				"font_color", Color.LIGHT_GREEN if bonus > 0 else Color.LIGHT_CORAL
			)
		else:
			bonus_label.text = ""


## ============================================================
## SKILLS (unchanged from the original creator)
## ============================================================
func _build_skill_section(parent: VBoxContainer) -> void:
	parent.add_child(_make_label("Skills", 16))
	skill_selection_label = _make_label("0 / %d proficiencies selected" % free_skill_count, 12)
	parent.add_child(skill_selection_label)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 340)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	parent.add_child(scroll)

	var grouped: Dictionary = {}  # Stat -> Array[SkillDefinition]
	for skill_id in registry.skills:
		var def: SkillDefinition = registry.skills[skill_id]
		if not grouped.has(def.governing_stat):
			grouped[def.governing_stat] = []
		grouped[def.governing_stat].append(def)

	for info in STAT_INFO:
		var group: Array = grouped.get(info.stat, [])
		if group.is_empty():
			continue

		list.add_child(_make_label(info.label, 13))
		group.sort_custom(func(a, b): return a.display_name < b.display_name)

		for def in group:
			var cb := CheckBox.new()
			cb.text = def.display_name
			cb.tooltip_text = def.description
			cb.toggled.connect(_on_skill_toggled.bind(def.skill_id, cb))
			skill_checkboxes[def.skill_id] = cb
			list.add_child(cb)


func _on_skill_toggled(pressed: bool, skill_id: String, checkbox: CheckBox) -> void:
	if pressed:
		if _selected_skill_ids.size() >= free_skill_count:
			checkbox.set_pressed_no_signal(false)
			return
		_selected_skill_ids.append(skill_id)
	else:
		_selected_skill_ids.erase(skill_id)

	_update_skill_selection_label()
	_update_skill_checkbox_states()


func _update_skill_selection_label() -> void:
	skill_selection_label.text = "%d / %d proficiencies selected" % [_selected_skill_ids.size(), free_skill_count]


func _update_skill_checkbox_states() -> void:
	var limit_reached := _selected_skill_ids.size() >= free_skill_count
	for skill_id in skill_checkboxes:
		var cb: CheckBox = skill_checkboxes[skill_id]
		if not cb.button_pressed:
			cb.disabled = limit_reached


## ============================================================
## OCCUPATION (unchanged from the original creator)
## ============================================================
func _build_occupation_section(parent: VBoxContainer) -> void:
	parent.add_child(_make_label("Occupation", 16))

	occupation_option = OptionButton.new()
	if registry.occupations.is_empty():
		occupation_option.add_item("(none found — run generate_sample_data.gd first)")
	else:
		for occ_id in registry.occupations.keys():
			_occupation_ids.append(occ_id)
			var occ: OccupationDefinition = registry.occupations[occ_id]
			occupation_option.add_item(occ.display_name)
	occupation_option.item_selected.connect(_on_occupation_selected)
	parent.add_child(occupation_option)

	occupation_preview = RichTextLabel.new()
	occupation_preview.bbcode_enabled = true
	occupation_preview.custom_minimum_size = Vector2(0, 340)
	occupation_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(occupation_preview)

	_update_occupation_preview()


func _on_occupation_selected(_index: int) -> void:
	_update_occupation_preview()
	_update_stat_displays()


func _update_occupation_preview() -> void:
	if _occupation_ids.is_empty():
		occupation_preview.text = ""
		return

	var occ_id: String = _occupation_ids[occupation_option.selected]
	var occ: OccupationDefinition = registry.occupations[occ_id]

	var lines: Array = []
	lines.append("[b]%s[/b]" % occ.display_name)
	lines.append(occ.description)
	lines.append("")
	lines.append("[b]Stat Modifiers:[/b]")
	if occ.stat_modifiers.is_empty():
		lines.append("  (none)")
	for stat_value in occ.stat_modifiers:
		var label := _stat_label_for_enum(stat_value)
		var val: int = occ.stat_modifiers[stat_value]
		var val_str: String = ("+%d" % val) if val >= 0 else str(val)
		lines.append("  %s %s" % [label, val_str])

	lines.append("")
	var trait_def: TraitDefinition = registry.traits.get(occ.granted_trait_id)
	if trait_def:
		lines.append("[b]Grants Trait:[/b] %s" % trait_def.display_name)
		lines.append(trait_def.description)

	occupation_preview.text = "\n".join(lines)


func _stat_label_for_enum(stat_value) -> String:
	for info in STAT_INFO:
		if info.stat == stat_value:
			return info.label
	return "Unknown"


## ============================================================
## CONFIRM
## ============================================================
func _on_confirm_pressed() -> void:
	var scores := _current_scores()

	if PointBuyRules.points_remaining(scores) < 0:
		status_label.text = "[color=red]Point buy pool exceeded — adjust stats before confirming.[/color]"
		return

	if _occupation_ids.is_empty():
		status_label.text = "[color=red]No Occupations loaded — run generate_sample_data.gd first.[/color]"
		return

	if _selected_skill_ids.size() != free_skill_count:
		status_label.text = (
			"[color=red]Choose exactly %d skill proficiencies before confirming.[/color]" % free_skill_count
		)
		return

	var sheet := _build_sheet_from_current_state(scores)
	confirmed.emit(sheet)


## Builds against _editing_sheet if editing (modifies it in place,
## leaving Hunger/Fatigue/Injuries/Diseases/Morale/Relationships
## untouched), or a fresh CharacterSheet if this is a new character.
## Mirrors the original creator's build logic exactly — editing is
## just "re-run the same build against the same object," not a
## separate code path. Note: is_main_character is deliberately NOT
## set here — PartyManager stamps that from slot position on
## add_character()/update_character(), the single place that rule lives.
func _build_sheet_from_current_state(scores: Dictionary) -> CharacterSheet:
	var sheet := _editing_sheet if _editing_sheet != null else CharacterSheet.new()

	sheet.character_name = name_edit.text if name_edit.text != "" else "Unnamed"

	# Strip any previously-granted INNATE trait before reapplying —
	# otherwise re-confirming the same Occupation on an edit would
	# append a duplicate each time. EARNED traits (future Event
	# System grants) are left untouched.
	sheet.traits = sheet.traits.filter(func(t): return t.source != TraitInstance.Source.INNATE)

	for key in scores:
		sheet.set(key, scores[key])

	var occ_id: String = _occupation_ids[occupation_option.selected]
	var occupation: OccupationDefinition = registry.occupations[occ_id]
	occupation.apply_to(sheet, 0)

	# Two free proficiencies = enough starting xp to land at Skilled
	# rank immediately, reusing the same rank/xp system skills grow
	# through during play rather than adding a separate flag.
	var proficient_xp: int = SkillProgress.RANK_THRESHOLDS[SkillProgress.Rank.SKILLED]
	sheet.skills = []
	for skill_id in registry.skills:
		var progress := SkillProgress.new()
		progress.skill_id = skill_id
		if skill_id in _selected_skill_ids:
			progress.xp = proficient_xp
		sheet.skills.append(progress)

	return sheet
