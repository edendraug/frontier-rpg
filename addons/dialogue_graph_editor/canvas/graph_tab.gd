@tool
extends Control

## Rendering + editing of a DialogueTree onto a GraphEdit canvas.
## Read-only render was Stage 4 (Dialogue Graph Editor design doc,
## Section 3.1). Stage 5a added live field editing for DialogueLineNode
## plus the Save mechanism; 5b added it for DialogueChoiceNode's
## per-Option fields; 5c added it for SkillCheckGate's skill_id/dc_mode/
## dc_tier/dc_manual; 5d added the Effects repeater (Option.effects and
## every SkillCheckBranch.effects). Still outstanding: the Conditions
## repeater (5e - genuinely separate from Effects since conditions is a
## mixed inline-DialogueCondition/ConditionSet-reference array, not a
## single uniform type), toggling a critical branch's authored/
## unauthored state (needs live connection redraw, deferred alongside
## Stage 6 wiring), and adding/removing Options or nodes themselves
## (needs a full rebuild since it changes port counts - deliberately
## kept separate from simple in-place field edits).
##
## Live write-through, not gather-on-save: every Control mutates its
## node's field the instant it changes, matching the design doc's
## Section 5.1 reasoning for why inline editing and a future Inspector
## sub-editor "can never drift out of sync" - that's only true if both
## write straight into the same live Resource. "Save Tree" therefore
## just persists whatever's already sitting in memory; it doesn't
## gather anything from the UI itself. This is a different mechanism
## than ActorFormTab's gather-on-save, deliberately - Actor edits have
## no competing live editor, so gather-on-save was simpler there.
##
## GraphNode is instantiated per DialogueLineNode/DialogueChoiceNode in
## tree.nodes, PLUS one per SkillCheckGate reachable only through an
## Option's skill_check field - gates are never entries in tree.nodes
## themselves (design doc Section 4.1: DialoguePlayer always reaches a
## gate via option.skill_check, never by node_id lookup), so they're
## discovered by walking every Choice node's Options instead. Each
## gate's GraphNode gets a synthetic name (_gate_node_name) since
## SkillCheckGate.node_id goes unused/unpopulated at runtime - this is
## in-memory only for this session's rendering, never written back to
## the Resource.
##
## Positions: uses each node's real editor_position if it's ever been
## set; falls back to a simple auto-grid layout, in-memory only, for
## anything still at the (0,0) default - true of all of Silas Cobb's
## sample data today, since it predates the DialogueGraphNode refactor
## and was never authored with real positions. Dragging a node to a new
## position doesn't persist yet - editor_position isn't written back to
## the Resource anywhere yet, node-drag persistence is Stage 6+
## territory alongside wiring.
##
## Wire dragging is already a no-op: GraphEdit only EMITS
## connection_request/disconnection_request signals on its own, it
## doesn't create/remove connections itself, and this tab doesn't
## handle those signals yet either (Stage 6).

const PORT_TYPE := 0
const LINE_PORT_COLOR := Color(0.6, 0.8, 1.0)
const CHOICE_PORT_COLOR := Color(1.0, 0.8, 0.4)
const SKILL_CHECK_PORT_COLOR := Color(0.8, 0.5, 1.0)

const AUTO_LAYOUT_COLUMNS := 4
const AUTO_LAYOUT_SPACING := Vector2(320, 220)

var _graph_edit: GraphEdit
var _status_label: Label
var _tree: DialogueTree
var tree_id: String = ""   # read by MainPanel to avoid opening duplicate tabs for the same tree


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	_ensure_graph_edit()


## Idempotent - safe to call from _ready() or from load_tree()
## directly, whichever happens first. Kept as a defensive guard even
## though MainPanel now adds this node to the TabContainer BEFORE
## calling load_tree() (required so GraphEdit's own internal setup -
## the connections-drawing layer, among others - actually exists by
## the time load_tree() calls connect_node() on it) - so _ready()
## should normally have already run _ensure_graph_edit() once by the
## time load_tree() calls it again here, making this a no-op in the
## common case.
func _ensure_graph_edit() -> void:
	if _graph_edit != null:
		return

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(vbox)

	var toolbar := HBoxContainer.new()
	vbox.add_child(toolbar)

	var save_button := Button.new()
	save_button.text = "Save Tree"
	save_button.pressed.connect(_on_save_pressed)
	toolbar.add_child(save_button)

	_status_label = Label.new()
	toolbar.add_child(_status_label)

	_graph_edit = GraphEdit.new()
	_graph_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_graph_edit)


## Persists whatever's currently in memory - see file header on why
## there's nothing to gather here, edits already live on the Resource
## the instant each Control changes. _tree.resource_path is already
## valid without needing a take_over_path() fix (unlike the ConditionSet
## bug elsewhere in this project): DialogueTreeRegistry populates
## trees/presets via plain load() calls, which sets resource_path
## correctly, and every node here is a genuine sub-resource reachable
## from that same tree object, so saving the tree root serializes all
## of them together.
func _on_save_pressed() -> void:
	if _tree == null:
		return
	var err := ResourceSaver.save(_tree, _tree.resource_path)
	if err != OK:
		_status_label.text = "Save failed (error %d) - see Output panel." % err
		push_warning("GraphTab: ResourceSaver.save() failed for '%s' with error %d" % [_tree.resource_path, err])
		return
	EditorInterface.get_resource_filesystem().scan()
	_status_label.text = "Saved '%s'." % tree_id


## Loads and renders `id` from `registry` (checking regular trees
## first, then Presets - both are plain DialogueTree Resources per the
## design doc's Section 4.9, just discovered from different folders).
## Returns false (with a warning) if not found in either.
func load_tree(id: String, registry: DialogueTreeRegistry) -> bool:
	_ensure_graph_edit()
	tree_id = id
	var tree: DialogueTree = registry.trees.get(id)
	if tree == null:
		tree = registry.presets.get(id)
	if tree == null:
		push_warning("GraphTab: tree/preset id '%s' not found in registry" % id)
		return false

	_tree = tree
	_build_graph(tree)
	return true


func _build_graph(tree: DialogueTree) -> void:
	# Only free GraphElements (GraphNode/GraphFrame - i.e. things we
	# actually added). GraphEdit.get_children() also includes its own
	# internal connections-drawing layer, which Godot deliberately does
	# NOT flag as an internal child (for its own technical reasons) -
	# queue_free()-ing it too, as an earlier version of this loop did,
	# breaks GraphEdit's own connection rendering entirely.
	for child in _graph_edit.get_children():
		if child is GraphElement:
			child.queue_free()

	var auto_layout_index := 0
	var gate_entries: Array = []   # [SkillCheckGate, owning_node_id, option_id]

	for node_id in tree.nodes:
		var node: DialogueGraphNode = tree.nodes[node_id]
		var graph_node: GraphNode

		if node is DialogueChoiceNode:
			graph_node = _build_choice_node(node)
			for option in node.options:
				if option.has_skill_check():
					gate_entries.append([option.skill_check, node_id, option.option_id])
		elif node is DialogueLineNode:
			graph_node = _build_line_node(node)
		else:
			push_warning("GraphTab: unrecognized node type for node_id '%s', skipping" % node_id)
			continue

		graph_node.name = node_id
		_position_node(graph_node, node.editor_position, auto_layout_index)
		auto_layout_index += 1
		_graph_edit.add_child(graph_node)

	for entry in gate_entries:
		var gate: SkillCheckGate = entry[0]
		var owning_node_id: String = entry[1]
		var option_id: String = entry[2]
		var gate_node := _build_skill_check_node(gate)
		gate_node.name = _gate_node_name(owning_node_id, option_id)
		_position_node(gate_node, gate.editor_position, auto_layout_index)
		auto_layout_index += 1
		_graph_edit.add_child(gate_node)

	_draw_connections(tree)


func _gate_node_name(owning_node_id: String, option_id: String) -> String:
	return "%s__%s__skill_check" % [owning_node_id, option_id]


func _position_node(graph_node: GraphNode, editor_position: Vector2, auto_index: int) -> void:
	if editor_position != Vector2.ZERO:
		graph_node.position_offset = editor_position
		return
	# Auto-grid fallback for never-positioned nodes (see file header).
	var column := auto_index % AUTO_LAYOUT_COLUMNS
	var row := auto_index / AUTO_LAYOUT_COLUMNS
	graph_node.position_offset = Vector2(column, row) * AUTO_LAYOUT_SPACING


# ---------------------------------------------------------------------------
# Node builders
# ---------------------------------------------------------------------------

## speaker and emotion_tag are plain text fields for now, not an
## actor-id/portrait-key picker - the project's own established
## convention (Known project conventions - IDs vs display names) flags
## exactly this kind of free-text id field as a real risk (a HAS_TRAIT
## condition once silently failed from a display-name/id mixup). Noted
## deliberately as a fast-follow once this pass's live write-through
## mechanism is proven, rather than combining "new editing mechanism"
## and "smarter picker" risk in one change.
func _build_line_node(node: DialogueLineNode) -> GraphNode:
	var graph_node := GraphNode.new()
	graph_node.title = "Line: %s" % node.node_id

	var speaker_field := LineEdit.new()
	speaker_field.placeholder_text = "speaker (actor_id, empty = narration)"
	speaker_field.text = node.speaker
	speaker_field.custom_minimum_size = Vector2(240, 0)
	speaker_field.text_changed.connect(func(new_text: String) -> void:
		node.speaker = new_text
	)
	graph_node.add_child(speaker_field)
	# Row 0 carries both this node's ports - unchanged from Stage 4,
	# every other row added below stays portless (never had set_slot()
	# called on it, which defaults a row to no ports at all).
	graph_node.set_slot(0, true, PORT_TYPE, LINE_PORT_COLOR, true, PORT_TYPE, LINE_PORT_COLOR)

	var variant_mode_row := HBoxContainer.new()
	var variant_mode_label := Label.new()
	variant_mode_label.text = "Variant mode:"
	variant_mode_row.add_child(variant_mode_label)
	var variant_mode_picker := OptionButton.new()
	variant_mode_picker.add_item("Sticky", DialogueLineNode.VariantMode.STICKY)
	variant_mode_picker.add_item("Reroll", DialogueLineNode.VariantMode.REROLL)
	variant_mode_picker.select(variant_mode_picker.get_item_index(node.variant_mode))
	variant_mode_picker.item_selected.connect(func(index: int) -> void:
		node.variant_mode = variant_mode_picker.get_item_id(index)
	)
	variant_mode_row.add_child(variant_mode_picker)
	graph_node.add_child(variant_mode_row)

	var emotion_tag_field := LineEdit.new()
	emotion_tag_field.placeholder_text = "emotion_tag (empty = default)"
	emotion_tag_field.text = node.emotion_tag
	emotion_tag_field.text_changed.connect(func(new_text: String) -> void:
		node.emotion_tag = new_text
	)
	graph_node.add_child(emotion_tag_field)

	var variants_box := VBoxContainer.new()
	var variants_label := Label.new()
	variants_label.text = "Variants:"
	variants_box.add_child(variants_label)
	var variants_rows := VBoxContainer.new()
	variants_box.add_child(variants_rows)
	for variant in node.variants:
		_add_variant_row(variants_rows, node, variant)
	var add_variant_button := Button.new()
	add_variant_button.text = "+ Add Variant"
	add_variant_button.pressed.connect(func() -> void:
		var new_variant := DialogueLineVariant.new()
		node.variants.append(new_variant)
		_add_variant_row(variants_rows, node, new_variant)
	)
	variants_box.add_child(add_variant_button)
	graph_node.add_child(variants_box)

	return graph_node


## Binds one row directly to `variant` (the actual DialogueLineVariant
## object, not an array index) so add/remove never desyncs a row from
## the wrong entry after reordering - removal erases this exact object
## reference from node.variants rather than an index that could have
## shifted.
func _add_variant_row(container: VBoxContainer, node: DialogueLineNode, variant: DialogueLineVariant) -> void:
	var row := HBoxContainer.new()

	var text_edit := TextEdit.new()
	text_edit.text = variant.text
	text_edit.custom_minimum_size = Vector2(200, 60)
	text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_edit.text_changed.connect(func() -> void:
		variant.text = text_edit.text
	)
	row.add_child(text_edit)

	var remove_button := Button.new()
	remove_button.text = "✕"
	remove_button.pressed.connect(func() -> void:
		node.variants.erase(variant)
		row.queue_free()
	)
	row.add_child(remove_button)

	container.add_child(row)


func _build_choice_node(node: DialogueChoiceNode) -> GraphNode:
	var graph_node := GraphNode.new()
	graph_node.title = "Choice: %s" % node.node_id

	if node.options.is_empty():
		var empty_label := Label.new()
		empty_label.text = "(no Options authored)"
		graph_node.add_child(empty_label)
		graph_node.set_slot(0, true, PORT_TYPE, CHOICE_PORT_COLOR, false, PORT_TYPE, CHOICE_PORT_COLOR)
		return graph_node

	for i in node.options.size():
		var option: DialogueOption = node.options[i]
		var row := _build_option_row(option)
		graph_node.add_child(row)
		# Row 0 doubles as this node's entry point (input enabled
		# alongside its own Option's output) - matches Line/SkillCheck
		# nodes also placing their single input on row 0. Slot count/
		# enabled sides are unchanged from Stage 4 here - only each
		# row's CONTENT changed from a read-only Label to an editable
		# composite, so _draw_connections()'s existing port-i mapping
		# for Choice nodes still holds.
		graph_node.set_slot(i, i == 0, PORT_TYPE, CHOICE_PORT_COLOR, true, PORT_TYPE, CHOICE_PORT_COLOR)

	return graph_node


## option_id is editable here the same way actor_id is in ActorFormTab,
## with the same known caveat: renaming it doesn't migrate any existing
## save's ActorState.options_taken entry keyed to the old id - that
## entry just goes stale/unused (harmless, matches the project's
## general missing-reference-degrades-gracefully posture), not
## something that breaks anything, just worth knowing before renaming
## a live Option. Adding/removing Options entirely isn't supported
## yet - that changes this node's port count, which needs a full
## tab rebuild to stay consistent rather than in-place field mutation,
## and is deliberately deferred to its own pass.
func _build_option_row(option: DialogueOption) -> VBoxContainer:
	var row := VBoxContainer.new()
	row.custom_minimum_size = Vector2(240, 0)

	var top_line := HBoxContainer.new()
	var id_field := LineEdit.new()
	id_field.placeholder_text = "option_id"
	id_field.text = option.option_id
	id_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_field.text_changed.connect(func(new_text: String) -> void:
		option.option_id = new_text
	)
	top_line.add_child(id_field)

	var consume_check := CheckBox.new()
	consume_check.text = "Once"
	consume_check.button_pressed = option.consume_once
	consume_check.toggled.connect(func(toggled_on: bool) -> void:
		option.consume_once = toggled_on
	)
	top_line.add_child(consume_check)
	row.add_child(top_line)

	var text_edit := TextEdit.new()
	text_edit.text = option.text
	text_edit.custom_minimum_size = Vector2(220, 50)
	text_edit.text_changed.connect(func() -> void:
		option.text = text_edit.text
	)
	row.add_child(text_edit)

	if option.has_skill_check():
		var skill_check_note := Label.new()
		skill_check_note.text = "[skill check: %s]" % option.skill_check.skill_id
		row.add_child(skill_check_note)
	else:
		# Unused entirely when skill_check is set (effects live on the
		# branches instead - see _add_branch_row), so showing/editing
		# them here for a skill-check Option would be pointless and
		# misleading about what actually fires.
		row.add_child(_build_effects_repeater(option.effects))

	return row


## skill_id is a plain text field for now - same known id-vs-display-
## name caveat noted on Line's speaker field applies here too (see
## _build_line_node's header comment): deferred smarter-picker
## treatment, not overlooked.
##
## dc_tier/dc_manual are both always built, but only one is visible at
## a time based on dc_mode - matches SkillCheckGate.get_dc()'s own
## behavior of only ever reading whichever field is active, so showing
## both unconditionally would misrepresent which one actually matters.
##
## Branch rows (Success/Failure/Critical Success/Critical Failure)
## stay read-only labels for now - toggling a critical branch between
## authored/unauthored would change what its port's connection means,
## and redrawing that connection live is wiring-adjacent work deferred
## alongside Stage 6, not simple field mutation like everything else
## in this pass.
func _build_skill_check_node(gate: SkillCheckGate) -> GraphNode:
	var graph_node := GraphNode.new()
	graph_node.title = "Skill Check: %s" % (gate.skill_id if not gate.skill_id.is_empty() else "(no skill_id)")

	var skill_id_field := LineEdit.new()
	skill_id_field.placeholder_text = "skill_id"
	skill_id_field.text = gate.skill_id
	skill_id_field.custom_minimum_size = Vector2(220, 0)
	skill_id_field.text_changed.connect(func(new_text: String) -> void:
		gate.skill_id = new_text
		graph_node.title = "Skill Check: %s" % (new_text if not new_text.is_empty() else "(no skill_id)")
	)
	graph_node.add_child(skill_id_field)
	# Row 0 carries both this node's ports, unchanged from Stage 4 -
	# its output stays disabled since this row isn't a branch.
	graph_node.set_slot(0, true, PORT_TYPE, SKILL_CHECK_PORT_COLOR, false, PORT_TYPE, SKILL_CHECK_PORT_COLOR)

	var dc_tier_picker := OptionButton.new()
	for tier_name in DiceResolver.DifficultyTier.keys():
		dc_tier_picker.add_item(tier_name, DiceResolver.DifficultyTier[tier_name])
	dc_tier_picker.select(dc_tier_picker.get_item_index(gate.dc_tier))
	dc_tier_picker.item_selected.connect(func(index: int) -> void:
		gate.dc_tier = dc_tier_picker.get_item_id(index)
	)

	var dc_manual_field := SpinBox.new()
	dc_manual_field.min_value = 0
	dc_manual_field.max_value = 100   # placeholder bound, not a confirmed real DC ceiling
	dc_manual_field.step = 1
	dc_manual_field.value = gate.dc_manual
	dc_manual_field.value_changed.connect(func(new_value: float) -> void:
		gate.dc_manual = int(new_value)
	)

	var dc_mode_picker := OptionButton.new()
	dc_mode_picker.add_item("DC: Tier", SkillCheckGate.DCMode.TIER)
	dc_mode_picker.add_item("DC: Manual", SkillCheckGate.DCMode.MANUAL)
	dc_mode_picker.select(dc_mode_picker.get_item_index(gate.dc_mode))
	dc_mode_picker.item_selected.connect(func(index: int) -> void:
		var mode: int = dc_mode_picker.get_item_id(index)
		gate.dc_mode = mode
		dc_tier_picker.visible = mode == SkillCheckGate.DCMode.TIER
		dc_manual_field.visible = mode == SkillCheckGate.DCMode.MANUAL
	)
	graph_node.add_child(dc_mode_picker)

	dc_tier_picker.visible = gate.dc_mode == SkillCheckGate.DCMode.TIER
	graph_node.add_child(dc_tier_picker)

	dc_manual_field.visible = gate.dc_mode == SkillCheckGate.DCMode.MANUAL
	graph_node.add_child(dc_manual_field)

	_add_branch_row(graph_node, "Success", gate.success)
	_add_branch_row(graph_node, "Failure", gate.failure)
	_add_branch_row(graph_node, "Critical Success", gate.critical_success, "falls back to Success" if gate.critical_success == null else "")
	_add_branch_row(graph_node, "Critical Failure", gate.critical_failure, "falls back to Failure" if gate.critical_failure == null else "")

	return graph_node


## branch is null for an unauthored critical branch (falls back to
## success/failure per SkillCheckGate.get_critical_success_branch()/
## get_critical_failure_branch()) - there's nothing to attach an
## effects repeater to in that case, so the row stays label-only.
func _add_branch_row(graph_node: GraphNode, branch_label: String, branch: SkillCheckBranch, fallback_note: String = "") -> void:
	var row := VBoxContainer.new()

	var label := Label.new()
	label.text = branch_label if fallback_note.is_empty() else "%s (%s)" % [branch_label, fallback_note]
	row.add_child(label)

	if branch != null:
		row.add_child(_build_effects_repeater(branch.effects))

	graph_node.add_child(row)
	var slot_index := graph_node.get_child_count() - 1
	graph_node.set_slot(slot_index, false, PORT_TYPE, SKILL_CHECK_PORT_COLOR, true, PORT_TYPE, SKILL_CHECK_PORT_COLOR)


func _truncate(text: String, max_length: int) -> String:
	if text.length() <= max_length:
		return text
	return text.substr(0, max_length - 1) + "…"


# ---------------------------------------------------------------------------
# Effects repeater (shared by Option.effects and every SkillCheckBranch.effects)
# ---------------------------------------------------------------------------

## `effects` is the actual Array reference held by the owning Resource
## (DialogueOption.effects or SkillCheckBranch.effects) - Godot Arrays
## are reference types, so append()/erase() here mutate that same live
## array directly, matching this whole file's live-write-through
## approach. No return value needed for that reason.
func _build_effects_repeater(effects: Array) -> VBoxContainer:
	var box := VBoxContainer.new()

	var label := Label.new()
	label.text = "Effects:"
	box.add_child(label)

	var rows := VBoxContainer.new()
	box.add_child(rows)
	for effect in effects:
		_add_effect_row(rows, effects, effect)

	var add_button := Button.new()
	add_button.text = "+ Add Effect"
	add_button.pressed.connect(func() -> void:
		var new_effect := DialogueEffect.new()
		effects.append(new_effect)
		_add_effect_row(rows, effects, new_effect)
	)
	box.add_child(add_button)

	return box


## custom_script picker only shown when type == CUSTOM, matching the
## DC-field show/hide pattern in _build_skill_check_node - target/value
## are always shown regardless of type, since every type besides
## CUSTOM still uses at least one of them (see DialogueEffect's own
## field-meaning-by-type docstring).
func _add_effect_row(container: VBoxContainer, effects: Array, effect: DialogueEffect) -> void:
	var row := VBoxContainer.new()
	var top_line := HBoxContainer.new()

	var type_picker := OptionButton.new()
	for type_name in DialogueEffect.Type.keys():
		type_picker.add_item(type_name, DialogueEffect.Type[type_name])
	type_picker.select(type_picker.get_item_index(effect.type))
	top_line.add_child(type_picker)

	var target_field := LineEdit.new()
	target_field.placeholder_text = "target"
	target_field.text = effect.target
	target_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_field.text_changed.connect(func(new_text: String) -> void:
		effect.target = new_text
	)
	top_line.add_child(target_field)

	var value_field := SpinBox.new()
	value_field.min_value = -1000   # placeholder bound, not a confirmed real range
	value_field.max_value = 1000
	value_field.step = 0.1
	value_field.value = effect.value
	value_field.value_changed.connect(func(new_value: float) -> void:
		effect.value = new_value
	)
	top_line.add_child(value_field)

	var remove_button := Button.new()
	remove_button.text = "✕"
	remove_button.pressed.connect(func() -> void:
		effects.erase(effect)
		row.queue_free()
	)
	top_line.add_child(remove_button)

	row.add_child(top_line)

	var script_picker := EditorResourcePicker.new()
	script_picker.base_type = "Script"
	script_picker.edited_resource = effect.custom_script
	script_picker.visible = effect.type == DialogueEffect.Type.CUSTOM
	# resource_changed is typed Resource (base_type only filters what's
	# selectable, it doesn't change the signal's own declared type) -
	# custom_script is specifically Script-typed, so this needs an
	# explicit cast, same category of narrowing GDScript rejects
	# without one as the earlier row.get_child(0) bug in ActorFormTab.
	script_picker.resource_changed.connect(func(resource: Resource) -> void:
		effect.custom_script = resource as Script
	)
	row.add_child(script_picker)

	type_picker.item_selected.connect(func(index: int) -> void:
		var new_type: int = type_picker.get_item_id(index)
		effect.type = new_type
		script_picker.visible = new_type == DialogueEffect.Type.CUSTOM
	)

	container.add_child(row)


# ---------------------------------------------------------------------------
# Connections
# ---------------------------------------------------------------------------

func _draw_connections(tree: DialogueTree) -> void:
	for node_id in tree.nodes:
		var node: DialogueGraphNode = tree.nodes[node_id]

		if node is DialogueLineNode:
			_connect_if_valid(tree, node_id, 0, node.next)

		elif node is DialogueChoiceNode:
			for i in node.options.size():
				var option: DialogueOption = node.options[i]
				if option.has_skill_check():
					var gate_name := _gate_node_name(node_id, option.option_id)
					if _graph_edit.has_node(NodePath(gate_name)):
						_graph_edit.connect_node(node_id, i, gate_name, 0)
						_draw_gate_branch_connections(tree, gate_name, option.skill_check)
					else:
						push_warning("GraphTab: skill-check gate node '%s' missing, skipping connection" % gate_name)
				else:
					_connect_if_valid(tree, node_id, i, option.next)


## Branch port indices here are 0-3, NOT the branches' row indices
## (1-4) on the GraphNode. connect_node()'s port index is into the
## COMPACTED list of enabled ports on that side, skipping any row
## where that side is disabled - row 0 (the DC label) has its output
## disabled, so it doesn't consume a right-port slot, and Success
## (row 1) is actually right-port index 0, not 1. Getting this wrong
## produces a GraphNode "port index out of bounds" engine error, not
## a GDScript-level one, so it won't show up as a script error at the
## call site - worth remembering for any future node type whose rows
## don't all enable the same side uniformly (Line and Choice nodes
## currently do, which is why they never hit this).
func _draw_gate_branch_connections(tree: DialogueTree, gate_name: String, gate: SkillCheckGate) -> void:
	_connect_if_valid(tree, gate_name, 0, gate.success.next if gate.success != null else "")
	_connect_if_valid(tree, gate_name, 1, gate.failure.next if gate.failure != null else "")

	var crit_success := gate.get_critical_success_branch()
	_connect_if_valid(tree, gate_name, 2, crit_success.next if crit_success != null else "")

	var crit_failure := gate.get_critical_failure_branch()
	_connect_if_valid(tree, gate_name, 3, crit_failure.next if crit_failure != null else "")


## Draws from_node_id/from_port -> to_node_id/0, unless to_node_id is
## empty (end of tree/Preset - no edge to draw, matches DialoguePlayer's
## own "empty next means exhausted" convention) or the target doesn't
## actually exist in this tree (missing-reference - mirrors the
## runtime's own push_warning-and-degrade-gracefully convention,
## design doc Section 5.4, rather than crashing the render).
func _connect_if_valid(tree: DialogueTree, from_node_id: String, from_port: int, to_node_id: String) -> void:
	if to_node_id.is_empty():
		return
	if not tree.nodes.has(to_node_id):
		push_warning("GraphTab: '%s' references missing node_id '%s', skipping connection" % [from_node_id, to_node_id])
		return
	_graph_edit.connect_node(from_node_id, from_port, to_node_id, 0)
