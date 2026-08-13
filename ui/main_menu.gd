extends Control

## SETUP: create an empty scene with a Control root, attach this
## script, save as main_menu.tscn — same convention as every other
## prototype scene in this project. Set as the project's main scene
## (Project Settings > Application > Run > Main Scene).

const PARTY_CREATOR_SCENE_PATH := "res://party/scenes/party_creator.tscn"
const EXPEDITION_HUB_SCENE_PATH := "res://ui/expedition_hub.tscn"

var main_panel: VBoxContainer
var load_panel: VBoxContainer
var load_list: VBoxContainer


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# CenterContainer, not set_anchors_preset(PRESET_CENTER) on
	# main_panel directly — that preset bakes in a centering OFFSET
	# based on the control's size at the moment it's called, and
	# main_panel had no children (title/buttons) yet at that point.
	# CenterContainer recalculates dynamically instead, so this stays
	# correct regardless of content size or future changes.
	var main_center := CenterContainer.new()
	main_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(main_center)

	main_panel = VBoxContainer.new()
	main_panel.add_theme_constant_override("separation", 12)
	main_center.add_child(main_panel)

	main_panel.add_child(_make_label("Frontier RPG", 28))

	var new_game_button := Button.new()
	new_game_button.text = "New Game"
	new_game_button.pressed.connect(_on_new_game_pressed)
	main_panel.add_child(new_game_button)

	var load_game_button := Button.new()
	load_game_button.text = "Load Game"
	load_game_button.pressed.connect(_on_load_game_pressed)
	main_panel.add_child(load_game_button)

	_build_load_panel()


func _build_load_panel() -> void:
	load_panel = VBoxContainer.new()
	# Percentage-based anchors rather than a centered/fixed-size box, so
	# this scales with the actual window size instead of being capped
	# at a hardcoded pixel height regardless of how much room there is.
	load_panel.anchor_left = 0.3
	load_panel.anchor_top = 0.3
	load_panel.anchor_right = 0.7
	load_panel.anchor_bottom = 0.7
	load_panel.add_theme_constant_override("separation", 8)
	load_panel.visible = false
	add_child(load_panel)

	load_panel.add_child(_make_label("Load Game", 20))

	var scroll := ScrollContainer.new()
	# EXPAND_FILL, no custom_minimum_size — takes whatever vertical
	# space load_panel actually has (title and Back button excluded)
	# rather than being artificially capped. Still a real
	# ScrollContainer, so a long save list still scrolls correctly if
	# it ever exceeds that space.
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	load_list = VBoxContainer.new()
	load_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(load_list)
	load_panel.add_child(scroll)

	var back_button := Button.new()
	back_button.text = "Back"
	back_button.pressed.connect(_on_load_back_pressed)
	load_panel.add_child(back_button)


func _make_label(text: String, font_size: int = 14) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	return l


## New Game is the one moment a genuinely fresh expedition begins —
## clears the roster, the shared inventory, and SaveManager's sense of
## "which file is this session tied to." Without this, a previous
## session's leftover party/inventory would show up in Party Creator,
## and worse, the FIRST save of this new expedition would silently
## overwrite whatever the last one had active.
func _on_new_game_pressed() -> void:
	PartyManager.reset()
	InventorySystem.reset()
	SaveManager.clear_active_save()
	get_tree().change_scene_to_file(PARTY_CREATOR_SCENE_PATH)


func _on_load_game_pressed() -> void:
	_refresh_load_list()
	main_panel.visible = false
	load_panel.visible = true


func _on_load_back_pressed() -> void:
	load_panel.visible = false
	main_panel.visible = true


func _refresh_load_list() -> void:
	for child in load_list.get_children():
		child.queue_free()

	var saves := SaveManager.list_saves()
	if saves.is_empty():
		load_list.add_child(_make_label("(no saves found)", 12))
		return

	for entry in saves:
		var row := HBoxContainer.new()

		var info := Label.new()
		info.text = "%s — %s (%d members)" % [entry["save_name"], entry["created_at"], entry["party_size"]]
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)

		var load_button := Button.new()
		load_button.text = "Load"
		var slug: String = entry["slug"]
		load_button.pressed.connect(_on_load_slot_pressed.bind(slug))
		row.add_child(load_button)

		load_list.add_child(row)


## SaveManager.load_game() already restores PartyManager/InventorySystem/
## TimeSystem AND establishes active-save tracking, so a save made once
## you're on Expedition Hub updates this same file rather than minting
## a new one — no extra reset needed here, unlike New Game.
func _on_load_slot_pressed(slug: String) -> void:
	if SaveManager.load_game(slug):
		get_tree().change_scene_to_file(EXPEDITION_HUB_SCENE_PATH)
	else:
		print("Failed to load save '%s' — check the Output panel." % slug)
