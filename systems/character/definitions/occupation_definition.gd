class_name OccupationDefinition
extends Resource

## Defines an Occupation — the merged Background+Profession concept.
## Meant to be authored as a .tres data file per occupation
## (e.g. blacksmith.tres, trapper.tres).
##
## Applied ONCE, at character creation, via apply_to() below. This
## Resource never reaches into a CharacterSheet on its own — the
## caller (e.g. the character creator) decides when that happens.

@export var occupation_id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""

## Flat bonuses/penalties applied to base stat scores at creation.
## Keyed by CharacterSheet.Stat, e.g. {CharacterSheet.Stat.BRAWN: 2}
@export var stat_modifiers: Dictionary = {}

## The single starting Trait granted at creation, referencing a
## TraitDefinition's trait_id. Leave empty for no granted trait.
@export var granted_trait_id: String = ""

## Starting gear seeded into the PARTY inventory, not carried by the
## character individually. Formalized now that the Inventory System
## exists — ItemStack (item_id + quantity) replaces the earlier loose
## Array[Dictionary] placeholder.
##
## Per Party Creator design: only the party's MAIN character's gear
## gets seeded, even though every character (main or NPC) still gets
## this Occupation's stat_modifiers and granted_trait_id normally.
## That distinction is enforced by the caller (PartyManager), not
## here — apply_to() below still only touches stats/traits and never
## reaches into Inventory, same as before this change.
@export var starting_gear: Array[ItemStack] = []

## Starting funds. Same "party inventory, not per-character" and
## "main character only" rules as starting_gear above.
@export var starting_money: int = 0


## Applies this occupation's stat bonuses and grants its trait to
## the given sheet, and records the occupation reference. Does NOT
## touch the party inventory or money — the caller (PartyManager) is
## responsible for seeding starting_gear/starting_money, and only
## for the main character.
func apply_to(sheet: CharacterSheet, day_acquired: int = 0) -> void:
	_apply_stat_modifiers(sheet)
	_grant_starting_trait(sheet, day_acquired)
	sheet.occupation_id = occupation_id


func _apply_stat_modifiers(sheet: CharacterSheet) -> void:
	for stat in stat_modifiers.keys():
		var bonus: int = stat_modifiers[stat]
		match stat:
			CharacterSheet.Stat.BRAWN:
				sheet.brawn += bonus
			CharacterSheet.Stat.AGILITY:
				sheet.agility += bonus
			CharacterSheet.Stat.GRIT:
				sheet.grit += bonus
			CharacterSheet.Stat.WITS:
				sheet.wits += bonus
			CharacterSheet.Stat.KNOWLEDGE:
				sheet.knowledge += bonus
			CharacterSheet.Stat.PRESENCE:
				sheet.presence += bonus


func _grant_starting_trait(sheet: CharacterSheet, day_acquired: int) -> void:
	if granted_trait_id == "":
		return
	var t := TraitInstance.new()
	t.trait_id = granted_trait_id
	t.source = TraitInstance.Source.INNATE
	t.day_acquired = day_acquired
	sheet.traits.append(t)
