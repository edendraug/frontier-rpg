extends Control

## SETUP: create an empty scene with a Control root, attach this
## script, save as party_creator.tscn — same convention as every
## other prototype scene in this project (see character_creator.gd's
## original header). Reachable either standalone for testing, or via
## Main Menu's "New Game" button.
##
## Sidebar shows PartyManager.MAX_PARTY_SIZE slots. Slot state is
## computed fresh from PartyManager on every refresh, never cached —
## same "derived, not stored" instinct used for Condition/Morale.
##   - index < party size        -> FILLED (click to edit, ✕ to remove)
##   - index == party size       -> the one OPEN slot (click to create)
##   - index > party size        -> LOCKED (grayed, inert)
## Slot 0 never shows a remove button — a party without a main
## character isn't a valid state, per PartyManager.remove_character().

const EXPEDITION_HUB_SCENE_PATH := "res://ui/expedition_hub.tscn"
const MAIN_MENU_SCENE_PATH := "res://ui/main_menu.tscn"

var slot_buttons: Array = []
var slot_remove_buttons: Array = []

var card: PartyCharacterCard
var save_name_edit: LineEdit
var begin_button: Button

## Which slot the card is currently open for. Matches whichever slot
## was clicked — either an existing index (editing) or exactly
## PartyManager.get_party_size() at the time it was opened (creating new).
var _editing_index: int = -1


func _ready() -> void:
	_build_ui()
	_refresh_sidebar()
	_refresh_save_name_field()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 16)
	add_child(root)

	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size = Vector2(220, 0)
	sidebar.add_theme_constant_override("separation", 8)
	root.add_child(sidebar)

	sidebar.add_child(_make_label("Party", 18))

	for i in PartyManager.MAX_PARTY_SIZE:
		var slot_row := HBoxContainer.new()

		var slot_button := Button.new()
		slot_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot_button.pressed.connect(_on_slot_pressed.bind(i))
		slot_row.add_child(slot_button)
		slot_buttons.append(slot_button)

		var remove_button := Button.new()
		remove_button.text = "✕"
		remove_button.pressed.connect(_on_remove_pressed.bind(i))
		slot_row.add_child(remove_button)
		slot_remove_buttons.append(remove_button)

		sidebar.add_child(slot_row)

	var save_name_row := HBoxContainer.new()
	save_name_row.add_child(_make_label("Save Name:", 12))
	save_name_edit = LineEdit.new()
	save_name_edit.placeholder_text = "defaults to date/time"
	save_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_name_row.add_child(save_name_edit)
	sidebar.add_child(save_name_row)

	begin_button = Button.new()
	begin_button.text = "Begin Expedition"
	begin_button.pressed.connect(_on_begin_expedition_pressed)
	sidebar.add_child(begin_button)

	var back_button := Button.new()
	back_button.text = "Back to Main Menu"
	back_button.pressed.connect(_on_back_pressed)
	sidebar.add_child(back_button)

	var card_container := Control.new()
	card_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(card_container)

	card = PartyCharacterCard.new()
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.visible = false
	card.confirmed.connect(_on_card_confirmed)
	card.cancelled.connect(_on_card_cancelled)
	card_container.add_child(card)


func _make_label(text: String, font_size: int = 14) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	return l


func _on_slot_pressed(index: int) -> void:
	var size := PartyManager.get_party_size()
	if index < size:
		_editing_index = index
		card.configure(index == 0, PartyManager.get_character(index))
		card.visible = true
	elif index == size:
		_editing_index = index
		card.configure(index == 0, null)
		card.visible = true
	# else: locked slot — its button is disabled, so this shouldn't fire.


func _on_remove_pressed(index: int) -> void:
	if not PartyManager.remove_character(index):
		return
	if _editing_index == index:
		card.visible = false
		_editing_index = -1
	_refresh_sidebar()


func _on_card_confirmed(sheet: CharacterSheet) -> void:
	if _editing_index < PartyManager.get_party_size():
		PartyManager.update_character(_editing_index, sheet)
	else:
		PartyManager.add_character(sheet)

	card.visible = false
	_editing_index = -1
	_refresh_sidebar()


func _on_card_cancelled() -> void:
	card.visible = false
	_editing_index = -1


## begin_expedition() is guarded by PartyManager itself (refuses on
## an empty roster). On success this saves — Begin Expedition doubles
## as the initial save point rather than needing a separate button,
## per design — then transitions straight to Expedition Hub.
func _on_begin_expedition_pressed() -> void:
	if not PartyManager.begin_expedition():
		print("Add at least one character before beginning the expedition.")
		return

	var slug := SaveManager.save_game(save_name_edit.text)
	if slug == "":
		print("Expedition begun, but the save failed — check the Output panel for details.")
		return

	get_tree().change_scene_to_file(EXPEDITION_HUB_SCENE_PATH)


## Discards whatever's been drafted so far and returns to Main Menu.
## Nothing here was ever saved -- Begin Expedition is the only thing
## that saves -- so "cancel" just means clearing the in-progress
## roster/inventory. Resets explicitly here rather than relying on
## New Game's own reset-on-entry to clean up after the fact, so this
## button is self-contained regardless of how you got to this screen.
func _on_back_pressed() -> void:
	PartyManager.reset()
	InventorySystem.reset()
	SaveManager.clear_active_save()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


## Once a save is active for this session (via a prior save OR a
## load), save_game() ignores whatever's typed here and updates that
## file instead — see SaveManager's one-save-per-expedition rule. The
## field is disabled and relabeled in that case so it's clear typing
## a name here won't do anything, rather than silently ignoring it.
func _refresh_save_name_field() -> void:
	if SaveManager.has_active_save():
		save_name_edit.text = "(continuing: %s)" % SaveManager.get_active_save_name()
		save_name_edit.editable = false
	else:
		save_name_edit.text = ""
		save_name_edit.editable = true


func _refresh_sidebar() -> void:
	var size := PartyManager.get_party_size()

	for i in PartyManager.MAX_PARTY_SIZE:
		var button: Button = slot_buttons[i]
		var remove_button: Button = slot_remove_buttons[i]

		if i < size:
			var sheet := PartyManager.get_character(i)
			button.text = "%d. %s%s" % [i + 1, sheet.character_name, " (Main)" if i == 0 else ""]
			button.disabled = false
			remove_button.visible = (i != 0)
		elif i == size:
			button.text = "%d. (Empty — click to create)" % (i + 1)
			button.disabled = false
			remove_button.visible = false
		else:
			button.text = "%d. (Locked)" % (i + 1)
			button.disabled = true
			remove_button.visible = false

	begin_button.disabled = size < PartyManager.MIN_PARTY_SIZE
