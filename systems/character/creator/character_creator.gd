extends Control
## Prototype Character Creator.
##
## SETUP: create a new empty scene with a Control node as the root,
## attach this script to it, and run the scene. The UI builds itself
## at runtime — no hand-authored .tscn layout needed for this pass.
##
## Layout: a stat point-buy row across the top, then two columns
## below — Skills on the left, Occupation on the right — followed
## by a Create button and a result summary.

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

var creation_mode_option: OptionButton
var free_skill_count: int = MAIN_CHARACTER_SKILL_COUNT

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

var output_label: RichTextLabel
var _last_created_sheet: CharacterSheet = null


func _ready() -> void:
	registry = CharacterDataRegistry.new()
	_build_ui()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 12)
	add_child(root)

	root.add_child(_make_label("Character Creator (Prototype)", 20))

	var mode_row := HBoxContainer.new()
	mode_row.add_child(_make_label("Creation Mode", 14))
	creation_mode_option = OptionButton.new()
	creation_mode_option.add_item("Main Character")
	creation_mode_option.add_item("NPC (Party Member)")
	creation_mode_option.item_selected.connect(_on_mode_changed)
	mode_row.add_child(creation_mode_option)
	root.add_child(mode_row)

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

	# Stat cards were built before the Occupation dropdown existed,
	# so their initial bonus/modifier display didn't know about the
	# default selection yet — sync it now that both exist.
	_update_stat_displays()

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 12)

	var create_button := Button.new()
	create_button.text = "Create Character"
	create_button.pressed.connect(_on_create_pressed)
	button_row.add_child(create_button)

	var save_button := Button.new()
	save_button.text = "Save to .tres"
	save_button.pressed.connect(_on_save_pressed)
	button_row.add_child(save_button)

	root.add_child(button_row)

	output_label = RichTextLabel.new()
	output_label.custom_minimum_size = Vector2(0, 220)
	output_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	output_label.bbcode_enabled = true
	root.add_child(output_label)


func _make_label(text: String, font_size: int = 14) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	return l


## NPCs get fewer starting skill proficiencies than the Main
## Character, per design — this is a manual stand-in for what the
## future Party Creator will decide automatically based on creation
## order. If shrinking the count leaves too many boxes checked,
## the newest picks are dropped first.
func _on_mode_changed(index: int) -> void:
	free_skill_count = MAIN_CHARACTER_SKILL_COUNT if index == 0 else NPC_SKILL_COUNT

	while _selected_skill_ids.size() > free_skill_count:
		var excess_id: String = _selected_skill_ids.pop_back()
		var cb: CheckBox = skill_checkboxes[excess_id]
		cb.set_pressed_no_signal(false)

	_update_skill_selection_label()
	_update_skill_checkbox_states()


## ============================================================
## STAT POINT BUY (top row)
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


## Reverts overspending rather than just flagging it — the pool is
## a hard cap here, not a suggestion. A manual edit also breaks any
## preset that was applied, since the values no longer match it —
## drop the dropdown back to "Custom" so the UI never lies about it.
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
		return  # "Custom" — leave whatever values are already set
	_apply_preset(registry.stat_presets[preset_id])


## Applies a preset by writing straight into the same spinboxes
## point buy uses — a preset is just a shortcut starting point, not
## a separate mechanic, so everything downstream (points remaining,
## occupation bonuses, modifier display) keeps working unchanged.
## Uses set_value_no_signal() rather than .value = x so that filling
## in stats one at a time can never trip the overspend-revert guard
## on an intermediate, momentarily-invalid state.
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


## Modifier shown here is the EFFECTIVE modifier — base score plus
## whatever the currently selected Occupation contributes — so the
## number the player sees always matches what they'll actually get.
## The bonus itself is called out separately so it's never hidden.
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
## SKILLS (left column)
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


## Disables unchecked boxes once the limit is reached, so a third
## pick can't even be attempted — same hard-cap treatment as the
## point-buy pool above.
func _update_skill_checkbox_states() -> void:
	var limit_reached := _selected_skill_ids.size() >= free_skill_count
	for skill_id in skill_checkboxes:
		var cb: CheckBox = skill_checkboxes[skill_id]
		if not cb.button_pressed:
			cb.disabled = limit_reached


## ============================================================
## OCCUPATION (right column)
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
## CREATE
## ============================================================
func _on_create_pressed() -> void:
	var scores := _current_scores()

	if PointBuyRules.points_remaining(scores) < 0:
		output_label.text = "[color=red]Point buy pool exceeded — adjust stats before creating.[/color]"
		return

	if _occupation_ids.is_empty():
		output_label.text = "[color=red]No Occupations loaded — run generate_sample_data.gd first.[/color]"
		return

	if _selected_skill_ids.size() != free_skill_count:
		output_label.text = "[color=red]Choose exactly %d skill proficiencies before creating.[/color]" % free_skill_count
		return

	var sheet := CharacterSheet.new()
	sheet.character_name = name_edit.text if name_edit.text != "" else "Unnamed"
	sheet.is_main_character = (creation_mode_option.selected == 0)

	for key in scores:
		sheet.set(key, scores[key])

	var occ_id: String = _occupation_ids[occupation_option.selected]
	var occupation: OccupationDefinition = registry.occupations[occ_id]
	occupation.apply_to(sheet, 0)

	# Two free proficiencies = enough starting xp to land at Skilled
	# rank immediately, reusing the same rank/xp system skills grow
	# through during play rather than adding a separate flag.
	var proficient_xp: int = SkillProgress.RANK_THRESHOLDS[SkillProgress.Rank.SKILLED]
	for skill_id in registry.skills:
		var progress := SkillProgress.new()
		progress.skill_id = skill_id
		if skill_id in _selected_skill_ids:
			progress.xp = proficient_xp
		sheet.skills.append(progress)

	_display_sheet(sheet, occupation)
	_last_created_sheet = sheet


func _display_sheet(sheet: CharacterSheet, occupation: OccupationDefinition) -> void:
	var lines: Array = []
	lines.append("[b]%s[/b] — %s" % [sheet.character_name, occupation.display_name])
	lines.append("")

	for info in STAT_INFO:
		var score: int = sheet.get(info.key)
		var mod: int = sheet.get_base_modifier(info.stat)
		var mod_str: String = ("+%d" % mod) if mod >= 0 else str(mod)
		lines.append("%s: %d (%s)" % [info.label, score, mod_str])

	lines.append("")
	lines.append("Traits:")
	for t in sheet.traits:
		var def: TraitDefinition = registry.traits.get(t.trait_id)
		var label: String = def.display_name if def else t.trait_id
		lines.append("  - %s (%s)" % [label, TraitInstance.Source.keys()[t.source]])

	lines.append("")
	lines.append("Skill Proficiencies:")
	for progress in sheet.skills:
		if progress.get_rank() != SkillProgress.Rank.UNSKILLED:
			var def: SkillDefinition = registry.skills.get(progress.skill_id)
			var label: String = def.display_name if def else progress.skill_id
			lines.append("  - %s (%s)" % [label, SkillProgress.Rank.keys()[progress.get_rank()]])

	lines.append("")
	lines.append("Condition: %s" % CharacterSheet.ConditionTier.keys()[sheet.get_condition_tier()])
	lines.append("Morale: %s" % CharacterSheet.MoraleTier.keys()[sheet.get_morale_tier()])

	output_label.text = "\n".join(lines)


## ============================================================
## SAVE
## ============================================================
## Saves to user:// rather than res:// — res:// is only writable
## from inside the editor during development; user:// is the path
## that stays writable once this ever runs as an exported build.
func _on_save_pressed() -> void:
	if _last_created_sheet == null:
		output_label.text = "[color=red]Create a character first before saving.[/color]"
		return

	var dir_path := "user://characters/"
	DirAccess.make_dir_recursive_absolute(dir_path)

	var slug := _slugify(_last_created_sheet.character_name)
	var file_path := dir_path + slug + ".tres"

	var err := ResourceSaver.save(_last_created_sheet, file_path)
	if err == OK:
		output_label.append_text("\n\n[color=green]Saved to %s[/color]" % file_path)
	else:
		output_label.append_text("\n\n[color=red]Save failed (error code %d)[/color]" % err)


func _slugify(text: String) -> String:
	var slug := text.strip_edges().to_lower().replace(" ", "_")
	if slug == "":
		slug = "unnamed_%d" % Time.get_unix_time_from_system()
	return slug
