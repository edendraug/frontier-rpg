class_name SaveDebugTab
extends DebugTab

var _list_container: VBoxContainer


func get_tab_title() -> String:
	return "Save/Load"


func _ready() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var force_save_button := Button.new()
	force_save_button.text = "Force Save Now"
	force_save_button.pressed.connect(func():
		var slug := SaveManager.save_game()
		print("Saved as '%s'." % slug if slug != "" else "Save failed — check the Output panel.")
		refresh()
	)
	root.add_child(force_save_button)

	root.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_container = VBoxContainer.new()
	_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_container)
	root.add_child(scroll)

	refresh()


## Load here restores state in place without changing scenes — since
## this tab lives inside whatever gameplay scene is already running,
## that's actually the useful behavior: swap between saves instantly
## while testing, no navigating away and back.
func refresh() -> void:
	if _list_container == null:
		return

	for child in _list_container.get_children():
		child.queue_free()

	var saves := SaveManager.list_saves()
	if saves.is_empty():
		_list_container.add_child(_make_label("(no saves found)", 12))
		return

	for entry in saves:
		var row := HBoxContainer.new()

		var info := _make_label(
			"%s — %s (%d)" % [entry["save_name"], entry["created_at"], entry["party_size"]], 11
		)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)

		var slug: String = entry["slug"]

		var load_button := Button.new()
		load_button.text = "Load"
		load_button.pressed.connect(func():
			SaveManager.load_game(slug)
			refresh()
		)
		row.add_child(load_button)

		var delete_button := Button.new()
		delete_button.text = "Delete"
		delete_button.pressed.connect(func():
			SaveManager.delete_save(slug)
			refresh()
		)
		row.add_child(delete_button)

		_list_container.add_child(row)
