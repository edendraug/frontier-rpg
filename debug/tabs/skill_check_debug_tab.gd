class_name SkillCheckDebugTab
extends DebugTab

var _member_option: OptionButton
var _skill_option: OptionButton
var _skill_ids: Array[String] = []
var _difficulty_option: OptionButton
var _result_label: RichTextLabel


func get_tab_title() -> String:
	return "Skill Check"


func _ready() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	_member_option = _build_member_option()
	root.add_child(_member_option)

	_skill_option = OptionButton.new()
	_populate_skill_option()
	root.add_child(_skill_option)

	_difficulty_option = OptionButton.new()
	for key in DiceResolver.DifficultyTier.keys():
		_difficulty_option.add_item("%s (DC %d)" % [
			key.capitalize(),
			DiceResolver.dc_for_tier(DiceResolver.DifficultyTier[key]),
		])
	_difficulty_option.select(DiceResolver.DifficultyTier.MEDIUM)
	root.add_child(_difficulty_option)

	var roll_button := Button.new()
	roll_button.text = "Roll"
	roll_button.pressed.connect(_on_roll_pressed)
	root.add_child(roll_button)

	root.add_child(HSeparator.new())

	_result_label = RichTextLabel.new()
	_result_label.bbcode_enabled = true
	_result_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_result_label)

	refresh()


## Sorted alphabetically by display name, same convention used
## elsewhere skills get listed (Party Character Card's skill section).
func _populate_skill_option() -> void:
	var registry := PartyManager.get_registry()
	var defs: Array = registry.skills.values()
	defs.sort_custom(func(a, b): return a.display_name < b.display_name)

	_skill_ids.clear()
	for def in defs:
		_skill_option.add_item(def.display_name)
		_skill_ids.append(def.skill_id)


func refresh() -> void:
	if _member_option == null:
		return
	_refresh_member_option(_member_option)


func _on_roll_pressed() -> void:
	var sheet := _selected_member(_member_option)
	if sheet == null:
		_result_label.text = "(no party members)"
		return

	if _skill_ids.is_empty():
		_result_label.text = "(no skills loaded)"
		return

	var skill_id: String = _skill_ids[_skill_option.selected]
	var tier: DiceResolver.DifficultyTier = _difficulty_option.selected as DiceResolver.DifficultyTier
	var dc := DiceResolver.dc_for_tier(tier)
	var registry := PartyManager.get_registry()

	var result := SkillCheck.new(sheet, skill_id, dc, registry).resolve()
	_display_result(result)


func _display_result(result: SkillCheckResult) -> void:
	var lines: Array = []
	lines.append("Base dice (2d6): %s = %d" % [str(result.base_dice), result.base_dice_total()])

	if not result.bonus_dice.is_empty():
		lines.append("Bonus dice (%dd4): %s = %d" % [result.bonus_dice.size(), str(result.bonus_dice), result.bonus_dice_total()])
	else:
		lines.append("Bonus dice: none (Unskilled)")

	lines.append("Stat modifier: %s" % _signed(result.stat_modifier))
	lines.append("Modifier bonus: %s" % _signed(result.modifier_bonus))

	for m in result.contributing_modifiers:
		lines.append("  - %s: %s" % [m.source_label, _signed(m.value)])

	lines.append("")
	lines.append("[b]Total: %d  vs  DC %d[/b]" % [result.total, result.difficulty])

	var outcome_color := "white"
	match result.outcome:
		DiceResolver.Outcome.CRITICAL_SUCCESS:
			outcome_color = "lime"
		DiceResolver.Outcome.SUCCESS:
			outcome_color = "lightgreen"
		DiceResolver.Outcome.FAILURE:
			outcome_color = "orange"
		DiceResolver.Outcome.CRITICAL_FAILURE:
			outcome_color = "red"
	lines.append("[color=%s][b]%s[/b][/color]" % [outcome_color, result.outcome_name()])

	_result_label.text = "\n".join(lines)
