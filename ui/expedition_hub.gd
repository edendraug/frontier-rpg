extends Control

## Expedition Hub — the "you are now playing" screen, reached from
## Party Creator's Begin Expedition (and, once wired, Main Menu's Load
## Game). Unlike every other screen so far, this scene's node
## structure is hand-built in the editor rather than constructed in
## code — see the node blueprint alongside this file for the expected
## hierarchy.
##
## This script finds its nodes via UNIQUE NAMES (%NodeName), not exact
## $Paths, so exact nesting/wrapping in the editor is free to change —
## only the unique name and node type of each one below has to match.
##
## REQUIRED UNIQUE-NAMED NODES (Scene panel → right-click → Access as
## Unique Name):
##   %PartyButton            (Button)
##   %InventoryButton        (Button)
##   %PartyOverlay           (Control/Panel) — Mouse Filter: Stop, starts hidden
##   %PartyCloseButton       (Button)
##   %PartyTabs              (TabContainer) — one tab per party member, built at runtime
##   %InventoryOverlay       (Control/Panel) — Mouse Filter: Stop, starts hidden
##   %InventoryCloseButton   (Button)
##   %InventorySummaryLabel  (Label)
##   %ItemList               (VBoxContainer) — rows built here at runtime
##   %TimeLabel              (Label)
##   %DateLabel              (Label)
##   %EscapeMenuOverlay      (Control/Panel) — Mouse Filter: Stop, starts hidden. Suggest a smaller centered box, unlike Party/Inventory's "most of the screen" sizing — this is a compact pause menu, not a content browser.
##   %EscapeSaveButton       (Button) — "Save Game"
##   %EscapeSaveQuitButton   (Button) — "Save and Quit"
##   %EscapeQuitButton       (Button) — "Quit Without Saving"
##   %EscapeResumeButton     (Button) — "Resume" — closes the menu without acting; not one of the three you asked for, but needed so opening the menu isn't a one-way trip into a consequential choice.
##
## Opens via the Escape key (Godot's built-in "ui_cancel" action, no
## input map setup needed). If Party or Inventory is already open,
## Escape closes THAT first rather than jumping straight to a menu
## full of quit options on top of it — see _unhandled_input() below.

var _active_overlay: Control = null

const MAIN_MENU_SCENE_PATH := "res://ui/main_menu.tscn"


func _make_label(text: String, font_size: int = 13) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	return l


func _ready() -> void:
	%PartyButton.pressed.connect(_on_party_button_pressed)
	%InventoryButton.pressed.connect(_on_inventory_button_pressed)
	%PartyCloseButton.pressed.connect(_close_active_overlay)
	%InventoryCloseButton.pressed.connect(_close_active_overlay)

	%PartyOverlay.visible = false
	%InventoryOverlay.visible = false

	%EscapeResumeButton.pressed.connect(_close_active_overlay)
	%EscapeSaveButton.pressed.connect(_on_escape_save_pressed)
	%EscapeSaveQuitButton.pressed.connect(_on_escape_save_and_quit_pressed)
	%EscapeQuitButton.pressed.connect(_on_escape_quit_pressed)
	%EscapeMenuOverlay.visible = false

	# time_advanced fires on every pass_minutes() call, unlike
	# hour_passed/day_passed which only fire on a boundary crossing --
	# a 30-minute skip should still move the displayed clock even when
	# it doesn't happen to cross an hour line. Still refresh once
	# immediately below, since _ready() itself won't fire the signal
	# (matters right after a Load, where the clock may already be well
	# past 0).
	TimeSystem.time_advanced.connect(func(_total): _refresh_time_display())
	_refresh_time_display()

	# Live-refresh the Party/Inventory overlays if they're OPEN when
	# underlying state changes elsewhere (e.g. the debug menu adding
	# an item or editing a stat) -- previously these only refreshed on
	# open/close, so a change made while already open went unseen
	# until you closed and reopened.
	InventorySystem.inventory_changed.connect(func(): _refresh_if_active(%InventoryOverlay, _refresh_inventory_overlay))
	InventorySystem.money_changed.connect(func(_m): _refresh_if_active(%InventoryOverlay, _refresh_inventory_overlay))
	InventorySystem.weight_status_changed.connect(func(_s): _refresh_if_active(%InventoryOverlay, _refresh_inventory_overlay))
	# Freshness/spoilage is computed live from the clock, not stored --
	# nothing mutates Inventory just because time passes, so none of
	# the three signals above catch it. time_advanced does, since it's
	# the one thing that's actually true every time freshness changes.
	TimeSystem.time_advanced.connect(func(_t): _refresh_if_active(%InventoryOverlay, _refresh_inventory_overlay))
	PartyManager.roster_loaded.connect(func(): _refresh_if_active(%PartyOverlay, _refresh_party_overlay))

	add_child(DebugMenu.new())


## Only rebuilds an overlay if it's the one currently showing --
## rebuilding a hidden overlay would be wasted work, and there's no
## reason to pay that cost every time inventory changes while, say,
## the Party overlay (or nothing) is open instead.
func _refresh_if_active(overlay: Control, refresh_fn: Callable) -> void:
	if _active_overlay == overlay:
		refresh_fn.call()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return

	if _active_overlay != null and _active_overlay != %EscapeMenuOverlay:
		# Party or Inventory is open — Escape backs out of THAT first,
		# one layer at a time, rather than jumping straight to a pause
		# menu (with destructive quit options) on top of it.
		_close_active_overlay()
	else:
		_toggle_overlay(%EscapeMenuOverlay, func(): pass)

	get_viewport().set_input_as_handled()


## ============================================================
## OVERLAY TOGGLE
## ============================================================
## Only one overlay open at a time. Each overlay's own Mouse Filter
## (set in the editor, see blueprint) is what actually blocks input
## to the buttons underneath — this function just tracks which one is
## currently showing and swaps between them.
## ============================================================
func _on_party_button_pressed() -> void:
	_toggle_overlay(%PartyOverlay, _refresh_party_overlay)


func _on_inventory_button_pressed() -> void:
	_toggle_overlay(%InventoryOverlay, _refresh_inventory_overlay)


func _toggle_overlay(overlay: Control, refresh_fn: Callable) -> void:
	if _active_overlay == overlay:
		_close_active_overlay()
		return

	if _active_overlay != null:
		_active_overlay.visible = false

	refresh_fn.call()
	overlay.visible = true
	_active_overlay = overlay


func _close_active_overlay() -> void:
	if _active_overlay != null:
		_active_overlay.visible = false
	_active_overlay = null


## ============================================================
## ESCAPE MENU — placeholder. Save Game stays on this screen; the
## other two return to Main Menu. Neither quit path resets
## PartyManager/InventorySystem/SaveManager's active-save tracking on
## the way out — both of Main Menu's own actions (New Game, Load
## Game) already fully establish correct state on the way IN, so
## there's nothing to leak in between.
## ============================================================
func _on_escape_save_pressed() -> void:
	var slug := SaveManager.save_game()
	if slug != "":
		print("Saved as '%s'." % slug)
	else:
		print("Save failed — check the Output panel.")
	_close_active_overlay()


func _on_escape_save_and_quit_pressed() -> void:
	var slug := SaveManager.save_game()
	if slug == "":
		print("Save failed — check the Output panel. Not quitting, to avoid losing progress.")
		return
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _on_escape_quit_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


## ============================================================
## TIME OVERLAY — always visible, per design. Uses TimeFormatter for
## both pieces rather than reimplementing AM/PM or weekday/season
## naming here — same shared-formatting-layer reasoning TimeFormatter
## was originally split out for.
## ============================================================
func _refresh_time_display() -> void:
	%TimeLabel.text = TimeFormatter.format_time_ampm(
		TimeSystem.get_current_hour(), TimeSystem.get_current_minute()
	)
	%DateLabel.text = "%s, Day %d — %s, Year %d" % [
		TimeFormatter.get_weekday_name(TimeSystem.get_day_of_week()),
		TimeSystem.get_day_of_month(),
		TimeFormatter.get_season_name(TimeSystem.get_current_season()),
		TimeSystem.get_current_year(),
	]


## ============================================================
## PARTY OVERLAY — read-only. Rebuilt fresh every time it opens
## rather than kept live-synced, same "just recompute" approach every
## dev tester has used so far — simplest correct option at this data
## scale, and guarantees it can never show stale state.
## ============================================================
func _refresh_party_overlay() -> void:
	var previous_tab: int = %PartyTabs.current_tab

	for child in %PartyTabs.get_children():
		child.queue_free()

	var registry := PartyManager.get_registry()
	for sheet in PartyManager.get_roster():
		var content := _build_party_tab_content(sheet, registry)
		%PartyTabs.add_child(content)
		var tab_title := sheet.character_name
		if sheet.is_main_character:
			tab_title += " (Main)"
		%PartyTabs.set_tab_title(%PartyTabs.get_child_count() - 1, tab_title)

	if previous_tab >= 0 and previous_tab < %PartyTabs.get_child_count():
		%PartyTabs.current_tab = previous_tab


## One tab per party member — TabContainer handles "only one visible
## at a time" natively, so this just builds a single tab's content
## rather than a whole stacked list like before.
##
## VITALS SECTION: Hunger/Fatigue/Condition/Morale are exposed here
## with raw numbers and real progress bars, deliberately breaking
## from the original "hidden tier only" design for Condition/Morale --
## explicit temporary call for testing accuracy while VitalsSystem is
## being built and verified. Revisit once real player-facing UI gets
## designed. Condition has no single underlying continuous value the
## way Hunger/Fatigue/Morale do, so its bar uses tier INDEX out of
## the highest tier rather than a raw stat.
func _build_party_tab_content(sheet: CharacterSheet, registry: CharacterDataRegistry) -> Control:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 12)

	var content := VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.add_theme_constant_override("separation", 6)
	margin.add_child(content)

	var header := _make_label("%s%s" % [sheet.character_name, "  (Main)" if sheet.is_main_character else ""], 16)
	content.add_child(header)

	var occupation: OccupationDefinition = registry.occupations.get(sheet.occupation_id)
	content.add_child(_make_label(occupation.display_name if occupation != null else "(no occupation)", 12))

	content.add_child(HSeparator.new())

	content.add_child(_build_vitals_row(
		"Hunger", sheet.hunger, 100.0, "%.1f / 100 (100 = fed)" % sheet.hunger
	))
	content.add_child(_build_vitals_row(
		"Fatigue", sheet.fatigue, 100.0, "%.1f / 100 (0 = rested)" % sheet.fatigue
	))
	content.add_child(_build_vitals_row(
		"Morale", sheet.morale, 100.0,
		"%.1f / 100 — %s" % [sheet.morale, CharacterSheet.MoraleTier.keys()[sheet.get_morale_tier()]]
	))
	var condition_tier := sheet.get_condition_tier()
	var condition_max := CharacterSheet.ConditionTier.keys().size() - 1
	content.add_child(_build_vitals_row(
		"Condition", condition_tier, condition_max, CharacterSheet.ConditionTier.keys()[condition_tier]
	))

	content.add_child(HSeparator.new())

	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var lines: Array = []

	for entry in [
		["Brawn", CharacterSheet.Stat.BRAWN, sheet.brawn],
		["Agility", CharacterSheet.Stat.AGILITY, sheet.agility],
		["Grit", CharacterSheet.Stat.GRIT, sheet.grit],
		["Wits", CharacterSheet.Stat.WITS, sheet.wits],
		["Knowledge", CharacterSheet.Stat.KNOWLEDGE, sheet.knowledge],
		["Presence", CharacterSheet.Stat.PRESENCE, sheet.presence],
	]:
		var mod: int = sheet.get_base_modifier(entry[1])
		var mod_str: String = ("+%d" % mod) if mod >= 0 else str(mod)
		lines.append("%s: %d (%s)" % [entry[0], entry[2], mod_str])

	lines.append("")
	lines.append("[b]Traits:[/b]")
	if sheet.traits.is_empty():
		lines.append("  (none)")
	for t in sheet.traits:
		var trait_def: TraitDefinition = registry.traits.get(t.trait_id)
		lines.append("  - %s" % (trait_def.display_name if trait_def else t.trait_id))

	lines.append("")
	lines.append("[b]Skills:[/b]")
	var any_proficient := false
	for progress in sheet.skills:
		if progress.get_rank() != SkillProgress.Rank.UNSKILLED:
			any_proficient = true
			var skill_def: SkillDefinition = registry.skills.get(progress.skill_id)
			lines.append("  - %s (%s)" % [
				skill_def.display_name if skill_def else progress.skill_id,
				SkillProgress.Rank.keys()[progress.get_rank()],
			])
	if not any_proficient:
		lines.append("  (none)")

	label.text = "\n".join(lines)
	content.add_child(label)
	return margin


func _build_vitals_row(label_text: String, value: float, max_value: float, readout_text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var name_label := _make_label(label_text, 12)
	name_label.custom_minimum_size = Vector2(70, 0)
	row.add_child(name_label)

	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = max_value
	bar.value = value
	bar.show_percentage = false
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar)

	row.add_child(_make_label(readout_text, 11))

	return row


## ============================================================
## INVENTORY OVERLAY — user-facing REMOVAL only, per design. Adding
## items stays reserved to the not-yet-built debug menu; this is the
## real player-facing view, so it only exposes what a player should
## actually be able to do: discard some quantity of something.
## ============================================================
func _refresh_inventory_overlay() -> void:
	var status_names := ["Unencumbered", "Encumbered", "OVERLOADED"]
	%InventorySummaryLabel.text = "Money: $%.2f    Weight: %.1f / %.1f lbs (%s)" % [
		InventorySystem.get_money(),
		InventorySystem.get_total_weight(),
		InventorySystem.get_max_capacity(),
		status_names[InventorySystem.get_weight_status()],
	]

	for child in %ItemList.get_children():
		child.queue_free()

	for item in ItemRegistry.get_all_items():
		var qty := InventorySystem.get_quantity(item.item_id)
		if qty <= 0:
			continue
		%ItemList.add_child(_build_item_row(item, qty))


func _build_item_row(item: ItemDefinition, quantity: int) -> Control:
	var row := HBoxContainer.new()

	var label := Label.new()
	label.text = _item_row_text(item, quantity)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var qty_spin := SpinBox.new()
	qty_spin.min_value = 1
	qty_spin.max_value = quantity
	qty_spin.value = 1
	row.add_child(qty_spin)

	var remove_button := Button.new()
	remove_button.text = "Remove"
	remove_button.pressed.connect(func():
		InventorySystem.remove_item(item.item_id, int(qty_spin.value))
		_refresh_inventory_overlay()
	)
	row.add_child(remove_button)

	return row


## Non-perishables: exact weight, no further detail needed. Perishables:
## sums each batch's REAL effective weight (spoiled batches already
## count at half, per ItemFreshness) rather than naively multiplying
## item.weight * quantity, which would ignore any spoilage discount
## already baked into the true total. Surfaces only the OLDEST batch's
## freshness — matches the original Inventory design call ("one
## aggregate reading per item, not one line per batch") rather than
## listing every batch here.
func _item_row_text(item: ItemDefinition, quantity: int) -> String:
	if not item.perishable:
		return "%s — %d (%.1f lbs)" % [item.display_name, quantity, item.weight * quantity]

	var batches := InventorySystem.get_batches(item.item_id)
	var current_minute := TimeSystem.get_total_minutes_elapsed()

	var total_weight := 0.0
	var oldest: InventoryBatch = null
	for batch in batches:
		total_weight += ItemFreshness.get_effective_weight(batch, item, current_minute)
		if oldest == null or batch.acquired_minute < oldest.acquired_minute:
			oldest = batch

	var text := "%s — %d (%.1f lbs)" % [item.display_name, quantity, total_weight]
	if oldest == null:
		return text

	var freshness := ItemFreshness.get_freshness(oldest, item, current_minute)
	if freshness <= 0.0:
		return text + "  [spoiled batch present]"
	return text + "  (oldest batch %.0f%% fresh)" % (freshness * 100.0)
