class_name PartyDebugTab
extends DebugTab

var _member_option: OptionButton
var _hunger_spin: SpinBox
var _fatigue_spin: SpinBox
var _apply_vitals_button: Button

var _skill_option: OptionButton
var _skill_xp_spin: SpinBox
var _skill_readout: Label

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

	_build_skill_xp_section(root)

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


## ============================================================
## SKILL XP
## ============================================================
## Built once at _ready() -- the skill list itself is static data
## (loaded from .tres via the registry), so unlike _member_option
## (which rebuilds on roster changes) this option list never needs
## refreshing, only the readout/spin VALUE does when the selected
## character or skill changes.
func _build_skill_xp_section(root: VBoxContainer) -> void:
	root.add_child(_make_label("Skill XP", 14))

	var registry := PartyManager.get_registry()
	_skill_option = OptionButton.new()
	var skill_ids: Array = registry.skills.keys()
	skill_ids.sort()
	for id in skill_ids:
		var def: SkillDefinition = registry.skills[id]
		_skill_option.add_item("%s (%s)" % [def.display_name, id])
		_skill_option.set_item_metadata(_skill_option.item_count - 1, id)
	_skill_option.item_selected.connect(func(_i): _update_skill_readout())
	root.add_child(_skill_option)

	var xp_row := HBoxContainer.new()
	xp_row.add_child(_make_label("XP:", 12))
	_skill_xp_spin = SpinBox.new()
	_skill_xp_spin.min_value = 0
	_skill_xp_spin.max_value = 1000
	_skill_xp_spin.step = 10
	xp_row.add_child(_skill_xp_spin)

	var set_button := Button.new()
	set_button.text = "Set XP"
	set_button.pressed.connect(_on_set_skill_xp_pressed)
	xp_row.add_child(set_button)
	root.add_child(xp_row)

	# Quick-jump buttons pulled straight from SkillProgress's own
	# thresholds rather than hand-typed numbers, so these can't drift
	# out of sync if the thresholds are ever retuned.
	var preset_row := HBoxContainer.new()
	preset_row.add_child(_make_skill_preset_button("Unskilled (0)", 0))
	var skilled_xp: int = SkillProgress.RANK_THRESHOLDS[SkillProgress.Rank.SKILLED]
	preset_row.add_child(_make_skill_preset_button("Skilled (%d)" % skilled_xp, skilled_xp))
	var expert_xp: int = SkillProgress.RANK_THRESHOLDS[SkillProgress.Rank.EXPERT]
	preset_row.add_child(_make_skill_preset_button("Expert (%d)" % expert_xp, expert_xp))
	root.add_child(preset_row)

	_skill_readout = _make_label("")
	root.add_child(_skill_readout)


func _make_skill_preset_button(text: String, xp_value: int) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func():
		_skill_xp_spin.value = xp_value
		_apply_skill_xp(xp_value)
	)
	return b


func _selected_skill_id() -> String:
	if _skill_option == null or _skill_option.item_count == 0:
		return ""
	return _skill_option.get_item_metadata(_skill_option.selected)


func _on_set_skill_xp_pressed() -> void:
	_apply_skill_xp(int(_skill_xp_spin.value))


func _apply_skill_xp(xp: int) -> void:
	var sheet := _selected_member(_member_option)
	var skill_id := _selected_skill_id()
	if sheet == null or skill_id == "":
		return

	var progress := sheet.get_skill(skill_id)
	if progress == null:
		# Character has never touched this skill before -- CharacterSheet
		# has no add_skill() helper, since normal play always seeds
		# skills at creation (point-buy skill selection). This is the
		# one place a SkillProgress gets created outside that flow; a
		# debug-only shortcut, not a new house pattern to build on.
		progress = SkillProgress.new()
		progress.skill_id = skill_id
		sheet.skills.append(progress)

	progress.xp = xp
	_update_skill_readout()
	PartyManager.notify_roster_changed()


func _update_skill_readout() -> void:
	var sheet := _selected_member(_member_option)
	var skill_id := _selected_skill_id()
	if sheet == null or skill_id == "":
		_skill_readout.text = ""
		return

	var progress := sheet.get_skill(skill_id)
	var xp: int = progress.xp if progress != null else 0
	var rank: SkillProgress.Rank = progress.get_rank() if progress != null else SkillProgress.Rank.UNSKILLED
	var bonus: int = progress.get_bonus_dice() if progress != null else 0

	_skill_xp_spin.set_value_no_signal(xp)
	_skill_readout.text = "%s: %d xp (%s, +%d bonus dice)" % [
		skill_id, xp, SkillProgress.Rank.keys()[rank], bonus
	]


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
	_update_skill_readout()
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
