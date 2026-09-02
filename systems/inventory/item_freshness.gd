class_name ItemFreshness
extends RefCounted

## Pure computation, no state. Spoilage is never stored as a flag on a batch --
## freshness, spoiled/fresh state, effective weight, and display name are all
## derived on read from acquired_minute + spoil_minutes vs. the current clock.
## Same reasoning as Condition/Morale on CharacterSheet: derived, not stored.
##
## Every function below takes a plain ItemDefinition and checks
## `is FoodDefinition` internally, rather than being retyped to demand
## FoodDefinition directly. perishable/spoil_minutes now live only on
## FoodDefinition (see food_definition.gd), but every existing caller
## (InventorySystem, expedition_hub.gd) already holds whatever
## ItemRegistry.get_item() returns, statically typed ItemDefinition --
## checking internally means none of those callers need to change. A
## non-food item now simply, correctly, always reports Fresh/never-spoiled,
## exactly how it already behaved before FoodDefinition existed.

## Once a batch hits 0% freshness, its effective weight drops to half the
## fresh weight -- authored directly as this constant rather than a per-item
## CSV column, since it's a flat rule rather than per-item content.
const SPOILED_WEIGHT_MULTIPLIER := 0.5

## Freshness at or below this fraction, but still above 0%, is "Spoiling"
## rather than "Fresh" -- see FreshnessTier and the design doc, Section 3.2.
## Same flat-rule reasoning as SPOILED_WEIGHT_MULTIPLIER above: a game rule,
## not per-item content, so it lives here rather than in a CSV column.
const SPOILING_THRESHOLD := 0.3

enum FreshnessTier { FRESH, SPOILING, SPOILED }


## Returns 0.0 (fully spoiled) to 1.0 (freshly acquired). Non-food items,
## and food items that aren't marked perishable (or have no spoil_minutes
## set), are always fully fresh.
static func get_freshness(batch: InventoryBatch, item: ItemDefinition, current_minute: int) -> float:
	if not (item is FoodDefinition):
		return 1.0
	var food := item as FoodDefinition
	if not food.perishable or food.spoil_minutes <= 0:
		return 1.0
	var elapsed := current_minute - batch.acquired_minute
	var remaining := food.spoil_minutes - elapsed
	return clampf(float(remaining) / float(food.spoil_minutes), 0.0, 1.0)


## The hard 0% cutoff. This is the only point where spoilage changes
## weight/label (below) -- there is no gradual transition for those two,
## only the freshness bar and FreshnessTier (below) are graduated.
static func is_spoiled(batch: InventoryBatch, item: ItemDefinition, current_minute: int) -> bool:
	if not (item is FoodDefinition):
		return false
	var food := item as FoodDefinition
	return food.perishable and get_freshness(batch, item, current_minute) <= 0.0


## Fresh (>SPOILING_THRESHOLD), Spoiling (>0%, <=SPOILING_THRESHOLD), or
## Spoiled (0%) -- see design doc Section 3.2/5.2. Non-food items are
## always FRESH, same permissive default as get_freshness()/is_spoiled()
## above.
static func get_freshness_tier(batch: InventoryBatch, item: ItemDefinition, current_minute: int) -> FreshnessTier:
	var freshness := get_freshness(batch, item, current_minute)
	if freshness <= 0.0:
		return FreshnessTier.SPOILED
	elif freshness <= SPOILING_THRESHOLD:
		return FreshnessTier.SPOILING
	else:
		return FreshnessTier.FRESH


static func get_effective_weight(batch: InventoryBatch, item: ItemDefinition, current_minute: int) -> float:
	var base_weight := item.weight * batch.quantity
	if is_spoiled(batch, item, current_minute):
		return base_weight * SPOILED_WEIGHT_MULTIPLIER
	return base_weight


## "Spoiled " prefix only -- there is no separate "Spoiled Jerky" CSV row,
## this is purely a presentation-layer relabel of the same item_id.
static func get_display_name(batch: InventoryBatch, item: ItemDefinition, current_minute: int) -> String:
	if is_spoiled(batch, item, current_minute):
		return "Spoiled " + item.display_name
	return item.display_name
