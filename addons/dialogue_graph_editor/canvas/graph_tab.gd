@tool
extends Control

## Rendering + editing of a DialogueTree onto a GraphEdit canvas.
## REWRITTEN against the Dialogue Graph Node Restructure design doc,
## which is now this file's source of truth for node shapes - the
## earlier "Choice holds a list of Options, SkillCheckGate reached only
## through an Option" model is gone entirely. Five node types now:
## DialogueLineNode, DialogueStructureNode, DialogueConditionNode,
## DialogueChoiceNode, DialogueSkillCheckChoiceNode (extends
## DialogueChoiceNode). Port summary (Restructure doc Section 2):
##
##   Line             1 input (multi-wire) | 1 output
##   Structure        1 input (multi-wire) | N outputs (array-backed, "+ Add Choice")
##   Condition        0 inputs             | 1 output (fans out to many choices)
##   Choice           2 inputs (main + condition, condition = port 1) | 1 output
##   SkillCheckChoice 2 inputs (same)      | 4 outputs (Success/Failure/CritSuccess/CritFailure)
##
## Biggest structural simplification this rewrite gets for free: no
## more synthetic gate naming or side-channel lookup. The old
## SkillCheckGate was never a real tree.nodes entry (reachable only via
## option.skill_check), which is why the previous version needed
## _gate_lookup/_gate_node_name() at all. DialogueSkillCheckChoiceNode
## is a full graph node now, discovered by the same single pass over
## tree.nodes as everything else.
##
## Condition wiring is represented in the OPPOSITE direction from every
## other wire in this file: DialogueChoiceNode.condition_node_id has
## the CHOICE storing a reference to whichever DialogueConditionNode
## feeds it (chosen so one ConditionNode can fan out to several choices
## without needing its own target list - Restructure doc Section 6).
## The VISUAL wire is still drawn from the ConditionNode's output to
## the choice's condition input though (connect_node()'s from/to
## describes the wire, not which side owns the data) - see
## _draw_connections() and CONDITION_INPUT_PORT.
##
## Everything below this point is preserved, hard-won behavior from the
## original build, unrelated to which node types exist:
##
## - clear_connections() before every rebuild: GraphEdit's connection
##   list is name/port tuples independent of the actual GraphNode
##   objects, so recreating nodes never clears old wires on its own.
## - remove_child() before queue_free() in the cleanup loop: queue_free()
##   alone leaves a node attached (name and all) until end of frame,
##   so a same-named replacement gets silently renamed to its
##   @ClassName@id default by Godot's own uniqueness check.
## - _request_rebuild()'s deferred, coalesced call: GraphEdit is still
##   internally finishing a gesture in the same call stack when
##   connection_request/disconnection_request fire: doing the rebuild
##   synchronously queue_free()s nodes GraphEdit is still referencing
##   (confirmed engine issue #101005 - "Parameter graph_node_from is
##   null").
## - right_disconnects stays on for the common case, but is known
##   unreliable specifically when several wires converge on one input
##   port (confirmed engine issue #92120 - a completely normal pattern
##   here, e.g. any Structure node's multiple incoming wires) - every
##   `next`-style field also gets an explicit "Clear Connection" button
##   (_build_next_status_row) as the reliable fallback.
## - _capture_current_positions() runs before every rebuild/Save: without
##   it, editor_position never actually changes from whatever it was on
##   load, so every rebuild reset the whole graph to the auto-grid
##   layout.
## - Live write-through, not gather-on-save: every Control mutates its
##   node's field the instant it changes (Dialogue & Relations doc
##   Section 5.1) - "Save Tree" just persists whatever's already in
##   memory.

const PORT_TYPE := 0
const LINE_PORT_COLOR := Color(0.6, 0.8, 1.0)
const STRUCTURE_PORT_COLOR := Color(0.7, 0.7, 0.7)
const CONDITION_PORT_COLOR := Color(0.5, 1.0, 0.6)
const CHOICE_PORT_COLOR := Color(1.0, 0.8, 0.4)
const SKILL_CHECK_PORT_COLOR := Color(0.8, 0.5, 1.0)

## The condition input's compacted port index on ANY DialogueChoiceNode
## or DialogueSkillCheckChoiceNode - always 1, since row 0 (main input)
## always has its own left port enabled too, and the condition input is
## always the very next row after it. See _add_condition_input_row.
const CONDITION_INPUT_PORT := 1

const AUTO_LAYOUT_COLUMNS := 4
const AUTO_LAYOUT_SPACING := Vector2(320, 220)

# Which types actually read their numeric field, per each class's own
# field-meaning-by-type docstring (dialogue_condition.gd,
# dialogue_effect.gd). target is used by every type except CUSTOM in
# both cases - CUSTOM uses custom_script instead, and per the actual
# resolvers, target/threshold/value are never even passed to a CUSTOM
# script, only actor/player_state are.
const CONDITION_TYPES_USING_THRESHOLD := [
	DialogueCondition.Type.FACTION_REPUTATION_AT_LEAST,
	DialogueCondition.Type.ACTOR_ALIGNMENT_IS,
	DialogueCondition.Type.HAS_SKILL_RANK_AT_LEAST,
	DialogueCondition.Type.HAS_ITEM,
]
const EFFECT_TYPES_USING_VALUE := [
	DialogueEffect.Type.FACTION_REPUTATION_DELTA,
	DialogueEffect.Type.GRANT_ITEM,
]

## Emitted when the Close Tab button is pressed - MainPanel owns the
## actual removal from the TabContainer/its _open_graph_tabs tracking
## dict, since this tab has no reference to either of those itself.
signal close_requested(closed_tree_id: String)

var _graph_edit: GraphEdit
var _status_label: Label
var _tree: DialogueTree
var tree_id: String = ""   # read by MainPanel to avoid opening duplicate tabs for the same tree
var _rebuild_pending: bool = false   # guards against multiple overlapping deferred rebuilds if several edits fire before the first one runs
var _start_node_picker: OptionButton


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

	var add_node_menu := MenuButton.new()
	add_node_menu.text = "+ Add Node"
	var add_node_popup := add_node_menu.get_popup()
	for i in ADD_NODE_LABELS.size():
		add_node_popup.add_item(ADD_NODE_LABELS[i], i)
	add_node_popup.id_pressed.connect(_on_add_node_selected)
	toolbar.add_child(add_node_menu)

	var close_button := Button.new()
	close_button.text = "Close Tab"
	# No unsaved-changes warning here - a known, accepted gap, not an
	# oversight. Live write-through means anything typed is already on
	# the in-memory Resource the instant it changes, but closing the
	# tab without a prior Save Tree still discards it: nothing else
	# keeps that Resource alive once this tab's own reference to it is
	# gone. Tracking "has this tree been modified since last save"
	# would need a real dirty-flag mechanism that doesn't exist
	# anywhere in this file yet.
	close_button.pressed.connect(func() -> void:
		close_requested.emit(tree_id)
	)
	toolbar.add_child(close_button)

	var start_node_label := Label.new()
	start_node_label.text = "Start Node:"
	toolbar.add_child(start_node_label)

	# A dropdown rather than free text, deliberately - unlike most id
	# fields in this file (speaker, skill_id, etc., where a smarter
	# picker is a known, deferred fast-follow), the valid options here
	# are naturally bounded to this tree's OWN current node ids, so
	# there's no reason to risk a typo'd id when a picker is this cheap
	# to build. Repopulated on every _build_graph() rebuild, not just
	# once - the valid options change whenever a node is added,
	# removed, or renamed.
	_start_node_picker = OptionButton.new()
	_start_node_picker.item_selected.connect(_on_start_node_selected)
	toolbar.add_child(_start_node_picker)

	_status_label = Label.new()
	toolbar.add_child(_status_label)

	_graph_edit = GraphEdit.new()
	_graph_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph_edit.right_disconnects = true
	_graph_edit.connection_request.connect(_on_connection_request)
	_graph_edit.disconnection_request.connect(_on_disconnection_request)
	_graph_edit.delete_nodes_request.connect(_on_delete_nodes_request)
	vbox.add_child(_graph_edit)


## Index into this array IS the popup item id used by
## _on_add_node_selected - keep both in sync if this list ever changes.
const ADD_NODE_LABELS := ["Line", "Structure", "Condition", "Choice", "Skill Check"]


## Creates a fresh, minimally-populated node of the selected type with
## an auto-generated unique node_id, adds it directly to _tree.nodes,
## and rebuilds. Positioning is whatever _position_node's auto-grid
## fallback gives it, same as any node whose editor_position is still
## Vector2.ZERO.
##
## Known gap, not solved here: node_id can't be renamed anywhere in
## this tool yet, since every wire references a node by that id and a
## rename would need to cascade-update every reference pointing at it -
## real, separate work. The auto-generated id (e.g. "line_1") is what a
## freshly-added node keeps.
func _on_add_node_selected(id: int) -> void:
	if _tree == null:
		return

	var new_node: DialogueGraphNode
	var id_prefix: String
	match id:
		0:
			new_node = DialogueLineNode.new()
			id_prefix = "line"
		1:
			new_node = DialogueStructureNode.new()
			id_prefix = "structure"
		2:
			new_node = DialogueConditionNode.new()
			id_prefix = "condition"
		3:
			new_node = DialogueChoiceNode.new()
			id_prefix = "choice"
		4:
			# success/failure pre-populated with fresh branches, unlike
			# the class's own bare default (both null) - Section 7 of
			# the Restructure doc treats these two as "always
			# authored," and _set_branch_next() refuses to wire branch
			# ports 0/1 at all when null (unlike 2/3, which auto-author
			# on first wire) - leaving them null here would make a
			# freshly-added skill check silently un-wireable on its two
			# mandatory branches.
			var choice := DialogueSkillCheckChoiceNode.new()
			choice.success = SkillCheckBranch.new()
			choice.failure = SkillCheckBranch.new()
			new_node = choice
			id_prefix = "skill_check"
		_:
			push_warning("GraphTab: unrecognized add-node menu id %d" % id)
			return

	var new_id := _generate_unique_node_id(id_prefix)
	new_node.node_id = new_id
	_tree.nodes[new_id] = new_node
	_request_rebuild()


func _generate_unique_node_id(prefix: String) -> String:
	var counter := 1
	var candidate := "%s_%d" % [prefix, counter]
	while _tree.nodes.has(candidate):
		counter += 1
		candidate = "%s_%d" % [prefix, counter]
	return candidate


## GraphEdit's own delete_nodes_request (Delete/Backspace by default)
## hands back exactly the node names to remove - no need to track
## selection manually via node_selected/node_deselected, unlike the
## older Godot 3-era pattern for this. GraphEdit only removes the
## VISUAL nodes/wires on its own; it knows nothing about the underlying
## data model, so _delete_node() below does the real work (removing
## the node AND clearing every remaining reference to it elsewhere in
## the tree) before the rebuild redraws everything from the now-
## updated data.
func _on_delete_nodes_request(nodes: Array[StringName]) -> void:
	if _tree == null:
		return
	for node_name in nodes:
		_delete_node(node_name)
	_request_rebuild()


## Removes `node_id_to_delete` entirely, then clears every remaining
## node's own outgoing reference to it (see _replace_node_references).
## No confirmation prompt and no undo, matching how Close Tab also has
## no unsaved-changes warning - consistent with this file's general
## posture of explicit-but-immediate actions, not silent/automatic ones.
func _delete_node(node_id_to_delete: String) -> void:
	if not _tree.nodes.has(node_id_to_delete):
		return
	_tree.nodes.erase(node_id_to_delete)
	_replace_node_references(node_id_to_delete, "")


## Walks every node currently in the tree (plus tree.start_node_id) and
## replaces any outgoing reference equal to `old_id` with `new_value` -
## next/outputs[i]/condition_node_id/default_return_id, and each
## SkillCheckChoiceNode branch's own next. Shared by _delete_node
## (new_value = "") and _rename_node (new_value = the new id) - same
## reference-walking logic either way, just a different replacement
## value. DialogueConditionNode is never touched here - it has no
## outgoing `next`-style field of its own; nothing wires FROM it except
## via a Choice-family node's condition_node_id, already covered below.
func _replace_node_references(old_id: String, new_value: String) -> void:
	if _tree.start_node_id == old_id:
		_tree.start_node_id = new_value

	for other_id in _tree.nodes:
		var other: DialogueGraphNode = _tree.nodes[other_id]

		# DialogueSkillCheckChoiceNode BEFORE DialogueChoiceNode - see
		# _build_graph()'s own dispatch for why the order matters.
		if other is DialogueSkillCheckChoiceNode:
			if other.condition_node_id == old_id:
				other.condition_node_id = new_value
			if other.default_return_id == old_id:
				other.default_return_id = new_value
			for branch in [other.success, other.failure, other.critical_success, other.critical_failure]:
				if branch != null and branch.next == old_id:
					branch.next = new_value

		elif other is DialogueChoiceNode:
			if other.next == old_id:
				other.next = new_value
			if other.condition_node_id == old_id:
				other.condition_node_id = new_value
			if other.default_return_id == old_id:
				other.default_return_id = new_value

		elif other is DialogueLineNode:
			if other.next == old_id:
				other.next = new_value
			if other.default_return_id == old_id:
				other.default_return_id = new_value

		elif other is DialogueStructureNode:
			for i in other.outputs.size():
				if other.outputs[i] == old_id:
					other.outputs[i] = new_value


## Renames `old_id` to `new_id` - re-keys its own tree.nodes entry
## (since it's keyed by node_id), updates the node's own node_id field,
## then cascades the change everywhere else via
## _replace_node_references (including a self-reference, e.g. a node
## whose own `next` pointed at itself - the walk doesn't skip the
## renamed node, so that case is handled correctly too, not left
## dangling). Rejects (reverting the field's displayed text via a
## rebuild, no warning dialog) an empty new_id or one that collides
## with a DIFFERENT, already-existing node - same category of guard
## ActorFormTab already uses for actor_id.
##
## Deliberately NOT live-write-through like every other field in this
## file - see _build_node_id_field's own docstring for why a rename
## can't safely fire on every keystroke the way a plain text field's
## contents do.
func _rename_node(old_id: String, new_id: String) -> void:
	if new_id == old_id:
		return
	if new_id.is_empty():
		push_warning("GraphTab: cannot rename '%s' to an empty id" % old_id)
		_request_rebuild()
		return
	if _tree.nodes.has(new_id):
		push_warning("GraphTab: cannot rename '%s' to '%s' - that id is already used by another node" % [old_id, new_id])
		_request_rebuild()
		return
	if not _tree.nodes.has(old_id):
		return

	var node: DialogueGraphNode = _tree.nodes[old_id]
	_tree.nodes.erase(old_id)
	node.node_id = new_id
	_tree.nodes[new_id] = node

	_replace_node_references(old_id, new_id)

	_request_rebuild()


## Deep-duplicates `source_id`'s node via Resource.duplicate(true), then
## manually re-duplicates every Array-of-Resources field the built-in
## call leaves silently shared. This is a confirmed, long-standing
## Godot engine limitation (godotengine/godot issues #74918, #82348,
## #105904 - still present as of 4.4/4.5): duplicate(true) correctly
## deep-copies a DIRECT Resource-typed property (e.g. a
## SkillCheckBranch stored directly in `success`), but a Resource
## stored INSIDE an Array or Dictionary property is NEVER duplicated,
## even with subresources=true - the array container itself is fresh,
## but every element inside it stays the exact same object as the
## original. Left unpatched, this is exactly the bug it produces:
## editing a "duplicated" node's effects/conditions/variants silently
## also edits the original's, since they were never actually different
## objects to begin with.
##
## Gets a fresh, auto-generated node_id and a small position offset so
## the copy isn't stacked exactly on the original. Outgoing wiring
## (next, etc.) is preserved as part of "all its settings," same as
## every other field - nothing ELSE in the tree gets rewired to point
## at the new copy, since only the ORIGINAL was ever anyone else's
## target to begin with.
func _duplicate_node(source_id: String) -> void:
	if not _tree.nodes.has(source_id):
		return
	var source: DialogueGraphNode = _tree.nodes[source_id]
	var new_node := source.duplicate(true) as DialogueGraphNode
	_deep_copy_array_fields(new_node)

	var new_id := _generate_unique_node_id(source_id)
	new_node.node_id = new_id
	new_node.editor_position = source.editor_position + Vector2(40, 40)

	_tree.nodes[new_id] = new_node
	_request_rebuild()


## The manual fix-up for duplicate(true)'s Array-of-Resources gap - see
## _duplicate_node()'s own docstring. Mutates `node` in place,
## replacing each affected array's elements with genuinely independent
## copies. Explicit "as" casts throughout rather than relying on the
## `is` check alone to narrow `node`'s type - GDScript does not
## reliably narrow a variable's STATIC type from an `is` check (see
## _draw_skill_check_branch_connections's docstring for the parse
## error this caused elsewhere when relied on).
##
## ConditionSet entries are deliberately EXCLUDED from this - a
## ConditionSet is explicitly meant to be a shared, reusable resource
## across many different nodes/trees (Dialogue & Relations doc Section
## 4.7); forking a private copy of one on every node duplication would
## break that sharing rather than fix a bug. Inline DialogueCondition
## entries still get duplicated normally, same as everywhere else.
##
## DialogueStructureNode needs no entry here - its only array
## (`outputs`) holds plain Strings, which duplicate() already copies
## correctly regardless of this bug (the bug is specifically about
## Resource OBJECTS inside an array, not value types like String).
func _deep_copy_array_fields(node: DialogueGraphNode) -> void:
	if node is DialogueLineNode:
		var line := node as DialogueLineNode
		for i in line.variants.size():
			line.variants[i] = line.variants[i].duplicate(false)

	elif node is DialogueSkillCheckChoiceNode:
		# Checked BEFORE DialogueChoiceNode - it extends that class, so
		# the broader check would otherwise also match it.
		var skill_check := node as DialogueSkillCheckChoiceNode
		for branch in [skill_check.success, skill_check.failure, skill_check.critical_success, skill_check.critical_failure]:
			if branch != null:
				_deep_copy_effects(branch.effects)

	elif node is DialogueChoiceNode:
		var choice := node as DialogueChoiceNode
		_deep_copy_effects(choice.effects)

	elif node is DialogueConditionNode:
		var condition_node := node as DialogueConditionNode
		for i in condition_node.conditions.size():
			var entry = condition_node.conditions[i]
			if entry is DialogueCondition:
				condition_node.conditions[i] = entry.duplicate(false)
			# ConditionSet entries left as the same shared reference on
			# purpose - see this function's own docstring.


## `duplicate(false)`, not `true`, deliberately - a DialogueEffect's
## own `custom_script: Script` field is a REFERENCE to an existing,
## shared .gd file (e.g. a CUSTOM effect's script), not owned data.
## duplicate(true) would try to deep-copy that reference too, silently
## detaching it from the real file on disk - `false` copies the plain
## fields (type/target/value) correctly while leaving custom_script as
## the same shared reference, which is what's actually wanted.
func _deep_copy_effects(effects: Array) -> void:
	for i in effects.size():
		effects[i] = effects[i].duplicate(false)


## Renaming a node_id is COMMIT-based (Enter, or losing focus), NOT
## live-write-through like every other field in this file. A rename
## needs to cascade-update every OTHER reference to the old id across
## the whole tree (_rename_node), which is far too expensive - and, if
## a partial mid-typing value happened to collide with an existing
## node_id, genuinely risky (a real id collision, not just a cosmetic
## glitch) - to re-run on every single keystroke the way a plain text
## field's contents do. Both text_submitted (Enter) and focus_exited
## commit, so clicking away without pressing Enter still saves the
## rename rather than silently discarding it.
func _build_node_id_field(node: DialogueGraphNode) -> HBoxContainer:
	var row := HBoxContainer.new()

	var label := Label.new()
	label.text = "ID:"
	row.add_child(label)

	var field := LineEdit.new()
	field.text = node.node_id
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var commit := func() -> void:
		_rename_node(node.node_id, field.text.strip_edges())
	field.text_submitted.connect(func(_new_text: String) -> void:
		commit.call()
	)
	field.focus_exited.connect(commit)
	row.add_child(field)

	return row


## Small Duplicate/Delete button pair added to the bottom of every node
## type's body. Delete here is a redundant, explicit alternative to the
## Delete/Backspace keyboard shortcut (_on_delete_nodes_request), for
## anyone who'd rather click than select-and-press-key - both paths
## call the exact same underlying _delete_node()/_duplicate_node(), so
## there's only one place that actually implements either action.
func _build_node_actions_row(node_id: String) -> HBoxContainer:
	var row := HBoxContainer.new()

	var duplicate_button := Button.new()
	duplicate_button.text = "Duplicate"
	duplicate_button.pressed.connect(func() -> void:
		_duplicate_node(node_id)
	)
	row.add_child(duplicate_button)

	var delete_button := Button.new()
	delete_button.text = "Delete"
	delete_button.pressed.connect(func() -> void:
		_delete_node(node_id)
		_request_rebuild()
	)
	row.add_child(delete_button)

	return row


func _on_start_node_selected(index: int) -> void:
	if _tree == null:
		return
	if index == 0:
		_tree.start_node_id = ""
	else:
		_tree.start_node_id = _start_node_picker.get_item_text(index)


## Repopulates the Start Node dropdown from the tree's CURRENT node
## ids, with "(none)" as item 0 for a brand-new tree or one whose start
## node was just deleted (_delete_node()/_replace_node_references()
## already clear tree.start_node_id in that case, but leave nothing to
## re-point it at until a new one is picked here). Called once from
## load_tree() (via the initial _build_graph() call) and again at the
## end of every subsequent rebuild, since adding/removing/renaming a
## node changes what's valid to pick.
func _refresh_start_node_picker() -> void:
	_start_node_picker.clear()
	_start_node_picker.add_item("(none)")
	var ids := _tree.nodes.keys()
	ids.sort()
	var selected_index := 0
	for i in ids.size():
		_start_node_picker.add_item(ids[i])
		if ids[i] == _tree.start_node_id:
			selected_index = i + 1   # +1 to account for the "(none)" entry at index 0
	_start_node_picker.select(selected_index)


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
	_capture_current_positions()
	var err := ResourceSaver.save(_tree, _tree.resource_path)
	if err != OK:
		_status_label.text = "Save failed (error %d) - see Output panel." % err
		push_warning("GraphTab: ResourceSaver.save() failed for '%s' with error %d" % [_tree.resource_path, err])
		return
	EditorInterface.get_resource_filesystem().scan()
	_status_label.text = "Saved '%s'." % tree_id


# ---------------------------------------------------------------------------
# Wiring - dragging a connection sets the relevant `next`-style field
# (or, for a condition-input wire, condition_node_id); dragging one
# away clears it. See file header for why this rebuilds (deferred,
# coalesced) rather than patching the one changed connection in place.
# ---------------------------------------------------------------------------

## to_port == CONDITION_INPUT_PORT is handled as a special case FIRST,
## since its data direction is reversed from every other wire (the
## TARGET choice stores the reference, not the source ConditionNode -
## see file header). Everything else keeps the original "source field
## depends on from_node's type" dispatch, just against the new types
## and without the old structural-connection guard - a skill check's
## branches are real, directly wireable outputs now, there's no more
## "always routes to its own gate automatically" case to reject.
func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	if not _tree.nodes.has(to_node):
		push_warning("GraphTab: connection target '%s' (dragged from '%s' port %d) isn't a real tree node - refusing to wire to it" % [to_node, from_node, from_port])
		return
	var to_node_obj: DialogueGraphNode = _tree.nodes[to_node]

	if to_port == CONDITION_INPUT_PORT:
		if not (to_node_obj is DialogueChoiceNode):
			push_warning("GraphTab: port %d (condition input) only exists on Choice-family nodes, but '%s' isn't one" % [CONDITION_INPUT_PORT, to_node])
			return
		if not (_tree.nodes.has(from_node) and _tree.nodes[from_node] is DialogueConditionNode):
			push_warning("GraphTab: a choice's condition input can only be wired from a DialogueConditionNode - '%s' isn't one" % from_node)
			return
		to_node_obj.condition_node_id = from_node
		_request_rebuild()
		return

	if not _tree.nodes.has(from_node):
		push_warning("GraphTab: connection source '%s' not recognized, ignoring" % from_node)
		return
	var from_node_obj: DialogueGraphNode = _tree.nodes[from_node]

	if from_node_obj is DialogueLineNode:
		from_node_obj.next = to_node
	elif from_node_obj is DialogueStructureNode:
		if from_port < 0 or from_port >= from_node_obj.outputs.size():
			push_warning("GraphTab: connection source port %d out of range for Structure node '%s'" % [from_port, from_node])
			return
		from_node_obj.outputs[from_port] = to_node
		if to_port == 0:
			_maybe_set_default_return(to_node_obj, from_node)
	elif from_node_obj is DialogueSkillCheckChoiceNode:
		_set_branch_next(from_node_obj as DialogueSkillCheckChoiceNode, from_port, to_node)
	elif from_node_obj is DialogueChoiceNode:
		from_node_obj.next = to_node
	else:
		push_warning("GraphTab: connection source '%s' has an unrecognized type, ignoring" % from_node)
		return

	_request_rebuild()


func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	if to_port == CONDITION_INPUT_PORT:
		if _tree.nodes.has(to_node) and _tree.nodes[to_node] is DialogueChoiceNode:
			_tree.nodes[to_node].condition_node_id = ""
		_request_rebuild()
		return

	if not _tree.nodes.has(from_node):
		push_warning("GraphTab: disconnection source '%s' not recognized, ignoring" % from_node)
		return
	var from_node_obj: DialogueGraphNode = _tree.nodes[from_node]

	if from_node_obj is DialogueLineNode:
		from_node_obj.next = ""
	elif from_node_obj is DialogueStructureNode:
		if from_port >= 0 and from_port < from_node_obj.outputs.size():
			from_node_obj.outputs[from_port] = ""
	elif from_node_obj is DialogueSkillCheckChoiceNode:
		_set_branch_next(from_node_obj as DialogueSkillCheckChoiceNode, from_port, "")
	elif from_node_obj is DialogueChoiceNode:
		from_node_obj.next = ""
	else:
		push_warning("GraphTab: disconnection source '%s' has an unrecognized type, ignoring" % from_node)
		return

	_request_rebuild()


## from_port here is the SAME compacted branch-port numbering as
## before (0=Success, 1=Failure, 2=Critical Success, 3=Critical
## Failure) - connect_node()'s port index is into the COMPACTED list of
## enabled ports on that side, skipping any row where that side is
## disabled. Wiring FROM an unauthored critical branch (2/3, currently
## null) implicitly authors it - creating a fresh SkillCheckBranch to
## hold the new `next` value, since there's nowhere else to store it.
## An empty next_value (from a disconnect, or from
## _build_next_status_row's Clear Connection button) only clears the
## field; it never un-authors an existing branch back to null, since
## that could silently destroy any effects already authored on it.
func _set_branch_next(choice: DialogueSkillCheckChoiceNode, from_port: int, next_value: String) -> void:
	match from_port:
		0:
			if choice.success == null:
				push_warning("GraphTab: '%s' has no Success branch - malformed data, cannot wire" % choice.node_id)
				return
			choice.success.next = next_value
		1:
			if choice.failure == null:
				push_warning("GraphTab: '%s' has no Failure branch - malformed data, cannot wire" % choice.node_id)
				return
			choice.failure.next = next_value
		2:
			if choice.critical_success == null:
				if next_value.is_empty():
					return
				choice.critical_success = SkillCheckBranch.new()
			choice.critical_success.next = next_value
		3:
			if choice.critical_failure == null:
				if next_value.is_empty():
					return
				choice.critical_failure = SkillCheckBranch.new()
			choice.critical_failure.next = next_value
		_:
			push_warning("GraphTab: unrecognized skill-check branch port %d" % from_port)


## Convenience auto-set, not authoritative: remembers `structure_node_id`
## as this node's implicit "return to parent" target the FIRST time
## it's wired from any DialogueStructureNode's main-input connection -
## never overwrites an already-set value (e.g. a node deliberately
## given a different default, or one reached from more than one
## structure node, where the first wire wins). Only Line/Choice-family
## nodes have default_return_id at all (DialogueStructureNode/
## DialogueConditionNode don't - silently skipped here, not an error,
## since a wire landing on one of those is a perfectly normal, if
## unusual, topology).
func _maybe_set_default_return(target: DialogueGraphNode, structure_node_id: String) -> void:
	if target is DialogueLineNode or target is DialogueChoiceNode:
		if target.default_return_id.is_empty():
			target.default_return_id = structure_node_id


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


## Coalesces any number of rebuild requests fired in quick succession
## into at most one actual _build_graph() call - see file header on why
## this matters for the remove_child()/queue_free() ordering.
func _request_rebuild() -> void:
	if _rebuild_pending:
		return
	_rebuild_pending = true
	call_deferred("_do_deferred_rebuild")


func _do_deferred_rebuild() -> void:
	_rebuild_pending = false
	_build_graph(_tree)


func _build_graph(tree: DialogueTree) -> void:
	_capture_current_positions()
	_graph_edit.clear_connections()

	for child in _graph_edit.get_children():
		if child is GraphElement:
			_graph_edit.remove_child(child)
			child.queue_free()

	var auto_layout_index := 0

	for node_id in tree.nodes:
		var node: DialogueGraphNode = tree.nodes[node_id]
		var graph_node: GraphNode

		# DialogueSkillCheckChoiceNode BEFORE DialogueChoiceNode - it
		# extends that class, so the broader check would otherwise also
		# match it and build it as a plain choice.
		#
		# Explicit "as" casts throughout, not just relying on the `is`
		# check above each branch - GDScript does not reliably narrow a
		# variable's STATIC type from an `is` check alone (see
		# _draw_skill_check_branch_connections's docstring for the
		# parse error this caused elsewhere when relied on for `:=`
		# inference). These particular calls didn't error without a
		# cast, but there's no reason to depend on that.
		if node is DialogueSkillCheckChoiceNode:
			graph_node = _build_skill_check_choice_node(node as DialogueSkillCheckChoiceNode)
		elif node is DialogueChoiceNode:
			graph_node = _build_choice_node(node as DialogueChoiceNode)
		elif node is DialogueLineNode:
			graph_node = _build_line_node(node as DialogueLineNode)
		elif node is DialogueStructureNode:
			graph_node = _build_structure_node(node as DialogueStructureNode)
		elif node is DialogueConditionNode:
			graph_node = _build_condition_node(node as DialogueConditionNode)
		else:
			push_warning("GraphTab: unrecognized node type for node_id '%s', skipping" % node_id)
			continue

		graph_node.name = node_id
		_position_node(graph_node, node.editor_position, auto_layout_index)
		auto_layout_index += 1
		_graph_edit.add_child(graph_node)

	_draw_connections(tree)
	_refresh_start_node_picker()


func _position_node(graph_node: GraphNode, editor_position: Vector2, auto_index: int) -> void:
	if editor_position != Vector2.ZERO:
		graph_node.position_offset = editor_position
		return
	# Auto-grid fallback for never-positioned nodes (see file header).
	var column := auto_index % AUTO_LAYOUT_COLUMNS
	var row := auto_index / AUTO_LAYOUT_COLUMNS
	graph_node.position_offset = Vector2(column, row) * AUTO_LAYOUT_SPACING


## Counterpart to _position_node - walks whatever's CURRENTLY rendered
## and writes each one's on-screen position_offset back into its
## backing data object's editor_position, before a rebuild (or a Save)
## can discard that layout. Simpler than before: every GraphNode's name
## is a real tree.nodes key now, no more _gate_lookup side-table to
## check first.
func _capture_current_positions() -> void:
	if _tree == null:
		return
	for child in _graph_edit.get_children():
		if not (child is GraphNode):
			continue
		var graph_node := child as GraphNode
		if _tree.nodes.has(graph_node.name):
			var node: DialogueGraphNode = _tree.nodes[graph_node.name]
			node.editor_position = graph_node.position_offset


# ---------------------------------------------------------------------------
# Node builders
# ---------------------------------------------------------------------------

## Unchanged from before the restructure - DialogueLineNode's own shape
## never changed. speaker/emotion_tag stay plain text fields for the
## same reason noted previously (Known project conventions - IDs vs
## display names): a smarter actor-id/portrait-key picker is a
## deliberate, deferred fast-follow, not an oversight.
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
	# Row 0 carries both this node's ports - every other row added
	# below stays portless (never had set_slot() called on it, which
	# defaults a row to no ports at all).
	graph_node.set_slot(0, true, PORT_TYPE, LINE_PORT_COLOR, true, PORT_TYPE, LINE_PORT_COLOR)

	graph_node.add_child(_build_node_id_field(node))

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

	var set_line_next := func(new_value: String) -> void:
		node.next = new_value
	graph_node.add_child(_build_next_status_row(node.next, set_line_next))
	graph_node.add_child(_build_default_return_field(node))
	graph_node.add_child(_build_node_actions_row(node.node_id))

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


## Purely topological - no text, no conditions, no effects (Restructure
## doc Section 4). Each row is one output slot: a status+clear row
## (reusing _build_next_status_row exactly like every other `next`-
## style field) plus a Remove Output button, bound to that specific
## array index via a small "box" closure, since the row is built inside
## a loop and each row's setters need to close over ITS OWN index, not
## whichever value `i` happens to hold by the time the closure runs.
func _build_structure_node(node: DialogueStructureNode) -> GraphNode:
	var graph_node := GraphNode.new()
	graph_node.title = "Structure: %s" % node.node_id

	for i in node.outputs.size():
		var index := i   # fresh per-iteration capture - see docstring above
		var set_output := func(new_value: String) -> void:
			node.outputs[index] = new_value
		var row := _build_next_status_row(node.outputs[i], set_output)

		var remove_button := Button.new()
		remove_button.text = "Remove Output"
		# Only enabled once this slot is unconnected - removing a
		# still-wired slot would silently discard that connection with
		# no undo, so it's Clear Connection first, then Remove, rather
		# than one riskier action doing both.
		remove_button.disabled = not node.outputs[i].is_empty()
		remove_button.pressed.connect(func() -> void:
			# Changes this node's port count (and every LATER slot's
			# compacted port index), so this needs a full rebuild - same
			# rule already established for +Add Choice below and for
			# Options/Variants elsewhere in this file.
			node.outputs.remove_at(index)
			_request_rebuild()
		)
		row.add_child(remove_button)

		graph_node.add_child(row)
		# Row 0 doubles as this node's entry point, matching every
		# other node type's single-input convention. Every row has
		# output enabled uniformly (no disabled-output rows precede
		# them), so compacted output index == array index == loop
		# index i directly - no offset to account for.
		graph_node.set_slot(i, i == 0, PORT_TYPE, STRUCTURE_PORT_COLOR, true, PORT_TYPE, STRUCTURE_PORT_COLOR)

	# Added AFTER the loop, deliberately - unlike every other builder in
	# this file, this one indexes set_slot() by the raw loop index `i`
	# directly (not a dynamically-computed get_child_count() - 1), since
	# every output row needs a STABLE index matching its array position.
	# Adding a row BEFORE the loop would shift every row's actual child
	# position without shifting `i` to match, silently breaking every
	# output's port.
	graph_node.add_child(_build_node_id_field(node))

	var add_button := Button.new()
	add_button.text = "+ Add Choice"
	add_button.pressed.connect(func() -> void:
		# Changes this node's port count, so it needs a full rebuild
		# rather than in-place mutation - same rule already established
		# for Options/Variants elsewhere in this file.
		node.outputs.append("")
		_request_rebuild()
	)
	graph_node.add_child(add_button)
	graph_node.add_child(_build_node_actions_row(node.node_id))

	return graph_node


## Self-contained gate - reopens Condition-as-graph-node (Restructure
## doc Section 5). 0 inputs, 1 output that can fan out to many choices'
## condition inputs (drawn from the CHOICE side - see
## _draw_connections). The mode picker doubles as this node's only
## port-carrying row; the conditions repeater below it is entirely
## portless, reusing _build_conditions_repeater exactly as it already
## worked for the old per-Option conditions list.
func _build_condition_node(node: DialogueConditionNode) -> GraphNode:
	var graph_node := GraphNode.new()
	graph_node.title = "Condition: %s" % node.node_id

	var mode_picker := OptionButton.new()
	for mode_name in DialogueConditionNode.Mode.keys():
		mode_picker.add_item(mode_name, DialogueConditionNode.Mode[mode_name])
	mode_picker.select(mode_picker.get_item_index(node.mode))
	mode_picker.item_selected.connect(func(index: int) -> void:
		node.mode = mode_picker.get_item_id(index)
	)
	graph_node.add_child(mode_picker)
	# 0 inputs, 1 output - the ONLY row carries the output; there's
	# never a left/input port on this node type at all.
	graph_node.set_slot(0, false, PORT_TYPE, CONDITION_PORT_COLOR, true, PORT_TYPE, CONDITION_PORT_COLOR)

	graph_node.add_child(_build_node_id_field(node))
	graph_node.add_child(_build_conditions_repeater(node.conditions))
	graph_node.add_child(_build_node_actions_row(node.node_id))

	return graph_node


## Row 1 on any DialogueChoiceNode (or its DialogueSkillCheckChoiceNode
## subtype) - the condition input. Status-only, no inline field: per
## the Restructure design doc, no choice authors its own conditions -
## only a wired DialogueConditionNode does, set exclusively by dragging
## a wire onto this port (or cleared via drag-away/the same "Clear
## Connection" mechanism other `next`-style fields use, since
## disconnecting FROM a Condition node's output hits the exact same
## multi-wire-convergence risk as any other port - see file header on
## issue #92120). Always called as the second row added in both
## builders below, so get_child_count() - 1 reliably lands on row 1.
func _add_condition_input_row(graph_node: GraphNode, node: DialogueChoiceNode) -> void:
	var set_condition := func(new_value: String) -> void:
		node.condition_node_id = new_value
	var status_text := ("← %s" % node.condition_node_id) if not node.condition_node_id.is_empty() else "(no condition - always available)"
	var row := _build_next_status_row(status_text, set_condition)
	# _build_next_status_row's own status label always shows its raw
	# current_next argument verbatim (prefixed with "→ "), which reads
	# backwards for an INPUT - swap in a clearer label after the fact
	# rather than fork the shared helper over one line of text.
	var status_label := row.get_child(0) as Label
	status_label.text = "Condition: %s" % status_text
	graph_node.add_child(row)
	var slot_index := graph_node.get_child_count() - 1
	graph_node.set_slot(slot_index, true, PORT_TYPE, CONDITION_PORT_COLOR, false, PORT_TYPE, CONDITION_PORT_COLOR)


## A single dialogue choice - text, consume_once, effects, one output.
## Row 0 carries the main input AND this choice's single output
## together (matching every other single-output node type's
## convention); DialogueSkillCheckChoiceNode's own builder below
## differs here, since its 4 outputs live on separate branch rows
## instead.
func _build_choice_node(node: DialogueChoiceNode) -> GraphNode:
	var graph_node := GraphNode.new()
	graph_node.title = "Choice: %s" % node.node_id

	var consume_check := CheckBox.new()
	consume_check.text = "Once"
	consume_check.button_pressed = node.consume_once
	consume_check.toggled.connect(func(toggled_on: bool) -> void:
		node.consume_once = toggled_on
	)
	graph_node.add_child(consume_check)
	graph_node.set_slot(0, true, PORT_TYPE, CHOICE_PORT_COLOR, true, PORT_TYPE, CHOICE_PORT_COLOR)

	graph_node.add_child(_build_node_id_field(node))
	_add_condition_input_row(graph_node, node)

	var text_edit := TextEdit.new()
	text_edit.text = node.text
	text_edit.custom_minimum_size = Vector2(220, 50)
	text_edit.text_changed.connect(func() -> void:
		node.text = text_edit.text
	)
	graph_node.add_child(text_edit)

	graph_node.add_child(_build_effects_repeater(node.effects))

	var set_choice_next := func(new_value: String) -> void:
		node.next = new_value
	graph_node.add_child(_build_next_status_row(node.next, set_choice_next))
	graph_node.add_child(_build_default_return_field(node))
	graph_node.add_child(_build_node_actions_row(node.node_id))

	return graph_node


## skill_id is a plain text field for now - same known id-vs-display-
## name caveat noted on Line's speaker field (deferred smarter-picker
## treatment, not overlooked).
##
## dc_tier/dc_manual are both always built, but only one is visible at
## a time based on dc_mode - matches get_dc()'s own behavior of only
## ever reading whichever field is active.
##
## The inherited `effects` field is deliberately never surfaced here -
## see this class's own docstring on why (fires per-branch once an
## outcome is known, not on selection).
func _build_skill_check_choice_node(node: DialogueSkillCheckChoiceNode) -> GraphNode:
	var graph_node := GraphNode.new()
	graph_node.title = "Skill Check: %s" % (node.skill_id if not node.skill_id.is_empty() else "(no skill_id)")

	var skill_id_field := LineEdit.new()
	skill_id_field.placeholder_text = "skill_id"
	skill_id_field.text = node.skill_id
	skill_id_field.custom_minimum_size = Vector2(220, 0)
	skill_id_field.text_changed.connect(func(new_text: String) -> void:
		node.skill_id = new_text
		graph_node.title = "Skill Check: %s" % (new_text if not new_text.is_empty() else "(no skill_id)")
	)
	graph_node.add_child(skill_id_field)
	# Row 0: main input only - no output here, unlike a plain
	# DialogueChoiceNode. This subtype's 4 outputs live on the branch
	# rows further down instead.
	graph_node.set_slot(0, true, PORT_TYPE, SKILL_CHECK_PORT_COLOR, false, PORT_TYPE, SKILL_CHECK_PORT_COLOR)

	graph_node.add_child(_build_node_id_field(node))
	_add_condition_input_row(graph_node, node)
	graph_node.add_child(_build_default_return_field(node))

	var consume_check := CheckBox.new()
	consume_check.text = "Once"
	consume_check.button_pressed = node.consume_once
	consume_check.toggled.connect(func(toggled_on: bool) -> void:
		node.consume_once = toggled_on
	)
	graph_node.add_child(consume_check)

	var text_edit := TextEdit.new()
	text_edit.text = node.text
	text_edit.custom_minimum_size = Vector2(220, 50)
	text_edit.text_changed.connect(func() -> void:
		node.text = text_edit.text
	)
	graph_node.add_child(text_edit)

	var dc_tier_picker := OptionButton.new()
	for tier_name in DiceResolver.DifficultyTier.keys():
		dc_tier_picker.add_item(tier_name, DiceResolver.DifficultyTier[tier_name])
	dc_tier_picker.select(dc_tier_picker.get_item_index(node.dc_tier))
	dc_tier_picker.item_selected.connect(func(index: int) -> void:
		node.dc_tier = dc_tier_picker.get_item_id(index)
	)

	var dc_manual_field := SpinBox.new()
	dc_manual_field.min_value = 0
	dc_manual_field.max_value = 100   # placeholder bound, not a confirmed real DC ceiling
	dc_manual_field.step = 1
	dc_manual_field.value = node.dc_manual
	dc_manual_field.value_changed.connect(func(new_value: float) -> void:
		node.dc_manual = int(new_value)
	)

	var dc_mode_picker := OptionButton.new()
	dc_mode_picker.add_item("DC: Tier", DialogueSkillCheckChoiceNode.DCMode.TIER)
	dc_mode_picker.add_item("DC: Manual", DialogueSkillCheckChoiceNode.DCMode.MANUAL)
	dc_mode_picker.select(dc_mode_picker.get_item_index(node.dc_mode))
	dc_mode_picker.item_selected.connect(func(index: int) -> void:
		var mode: int = dc_mode_picker.get_item_id(index)
		node.dc_mode = mode
		dc_tier_picker.visible = mode == DialogueSkillCheckChoiceNode.DCMode.TIER
		dc_manual_field.visible = mode == DialogueSkillCheckChoiceNode.DCMode.MANUAL
	)
	graph_node.add_child(dc_mode_picker)

	# dc_tier_picker/dc_manual_field share ONE row here rather than
	# being added as two separate top-level GraphNode children (an
	# earlier version of this function did that) - GraphNode lays out
	# its DIRECT children like a VBoxContainer, so an invisible direct
	# child collapses to zero height visually, but its PORT/slot index
	# doesn't shift to match - everything after it (here, all 4 branch
	# rows) ends up with its port visually offset from its actual row.
	# This is the confirmed cause behind Success/Failure/etc. only
	# showing 3 output ports, mispositioned. Nesting both inside one
	# row sidesteps it entirely: the row itself is always visible and
	# always exactly one slot, regardless of which control inside it is
	# showing - matching how the Effects/Conditions repeaters' own
	# visibility-toggled fields (also nested, never top-level) never
	# hit this.
	dc_tier_picker.visible = node.dc_mode == DialogueSkillCheckChoiceNode.DCMode.TIER
	dc_manual_field.visible = node.dc_mode == DialogueSkillCheckChoiceNode.DCMode.MANUAL
	var dc_value_row := HBoxContainer.new()
	dc_value_row.add_child(dc_tier_picker)
	dc_value_row.add_child(dc_manual_field)
	graph_node.add_child(dc_value_row)

	_add_branch_row(graph_node, "Success", node.success)
	_add_branch_row(graph_node, "Failure", node.failure)
	_add_branch_row(graph_node, "Critical Success", node.critical_success, "falls back to Success" if node.critical_success == null else "")
	_add_branch_row(graph_node, "Critical Failure", node.critical_failure, "falls back to Failure" if node.critical_failure == null else "")
	graph_node.add_child(_build_node_actions_row(node.node_id))

	return graph_node


## branch is null for an unauthored critical branch (falls back to
## success/failure per get_critical_success_branch()/
## get_critical_failure_branch()) - there's nothing to attach a status
## row or effects repeater to in that case, so the row stays label-only.
func _add_branch_row(graph_node: GraphNode, branch_label: String, branch: SkillCheckBranch, fallback_note: String = "") -> void:
	var row := VBoxContainer.new()

	var label := Label.new()
	label.text = branch_label if fallback_note.is_empty() else "%s (%s)" % [branch_label, fallback_note]
	row.add_child(label)

	if branch != null:
		var set_branch_next_field := func(new_value: String) -> void:
			branch.next = new_value
		row.add_child(_build_next_status_row(branch.next, set_branch_next_field))
		row.add_child(_build_effects_repeater(branch.effects))

	graph_node.add_child(row)
	var slot_index := graph_node.get_child_count() - 1
	graph_node.set_slot(slot_index, false, PORT_TYPE, SKILL_CHECK_PORT_COLOR, true, PORT_TYPE, SKILL_CHECK_PORT_COLOR)


## Shared status+clear row for any `next`-style field (Line.next,
## Structure.outputs[i], Choice.next, SkillCheckBranch.next) or, via
## _add_condition_input_row, a choice's condition_node_id. This is the
## reliable way to clear a connection (see file header on issue
## #92120); dragging a NEW wire still works normally via
## connection_request.
func _build_next_status_row(current_next: String, set_next: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()

	var status_label := Label.new()
	status_label.text = ("→ %s" % current_next) if not current_next.is_empty() else "(unconnected - drag a wire from the port to set this)"
	row.add_child(status_label)

	var clear_button := Button.new()
	clear_button.text = "Clear Connection"
	clear_button.disabled = current_next.is_empty()
	clear_button.pressed.connect(func() -> void:
		set_next.call("")
		_request_rebuild()
	)
	row.add_child(clear_button)

	return row


## default_return_id, on Line/Choice-family nodes only (Restructure
## follow-up addendum) - deliberately a plain editable text field, NOT
## a port/wire (per the explicit requirement that this never need a
## wire present in the graph). Free text, not a picker, for the same
## reason speaker/skill_id are - see _build_line_node's header comment.
## Usually filled in automatically the first time this node is wired
## from a DialogueStructureNode's output (_maybe_set_default_return),
## but always editable/clearable by hand too - e.g. for existing nodes
## authored before this field existed, or a node like `leave` that's
## reached from hub but should genuinely end rather than loop back.
func _build_default_return_field(node: DialogueGraphNode) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = "default_return_id (used only when next is empty)"
	field.text = node.default_return_id
	field.text_changed.connect(func(new_text: String) -> void:
		node.default_return_id = new_text
	)
	return field


# ---------------------------------------------------------------------------
# Effects repeater (shared by Choice.effects and every SkillCheckBranch.effects)
# ---------------------------------------------------------------------------

## `effects` is the actual Array reference held by the owning Resource
## (DialogueChoiceNode.effects or SkillCheckBranch.effects) - Godot
## Arrays are reference types, so append()/erase() here mutate that
## same live array directly, matching this whole file's live-write-
## through approach.
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


## target/value visibility follows dialogue_effect.gd's own field-
## meaning-by-type docstring: target is used by every type except
## CUSTOM (which uses custom_script instead). value is used only by
## FACTION_REPUTATION_DELTA and GRANT_ITEM.
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
	value_field.prefix = "value:"
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
	script_picker.resource_changed.connect(func(resource: Resource) -> void:
		effect.custom_script = resource as Script
	)
	row.add_child(script_picker)

	_update_effect_row_visibility(effect.type, target_field, value_field, script_picker)

	type_picker.item_selected.connect(func(index: int) -> void:
		var new_type: int = type_picker.get_item_id(index)
		effect.type = new_type
		_update_effect_row_visibility(new_type, target_field, value_field, script_picker)
	)

	container.add_child(row)


func _update_effect_row_visibility(new_type: int, target_field: LineEdit, value_field: SpinBox, script_picker: EditorResourcePicker) -> void:
	target_field.visible = new_type != DialogueEffect.Type.CUSTOM
	value_field.visible = new_type in EFFECT_TYPES_USING_VALUE
	script_picker.visible = new_type == DialogueEffect.Type.CUSTOM


# ---------------------------------------------------------------------------
# Conditions repeater - now called only from _build_condition_node, since
# no choice authors its own conditions anymore (Restructure doc Section
# 6) - the repeater's own row-level logic is otherwise unchanged from
# when it served the old per-Option conditions list.
# ---------------------------------------------------------------------------

## `conditions` is the actual Array reference held by the owning
## DialogueConditionNode - mutated in place, matching the Effects
## repeater and this whole file's live-write-through approach.
func _build_conditions_repeater(conditions: Array) -> VBoxContainer:
	var box := VBoxContainer.new()

	var label := Label.new()
	label.text = "Conditions:"
	box.add_child(label)

	var rows := VBoxContainer.new()
	box.add_child(rows)
	for entry in conditions:
		_add_condition_entry_row(rows, conditions, entry)

	var buttons := HBoxContainer.new()
	var add_condition_button := Button.new()
	add_condition_button.text = "+ Condition"
	add_condition_button.pressed.connect(func() -> void:
		var new_condition := DialogueCondition.new()
		conditions.append(new_condition)
		_add_condition_entry_row(rows, conditions, new_condition)
	)
	buttons.add_child(add_condition_button)

	var add_set_button := Button.new()
	add_set_button.text = "+ ConditionSet Reference"
	add_set_button.pressed.connect(func() -> void:
		# Nothing is added to `conditions` yet here - the row itself
		# commits to the array lazily, on first pick (see
		# _add_condition_set_reference_row), avoiding an ambiguous
		# unpicked-null entry ever sitting in the saved data.
		_add_condition_set_reference_row(rows, conditions, null)
	)
	buttons.add_child(add_set_button)
	box.add_child(buttons)

	return box


func _add_condition_entry_row(container: VBoxContainer, conditions: Array, entry: Variant) -> void:
	if entry is ConditionSet:
		_add_condition_set_reference_row(container, conditions, entry)
	elif entry is DialogueCondition:
		_add_inline_condition_row(container, conditions, entry)
	else:
		push_warning("GraphTab: conditions array contains an unrecognized entry type, skipping row")


## Lazy-commit: `initial_condition_set` starts null for a freshly-added,
## not-yet-picked row. Nothing is written into `conditions` until the
## picker actually resolves to a real ConditionSet - clearing an
## already-picked row back to nothing removes it from the array again
## rather than leaving a stray null behind. Uses a single-element "box"
## array so both closures below (picker + remove button) share one
## mutable reference to the current value - GDScript lambdas capture
## outer locals by value at creation time, so without this, the remove
## button's closure would keep whatever the value was when the row was
## first built, not whatever's actually been picked since.
func _add_condition_set_reference_row(container: VBoxContainer, conditions: Array, initial_condition_set: ConditionSet) -> void:
	var row := HBoxContainer.new()
	var current := [initial_condition_set]

	var picker := EditorResourcePicker.new()
	picker.base_type = "ConditionSet"
	picker.edited_resource = initial_condition_set
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.resource_changed.connect(func(resource: Resource) -> void:
		var new_value := resource as ConditionSet
		if current[0] != null:
			var index := conditions.find(current[0])
			if index != -1:
				if new_value == null:
					conditions.remove_at(index)
				else:
					conditions[index] = new_value
		elif new_value != null:
			conditions.append(new_value)
		current[0] = new_value
	)
	row.add_child(picker)

	var remove_button := Button.new()
	remove_button.text = "✕"
	remove_button.pressed.connect(func() -> void:
		if current[0] != null:
			conditions.erase(current[0])
		row.queue_free()
	)
	row.add_child(remove_button)

	container.add_child(row)


## target/threshold visibility follows dialogue_condition.gd's own
## field-meaning-by-type docstring: target is used by every type
## except CUSTOM. threshold is used only by FACTION_REPUTATION_AT_LEAST,
## ACTOR_ALIGNMENT_IS, HAS_SKILL_RANK_AT_LEAST, and HAS_ITEM.
func _add_inline_condition_row(container: VBoxContainer, conditions: Array, condition: DialogueCondition) -> void:
	var row := VBoxContainer.new()
	var top_line := HBoxContainer.new()

	var type_picker := OptionButton.new()
	for type_name in DialogueCondition.Type.keys():
		type_picker.add_item(type_name, DialogueCondition.Type[type_name])
	type_picker.select(type_picker.get_item_index(condition.type))
	top_line.add_child(type_picker)

	var remove_button := Button.new()
	remove_button.text = "✕"
	remove_button.pressed.connect(func() -> void:
		conditions.erase(condition)
		row.queue_free()
	)
	top_line.add_child(remove_button)
	row.add_child(top_line)

	var target_field := LineEdit.new()
	target_field.placeholder_text = "target"
	target_field.text = condition.target
	target_field.text_changed.connect(func(new_text: String) -> void:
		condition.target = new_text
	)
	row.add_child(target_field)

	var threshold_field := SpinBox.new()
	threshold_field.prefix = "threshold:"
	threshold_field.min_value = -9999   # placeholder bound, not a confirmed real range
	threshold_field.max_value = 9999
	threshold_field.step = 0.1
	threshold_field.value = condition.threshold
	threshold_field.value_changed.connect(func(new_value: float) -> void:
		condition.threshold = new_value
	)
	row.add_child(threshold_field)

	var script_picker := EditorResourcePicker.new()
	script_picker.base_type = "Script"
	script_picker.edited_resource = condition.custom_script
	script_picker.resource_changed.connect(func(resource: Resource) -> void:
		condition.custom_script = resource as Script
	)
	row.add_child(script_picker)

	_update_condition_row_visibility(condition.type, target_field, threshold_field, script_picker)

	type_picker.item_selected.connect(func(index: int) -> void:
		var new_type: int = type_picker.get_item_id(index)
		condition.type = new_type
		_update_condition_row_visibility(new_type, target_field, threshold_field, script_picker)
	)

	container.add_child(row)


func _update_condition_row_visibility(new_type: int, target_field: LineEdit, threshold_field: SpinBox, script_picker: EditorResourcePicker) -> void:
	target_field.visible = new_type != DialogueCondition.Type.CUSTOM
	threshold_field.visible = new_type in CONDITION_TYPES_USING_THRESHOLD
	script_picker.visible = new_type == DialogueCondition.Type.CUSTOM


# ---------------------------------------------------------------------------
# Connections
# ---------------------------------------------------------------------------

## Two passes: first every "normal" `next`-style outgoing wire (source
## stores target, exactly like before); then every condition-input
## wire, drawn from the referring choice's perspective since that's
## where condition_node_id actually lives (see file header on why this
## one field's data direction is reversed from everything else).
func _draw_connections(tree: DialogueTree) -> void:
	for node_id in tree.nodes:
		var node: DialogueGraphNode = tree.nodes[node_id]

		if node is DialogueLineNode:
			_connect_if_valid(tree, node_id, 0, node.next)

		elif node is DialogueStructureNode:
			for i in node.outputs.size():
				_connect_if_valid(tree, node_id, i, node.outputs[i])

		elif node is DialogueSkillCheckChoiceNode:
			_draw_skill_check_branch_connections(tree, node_id, node as DialogueSkillCheckChoiceNode)

		elif node is DialogueChoiceNode:
			_connect_if_valid(tree, node_id, 0, node.next)

		# DialogueConditionNode has no outgoing `next`-style field of
		# its own to walk here - see the second pass below.

	for node_id in tree.nodes:
		var node: DialogueGraphNode = tree.nodes[node_id]
		if node is DialogueChoiceNode and not node.condition_node_id.is_empty():
			if tree.nodes.has(node.condition_node_id):
				_graph_edit.connect_node(node.condition_node_id, 0, node_id, CONDITION_INPUT_PORT)
			else:
				push_warning("GraphTab: '%s' references missing condition_node_id '%s'" % [node_id, node.condition_node_id])


## Kept as its own function with an explicitly-typed `choice` parameter
## deliberately - inlining this into _draw_connections()'s loop (an
## earlier version of this function did) breaks `:=` type inference on
## get_critical_success_branch()/get_critical_failure_branch(): even
## inside an `if node is DialogueSkillCheckChoiceNode` branch, GDScript
## does not reliably narrow node's STATIC type for a `:=`-inferred
## method call - the call still resolves against node's DECLARED type
## (DialogueGraphNode), which doesn't have that method at all, so the
## result has no knowable type and `:=` fails to parse ("Cannot infer
## the type... doesn't have a set type"). A real parameter with an
## explicit type doesn't have this problem, since the type is settled
## at the call site (node as DialogueSkillCheckChoiceNode, in
## _draw_connections above), not inferred from an `is`-narrowed local.
##
## Branch port indices are 0-3 (Success/Failure/Critical Success/
## Critical Failure) - connect_node()'s port index is into the
## COMPACTED list of enabled ports on that side (see
## _build_skill_check_choice_node for the row layout this depends on).
## Unauthored critical branches route to wherever their fallback
## actually resolves, making the effective routing visible rather than
## a dead-end port.
func _draw_skill_check_branch_connections(tree: DialogueTree, node_id: String, choice: DialogueSkillCheckChoiceNode) -> void:
	_connect_if_valid(tree, node_id, 0, choice.success.next if choice.success != null else "")
	_connect_if_valid(tree, node_id, 1, choice.failure.next if choice.failure != null else "")

	var crit_success := choice.get_critical_success_branch()
	_connect_if_valid(tree, node_id, 2, crit_success.next if crit_success != null else "")

	var crit_failure := choice.get_critical_failure_branch()
	_connect_if_valid(tree, node_id, 3, crit_failure.next if crit_failure != null else "")


## Draws from_node_id/from_port -> to_node_id/0, unless to_node_id is
## empty (end of tree/Preset - no edge to draw, matches DialoguePlayer's
## own "empty next means exhausted" convention) or the target doesn't
## actually exist in this tree (missing-reference - mirrors the
## runtime's own push_warning-and-degrade-gracefully convention rather
## than crashing the render). Always targets to_port 0 - every node
## type's main input is port 0, regardless of type.
func _connect_if_valid(tree: DialogueTree, from_node_id: String, from_port: int, to_node_id: String) -> void:
	if to_node_id.is_empty():
		return
	if not tree.nodes.has(to_node_id):
		push_warning("GraphTab: '%s' references missing node_id '%s', skipping connection" % [from_node_id, to_node_id])
		return
	_graph_edit.connect_node(from_node_id, from_port, to_node_id, 0)
