class_name VehiclePartDefinition
extends Resource

## Defines one pooled vehicle part slot (Wheels, Axle, Tongue at launch)
## -- shared, authored data referenced by id from VehicleDefinition.part_ids
## (systems/caravan/definitions/vehicle_definition.gd) and tracked per-
## instance in VehicleInstance.part_durability. Pooled per named slot, not
## per physical unit -- a wagon has four wheels, but "Wheels" is one
## trackable part, not four. Meant to be authored as one .tres file per
## part under systems/caravan/data/vehicle_parts/, discovered by
## CaravanSystem's own future directory scan (Phase 4) -- same
## DirAccess-scan convention as WorldRegistry._load_terrain_types() and
## CharacterDataRegistry._load_all(), not built in this file.
##
## Vehicles & Animals Design Doc v0.4, Section 3.2, 4.1.

@export var part_id: String = ""
@export var max_durability: float = 0.0

## Random-variant flavor text shown when this part breaks (e.g. "You
## hear a loud snap and the wagon jolts. Looks like a wheel has
## broken."), one picked at random by CaravanSystem the moment this
## part hits 0% durability -- same "author several variants, roll an
## int, display the corresponding string" pattern as
## DialogueLineNode.pick_variant_index() already uses for line variety,
## just simpler (no last-index-avoidance needed for a one-off event like
## a breakdown, unlike a line a player might hear repeatedly). Empty is
## fine -- CaravanSystem falls back to a generic message rather than
## requiring every part to have flavor text authored before it can
## break at all.
@export var break_messages: Array[String] = []

## Placeholder, default 1.0 -- lets e.g. Wheels be authored to wear
## faster than Axle on rough terrain without a code change (Section 3.4).
## Every number in this project's placeholder tables is flagged as such
## rather than presented as considered; this one is no exception.
@export var wear_rate_multiplier: float = 1.0

## Reserved seam, currently moot -- every launch part is critical
## (Section 3.2): any one reaching 0% durability halts the vehicle
## regardless of this flag's value. The earlier idea of a non-critical
## part (a canvas cover, implying weather mechanics) was considered and
## dropped as out of scope for this game, but the field stays cheap to
## keep now rather than retrofit onto every existing part later if a
## genuinely non-critical part is ever added.
@export var is_critical: bool = true
