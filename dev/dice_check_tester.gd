extends Control
## Dice / Skill Check Tester (Prototype).
##
## SETUP: create a new empty scene with a Control node as the root,
## attach this script, and run it. No visuals for the dice
## themselves yet — this is purely to sanity-check the resolution
## math (DC tiers, outcome bands) against real character data
## before any 3D dice exist.
##
## Loads every CharacterSheet .tres saved from the Character
## Creator's "Save to .tres" button (user://characters/). Pick a
## character, a skill, and a difficulty, then Roll — the log shows
## the full breakdown (individual dice, modifiers, total, outcome)
## for every roll so far, so you can fire off several in a row and
## see the spread.

const CHARACTER_SAVE_DIR := "user://characters/"

var registry: CharacterDataRegistry
var characters: Dictionary = {}   # file id (no extension) -> CharacterSheet
var _character_ids: Array = []
var _skill_ids: Array = []

var character_option: OptionButton
var skill_option: OptionButton
var difficulty_option: OptionButton
var log_output: RichTextLabel


func _ready() -> void:
	registry = CharacterDataRegistry.new()
	_load_characters()
	_build_ui()


func _load_characters() -> void:
	var dir := DirAccess.open(CHARACTER_SAVE_DIR)
	if dir == null:
		push_warning("No saved characters found at %s — save one from the Character Creator first." % CHARACTER_SAVE_DIR)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var sheet: CharacterSheet = load(CHARACTER_SAVE_DIR + file_name)
			if sheet != null:
				characters[file_name.trim_suffix(".tres")] = sheet
		file_name = dir.get_next()
	dir.list_dir_end()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 12)
	add_child(root)

	root.add_child(_make_label("Dice / Skill Check Tester (Prototype)", 20))

	var char_row := HBoxContainer.new()
	char_row.add_child(_make_label("Character", 14))
	character_option = OptionButton.new()
	if characters.is_empty():
		character_option.add_item("(none found — save one from the Character Creator first)")
	else:
		for char_id in characters.keys():
			_character_ids.append(char_id)
			var sheet: CharacterSheet = characters[char_id]
			character_option.add_item(sheet.character_name if sheet.character_name != "" else char_id)
	char_row.add_child(character_option)
	root.add_child(char_row)

	var skill_row := HBoxContainer.new()
	skill_row.add_child(_make_label("Skill", 14))
	skill_option = OptionButton.new()
	for skill_id in registry.skills.keys():
		_skill_ids.append(skill_id)
		var def: SkillDefinition = registry.skills[skill_id]
		skill_option.add_item(def.display_name)
	skill_row.add_child(skill_option)
	root.add_child(skill_row)

	var diff_row := HBoxContainer.new()
	diff_row.add_child(_make_label("Difficulty", 14))
	difficulty_option = OptionButton.new()
	for tier_name in DiceResolver.DifficultyTier.keys():
		var tier_value: int = DiceResolver.DifficultyTier[tier_name]
		var dc: int = DiceResolver.dc_for_tier(tier_value)
		difficulty_option.add_item("%s (DC %d)" % [tier_name.capitalize(), dc])
	difficulty_option.select(DiceResolver.DifficultyTier.MEDIUM)
	diff_row.add_child(difficulty_option)
	root.add_child(diff_row)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 12)

	var roll_button := Button.new()
	roll_button.text = "Roll"
	roll_button.pressed.connect(_on_roll_pressed)
	button_row.add_child(roll_button)

	var clear_button := Button.new()
	clear_button.text = "Clear Log"
	clear_button.pressed.connect(_on_clear_pressed)
	button_row.add_child(clear_button)

	root.add_child(button_row)

	log_output = RichTextLabel.new()
	log_output.bbcode_enabled = true
	log_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_output.custom_minimum_size = Vector2(0, 320)
	root.add_child(log_output)


func _make_label(text: String, font_size: int = 14) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	return l


func _on_clear_pressed() -> void:
	log_output.text = ""


func _on_roll_pressed() -> void:
	if _character_ids.is_empty():
		log_output.text = "[color=#FF4444]No saved characters found in %s[/color]" % CHARACTER_SAVE_DIR
		return

	var char_id: String = _character_ids[character_option.selected]
	var character: CharacterSheet = characters[char_id]

	var skill_id: String = _skill_ids[skill_option.selected]
	var def: SkillDefinition = registry.skills[skill_id]

	var tier: int = difficulty_option.selected
	var dc := DiceResolver.dc_for_tier(tier)

	var check := SkillCheck.new(character, skill_id, dc, registry)
	var result := check.resolve()

	# Outcome is already fully decided at this point — the 3D roll
	# below is presentation only, animating dice toward a result
	# that's already final.
	await DiceVisualizer.roll_and_show(result)

	_append_result(character, def, result)


func _append_result(character: CharacterSheet, def: SkillDefinition, result: SkillCheckResult) -> void:
	var lines: Array = []
	lines.append("[b]%s[/b] — %s (DC %d)" % [character.character_name, def.display_name, result.difficulty])
	lines.append("  Base 2d6: %s (sum %d)" % [str(result.base_dice), result.base_dice_total()])

	if not result.bonus_dice.is_empty():
		lines.append("  Bonus dice: %s (sum %d)" % [str(result.bonus_dice), result.bonus_dice_total()])
	else:
		lines.append("  Bonus dice: none (Unskilled)")

	lines.append("  Stat modifier (%s): %s" % [def.display_name, _signed(result.stat_modifier)])

	if not result.contributing_modifiers.is_empty():
		for entry in result.contributing_modifiers:
			lines.append("  Modifier — %s: %s" % [entry.source_label, _signed(int(entry.value))])
	elif result.modifier_bonus != 0:
		lines.append("  Modifier bonus: %s" % _signed(result.modifier_bonus))

	lines.append("  [b]Total: %d[/b] vs DC %d" % [result.total, result.difficulty])
	lines.append("  Outcome: [color=%s]%s[/color]" % [_outcome_color(result.outcome), result.outcome_name()])
	lines.append("")

	log_output.append_text("\n".join(lines))


func _signed(value: int) -> String:
	return ("+%d" % value) if value >= 0 else str(value)


func _outcome_color(outcome: DiceResolver.Outcome) -> String:
	match outcome:
		DiceResolver.Outcome.CRITICAL_SUCCESS:
			return "#7CFC00"
		DiceResolver.Outcome.SUCCESS:
			return "#4CAF50"
		DiceResolver.Outcome.FAILURE:
			return "#FF8C00"
		_:
			return "#FF4444"
