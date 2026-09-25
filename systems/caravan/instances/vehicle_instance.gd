class_name VehicleInstance
extends Resource

## Live, per-playthrough vehicle state -- the Instance half of the
## Definition/Instance split (VehicleDefinition, systems/caravan/
## definitions/vehicle_definition.gd), same convention as
## TerrainTypeDefinition/HexInstance and ActorDefinition/CharacterSheet.
## Resource-based so it round-trips through GameSaveData like every
## other live save-persisted state in this project (TravelState,
## CharacterSheet). Doubles as the abandoned-vehicle snapshot
## (CaravanSystem.abandoned_vehicles, Section 4.6) -- abandoning takes
## no special copy step beyond what CaravanSystem itself does (Section
## 5.3), since nothing here is live-reference state that would need
## detaching.
##
## Vehicles & Animals Design Doc v0.4, Section 4.3.

@export var vehicle_type_id: String = ""

## part_id (matches VehiclePartDefinition.part_id, listed in
## VehicleDefinition.part_ids) -> current durability. Absolute units
## matching VehiclePartDefinition.max_durability, NOT a 0.0-1.0
## fraction -- get_condition() below derives the fraction; this is the
## real number CaravanSystem's decay tick (Section 5.1) subtracts from
## directly.
@export var part_durability: Dictionary = {}  # String (part_id) -> float

## Only meaningful while this instance sits in
## CaravanSystem.abandoned_vehicles (Section 4.6) -- unused, and
## meaningless, during live ownership. The party's in-hex position at
## the moment of abandonment (Design Doc v0.4 follow-up, Section 4.9's
## rediscovery work), one of WorldRegistry.AXIAL_DIRECTIONS' six sector
## indices or LocationSceneDefinition.CENTER_SECTOR -- resolved by
## whoever calls abandon (CaravanSystem, via
## ExpeditionSceneRouter.get_current_position_sector()), not computed
## here. Defaults to CENTER_SECTOR rather than -2/unset, since an
## instance that's never been abandoned has no wrong answer to give if
## something reads this prematurely.
@export var hex_sector: int = LocationSceneDefinition.CENTER_SECTOR


## Reserved stub, Section 5.4 -- no caller exists yet. Restores
## durability toward part_def.max_durability, clamped there; actual
## resolution (a Repair assignment, a skill check, a resource cost) is
## Assignment System's future job. `amount` is an absolute durability
## amount, same units as part_durability above, NOT a fraction.
## part_def is caller-resolved (same "caller looks it up once, this
## just applies the number" posture as CharacterController.setup()
## taking an already-resolved body_texture) -- this instance holds no
## registry/definitions reference of its own.
func repair_part(part_id: String, amount: float, part_def: VehiclePartDefinition) -> void:
	if not part_durability.has(part_id):
		push_warning("VehicleInstance: repair_part() called for unknown part_id '%s'" % part_id)
		return
	part_durability[part_id] = minf(part_durability[part_id] + amount, part_def.max_durability)


## Condition is derived, never stored (Section 3.3) -- the MINIMUM of
## every tracked part's current/max ratio, not an average: the vehicle
## is only as sound as its weakest part. `part_defs` is the caller-
## resolved part_id -> VehiclePartDefinition map (CaravanSystem's own
## loaded definitions, Section 4.1) -- same caller-resolves posture as
## repair_part() above; this instance holds no registry reference.
## A part_id present in part_durability but missing from part_defs (or
## an unset/zero max_durability) is skipped rather than treated as 0%
## -- a data problem worth its own warning elsewhere, not something
## that should silently zero out the whole vehicle's readout. Returns
## 1.0 (full) for a vehicle with no trackable parts resolved at all --
## defensive only; shouldn't happen for a real vehicle type with a
## non-empty part_ids.
func get_condition(part_defs: Dictionary) -> float:  # String (part_id) -> VehiclePartDefinition
	var lowest := 1.0
	var found_any := false
	for part_id in part_durability:
		var def: VehiclePartDefinition = part_defs.get(part_id)
		if def == null or def.max_durability <= 0.0:
			continue
		found_any = true
		var ratio: float = part_durability[part_id] / def.max_durability
		lowest = minf(lowest, ratio)
	return lowest if found_any else 1.0


## Derived -- false the instant any TRACKED part sits at exactly 0.0
## durability (Section 3.4/3.5's full-stop rule). No part_defs needed
## here, unlike get_condition() -- 0.0 is 0.0 regardless of a part's
## max_durability.
func is_operable() -> bool:
	for part_id in part_durability:
		if part_durability[part_id] <= 0.0:
			return false
	return true
