extends Node

## Autoload. Swaps which local scene (a .tscn built on LocalSceneRoot)
## is currently loaded into Expedition Hub's content SubViewport --
## WITHOUT ever calling get_tree().change_scene_to_file(), which
## replaces the entire current tree, UI included. That's exactly what
## this exists to avoid: the persistent-shell/swappable-content split
## Cameron asked for, so Expedition Hub's UI stays loaded and
## interactable while different local scenes get swapped in and out
## underneath it.
##
## Finds its target viewport via the "local_scene_content_viewport"
## group (see that node's own tiny script) rather than a hardcoded
## path or a direct reference pushed in from expedition_hub.gd --
## looked up fresh on every call rather than cached, since this
## autoload exists from game start, long before Expedition Hub itself
## is ever loaded (Main Menu -> Party Creator -> Begin Expedition).
##
## Registration: add as an Autoload in Project Settings. Order
## relative to other autoloads doesn't matter -- load_local_scene()
## only ever runs during actual gameplay, long after every autoload's
## own _ready() has already completed, same reasoning already used
## for TravelSystem's position in the autoload list.

const CONTENT_VIEWPORT_GROUP := "local_scene_content_viewport"

## Fired by the content viewport's own marker script the moment it
## enters the tree -- lets a caller that tried to load a scene BEFORE
## Expedition Hub existed (e.g. ExpeditionSceneRouter.boot_new_expedition()/
## restore_from_save(), both of which can run from a Party Creator or
## Main Menu screen, before any scene transition into Expedition Hub
## has happened) retry once there's actually somewhere to load into,
## rather than the request just silently failing. See
## local_scene_content_viewport.gd's own comment for where this is
## emitted from.
signal content_viewport_ready

var _current_scene_node: Node


## Frees whatever local scene is currently loaded (if any) and
## instances a new one in its place. `party_members` is passed
## straight through to the new scene's LocalSceneRoot.configure() if
## it has one -- empty means "spawn the whole current roster," same
## default LocalSceneRoot itself already applies. Returns false
## (with a push_warning) if there's no content viewport to load into
## (Expedition Hub isn't currently loaded) or the scene fails to load.
func load_local_scene(scene_path: String, party_members: Array[CharacterSheet] = []) -> bool:
	var viewport := _find_content_viewport()
	if viewport == null:
		push_warning("LocalSceneManager: no content viewport found -- is Expedition Hub loaded?")
		return false

	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_warning("LocalSceneManager: couldn't load '%s'" % scene_path)
		return false

	unload_current_scene()

	var instance := packed.instantiate()
	if instance is LocalSceneRoot:
		instance.configure(party_members)
	viewport.add_child(instance)
	_current_scene_node = instance
	return true


func unload_current_scene() -> void:
	if _current_scene_node != null:
		_current_scene_node.queue_free()
		_current_scene_node = null


func has_scene_loaded() -> bool:
	return _current_scene_node != null


## Called by the content viewport's own marker script from its
## _ready() -- see content_viewport_ready's own comment above.
func notify_content_viewport_ready() -> void:
	content_viewport_ready.emit()


func _find_content_viewport() -> SubViewport:
	return get_tree().get_first_node_in_group(CONTENT_VIEWPORT_GROUP)
