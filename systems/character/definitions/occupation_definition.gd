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

## Starting gear seeded into the PARTY inventory, not carried by
## the character individually. Left as a loose array of
## dictionaries until the Inventory & Resource System defines a
## proper item id/format.
## e.g. [{"item_id": "hammer", "quantity": 1}]
@export var starting_gear: Array = []


## Applies this occupation's stat bonuses and grants its trait to
## the given sheet, and records the occupation reference. Does NOT
## touch the party inventory — the caller is responsible for handing
## starting_gear off once that system exists.
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
