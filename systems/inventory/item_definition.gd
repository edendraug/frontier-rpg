class_name ItemDefinition
extends RefCounted

## Represents one row from items.csv. Unlike Skill/Trait/Occupation definitions,
## items are NOT saved as individual .tres files -- the CSV is the single source
## of truth, parsed into these objects at load time by ItemRegistry. There is
## deliberately no per-item Resource file on disk.
##
## Food-specific fields (perishable, spoil_minutes, meal_type, nutrition,
## morale) live on FoodDefinition, a subtype ItemRegistry instantiates
## instead of this base class for FOOD-category rows -- see
## food_definition.gd. Every other category keeps using this class
## directly, and its schema stays exactly this small either way.

enum Category {
	FOOD,
	MEDICINE,
	AMMO,
	TRADE_GOODS,
	CRAFTING_MATERIAL,
	EQUIPMENT,
}

var item_id: String = ""
var display_name: String = ""
var category: Category = Category.FOOD
var weight: float = 0.0
var value: float = 0.0
var equippable: bool = false

## Item id of the ammo this piece of equipment consumes. Blank for anything
## that isn't a weapon. Direct item_id reference rather than an ammo_type enum --
## two weapons that share ammo just point at the same ammo item_id.
var required_ammo_id: String = ""

var description: String = ""


static func category_from_string(raw: String) -> Category:
	match raw.strip_edges().to_lower():
		"food":
			return Category.FOOD
		"medicine":
			return Category.MEDICINE
		"ammo":
			return Category.AMMO
		"trade_goods", "tradegoods", "trade goods":
			return Category.TRADE_GOODS
		"crafting_material", "craftingmaterial", "crafting material":
			return Category.CRAFTING_MATERIAL
		"equipment":
			return Category.EQUIPMENT
		_:
			push_warning("ItemDefinition: unrecognized category '%s', defaulting to FOOD" % raw)
			return Category.FOOD


static func category_to_string(category: Category) -> String:
	match category:
		Category.FOOD:
			return "Food"
		Category.MEDICINE:
			return "Medicine"
		Category.AMMO:
			return "Ammo"
		Category.TRADE_GOODS:
			return "Trade Goods"
		Category.CRAFTING_MATERIAL:
			return "Crafting Material"
		Category.EQUIPMENT:
			return "Equipment"
		_:
			return "Unknown"
