@tool
extends Control

## Root content of the Dialogue Graph Editor's main-screen tab. Hosts a
## TabContainer: a permanent "Actors" tab, with graph tabs (opened,
## created, and closed dynamically) alongside it. Sidebar (node
## palette + Preset list) as its own persistent panel, per the original
## design doc, hasn't been built - the node-add palette that exists
## lives per-tab inside GraphTab's own toolbar instead, which covers
## the same need without the larger MainPanel layout change a real
## sidebar would need.
##
## Built as plain script-constructed Controls throughout, no .tscn
## files - Cameron has no Godot editor-plugin experience to lean on
## for hand-editing scenes yet, so everything here is scriptable and
## diffable in chat. A later .tscn-based refactor is explicitly fine
## if that stops being the right call.

const ActorFormTabScript := preload("res://addons/dialogue_graph_editor/actor_form/actor_form_tab.gd")
const GraphTabScript := preload("res://addons/dialogue_graph_editor/canvas/graph_tab.gd")

var _tabs: TabContainer
var _open_graph_tabs: Dictionary = {}   # tree_id -> GraphTab, for tabs already open this session


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	_tabs = TabContainer.new()
	_tabs.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_tabs)

	var actor_form := ActorFormTabScript.new()
	actor_form.name = "Actors"
	actor_form.open_tree_requested.connect(_open_tree_tab)
	actor_form.create_tree_requested.connect(_create_tree_tab)
	_tabs.add_child(actor_form)


## Opens a graph tab for `tree_id` (creating it if not already open
## this session, otherwise just switching to the existing one - never
## opens the same tree twice). Only opens an EXISTING tree/preset;
## _create_tree_tab below handles the "doesn't exist yet" case.
##
## Failure (tree_id not found in either registry) currently only
## surfaces as a push_warning from GraphTab.load_tree() - no in-UI
## error message yet. Flagged as a known gap, not an oversight.
func _open_tree_tab(tree_id: String) -> void:
	if tree_id.is_empty():
		return

	if _open_graph_tabs.has(tree_id):
		_tabs.current_tab = _open_graph_tabs[tree_id].get_index()
		return

	# Fresh registry per open request rather than a cached shared
	# instance - DialogueTreeRegistry's own DirAccess scan is cheap at
	# this project's current content scale, and this guarantees a
	# tree saved/renamed since the plugin loaded is always picked up,
	# without needing a separate "rescan" mechanism for trees yet.
	var registry := DialogueTreeRegistry.new()
	_load_and_open_graph_tab(tree_id, registry)


## Constructs a brand-new, empty DialogueTree, saves it to
## res://systems/dialogue/data/trees/<tree_id>.tres, then opens it the
## same way any OTHER tree gets opened - through a fresh
## DialogueTreeRegistry scan, not a special "just use this in-memory
## object directly" shortcut, so a newly-created tree is discovered
## exactly like any already-saved one, with no divergent code path to
## keep in sync later. Warns (rather than overwriting) if a tree
## already exists on disk at that id, and opens the existing one
## instead.
##
## Only creates a regular tree (TREE_DIR), not a Preset (PRESET_DIR) -
## Preset creation isn't wired up from anywhere in the UI yet, matching
## how Preset AUTHORING generally (per Cameron's own steer earlier)
## is deliberately being left for later, quality-of-life work.
func _create_tree_tab(tree_id: String) -> void:
	if tree_id.is_empty():
		return

	if _open_graph_tabs.has(tree_id):
		_tabs.current_tab = _open_graph_tabs[tree_id].get_index()
		return

	var tree_path := "res://systems/dialogue/data/trees/%s.tres" % tree_id
	if FileAccess.file_exists(tree_path):
		push_warning("MainPanel: a tree already exists on disk at '%s' - opening it instead of overwriting" % tree_path)
		_open_tree_tab(tree_id)
		return

	var new_tree := DialogueTree.new()
	new_tree.tree_id = tree_id
	new_tree.start_node_id = ""
	new_tree.nodes = {}
	var err := ResourceSaver.save(new_tree, tree_path)
	if err != OK:
		push_warning("MainPanel: failed to save new tree '%s' (error %d)" % [tree_id, err])
		return
	EditorInterface.get_resource_filesystem().scan()

	var registry := DialogueTreeRegistry.new()
	_load_and_open_graph_tab(tree_id, registry)


## Shared by _open_tree_tab (an existing tree) and _create_tree_tab
## (one just saved to disk) - both need the exact same "build the tab,
## add it live, wire close_requested, load, track" sequence.
func _load_and_open_graph_tab(tree_id: String, registry: DialogueTreeRegistry) -> void:
	var graph_tab := GraphTabScript.new()
	graph_tab.name = tree_id
	graph_tab.close_requested.connect(_on_graph_tab_close_requested)
	# Added to the live tree BEFORE load_tree() runs - GraphEdit's own
	# internal setup (the connections-drawing layer, among others) only
	# happens once it's genuinely part of the scene tree, and
	# load_tree() calls connect_node() on it. Building first and adding
	# second (an earlier version of this function did that) produced
	# "connections_layer is missing" errors, since GraphEdit was still
	# sitting outside the live tree while being asked to draw
	# connections.
	_tabs.add_child(graph_tab)

	if not graph_tab.load_tree(tree_id, registry):
		graph_tab.queue_free()
		return

	_open_graph_tabs[tree_id] = graph_tab
	_tabs.current_tab = graph_tab.get_index()


## Undoes _load_and_open_graph_tab's tracking - MainPanel owns
## _open_graph_tabs/_tabs, which GraphTab has no reference to itself,
## so it just emits close_requested and leaves the actual removal to
## here. remove_child() before queue_free(), matching the same
## ordering GraphTab's own node-rebuild cleanup uses and for the same
## reason (queue_free() alone leaves the node attached - and its name
## still claimed - until end of frame; not an issue for a single tab
## being closed once, but cheap and consistent to do it the same way
## regardless).
func _on_graph_tab_close_requested(closed_tree_id: String) -> void:
	if not _open_graph_tabs.has(closed_tree_id):
		return
	var graph_tab: Control = _open_graph_tabs[closed_tree_id]
	_open_graph_tabs.erase(closed_tree_id)
	_tabs.remove_child(graph_tab)
	graph_tab.queue_free()
