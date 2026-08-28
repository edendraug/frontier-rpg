@tool
extends Control

## The Dialogue Graph Editor's Actor tab (Dialogue Graph Editor design
## doc, Section 3.3): flat form-based editing for ActorDefinition
## Resources - no graph structure, so it doesn't belong on a GraphEdit
## canvas. One permanent tab, browsing every discovered Actor via a
## list on the left and editing whichever is selected on the right.
##
## Discovery mirrors RelationsSystem._load_actor_definitions()'s
## DirAccess scan of the same folder (Known project conventions -
## Actor discovery should match the existing convention rather than
## inventing a second one).
##
## dialogue_tree_id has a plain text field plus "Open Tree" (an
## EXISTING tree only) and "New Tree" (creates a blank one at that id
## and opens it - MainPanel._create_tree_tab) buttons. Note "New Tree"
## only creates the tree file itself; it does NOT also save this
## Actor's own dialogue_tree_id - that still needs its own explicit
## "Save Actor" afterward, same as any other field on this form.
##
## Explicit save only (Section 6) - edits live in memory until the
## Save button is pressed. actor_id determines the save filename
## (ACTOR_DIR + actor_id + ".tres"); changing actor_id and saving
## currently just writes a NEW file under the new id rather than
## renaming/deleting the old one - a deliberate simplification, not an
## oversight. Revisit if stray duplicate files become a real problem.

signal open_tree_requested(tree_id: String)
signal create_tree_requested(tree_id: String)

const ActorDefinitionScript := preload("res://systems/dialogue/definitions/actor_definition.gd")
const ACTOR_DIR := "res://systems/dialogue/data/actors/"

const ALIGNMENT_LABELS := ["Opposed (-1)", "Neutral (0)", "Aligned (1)"]
const ALIGNMENT_VALUES := [-1, 0, 1]

var _actor_list: ItemList
var _status_label: Label

var _actor_id_field: LineEdit
var _unknown_name_field: LineEdit
var _known_name_field: LineEdit
var _dialogue_tree_id_field: LineEdit
var _shop_inventory_id_field: LineEdit
var _faction_alignment_rows: VBoxContainer
var _portraits_rows: VBoxContainer

var _loaded_actors: Dictionary = {}   # actor_id -> ActorDefinition, as discovered on disk / saved this session
var _current_actor: ActorDefinition = null   # whichever Actor the form currently shows (may be new/unsaved)


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	var split := HSplitContainer.new()
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 220
	add_child(split)

	split.add_child(_build_left_panel())
	split.add_child(_build_right_panel())

	_refresh_actor_list()
	_show_new_actor()


# ---------------------------------------------------------------------------
# Left panel: Actor list
# ---------------------------------------------------------------------------

func _build_left_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(200, 0)

	var new_button := Button.new()
	new_button.text = "New Actor"
	new_button.pressed.connect(_show_new_actor)
	panel.add_child(new_button)

	var refresh_button := Button.new()
	refresh_button.text = "Rescan Folder"
	refresh_button.pressed.connect(_refresh_actor_list)
	panel.add_child(refresh_button)

	_actor_list = ItemList.new()
	_actor_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_actor_list.item_selected.connect(_on_actor_list_selected)
	panel.add_child(_actor_list)

	_status_label = Label.new()
	panel.add_child(_status_label)

	return panel


## Full disk rescan - discards anything unsaved on the currently-edited
## Actor if it wasn't part of what's already on disk. Only called on
## initial load and the explicit "Rescan Folder" button, never
## automatically after a save (see _on_save_pressed - a fresh load()
## would hand back a different Resource instance than the one just
## saved, breaking the identity check that guards against accidental
## overwrites).
func _refresh_actor_list() -> void:
	_loaded_actors.clear()

	var dir := DirAccess.open(ACTOR_DIR)
	if dir == null:
		push_warning("ActorFormTab: could not open %s" % ACTOR_DIR)
		_sync_actor_list_display()
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var res: Resource = load(ACTOR_DIR + file_name)
			if res is ActorDefinition:
				_loaded_actors[res.actor_id] = res
			else:
				push_warning("ActorFormTab: '%s' is not an ActorDefinition, skipping" % file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	_sync_actor_list_display()


func _sync_actor_list_display() -> void:
	_actor_list.clear()
	var ids := _loaded_actors.keys()
	ids.sort()
	for actor_id in ids:
		_actor_list.add_item(actor_id)


func _on_actor_list_selected(index: int) -> void:
	var actor_id: String = _actor_list.get_item_text(index)
	var def: ActorDefinition = _loaded_actors.get(actor_id)
	if def != null:
		_show_actor(def)


# ---------------------------------------------------------------------------
# Right panel: form
# ---------------------------------------------------------------------------

func _build_right_panel() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 8)
	scroll.add_child(form)

	_actor_id_field = _add_text_field(form, "Actor ID (snake_case)")
	_unknown_name_field = _add_text_field(form, "Unknown Name")
	_known_name_field = _add_text_field(form, "Known Name")
	_dialogue_tree_id_field = _add_text_field(form, "Dialogue Tree ID")
	var tree_buttons_row := HBoxContainer.new()
	var open_tree_button := Button.new()
	open_tree_button.text = "Open Tree"
	open_tree_button.pressed.connect(_on_open_tree_pressed)
	tree_buttons_row.add_child(open_tree_button)
	var new_tree_button := Button.new()
	new_tree_button.text = "New Tree"
	new_tree_button.pressed.connect(_on_new_tree_pressed)
	tree_buttons_row.add_child(new_tree_button)
	form.add_child(tree_buttons_row)

	_shop_inventory_id_field = _add_text_field(form, "Shop Inventory ID (reference only)")

	form.add_child(_section_label("Faction Alignment"))
	_faction_alignment_rows = VBoxContainer.new()
	form.add_child(_faction_alignment_rows)
	var add_faction_button := Button.new()
	add_faction_button.text = "+ Add Faction"
	add_faction_button.pressed.connect(_add_faction_row.bind("", 0))
	form.add_child(add_faction_button)

	form.add_child(_section_label("Portraits"))
	_portraits_rows = VBoxContainer.new()
	form.add_child(_portraits_rows)
	var add_portrait_button := Button.new()
	add_portrait_button.text = "+ Add Portrait"
	add_portrait_button.pressed.connect(_add_portrait_row.bind("", null))
	form.add_child(add_portrait_button)

	var save_button := Button.new()
	save_button.text = "Save Actor"
	save_button.pressed.connect(_on_save_pressed)
	form.add_child(save_button)

	return scroll


func _on_open_tree_pressed() -> void:
	var requested_id := _dialogue_tree_id_field.text.strip_edges()
	if requested_id.is_empty():
		_status_label.text = "Cannot open tree: Dialogue Tree ID is empty."
		return
	open_tree_requested.emit(requested_id)


func _on_new_tree_pressed() -> void:
	var requested_id := _dialogue_tree_id_field.text.strip_edges()
	if requested_id.is_empty():
		_status_label.text = "Cannot create tree: Dialogue Tree ID is empty."
		return
	create_tree_requested.emit(requested_id)


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	return label


func _add_text_field(parent: VBoxContainer, label_text: String) -> LineEdit:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)

	var field := LineEdit.new()
	parent.add_child(field)
	return field


# ---------------------------------------------------------------------------
# Loading an Actor into the form
# ---------------------------------------------------------------------------

func _show_new_actor() -> void:
	_show_actor(ActorDefinitionScript.new())


func _show_actor(def: ActorDefinition) -> void:
	_current_actor = def

	_actor_id_field.text = def.actor_id
	_unknown_name_field.text = def.unknown_name
	_known_name_field.text = def.known_name
	_dialogue_tree_id_field.text = def.dialogue_tree_id
	_shop_inventory_id_field.text = def.shop_inventory_id

	for child in _faction_alignment_rows.get_children():
		child.queue_free()
	for faction_id in def.faction_alignment:
		_add_faction_row(faction_id, def.faction_alignment[faction_id])

	for child in _portraits_rows.get_children():
		child.queue_free()
	for emotion_tag in def.portraits:
		_add_portrait_row(emotion_tag, def.portraits[emotion_tag])

	_status_label.text = "Editing '%s'." % def.actor_id if not def.actor_id.is_empty() else "Editing a new, unsaved Actor."


# ---------------------------------------------------------------------------
# Repeater rows: faction_alignment (faction_id -> -1/0/1)
# ---------------------------------------------------------------------------

func _add_faction_row(faction_id: String, alignment: int) -> void:
	var row := HBoxContainer.new()

	var id_field := LineEdit.new()
	id_field.placeholder_text = "faction_id"
	id_field.text = faction_id
	id_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(id_field)

	var alignment_picker := OptionButton.new()
	for label in ALIGNMENT_LABELS:
		alignment_picker.add_item(label)
	var initial_index := ALIGNMENT_VALUES.find(alignment)
	alignment_picker.select(initial_index if initial_index >= 0 else 1)  # default Neutral if somehow out of range
	row.add_child(alignment_picker)

	var remove_button := Button.new()
	remove_button.text = "✕"
	remove_button.pressed.connect(row.queue_free)
	row.add_child(remove_button)

	_faction_alignment_rows.add_child(row)


# ---------------------------------------------------------------------------
# Repeater rows: portraits (emotion_tag -> Texture2D)
# ---------------------------------------------------------------------------

func _add_portrait_row(emotion_tag: String, texture: Texture2D) -> void:
	var row := HBoxContainer.new()

	var tag_field := LineEdit.new()
	tag_field.placeholder_text = "emotion_tag (\"default\" = no-tag fallback)"
	tag_field.text = emotion_tag
	tag_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(tag_field)

	var picker := EditorResourcePicker.new()
	picker.base_type = "Texture2D"
	picker.edited_resource = texture
	row.add_child(picker)

	var remove_button := Button.new()
	remove_button.text = "✕"
	remove_button.pressed.connect(row.queue_free)
	row.add_child(remove_button)

	_portraits_rows.add_child(row)


# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------

func _on_save_pressed() -> void:
	var actor_id := _actor_id_field.text.strip_edges()
	if actor_id.is_empty():
		_status_label.text = "Cannot save: Actor ID is required."
		return

	# Collision guard: if a different, already-loaded ActorDefinition
	# already owns this id, don't silently overwrite it - most likely
	# means actor_id was edited into another Actor's id by mistake, not
	# an intentional rename (see file header - true rename isn't
	# handled yet).
	if _loaded_actors.has(actor_id) and _loaded_actors[actor_id] != _current_actor:
		_status_label.text = "Cannot save: Actor ID '%s' is already used by another Actor." % actor_id
		push_warning("ActorFormTab: refusing to overwrite existing Actor '%s' from a different in-memory Actor" % actor_id)
		return

	_current_actor.actor_id = actor_id
	_current_actor.unknown_name = _unknown_name_field.text
	_current_actor.known_name = _known_name_field.text
	_current_actor.dialogue_tree_id = _dialogue_tree_id_field.text
	_current_actor.shop_inventory_id = _shop_inventory_id_field.text

	var faction_alignment: Dictionary = {}
	for row in _faction_alignment_rows.get_children():
		var id_field := row.get_child(0) as LineEdit
		var alignment_picker := row.get_child(1) as OptionButton
		var row_faction_id := id_field.text.strip_edges()
		if row_faction_id.is_empty():
			continue
		faction_alignment[row_faction_id] = ALIGNMENT_VALUES[alignment_picker.selected]
	_current_actor.faction_alignment = faction_alignment

	var portraits: Dictionary = {}
	for row in _portraits_rows.get_children():
		var tag_field := row.get_child(0) as LineEdit
		var picker := row.get_child(1) as EditorResourcePicker
		var emotion_tag := tag_field.text.strip_edges()
		if emotion_tag.is_empty() or picker.edited_resource == null:
			continue
		portraits[emotion_tag] = picker.edited_resource
	_current_actor.portraits = portraits

	var path := ACTOR_DIR + actor_id + ".tres"
	var err := ResourceSaver.save(_current_actor, path)
	if err != OK:
		_status_label.text = "Save failed (error %d) - see Output panel." % err
		push_warning("ActorFormTab: ResourceSaver.save() failed for '%s' with error %d" % [path, err])
		return

	# Same take_over_path() fix as generate_dialogue_sample_data.gd's
	# ConditionSet bug - without this, _current_actor stays path-less
	# in memory even though it's now on disk, and anything that embeds
	# it elsewhere later would bake in a duplicate instead of linking.
	_current_actor.take_over_path(path)
	EditorInterface.get_resource_filesystem().scan()

	# Update the in-memory index directly rather than a full
	# _refresh_actor_list() rescan - reloading from disk here would
	# hand back a different Resource instance than _current_actor,
	# which would make the next save's collision check above fire
	# incorrectly against our own Actor.
	_loaded_actors[actor_id] = _current_actor
	_sync_actor_list_display()

	_status_label.text = "Saved '%s'." % actor_id
