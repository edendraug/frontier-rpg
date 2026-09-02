class_name FoodDefinition
extends ItemDefinition

## Food-specific fields, split out of the base ItemDefinition so every
## non-food item's schema stays as small as it already is. Instantiated by
## ItemRegistry instead of ItemDefinition for any row whose category is
## FOOD; base fields (item_id, display_name, weight, ...) still come from
## items.csv as normal, food fields below come from a second pass over
## food_definitions.csv, matched by item_id. See
## Frontier_RPG_Food_Consumption_Design_Doc.md, Sections 4.1-4.3.

enum MealType {
	NONE,
	TRAIL_FOOD,
	CAMP_MEAL,
}

## Hunger points restored when Fresh, same 0-100 scale as
## CharacterSheet.hunger. Reduced at lower freshness tiers -- see
## ItemFreshness.FreshnessTier and VitalsSystem.feed_character().
var nutrition_value: float = 0.0

## Magnitude passed to VitalsSystem.apply_morale_event() when Fresh. Can be
## zero (Jerky: filling, unremarkable) or meaningfully positive (a proper
## camp meal, or something like chocolate that's mostly morale and little
## nutrition) -- the two values are deliberately independent.
var morale_value: float = 0.0
var morale_decay_per_hour: float = 0.0

## Perishable food fields, moved here from the base ItemDefinition.
var perishable: bool = false
## Converted from food_definitions.csv's spoil_days column at load time --
## authored in days for human readability, stored in minutes since
## TimeSystem's clock is minute-resolution and spoilage is tracked at that
## same precision.
var spoil_minutes: int = 0

var meal_type: MealType = MealType.NONE


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


## True unless this is a Camp Meal and the party isn't camped. Consulted
## both by UI (to gray a feed button before any attempt is made) and by
## VitalsSystem.feed_character() itself (to actually enforce it) -- one
## rule, defined once, checked from both places. See design doc Section 3.3.
func is_edible_now(is_at_camp: bool) -> bool:
	return meal_type != MealType.CAMP_MEAL or is_at_camp
