extends Node

## Autoload. The single shared party inventory -- no per-character inventories
## exist or are planned. Register AFTER ItemRegistry in Project Settings >
## Autoload, since every operation here looks item definitions up there.
##
## Permissive by design: add_item/remove_item never block on capacity, they
## only fail on insufficient quantity. Weight capacity is reported via
## get_weight_status(), never enforced here -- whatever system owns Travel
## later decides what to do with an Overloaded party. Money is the one
## exception: it can never go negative, remove_money() fails cleanly instead.

signal weight_status_changed(new_status: WeightStatus)
signal money_changed(new_total: float)

enum WeightStatus {
	UNENCUMBERED,
	ENCUMBERED,
	OVERLOADED,
}

# --- Placeholder/tunable constants, same spirit as the DC table and point-buy
# costs -- not playtested, expect these to move. ---
const DEFAULT_PER_PERSON_CARRY := 50.0  # lbs
const ENCUMBERED_THRESHOLD := 0.85  # 85% of max capacity

var _stock: Dictionary = {}  # item_id (String) -> int, non-perishables only
var _batches: Dictionary = {}  # item_id (String) -> Array[InventoryBatch], perishables only
var _money: float = 0.0

# Externally fed -- InventorySystem never queries a party roster or a vehicle
# system directly (neither exists yet). Whatever eventually owns "the party"
# is responsible for keeping these current. See set_party_size/set_vehicle_capacity.
var _party_size: int = 0
var _vehicle_capacity: float = -1.0  # -1 means "no vehicle", falls back to per-person carry

var _last_weight_status: WeightStatus = WeightStatus.UNENCUMBERED


# ---------------------------------------------------------------------------
# Items
# ---------------------------------------------------------------------------

## acquired_minute defaults to the current game time if left unset (-1).
## Only meaningful for perishable items; ignored for everything else.
func add_item(item_id: String, quantity: int, acquired_minute: int = -1) -> void:
	if quantity <= 0:
		return

	var item := ItemRegistry.get_item(item_id)
	if item == null:
		push_warning("InventorySystem: unknown item_id '%s'" % item_id)
		return

	if item.perishable:
		# TODO: confirm the exact getter name on your TimeSystem autoload --
		# assumed here as get_total_minutes_elapsed(). Swap to match whatever
		# TimeSystem actually exposes for "current total elapsed minutes."
		var minute := acquired_minute if acquired_minute >= 0 else TimeSystem.get_total_minutes_elapsed()
		_add_batch(item_id, quantity, minute)
	else:
		_stock[item_id] = _stock.get(item_id, 0) + quantity

	_check_weight_status_changed()


## Batches acquired in the same add_item call (same minute) merge into one --
## this is the "merge if acquired at the same time" rule, now at minute
## precision rather than day precision.
func _add_batch(item_id: String, quantity: int, acquired_minute: int) -> void:
	if not _batches.has(item_id):
		_batches[item_id] = []
	var batches: Array = _batches[item_id]

	for batch in batches:
		if batch.acquired_minute == acquired_minute:
			batch.quantity += quantity
			return

	batches.append(InventoryBatch.new(quantity, acquired_minute))


## Returns false (and removes nothing) if the party doesn't have enough.
## FIFO across batches for perishables -- oldest (closest to spoiling) goes first.
func remove_item(item_id: String, quantity: int) -> bool:
	if quantity <= 0:
		return true

	var item := ItemRegistry.get_item(item_id)
	if item == null:
		return false

	if item.perishable:
		return _remove_from_batches(item_id, quantity)

	var have: int = _stock.get(item_id, 0)
	if have < quantity:
		return false
	_stock[item_id] = have - quantity
	if _stock[item_id] <= 0:
		_stock.erase(item_id)

	_check_weight_status_changed()
	return true


func _remove_from_batches(item_id: String, quantity: int) -> bool:
	if get_quantity(item_id) < quantity:
		return false

	var batches: Array = _batches.get(item_id, [])
	batches.sort_custom(func(a, b): return a.acquired_minute < b.acquired_minute)

	var remaining := quantity
	var i := 0
	while remaining > 0 and i < batches.size():
		var batch: InventoryBatch = batches[i]
		if batch.quantity <= remaining:
			remaining -= batch.quantity
			batches.remove_at(i)
		else:
			batch.quantity -= remaining
			remaining = 0
			i += 1

	if batches.is_empty():
		_batches.erase(item_id)

	_check_weight_status_changed()
	return true


func has_item(item_id: String, quantity: int = 1) -> bool:
	return get_quantity(item_id) >= quantity


## Total quantity across all batches for perishables, or the flat count for
## everything else. Does not account for anything equipped -- see
## get_available_quantity() for that.
func get_quantity(item_id: String) -> int:
	var item := ItemRegistry.get_item(item_id)
	if item == null:
		return 0

	if item.perishable:
		var total := 0
		for batch in _batches.get(item_id, []):
			total += batch.quantity
		return total

	return _stock.get(item_id, 0)


## equipped_elsewhere_count is supplied by the caller -- InventorySystem never
## reaches into a character roster to compute this itself (no roster/Party
## system exists yet; this stays idle/manually-fed until one does).
func get_available_quantity(item_id: String, equipped_elsewhere_count: int = 0) -> int:
	return maxi(0, get_quantity(item_id) - equipped_elsewhere_count)


## requirements: Dictionary[item_id: String -> quantity: int]
func has_items(requirements: Dictionary) -> bool:
	for item_id in requirements:
		if not has_item(item_id, requirements[item_id]):
			return false
	return true


## Atomic all-or-nothing: either every requirement is met and all are
## removed, or nothing is removed. Generic primitive for future
## Crafting/Recipe and Consumption managers to build on.
func consume_items(requirements: Dictionary) -> bool:
	if not has_items(requirements):
		return false
	for item_id in requirements:
		remove_item(item_id, requirements[item_id])
	return true


# ---------------------------------------------------------------------------
# Freshness / batches (perishables only)
# ---------------------------------------------------------------------------

func get_batches(item_id: String) -> Array:
	return _batches.get(item_id, []).duplicate()


func get_batch_freshness(batch: InventoryBatch, item_id: String) -> float:
	var item := ItemRegistry.get_item(item_id)
	if item == null:
		return 1.0
	return ItemFreshness.get_freshness(batch, item, _current_minute())


func is_batch_spoiled(batch: InventoryBatch, item_id: String) -> bool:
	var item := ItemRegistry.get_item(item_id)
	if item == null:
		return false
	return ItemFreshness.is_spoiled(batch, item, _current_minute())


func get_batch_display_name(batch: InventoryBatch, item_id: String) -> String:
	var item := ItemRegistry.get_item(item_id)
	if item == null:
		return item_id
	return ItemFreshness.get_display_name(batch, item, _current_minute())


func _current_minute() -> int:
	# TODO: same TimeSystem getter as in add_item() -- keep these in sync.
	return TimeSystem.get_total_minutes_elapsed()


# ---------------------------------------------------------------------------
# Money -- special-cased, NOT permissive. Never goes negative.
# ---------------------------------------------------------------------------

func add_money(amount: float) -> void:
	if amount <= 0:
		return
	_money += amount
	money_changed.emit(_money)


## Fails cleanly (returns false, changes nothing) if funds are insufficient --
## unlike items, there is no "go over and deal with the consequences" here.
func remove_money(amount: float) -> bool:
	if amount <= 0:
		return true
	if _money < amount:
		return false
	_money -= amount
	money_changed.emit(_money)
	return true


func get_money() -> float:
	return _money


# ---------------------------------------------------------------------------
# Weight & capacity
# ---------------------------------------------------------------------------

## Money is deliberately excluded from weight entirely. Spoiled batches count
## at their reduced (halved) effective weight.
func get_total_weight() -> float:
	var total := 0.0

	for item_id in _stock:
		var item := ItemRegistry.get_item(item_id)
		if item:
			total += item.weight * _stock[item_id]

	var current_minute := _current_minute()
	for item_id in _batches:
		var item := ItemRegistry.get_item(item_id)
		if item == null:
			continue
		for batch in _batches[item_id]:
			total += ItemFreshness.get_effective_weight(batch, item, current_minute)

	return total


## No Party system exists yet -- this is externally fed by whatever stands in
## for one (a temp test-harness UI today, a real Party manager later).
func set_party_size(count: int) -> void:
	_party_size = maxi(0, count)
	_check_weight_status_changed()


## A vehicle OVERRIDES per-person carry entirely -- it does not add to it.
func set_vehicle_capacity(capacity: float) -> void:
	_vehicle_capacity = capacity
	_check_weight_status_changed()


func clear_vehicle() -> void:
	_vehicle_capacity = -1.0
	_check_weight_status_changed()


func has_vehicle() -> bool:
	return _vehicle_capacity >= 0.0


func get_max_capacity() -> float:
	if has_vehicle():
		return _vehicle_capacity
	return DEFAULT_PER_PERSON_CARRY * _party_size


## Capacity is never enforced here -- this is purely a status report.
## Encumbered/Overloaded are meant to feed a future travel-speed modifier
## (system:travel_speed already exists as a target in the Modifier System)
## and a future travel-blocking check, neither of which live in Inventory.
func get_weight_status() -> WeightStatus:
	var max_cap := get_max_capacity()
	if max_cap <= 0.0:
		return WeightStatus.UNENCUMBERED

	var ratio := get_total_weight() / max_cap
	if ratio >= 1.0:
		return WeightStatus.OVERLOADED
	elif ratio >= ENCUMBERED_THRESHOLD:
		return WeightStatus.ENCUMBERED
	return WeightStatus.UNENCUMBERED


func _check_weight_status_changed() -> void:
	var current := get_weight_status()
	if current != _last_weight_status:
		_last_weight_status = current
		weight_status_changed.emit(current)
