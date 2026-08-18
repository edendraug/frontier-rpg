class_name DialogueTreeRegistry
extends RefCounted

## Loads every authored DialogueTree .tres file into two id-keyed
## dictionaries - one for Actor-owned trees, one for actor-agnostic
## Presets (Section 4.9) - mirroring CharacterDataRegistry's DirAccess
## scan pattern exactly. Both key on DialogueTree.tree_id; a Preset's
## "preset id" (referenced by a START_PRESET effect's target) IS its
## tree_id, just discovered from a separate folder and never reached
## through an Actor's dialogue_tree_id.
##
## Instantiated once and passed explicitly to whatever builds a
## DialoguePlayer - same pattern CharacterDataRegistry already uses
## (constructed once, handed into SkillCheck's constructor) rather than
## a second autoload singleton.

const TREE_DIR := "res://systems/dialogue/data/trees/"
const PRESET_DIR := "res://systems/dialogue/data/presets/"

var trees: Dictionary = {}    # tree_id -> DialogueTree
var presets: Dictionary = {}  # preset_id (== tree_id) -> DialogueTree


func _init() -> void:
	_load_all(TREE_DIR, trees)
	_load_all(PRESET_DIR, presets)


func _load_all(dir_path: String, into: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("DialogueTreeRegistry: could not open %s" % dir_path)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var res: Resource = load(dir_path + file_name)
			if res is DialogueTree:
				into[res.tree_id] = res
			else:
				push_warning("DialogueTreeRegistry: '%s' is not a DialogueTree, skipping" % file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
