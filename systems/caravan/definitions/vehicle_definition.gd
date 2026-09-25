class_name VehicleDefinition
extends Resource

## Defines one ownable vehicle type (e.g. "Covered Wagon") -- shared,
## authored data. VehicleInstance (live, per-playthrough --
## systems/caravan/instances/vehicle_instance.gd) references one of
## these by vehicle_type_id rather than duplicating its stats. Meant to
## be authored as one .tres file per vehicle type under
## systems/caravan/data/vehicles/, discovered by CaravanSystem's own
## future directory scan (Phase 4) -- same convention as
## WorldRegistry._load_terrain_types(), not built in this file.
##
## Vehicles & Animals Design Doc v0.4, Section 4.2.

@export var vehicle_type_id: String = ""

## New this phase (Section 4.9/5.2) -- player-facing name for this
## vehicle type, used to build an abandoned-vehicle rediscovery prompt's
## text ("Abandoned <display_name>"). Not part of the original v0.4
## field list; added once ExpeditionSceneRouter's arrival prompt needed
## real text rather than a generic placeholder string.
@export var display_name: String = ""

## Additive contribution to total party carry capacity while this
## vehicle is owned (Design Doc v0.4, Section 4.8) -- summed with
## per-person carry and any PACK-role animals' own base_carry_capacity,
## never an override. The prior override-based InventorySystem model
## (a vehicle replacing per-person carry entirely) was retired this
## revision; this field's meaning changed accordingly even though its
## name didn't.
@export var base_carry_capacity: float = 0.0

## References into VehiclePartDefinition.part_id -- e.g. ["wheels",
## "axle", "tongue"] at launch (Section 3.2). Not hardcoded to exactly
## three parts so a future vehicle type could be authored with a
## different part set without a code change.
@export var part_ids: Array[String] = []

## Below this many hitched animals, the vehicle cannot move at all --
## same functional state as a breakdown (Section 3.7).
@export var hitch_minimum: int = 0

## Also functions as the CAP -- a vehicle never benefits from more
## animals hitched than this, and animals beyond it are simply not
## eligible to hitch to it in the first place (Section 3.7).
@export var hitch_target: int = 0

## The whole atlas texture (idle + whatever animation states a vehicle
## actually needs -- e.g. a rolling-wheels clip) -- same "authored data
## stays lightweight, one shared hand-built rig plays it" convention as
## SpriteSetDefinition.texture (systems/character/definitions/
## sprite_set_definition.gd) and CharacterController.tscn. Every vehicle
## type is expected to share ONE hand-authored VehicleVisualController.tscn
## (VisualRoot -> AnimationPlayer + BodySprite, mirroring
## CharacterController's shape exactly) with its own fixed frame layout;
## this field only swaps which atlas plays through that shared rig. Null
## degrades to a placeholder colored shape (Travel Ambient Scene doc
## Section 3.11), same as DressingProp/DressingStrip. A vehicle rig is
## its own shared scene, separate from the animal rig below and from
## CharacterController -- body proportions differ too much to share a
## single frame layout across all three.
@export var visual_atlas: Texture2D = null
