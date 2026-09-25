class_name AnimalInstance
extends Resource

## Live, per-playthrough animal state -- the Instance half of the
## Definition/Instance split (AnimalDefinition, systems/caravan/
## definitions/animal_definition.gd). Resource-based so it round-trips
## through GameSaveData like every other live save-persisted state in
## this project. Deliberately NOT routed through VitalsSystem/
## CharacterSheet (Section 3.8) -- hunger/fatigue only, no Morale, no
## Condition tier, no injuries/diseases.
##
## Vehicles & Animals Design Doc v0.4, Section 3.8, 4.5.

enum Role { UNASSIGNED, PACK, HITCHED }

## Stable per-instance id -- distinguishes two animals of the same
## animal_type_id from each other (e.g. two Oxen), same reason
## CharacterSheet identifies individuals separately from their shared
## occupation_id/sprite_id.
@export var animal_id: String = ""

@export var animal_type_id: String = ""

@export_range(0.0, 100.0) var hunger: float = 100.0   # 100 = fully fed, matching CharacterSheet's convention
@export_range(0.0, 100.0) var fatigue: float = 0.0     # 0 = fully rested, matching CharacterSheet's convention

@export var role: Role = Role.UNASSIGNED

## Only meaningful when role == HITCHED (Section 4.5) -- which vehicle
## this animal is currently pulling. set_role() below keeps this
## invariant enforced rather than relying on every caller to remember
## to clear it.
@export var hitched_vehicle_id: String = ""


## Single entry point for changing role -- enforces the "hitched_vehicle_id
## only meaningful when HITCHED" invariant in one place rather than
## leaving every call site responsible for clearing it. `vehicle_id` is
## ignored (and hitched_vehicle_id cleared to "") for any role other than
## HITCHED, including a caller passing one by mistake. Used directly by
## CaravanSystem's abandon flow (Section 3.6/5.3) to revert a HITCHED
## animal to PACK -- set_role(Role.PACK) alone is sufficient; the id
## clears itself.
func set_role(new_role: Role, vehicle_id: String = "") -> void:
	role = new_role
	hitched_vehicle_id = vehicle_id if new_role == Role.HITCHED else ""
