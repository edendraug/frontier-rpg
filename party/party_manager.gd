extends Node

## Autoload. Lightweight coordinator for "the current party" — sits
## alongside systems/, not as a tenth GDD system, since Party is a
## composition of things that already exist (CharacterSheets +
## InventorySystem) rather than an independent domain of its own.
## Same reasoning as dev/ sitting outside systems/.
##
## In-memory only for now — no .tres writes. Wiring this into a real
## save happens once the Save/Load system exists.
##
## Register in Project Settings > Autoload AFTER TimeSystem,
## ItemRegistry, and InventorySystem — begin_expedition() calls into
## InventorySystem directly.

signal character_added(index: int)
signal character_updated(index: int)
signal character_removed(index: int)
signal roster_loaded()
signal expedition_begun()

const MIN_PARTY_SIZE := 1
const MAX_PARTY_SIZE := 4

## Placeholder/tunable, same treatment as the DC table and the
## encumbrance threshold. Scales money by members BEYOND the main
## character rather than multiplying the Occupation's full
## starting_money by party size — keeps starting_money meaning "what
## this profession's purse looks like" rather than a per-person unit
## (a Preacher isn't wealthier just because they brought friends).
const PER_EXTRA_MEMBER_MONEY := 15

var _roster: Array[CharacterSheet] = []

## Own CharacterDataRegistry instance — same pattern the original
## character_creator.gd already used (the registry is a plain
## RefCounted, not an autoload, so each owner constructs its own).
## Shared out via get_registry() so the Party Creator screen and its
## card don't each re-scan disk separately.
var _registry: CharacterDataRegistry


func _ready() -> void:
	_registry = CharacterDataRegistry.new()


func get_registry() -> CharacterDataRegistry:
	return _registry


# ---------------------------------------------------------------------------
# Roster queries
# ---------------------------------------------------------------------------

func get_roster() -> Array[CharacterSheet]:
	return _roster.duplicate()


func get_character(index: int) -> CharacterSheet:
	if index < 0 or index >= _roster.size():
		return null
	return _roster[index]


func get_main_character() -> CharacterSheet:
	return _roster[0] if not _roster.is_empty() else null


func get_party_size() -> int:
	return _roster.size()


func is_full() -> bool:
	return _roster.size() >= MAX_PARTY_SIZE


func can_add_more() -> bool:
	return not is_full()


## The index the next EMPTY/unlocked slot would use, or -1 if the
## party is already full. UI reads this rather than recomputing
## "which slot is next" itself.
func next_open_slot_index() -> int:
	return _roster.size() if can_add_more() else -1


# ---------------------------------------------------------------------------
# Roster mutation
# ---------------------------------------------------------------------------

## is_main_character is stamped HERE, from position alone (index 0),
## never trusted from whatever the caller passed in — this is the
## single place that rule lives, fully replacing the old manual
## Main/NPC dropdown in the character creator.
func add_character(sheet: CharacterSheet) -> bool:
	if is_full():
		push_warning("PartyManager: party is full (max %d)" % MAX_PARTY_SIZE)
		return false
	sheet.is_main_character = _roster.is_empty()
	_roster.append(sheet)
	character_added.emit(_roster.size() - 1)
	return true


func update_character(index: int, sheet: CharacterSheet) -> bool:
	if index < 0 or index >= _roster.size():
		return false
	sheet.is_main_character = (index == 0)
	_roster[index] = sheet
	character_updated.emit(index)
	return true


## Refuses on index 0 — a party without a main character isn't a
## valid state. Everyone after the removed slot shifts down to close
## the gap; slot POSITION carries no gameplay meaning beyond "index 0
## is main," so shifting is safe — nothing else is keyed off a
## character's slot number.
func remove_character(index: int) -> bool:
	if index <= 0 or index >= _roster.size():
		return false
	_roster.remove_at(index)
	character_removed.emit(index)
	return true


## Bulk replace, used only by SaveManager on load -- distinct from
## add/update/remove, which are one-slot-at-a-time operations meant for the
## Party Creator loop. Re-stamps is_main_character defensively by position,
## same rule as everywhere else, even though a save produced by this game
## should already be consistent.
func load_roster(roster: Array[CharacterSheet]) -> void:
	_roster = roster.duplicate()
	for i in _roster.size():
		_roster[i].is_main_character = (i == 0)
	roster_loaded.emit()


## Notifies listeners that something WITHIN the roster changed in
## place -- fields mutated directly on a live CharacterSheet reference
## (e.g. by a debug tool editing hunger/morale, or inflicting an
## injury), rather than the roster's MEMBERSHIP changing.
## CharacterSheet has no change signal of its own, so this is the
## seam anything displaying live roster data (the Party overlay)
## listens to in order to refresh without polling. Reuses
## roster_loaded rather than a new signal -- the correct response
## either way is "just rebuild from current state."
func notify_roster_changed() -> void:
	roster_loaded.emit()


## Clears the roster back to empty -- used when starting a genuinely
## new expedition (Main Menu > New Game), so a party from a PREVIOUS
## session/expedition doesn't carry over into Party Creator. Reuses
## roster_loaded rather than a dedicated signal, since "the whole
## roster just changed non-incrementally" covers an empty result too.
func reset() -> void:
	_roster.clear()
	roster_loaded.emit()


# ---------------------------------------------------------------------------
# Vehicle — thin pass-through to InventorySystem, no local copy stored here.
# InventorySystem already owns what capacity means for weight math;
# duplicating the number here would just invite the two disagreeing.
# PartyManager is the CONCEPTUAL home for "does this party have a vehicle"
# (and later, a real VehicleDefinition reference), without owning the
# capacity number itself.
# ---------------------------------------------------------------------------

func has_vehicle() -> bool:
	return InventorySystem.has_vehicle()


func set_vehicle(capacity: float) -> void:
	InventorySystem.set_vehicle_capacity(capacity)


func clear_vehicle() -> void:
	InventorySystem.clear_vehicle()


# ---------------------------------------------------------------------------
# Finalize
# ---------------------------------------------------------------------------

## Seeds InventorySystem with party size, the main character's
## Occupation starting_gear, and starting_money (scaled by extra
## party members) — all done ONCE here, not incrementally as each
## slot fills, so removing a character mid-draft never has to
## "un-seed" anything already committed.
func begin_expedition() -> bool:
	if _roster.is_empty():
		push_warning("PartyManager: cannot begin expedition with an empty party")
		return false

	InventorySystem.set_party_size(get_party_size())
	_seed_starting_gear_and_money()

	expedition_begun.emit()
	return true


func _seed_starting_gear_and_money() -> void:
	var main := get_main_character()
	if main == null or main.occupation_id == "":
		return

	var occupation: OccupationDefinition = _registry.occupations.get(main.occupation_id)
	if occupation == null:
		push_warning(
			"PartyManager: main character's occupation_id '%s' not found in registry" % main.occupation_id
		)
		return

	for stack in occupation.starting_gear:
		InventorySystem.add_item(stack.item_id, stack.quantity)

	var extra_members := get_party_size() - 1
	var total_money := occupation.starting_money + (extra_members * PER_EXTRA_MEMBER_MONEY)
	InventorySystem.add_money(total_money)
