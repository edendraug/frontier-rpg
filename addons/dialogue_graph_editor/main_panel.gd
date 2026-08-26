@tool
extends Control

## Root content of the Dialogue Graph Editor's main-screen tab. Hosts a
## TabContainer: a permanent "Actors" tab (Stage 3), with graph tabs
## (DialogueTree/Preset canvases, Stage 4) opened dynamically alongside
## it as trees are requested. Sidebar (node palette + Preset list)
## arrives in Stage 7 - until then this tab container is the entire
## main panel.
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
	_tabs.add_child(actor_form)


## Opens a graph tab for `tree_id` (creating it if not already open
## this session, otherwise just switching to the existing one - never
## opens the same tree twice). Currently only OPENS an existing tree;
## there's no "create a new, empty tree" path yet, since that needs
## real save support on the canvas (Stage 6+), which doesn't exist
## yet either - GDD Section 3.3's "create tree from Actor form" entry
## point is only half-wired until then.
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

	var graph_tab := GraphTabScript.new()
	graph_tab.name = tree_id
	# Added to the live tree BEFORE load_tree() runs - GraphEdit's own
	# internal setup (the connections-drawing layer, among others) only
	# happens once it's genuinely part of the scene tree, and
	# load_tree() calls connect_node() on it. Building first and adding
	# second (the original order here) produced "connections_layer is
	# missing" errors, since GraphEdit was still sitting outside the
	# live tree while being asked to draw connections.
	_tabs.add_child(graph_tab)

	if not graph_tab.load_tree(tree_id, registry):
		graph_tab.queue_free()
		return

	_open_graph_tabs[tree_id] = graph_tab
	_tabs.current_tab = graph_tab.get_index()
