class_name CharacterDataRegistry
extends RefCounted

## Loads every authored Skill / Trait / Occupation .tres file into
## simple id-keyed dictionaries, so other systems (the character
## creator, dialogue checks, UI, etc.) can look definitions up by id
## without each reimplementing its own file-scanning logic.
##
## Usage: var registry := CharacterDataRegistry.new()
##        registry.skills["medicine"] -> SkillDefinition
##
## Adjust the path constants if your project structure differs from
## the recommended systems/character/data/... layout.

const SKILL_DIR := "res://systems/character/data/skills/"
const TRAIT_DIR := "res://systems/character/data/traits/"
const OCCUPATION_DIR := "res://systems/character/data/occupations/"
const STAT_PRESET_DIR := "res://systems/character/data/stat_presets/"

var skills: Dictionary = {}       # skill_id -> SkillDefinition
var traits: Dictionary = {}       # trait_id -> TraitDefinition
var occupations: Dictionary = {}  # occupation_id -> OccupationDefinition
var stat_presets: Dictionary = {} # preset_id -> StatSpreadPreset


func _init() -> void:
	_load_all(SKILL_DIR, skills)
	_load_all(TRAIT_DIR, traits)
	_load_all(OCCUPATION_DIR, occupations)
	_load_all(STAT_PRESET_DIR, stat_presets)


func _load_all(dir_path: String, into: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("CharacterDataRegistry: could not open %s" % dir_path)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var res: Resource = load(dir_path + file_name)
			if res is SkillDefinition:
				into[res.skill_id] = res
			elif res is TraitDefinition:
				into[res.trait_id] = res
			elif res is OccupationDefinition:
				into[res.occupation_id] = res
			elif res is StatSpreadPreset:
				into[res.preset_id] = res
		file_name = dir.get_next()
	dir.list_dir_end()
