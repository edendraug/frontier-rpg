extends Node

## Autoload. Owns the single live VehicleInstance (or none), the full
## AnimalInstance roster, and every abandoned-vehicle snapshot. Also
## owns discovery of VehiclePartDefinition/VehicleDefinition/
## AnimalDefinition -- no separate CaravanRegistry autoload, same
## "the system that owns the live state also owns its authored
## definitions" posture WorldRegistry already uses for terrain types,
## rather than ItemRegistry/InventorySystem's split (kept separate
## there mainly for a large CSV-driven catalog, which doesn't apply
## here).
##
## Register in Project Settings > Autoload AFTER TravelSystem and
## strictly BEFORE ExpeditionSceneRouter -- this depends on TravelSystem
## (registers pull-hooks into it at _ready(), reads its current hex/
## pace/hazard) and ExpeditionSceneRouter's arrival check queries
## get_abandoned_vehicle_prompt_at() (Section 4.9/5.2). Position
## relative to LocalSceneManager doesn't matter. Confirmed real autoload
## order:
##   ... -> TravelSystem -> CaravanSystem -> LocalSceneManager -> ExpeditionSceneRouter
##
## Vehicles & Animals Design Doc v0.4.
##
## ONE THING THIS PHASE DELIBERATELY DOES NOT DO, flagging rather than
## guessing silently: does NOT call
## TravelSystem.register_hazard_modifier_source(). Section 4.7's table
## lists it as something this system would use, but nothing in Sections
## 3-5 actually specifies what hazard entry a vehicle would contribute --
## there's no hazard equivalent of the Section 3.4 speed debuff described
## anywhere. Confirmed with Cameron as real, in-scope for this game
## eventually, but out of scope for this stage -- likely belongs to a
## later, more granular gameplay pass (possibly tied to a future
## Encounter system, which Section 4.7 already notes would also want
## get_effective_hazard()). register_speed_modifier_source() below IS
## implemented, since Section 3.4's speed debuff is concretely specified.
##
## ALSO NEW THIS PHASE, beyond what Section 5.1 spells out step-by-step:
## hitch-minimum enforcement (Section 3.7's "below hitch_minimum, vehicle
## cannot move at all -- same functional state as a breakdown") wasn't
## actually listed among Section 5.1's five numbered steps. Implemented
## here as an additional full-stop check at the top of
## _on_travel_time_passed(), reusing pause_for_event() the same way an
## at-zero part does -- confirm this matches what Section 3.7 intended,
## since it was inferred rather than explicitly specified.

const VEHICLE_PARTS_DIR := "res://systems/caravan/data/vehicle_parts/"
const VEHICLES_DIR := "res://systems/caravan/data/vehicles/"
const ANIMALS_DIR := "res://systems/caravan/data/animals/"

## Section 3.4 -- placeholder/tunable, flagged with the same extra
## emphasis the design doc itself uses: a single hex crossing can span
## 300+ in-game minutes, so these compound very differently at that
## scale than they look in isolation. Do not finalize by inspection.
const BREAK_RISK_THRESHOLD := 0.25
const BREAK_CHANCE_AT_THRESHOLD := 0.10   # t = 1.0 (right at the threshold)
const BREAK_CHANCE_AT_ZERO := 1.0          # t = 0.0 (durability at zero)

## Placeholder, untuned -- durability units drained per in-game minute
## per point of TravelSystem.get_effective_hazard(), before
## wear_rate_multiplier. No precedent number exists anywhere else in
## the project for this; picked to be revisited entirely once real
## tick rates and map distances exist to test against, same posture as
## every other number in this file.
const DECAY_RATE_PER_EFFECTIVE_HAZARD_MINUTE := 0.05

## Section 3.4's flat, non-scaling MULTIPLICATIVE speed penalty, applied
## whenever vehicle condition sits below BREAK_RISK_THRESHOLD. Untuned.
const SPEED_DEBUFF_MULTIPLIER := 0.85

## Section 3.7 -- placeholder linear hitch-shortfall curve. 1.0 at
## hitch_target (no penalty), scaling up to this multiplier at exactly
## hitch_minimum. Applied on TOP of the role-based baseline (Section
## 3.8), not in place of it.
const HITCH_SHORTFALL_MAX_MULTIPLIER := 2.0

## Section 3.8 -- placeholder, expected < 1.0, matching
## AnimalDefinition.fatigue_drain_rate_unhitched_multiplier's own field
## comment. Kept here too only as the doc-level cross-reference; the
## per-animal-type real value always comes from the resolved
## AnimalDefinition, never from a constant in this file.

## part_id -> VehiclePartDefinition, vehicle_type_id -> VehicleDefinition,
## animal_type_id -> AnimalDefinition. Loaded by _load_definitions()
## below, same DirAccess-scan convention as
## WorldRegistry._load_terrain_types() / CharacterDataRegistry._load_all().
var _vehicle_part_definitions: Dictionary = {}
var _vehicle_definitions: Dictionary = {}
var _animal_definitions: Dictionary = {}

## Live state (Section 4.6). Private, same reasoning TravelSystem keeps
## _travel_state private -- get_vehicle()/get_animals() below hand back
## duplicated snapshots, never the live reference, so a caller can't
## accidentally desync internal state by mutating what it was given.
var _vehicle: VehicleInstance = null
var _animals: Array[AnimalInstance] = []
var _abandoned_vehicles: Dictionary = {}  # String (coord) -> VehicleInstance

## Same RandomNumberGenerator-instance convention as
## systems/dialogue/dialogue_context.gd -- an owned instance rather
## than the global randf()/randi(), so a future test harness could
## inject a seeded one if that ever matters.
var _rng := RandomNumberGenerator.new()

## Distinguishes what a future repair-or-abandon (or, for UNDERMANNED,
## a rehitch-or-abandon) prompt needs to show -- these are NOT
## interchangeable causes with the same resolution. PART_BROKEN offers
## a real Repair option (Section 5.4, once it exists) alongside Abandon.
## UNDERMANNED has nothing to repair at all -- the fix is hitching more
## animals, or abandoning -- so a prompt built only for PART_BROKEN
## would offer the wrong buttons entirely if this weren't distinguished.
enum HaltReason { PART_BROKEN, UNDERMANNED }

## Fired when a part reaches 0% durability and the vehicle was
## previously operable, OR the hitched team falls below hitch_minimum
## while still otherwise operable (Section 3.5/3.7) -- either way,
## travel is now PAUSED_BY_EVENT and needs a resolution prompt from
## whatever UI eventually owns that. `detail` is player-facing flavor
## text -- a random VehiclePartDefinition.break_messages entry for
## PART_BROKEN (_get_break_detail_message() below), a fixed generic
## message for UNDERMANNED (nothing part-specific to say). No UI exists
## yet to consume this (Section 5.4's repair path is a reserved stub) --
## reserving the signal now rather than having a future phase retrofit
## it onto every mutation site that can cause a stop. Per Cameron's
## confirmed scene-generation model, resolving either reason will
## eventually happen through a generated local scene the party and
## caravan are both loaded into (any scene, not a special "breakdown"
## scene) -- repair is possible from anywhere travel is paused, not
## just here.
signal vehicle_halted(reason: HaltReason, detail: String)

## Fired after any mutation to the live vehicle or animal roster --
## acquire, abandon, a tick's decay/drain, a role change. Mirrors
## PartyManager.notify_roster_changed()'s "notify after mutating"
## posture, for a future UI (condition meters, animal roster panel) to
## refresh from rather than polling every frame.
signal caravan_changed


func _ready() -> void:
	_load_definitions()
	TravelSystem.register_speed_modifier_source(_get_speed_modifier_entries)
	TravelSystem.travel_time_passed.connect(_on_travel_time_passed)


# ---------------------------------------------------------------------------
# Definition discovery
# ---------------------------------------------------------------------------

func _load_definitions() -> void:
	_load_vehicle_parts()
	_load_vehicles()
	_load_animals()


func _load_vehicle_parts() -> void:
	_vehicle_part_definitions.clear()
	var dir := DirAccess.open(VEHICLE_PARTS_DIR)
	if dir == null:
		push_warning("CaravanSystem: could not open %s" % VEHICLE_PARTS_DIR)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var res: Resource = load(VEHICLE_PARTS_DIR + file_name)
			if res is VehiclePartDefinition:
				if _vehicle_part_definitions.has(res.part_id):
					push_warning("CaravanSystem: duplicate part_id '%s', overwriting" % res.part_id)
				_vehicle_part_definitions[res.part_id] = res
			else:
				push_warning("CaravanSystem: '%s' is not a VehiclePartDefinition, skipping" % file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	print("CaravanSystem: loaded %d vehicle parts" % _vehicle_part_definitions.size())


func _load_vehicles() -> void:
	_vehicle_definitions.clear()
	var dir := DirAccess.open(VEHICLES_DIR)
	if dir == null:
		push_warning("CaravanSystem: could not open %s" % VEHICLES_DIR)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var res: Resource = load(VEHICLES_DIR + file_name)
			if res is VehicleDefinition:
				if _vehicle_definitions.has(res.vehicle_type_id):
					push_warning("CaravanSystem: duplicate vehicle_type_id '%s', overwriting" % res.vehicle_type_id)
				_vehicle_definitions[res.vehicle_type_id] = res
			else:
				push_warning("CaravanSystem: '%s' is not a VehicleDefinition, skipping" % file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	print("CaravanSystem: loaded %d vehicle types" % _vehicle_definitions.size())


func _load_animals() -> void:
	_animal_definitions.clear()
	var dir := DirAccess.open(ANIMALS_DIR)
	if dir == null:
		push_warning("CaravanSystem: could not open %s" % ANIMALS_DIR)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var res: Resource = load(ANIMALS_DIR + file_name)
			if res is AnimalDefinition:
				if _animal_definitions.has(res.animal_type_id):
					push_warning("CaravanSystem: duplicate animal_type_id '%s', overwriting" % res.animal_type_id)
				_animal_definitions[res.animal_type_id] = res
			else:
				push_warning("CaravanSystem: '%s' is not an AnimalDefinition, skipping" % file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	print("CaravanSystem: loaded %d animal types" % _animal_definitions.size())


# ---------------------------------------------------------------------------
# Live state accessors
# ---------------------------------------------------------------------------

## Duplicated on the way out, same protective reasoning as
## TravelSystem.get_travel_state() -- null stays null (Resource.duplicate()
## on a null reference isn't meaningful; caller gets "no vehicle" back
## unambiguously either way).
func get_vehicle() -> VehicleInstance:
	return _vehicle.duplicate() if _vehicle != null else null


func get_animals() -> Array[AnimalInstance]:
	var out: Array[AnimalInstance] = []
	for animal in _animals:
		out.append(animal.duplicate())
	return out


func has_vehicle() -> bool:
	return _vehicle != null


func get_abandoned_vehicle_at(coord: String) -> VehicleInstance:
	var found: VehicleInstance = _abandoned_vehicles.get(coord)
	return found.duplicate() if found != null else null


## Section 4.9/5.2. Constructs a fresh AbandonedVehiclePromptEntry from
## the stored snapshot at `coord`, or null if nothing's abandoned there
## -- ExpeditionSceneRouter's own candidate-gathering step calls this
## directly, appending the result to its prompt queue alongside whatever
## get_locations_in_hex() returns. display_name is "Abandoned " plus the
## owning VehicleDefinition's own display_name, falling back to a
## generic label if the definition is somehow missing (shouldn't happen
## for real data, same defensive posture as elsewhere in this file).
## hex_sector comes straight from the stored VehicleInstance.hex_sector
## -- the party's REAL position at the moment of abandonment (Section
## 4.3's v0.4 follow-up), not the placeholder/central value the
## original Section 4.9 text assumed before that was resolved.
func get_abandoned_vehicle_prompt_at(coord: String) -> AbandonedVehiclePromptEntry:
	var vehicle := get_abandoned_vehicle_at(coord)
	if vehicle == null:
		return null

	var entry := AbandonedVehiclePromptEntry.new()
	var vdef: VehicleDefinition = _vehicle_definitions.get(vehicle.vehicle_type_id)
	entry.display_name = "Abandoned " + (vdef.display_name if vdef != null else "Vehicle")
	entry.hex_sector = vehicle.hex_sector
	return entry


# ---------------------------------------------------------------------------
# Acquisition (Section 10, Open Question 2 -- Dialogue-side wiring not
# built yet; these are the real hand-off methods a future DialoguePlayer
# effect, a trading system, or a debug tab can all call directly).
# ---------------------------------------------------------------------------

## Refuses (returns false, no mutation) if a vehicle is already owned --
## v1 scope is a single party vehicle (Section 2), and silently
## overwriting an owned one would be a real data-loss bug, not a
## permissive default worth extending here. Refuses if vehicle_type_id
## is unrecognized. New VehicleInstance starts every part at that
## part's own max_durability -- fully sound, per Section 3.3's "100% is
## full" convention.
func acquire_vehicle(vehicle_type_id: String) -> bool:
	if _vehicle != null:
		push_warning("CaravanSystem: acquire_vehicle() refused -- a vehicle is already owned")
		return false
	var def: VehicleDefinition = _vehicle_definitions.get(vehicle_type_id)
	if def == null:
		push_warning("CaravanSystem: acquire_vehicle() refused -- unknown vehicle_type_id '%s'" % vehicle_type_id)
		return false

	var instance := VehicleInstance.new()
	instance.vehicle_type_id = vehicle_type_id
	for part_id in def.part_ids:
		var part_def: VehiclePartDefinition = _vehicle_part_definitions.get(part_id)
		if part_def == null:
			push_warning("CaravanSystem: '%s' references unknown part_id '%s', skipping" % [vehicle_type_id, part_id])
			continue
		instance.part_durability[part_id] = part_def.max_durability

	_vehicle = instance
	InventorySystem.set_caravan_capacity_bonus(get_total_carry_capacity())
	caravan_changed.emit()
	return true


## Refuses (returns false) if animal_type_id is unrecognized. Always
## succeeds otherwise -- unlike the vehicle, the roster is genuinely a
## roster (Section 2 doesn't cap animal count). New animals start
## UNASSIGNED, fully fed, fully rested (Section 3.8's stored fields'
## own defaults).
func acquire_animal(animal_type_id: String) -> bool:
	var def: AnimalDefinition = _animal_definitions.get(animal_type_id)
	if def == null:
		push_warning("CaravanSystem: acquire_animal() refused -- unknown animal_type_id '%s'" % animal_type_id)
		return false

	var instance := AnimalInstance.new()
	instance.animal_id = _generate_animal_id(animal_type_id)
	instance.animal_type_id = animal_type_id
	_animals.append(instance)
	# Acquiring UNASSIGNED contributes nothing to carry capacity yet
	# (only PACK-role animals do, Section 4.8) -- re-syncing here anyway
	# costs nothing and means a future caller changing role doesn't have
	# to remember this call exists too. A LATER role change must go
	# through set_animal_role() below, not AnimalInstance.set_role()
	# directly, or this re-sync gets skipped.
	InventorySystem.set_caravan_capacity_bonus(get_total_carry_capacity())
	caravan_changed.emit()
	return true


## Public entry point for changing an animal's role from OUTSIDE this
## system (a future roster-management UI, a debug tab) -- routes
## through AnimalInstance.set_role() (which enforces the
## hitched_vehicle_id invariant, Section 4.5) and re-syncs carry
## capacity afterward, since moving into or out of PACK changes
## get_total_carry_capacity()'s result. abandon_vehicle() below mutates
## roles directly instead, since it already does its own single re-sync
## covering both the vehicle's removal and the reverted animals' PACK
## contribution together -- calling this method there would just mean
## redundant re-syncs, not a wrong result, but the direct-mutation path
## is only safe INSIDE this file, where the re-sync is known to still
## happen right after. Returns false if animal_id isn't found.
func set_animal_role(animal_id: String, new_role: AnimalInstance.Role, vehicle_id: String = "") -> bool:
	for animal in _animals:
		if animal.animal_id == animal_id:
			animal.set_role(new_role, vehicle_id)
			InventorySystem.set_caravan_capacity_bonus(get_total_carry_capacity())
			caravan_changed.emit()
			return true
	push_warning("CaravanSystem: set_animal_role() refused -- unknown animal_id '%s'" % animal_id)
	return false


## Time.get_unix_time_from_system(), matching the existing slug
## convention (character_creator.gd, save_manager.gd), plus a cheap
## disambiguating suffix loop for the rare same-second collision --
## no persisted counter needed across save/load this way.
func _generate_animal_id(animal_type_id: String) -> String:
	var base_id := "%s_%d" % [animal_type_id, Time.get_unix_time_from_system()]
	var candidate := base_id
	var suffix := 1
	while _animals.any(func(a: AnimalInstance) -> bool: return a.animal_id == candidate):
		candidate = "%s_%d" % [base_id, suffix]
		suffix += 1
	return candidate


# ---------------------------------------------------------------------------
# Abandonment (Section 3.6, 5.3)
# ---------------------------------------------------------------------------

## No-ops (with a warning) if no vehicle is owned. Snapshots the live
## VehicleInstance into _abandoned_vehicles keyed by the party's current
## hex, stamping its hex_sector (Section 4.3's v0.4 follow-up addition)
## from ExpeditionSceneRouter's real position -- NOT defaulted to
## CENTER_SECTOR, per Cameron's confirmed "find the real position, don't
## guess" call. Reverts every HITCHED animal to PACK via
## AnimalInstance.set_role() (Section 3.6), which also clears
## hitched_vehicle_id automatically. Resumes travel on the party's
## behalf -- this method assumes it's only ever called while paused
## (player-initiated abandon from the repair-or-abandon prompt, Section
## 3.5), same as Section 5.3 describes.
func abandon_vehicle() -> void:
	if _vehicle == null:
		push_warning("CaravanSystem: abandon_vehicle() called with no vehicle owned")
		return

	var coord := TravelSystem.get_current_hex()
	_vehicle.hex_sector = ExpeditionSceneRouter.get_current_position_sector()
	_abandoned_vehicles[coord] = _vehicle
	_vehicle = null

	for animal in _animals:
		if animal.role == AnimalInstance.Role.HITCHED:
			animal.set_role(AnimalInstance.Role.PACK)

	# One combined re-sync covers both changes at once (vehicle's
	# contribution just dropped out, reverted animals' PACK contribution
	# just came in) -- see set_animal_role()'s own comment for why the
	# direct set_role() mutation above is safe only here, immediately
	# followed by this.
	InventorySystem.set_caravan_capacity_bonus(get_total_carry_capacity())
	TravelSystem.resume_travel()
	caravan_changed.emit()


# ---------------------------------------------------------------------------
# Carry capacity (Section 4.8)
# ---------------------------------------------------------------------------

## Additive total this system contributes toward party carry capacity --
## the owned vehicle's base_carry_capacity (0.0 if none) plus every
## PACK-role animal's own base_carry_capacity. Pushed into
## InventorySystem.set_caravan_capacity_bonus() (Section 4.8) from every
## call site that can change this result -- acquire_vehicle(),
## acquire_animal(), abandon_vehicle(), set_animal_role() -- so this
## getter itself stays a pure computation, safe to call anytime for a
## future UI breakdown ("wagon: X, pack animals: Y") too.
func get_total_carry_capacity() -> float:
	var total := 0.0
	if _vehicle != null:
		var vdef: VehicleDefinition = _vehicle_definitions.get(_vehicle.vehicle_type_id)
		if vdef != null:
			total += vdef.base_carry_capacity
	for animal in _animals:
		if animal.role != AnimalInstance.Role.PACK:
			continue
		var adef: AnimalDefinition = _animal_definitions.get(animal.animal_type_id)
		if adef != null:
			total += adef.base_carry_capacity
	return total


# ---------------------------------------------------------------------------
# Travel-time tick (Section 5.1)
# ---------------------------------------------------------------------------

func _on_travel_time_passed(minutes: int) -> void:
	if _vehicle != null:
		var vdef: VehicleDefinition = _vehicle_definitions.get(_vehicle.vehicle_type_id)

		# New this phase, inferred from Section 3.7 rather than spelled
		# out in Section 5.1 -- see this file's header comment. Checked
		# BEFORE decay/break-risk: if the team is already undermanned,
		# there's nothing further to tick this frame; the vehicle isn't
		# moving.
		if vdef != null and _count_hitched() < vdef.hitch_minimum:
			TravelSystem.pause_for_event()
			vehicle_halted.emit(HaltReason.UNDERMANNED, "Your team can't pull the wagon shorthanded.")
			return

		var was_operable := _vehicle.is_operable()
		_decay_vehicle_parts(minutes)
		_roll_break_risk(minutes)

		if was_operable and not _vehicle.is_operable():
			TravelSystem.pause_for_event()
			vehicle_halted.emit(HaltReason.PART_BROKEN, _get_break_detail_message())

	_drain_animals(minutes)
	caravan_changed.emit()


## Step 1 (Section 5.1) -- decay is based on TravelSystem's effective
## hazard (terrain hazard_level * current hazard multiplier, which
## already folds in Pace -- see TravelSystem.get_effective_hazard()) and
## each part's own wear_rate_multiplier. Floored at 0.0, never negative.
func _decay_vehicle_parts(minutes: int) -> void:
	var coord := TravelSystem.get_current_hex()
	var effective_hazard := TravelSystem.get_effective_hazard(coord)

	for part_id in _vehicle.part_durability.keys():
		var part_def: VehiclePartDefinition = _vehicle_part_definitions.get(part_id)
		if part_def == null:
			continue
		var decay := DECAY_RATE_PER_EFFECTIVE_HAZARD_MINUTE * effective_hazard * part_def.wear_rate_multiplier * minutes
		_vehicle.part_durability[part_id] = maxf(_vehicle.part_durability[part_id] - decay, 0.0)


## Step 2 (Section 5.1, formula from Section 3.4) -- compounded properly
## across `minutes` rather than rolled once per tick, so odds stay
## consistent regardless of playback_speed. A part already at 0.0 (from
## decay above, or a prior tick's break) is skipped -- no further roll
## needed, it's already fully broken.
func _roll_break_risk(minutes: int) -> void:
	for part_id in _vehicle.part_durability.keys():
		var part_def: VehiclePartDefinition = _vehicle_part_definitions.get(part_id)
		if part_def == null or part_def.max_durability <= 0.0:
			continue

		var current: float = _vehicle.part_durability[part_id]
		if current <= 0.0:
			continue

		var pct := current / part_def.max_durability
		if pct >= BREAK_RISK_THRESHOLD:
			continue

		var t := pct / BREAK_RISK_THRESHOLD
		var break_chance_per_minute := lerpf(BREAK_CHANCE_AT_ZERO, BREAK_CHANCE_AT_THRESHOLD, t)
		var chance_this_tick := 1.0 - pow(1.0 - break_chance_per_minute, minutes)
		if _rng.randf() < chance_this_tick:
			_vehicle.part_durability[part_id] = 0.0


## Called only right after a PART_BROKEN transition (Section 5.1 step
## 3), when at least one part is guaranteed to be at exactly 0.0 --
## every part was above 0.0 at the start of this same tick (was_operable
## was true), so whatever's at 0.0 now broke THIS tick, not some earlier
## one. Picks one at random if more than one broke in the same tick
## (rare, but decay and the break-risk roll both run per-part per-tick,
## so not impossible) -- one message is enough for the player to read,
## even if two parts technically failed together. Falls back to a
## generic message if the part has no authored break_messages yet, or
## (shouldn't happen) no part is actually found at 0.0.
func _get_break_detail_message() -> String:
	var broken_part_ids: Array[String] = []
	for part_id in _vehicle.part_durability:
		if _vehicle.part_durability[part_id] <= 0.0:
			broken_part_ids.append(part_id)
	if broken_part_ids.is_empty():
		return "Something on your wagon has broken."

	var part_id: String = broken_part_ids[_rng.randi() % broken_part_ids.size()]
	var part_def: VehiclePartDefinition = _vehicle_part_definitions.get(part_id)
	if part_def == null or part_def.break_messages.is_empty():
		return "Your %s has broken." % part_id
	return part_def.break_messages[_rng.randi() % part_def.break_messages.size()]


## Step 5 (Section 5.1, rates from Section 3.8, shortfall scaling from
## Section 3.7). hunger_drain_rate/fatigue_drain_rate_hitched are
## per-HOUR rates on AnimalDefinition, matching VitalsSystem's own
## hunger/fatigue rate convention exactly (BASE_HUNGER_DRAIN_PER_HOUR,
## etc.) -- minutes converted to hours here the same way
## VitalsSystem._on_time_advanced() does.
func _drain_animals(minutes: int) -> void:
	var hours := minutes / 60.0
	var shortfall_multiplier := _get_hitch_shortfall_multiplier()

	for animal in _animals:
		var adef: AnimalDefinition = _animal_definitions.get(animal.animal_type_id)
		if adef == null:
			continue

		animal.hunger = clampf(animal.hunger - adef.hunger_drain_rate * hours, 0.0, 100.0)

		var fatigue_rate: float
		if animal.role == AnimalInstance.Role.HITCHED:
			fatigue_rate = adef.fatigue_drain_rate_hitched * shortfall_multiplier
		else:
			fatigue_rate = adef.fatigue_drain_rate_hitched * adef.fatigue_drain_rate_unhitched_multiplier
		animal.fatigue = clampf(animal.fatigue + fatigue_rate * hours, 0.0, 100.0)


func _count_hitched() -> int:
	var count := 0
	for animal in _animals:
		if animal.role == AnimalInstance.Role.HITCHED:
			count += 1
	return count


## Section 3.7 -- placeholder linear curve: 1.0x at hitch_target, scaling
## up to HITCH_SHORTFALL_MAX_MULTIPLIER at exactly hitch_minimum. Returns
## 1.0 flat whenever there's no vehicle, or hitch_target == hitch_minimum
## (nothing to scale between -- avoids a division by zero rather than
## asserting a vehicle type is authored wrong).
func _get_hitch_shortfall_multiplier() -> float:
	if _vehicle == null:
		return 1.0
	var vdef: VehicleDefinition = _vehicle_definitions.get(_vehicle.vehicle_type_id)
	if vdef == null or vdef.hitch_target <= vdef.hitch_minimum:
		return 1.0

	var hitched := _count_hitched()
	var shortfall_fraction := clampf(
		float(vdef.hitch_target - hitched) / float(vdef.hitch_target - vdef.hitch_minimum), 0.0, 1.0
	)
	return lerpf(1.0, HITCH_SHORTFALL_MAX_MULTIPLIER, shortfall_fraction)


# ---------------------------------------------------------------------------
# Speed modifier pull-hook (Section 4.7, 3.4)
# ---------------------------------------------------------------------------

## Registered with TravelSystem in _ready() above. Ignores `_coord` --
## the below-threshold speed debuff is a property of the vehicle's own
## condition, not of any particular hex, same reasoning Pace's own
## registered fatigue source already uses for ignoring the
## CharacterSheet parameter it's given. Returns an EMPTY array whenever
## there's no live vehicle or its condition is at/above the threshold --
## no neutral entry, since a fully healthy vehicle contributes NOTHING
## extra to speed (Section 3.4), unlike Pace's own always-present entry.
func _get_speed_modifier_entries(_coord: String) -> Array[ModifierEntry]:
	if _vehicle == null:
		return []
	var condition := _vehicle.get_condition(_vehicle_part_definitions)
	if condition >= BREAK_RISK_THRESHOLD:
		return []

	var entry := ModifierEntry.new()
	entry.targets = [TravelSystem.TRAVEL_SPEED_TARGET]
	entry.value = SPEED_DEBUFF_MULTIPLIER
	entry.type = ModifierEntry.Type.MULTIPLICATIVE
	entry.source_label = "Vehicle Condition"
	return [entry]


# ---------------------------------------------------------------------------
# Save / Load (Section 4.6)
# ---------------------------------------------------------------------------

## Duplicated on the way out, same reasoning as get_vehicle() above and
## TravelSystem.get_travel_state() -- SaveManager gets a snapshot, never
## a live reference it could desync from this system's own internal
## state.
func get_vehicle_for_save() -> VehicleInstance:
	return _vehicle.duplicate() if _vehicle != null else null


func get_animals_for_save() -> Array[AnimalInstance]:
	return get_animals()  # same duplication, already correct


func get_abandoned_vehicles_for_save() -> Dictionary:
	var out: Dictionary = {}
	for coord in _abandoned_vehicles:
		out[coord] = _abandoned_vehicles[coord].duplicate()
	return out


## Direct replace, same pattern as TravelSystem.load_travel_state() /
## PartyManager.load_roster() -- a load is a restore, not gameplay time
## actually passing, so this doesn't fire caravan_changed and doesn't
## re-derive anything; whatever was saved is trusted as-is.
func load_state(vehicle: VehicleInstance, animals: Array[AnimalInstance], abandoned_vehicles: Dictionary) -> void:
	_vehicle = vehicle.duplicate() if vehicle != null else null
	_animals.clear()
	for animal in animals:
		_animals.append(animal.duplicate())
	_abandoned_vehicles.clear()
	for coord in abandoned_vehicles:
		_abandoned_vehicles[coord] = abandoned_vehicles[coord].duplicate()
