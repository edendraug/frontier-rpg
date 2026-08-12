class_name ItemFreshness
extends RefCounted

## Pure computation, no state. Spoilage is never stored as a flag on a batch --
## freshness, spoiled/fresh state, effective weight, and display name are all
## derived on read from acquired_minute + spoil_minutes vs. the current clock.
## Same reasoning as Condition/Morale on CharacterSheet: derived, not stored.

## Once a batch hits 0% freshness, its effective weight drops to half the
## fresh weight -- authored directly as this constant rather than a per-item
## CSV column, since it's a flat rule rather than per-item content.
const SPOILED_WEIGHT_MULTIPLIER := 0.5


## Returns 0.0 (fully spoiled) to 1.0 (freshly acquired). Non-perishable items
## (or perishable items with no spoil_minutes set) are always fully fresh.
static func get_freshness(batch: InventoryBatch, item: ItemDefinition, current_minute: int) -> float:
	if not item.perishable or item.spoil_minutes <= 0:
		return 1.0
	var elapsed := current_minute - batch.acquired_minute
	var remaining := item.spoil_minutes - elapsed
	return clampf(float(remaining) / float(item.spoil_minutes), 0.0, 1.0)


## The hard 0% cutoff. This is the only point where spoilage actually changes
## anything -- weight and label, both computed below -- there is no gradual
## transition, only the freshness bar itself is smooth.
static func is_spoiled(batch: InventoryBatch, item: ItemDefinition, current_minute: int) -> bool:
	return item.perishable and get_freshness(batch, item, current_minute) <= 0.0


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
