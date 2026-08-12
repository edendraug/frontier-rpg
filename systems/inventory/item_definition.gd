class_name ItemDefinition
extends RefCounted

## Represents one row from items.csv. Unlike Skill/Trait/Occupation definitions,
## items are NOT saved as individual .tres files -- the CSV is the single source
## of truth, parsed into these objects at load time by ItemRegistry. There is
## deliberately no per-item Resource file on disk.

enum Category {
	FOOD,
	MEDICINE,
	AMMO,
	TRADE_GOODS,
	CRAFTING_MATERIAL,
	EQUIPMENT,
}

enum MealType {
	NONE,
	TRAIL_FOOD,
	CAMP_MEAL,
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

## Perishable food fields. Ignored/blank for every other category.
var perishable: bool = false
## Converted from the CSV's spoil_days column at load time -- authored in days
## for human readability, stored in minutes since TimeSystem's clock is
## minute-resolution and spoilage is tracked at that same precision.
var spoil_minutes: int = 0

var meal_type: MealType = MealType.NONE
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


static func meal_type_from_string(raw: String) -> MealType:
	match raw.strip_edges().to_lower():
		"trail_food", "trailfood", "trail food":
			return MealType.TRAIL_FOOD
		"camp_meal", "campmeal", "camp meal":
			return MealType.CAMP_MEAL
		_:
			return MealType.NONE


static func meal_type_to_string(meal_type: MealType) -> String:
	match meal_type:
		MealType.TRAIL_FOOD:
			return "Trail Food"
		MealType.CAMP_MEAL:
			return "Camp Meal"
		_:
			return ""
