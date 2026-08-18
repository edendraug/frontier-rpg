@tool
extends EditorScript

## Run this ONCE from the Script Editor (File > Run, or Ctrl+Shift+X)
## to generate a starter set of Skill / Trait / Occupation .tres files.
## Safe to re-run — it overwrites existing files with the same ids.
##
## Adjust the path constants below if your reorganized project
## structure differs from the recommended systems/character/... layout.
##
## Occupations' starting_gear now uses ItemStack instead of loose
## Dictionaries -- OccupationDefinition.starting_gear's type changed
## to Array[ItemStack] once Inventory/Party Creator needed to
## seed real items. Several gear item_ids referenced below
## (hammer, iron_ingot, medical_kit, herbs, trap, bible, robes,
## ledger, spectacles) need rows added to your items.csv -- see
## items_to_append.csv alongside this file.
##
## ModifierEntry.target (String) became ModifierEntry.targets
## (Array[String]) this pass -- re-running this script regenerates
## every trait .tres with the new field populated. Existing trait
## .tres files on disk from before this change still reference the
## old `target` field name; Godot will silently drop it on load
## (empty targets = the entry never matches anything) rather than
## error, so this script MUST be re-run before traits work again.

const SKILL_DIR := "res://systems/character/data/skills/"
const TRAIT_DIR := "res://systems/character/data/traits/"
const OCCUPATION_DIR := "res://systems/character/data/occupations/"
const STAT_PRESET_DIR := "res://systems/character/data/stat_presets/"


func _run() -> void:
	_ensure_dir(SKILL_DIR)
	_ensure_dir(TRAIT_DIR)
	_ensure_dir(OCCUPATION_DIR)
	_ensure_dir(STAT_PRESET_DIR)

	_generate_skills()
	_generate_traits()
	_generate_occupations()
	_generate_stat_presets()

	print("Sample character data generated: 15 skills, 5 traits, 5 occupations (with gear/money), 3 stat presets.")


func _ensure_dir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path)


## ============================================================
## SKILLS — 3 per active stat, Grit intentionally has none.
## ============================================================
func _make_skill(id: String, name: String, desc: String, stat: CharacterSheet.Stat) -> void:
	var s := SkillDefinition.new()
	s.skill_id = id
	s.display_name = name
	s.description = desc
	s.governing_stat = stat
	ResourceSaver.save(s, SKILL_DIR + id + ".tres")


func _generate_skills() -> void:
	_make_skill("melee_combat", "Melee Combat", "Fighting with fists, blades, and clubs at close range.", CharacterSheet.Stat.BRAWN)
	_make_skill("labor", "Labor", "Hauling, lifting, and heavy physical work — wagon repair, digging, chopping.", CharacterSheet.Stat.BRAWN)
	_make_skill("athletics", "Athletics", "Climbing, swimming, and general physical exertion.", CharacterSheet.Stat.BRAWN)

	_make_skill("marksmanship", "Marksmanship", "Accuracy with rifles, pistols, and thrown weapons.", CharacterSheet.Stat.AGILITY)
	_make_skill("stealth", "Stealth", "Moving unseen and unheard.", CharacterSheet.Stat.AGILITY)
	_make_skill("driving", "Driving", "Handling a wagon team, especially over rough or dangerous terrain.", CharacterSheet.Stat.AGILITY)

	_make_skill("perception", "Perception", "Spotting danger, tracks, and details others miss.", CharacterSheet.Stat.WITS)
	_make_skill("tracking", "Tracking", "Following trails and reading signs left by people and animals.", CharacterSheet.Stat.WITS)
	_make_skill("survival", "Survival", "Foraging, reading weather, and instinctive wilderness know-how.", CharacterSheet.Stat.WITS)

	_make_skill("medicine", "Medicine", "Diagnosing and treating injuries and disease.", CharacterSheet.Stat.KNOWLEDGE)
	_make_skill("craft", "Craft", "Repair, cooking, and building from trained know-how.", CharacterSheet.Stat.KNOWLEDGE)
	_make_skill("navigation", "Navigation", "Reading maps, stars, and terrain to plot a safe course.", CharacterSheet.Stat.KNOWLEDGE)

	_make_skill("persuasion", "Persuasion", "Convincing others honestly, through reason or charm.", CharacterSheet.Stat.PRESENCE)
	_make_skill("deception", "Deception", "Lying convincingly, and reading through others' lies.", CharacterSheet.Stat.PRESENCE)
	_make_skill("command", "Command", "Rallying morale and directing others under pressure.", CharacterSheet.Stat.PRESENCE)


## ============================================================
## TRAITS — deliberately a mix of positive and negative.
## ============================================================
## Single-target convenience wrapper -- the overwhelming majority of
## authored modifiers only ever need one target, so this keeps every
## existing call site below unchanged even though ModifierEntry.target
## became ModifierEntry.targets (Array[String]).
func _make_modifier(target: String, value: float, source_label: String) -> ModifierEntry:
	return _make_modifier_multi([target], value, source_label)


## For the genuinely-multi-target case -- one conceptual penalty
## (same type/value/source_label) that's relevant in more than one
## place, e.g. a future "Broken Hand" injury suppressing both
## "skill:craft" and "skill:marksmanship" as a single ModifierEntry
## rather than two near-duplicate ones. Nothing in this file's sample
## Traits currently needs this (none of them are multi-target), but
## Injury/Disease authoring (debug tools, or future data-driven
## content) will.
func _make_modifier_multi(targets: Array[String], value: float, source_label: String) -> ModifierEntry:
	var m := ModifierEntry.new()
	m.targets = targets
	m.value = value
	m.type = ModifierEntry.Type.ADDITIVE
	m.source_label = source_label
	return m


func _make_trait(id: String, name: String, desc: String, modifiers: Array[ModifierEntry]) -> void:
	var t := TraitDefinition.new()
	t.trait_id = id
	t.display_name = name
	t.description = desc
	t.modifiers = modifiers
	ResourceSaver.save(t, TRAIT_DIR + id + ".tres")


func _generate_traits() -> void:
	_make_trait(
		"natural_hunter", "Natural Hunter",
		"Raised tracking game and living off the land. Sharper instincts in the wild.",
		[
			_make_modifier(ModifierResolver.target_for_skill("tracking"), 2, "Natural Hunter"),
			_make_modifier(ModifierResolver.target_for_skill("marksmanship"), 1, "Natural Hunter"),
		]
	)
	_make_trait(
		"steady_hands", "Steady Hands",
		"Years at the forge or workbench have made for precise, patient work.",
		[_make_modifier(ModifierResolver.target_for_skill("craft"), 2, "Steady Hands")]
	)
	_make_trait(
		"formally_trained", "Formally Trained",
		"Educated in proper medical practice, not just field remedies.",
		[_make_modifier(ModifierResolver.target_for_skill("medicine"), 2, "Formally Trained")]
	)
	_make_trait(
		"silver_tongue", "Silver Tongue",
		"A natural, practiced way of winning people over.",
		[_make_modifier(ModifierResolver.target_for_skill("persuasion"), 2, "Silver Tongue")]
	)
	_make_trait(
		"green_horn", "Green Horn",
		"Raised in the city, more comfortable with ledgers than wilderness. Struggles to read the land.",
		[
			_make_modifier(ModifierResolver.target_for_skill("tracking"), -1, "Green Horn"),
			_make_modifier(ModifierResolver.target_for_skill("survival"), -1, "Green Horn"),
		]
	)


## ============================================================
## OCCUPATIONS — each grants a stat trade-off, a trait, starting
## gear, and starting money.
##
## Gear/money are placeholder values, same "tune freely" treatment as
## everything else marked that way in this project. Seeded into the
## PARTY inventory ONCE, and only from the MAIN character's Occupation
## — see PartyManager.begin_expedition(). Every character (main or
## NPC) still gets stat_modifiers and granted_trait_id normally;
## gear/money are the one main-character-only exception.
## ============================================================
func _make_item_stack(item_id: String, quantity: int) -> ItemStack:
	return ItemStack.new(item_id, quantity)


func _make_occupation(
	id: String, name: String, desc: String, stat_mods: Dictionary,
	trait_id: String, gear: Array[ItemStack], starting_money: int
) -> void:
	var o := OccupationDefinition.new()
	o.occupation_id = id
	o.display_name = name
	o.description = desc
	o.stat_modifiers = stat_mods
	o.granted_trait_id = trait_id
	o.starting_gear = gear
	o.starting_money = starting_money
	ResourceSaver.save(o, OCCUPATION_DIR + id + ".tres")


func _generate_occupations() -> void:
	_make_occupation(
		"blacksmith", "Blacksmith",
		"Forged tools and shod horses back home. Strong-armed and steady, if a little slow on their feet.",
		{CharacterSheet.Stat.BRAWN: 2, CharacterSheet.Stat.AGILITY: -1},
		"steady_hands",
		[_make_item_stack("hammer", 1), _make_item_stack("iron_ingot", 3)],
		40
	)
	_make_occupation(
		"physician", "Physician",
		"Trained in proper medicine back east. Book-smart, but no laborer.",
		{CharacterSheet.Stat.KNOWLEDGE: 2, CharacterSheet.Stat.BRAWN: -1},
		"formally_trained",
		[_make_item_stack("medical_kit", 1), _make_item_stack("herbs", 2), _make_item_stack("bandages", 3)],
		60
	)
	_make_occupation(
		"trapper", "Trapper",
		"Spent years alone in the wild, living by trap-lines and instinct.",
		{CharacterSheet.Stat.WITS: 2, CharacterSheet.Stat.PRESENCE: -1},
		"natural_hunter",
		[_make_item_stack("rifle", 1), _make_item_stack("rifle_ammo", 20), _make_item_stack("trap", 3)],
		25
	)
	_make_occupation(
		"preacher", "Preacher",
		"Led a congregation back home. Knows how to hold a room's attention.",
		{CharacterSheet.Stat.PRESENCE: 2, CharacterSheet.Stat.BRAWN: -1},
		"silver_tongue",
		[_make_item_stack("bible", 1), _make_item_stack("robes", 1)],
		30
	)
	_make_occupation(
		"clerk", "Clerk",
		"Kept the books at a trading post. Sharp with numbers, hopeless in the wilderness.",
		{CharacterSheet.Stat.KNOWLEDGE: 1, CharacterSheet.Stat.GRIT: -1},
		"green_horn",
		[_make_item_stack("ledger", 1), _make_item_stack("spectacles", 1)],
		50
	)


## ============================================================
## STAT PRESETS — shortcuts for point buy, not a separate system.
## Placeholder numbers, roughly point-buy-comparable — tune freely.
## ============================================================
func _make_stat_preset(id: String, name: String, desc: String, scores: Dictionary) -> void:
	var p := StatSpreadPreset.new()
	p.preset_id = id
	p.display_name = name
	p.description = desc
	p.scores = scores
	ResourceSaver.save(p, STAT_PRESET_DIR + id + ".tres")


func _generate_stat_presets() -> void:
	_make_stat_preset(
		"balanced", "Balanced",
		"No real weaknesses, no real specialty. A safe, flexible starting point.",
		{"brawn": 11, "agility": 11, "grit": 12, "wits": 11, "knowledge": 11, "presence": 12}
	)
	_make_stat_preset(
		"brawler", "Brawler",
		"Strong and tough, but not much of a thinker or a talker.",
		{"brawn": 16, "agility": 12, "grit": 14, "wits": 9, "knowledge": 8, "presence": 9}
	)
	_make_stat_preset(
		"scholar", "Scholar",
		"Educated and perceptive, but physically unremarkable.",
		{"brawn": 8, "agility": 9, "grit": 10, "wits": 14, "knowledge": 16, "presence": 12}
	)
