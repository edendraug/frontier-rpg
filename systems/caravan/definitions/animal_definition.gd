class_name AnimalDefinition
extends Resource

## Defines one ownable animal type (e.g. "Ox", "Mule") -- shared,
## authored data. AnimalInstance (live, per-playthrough --
## systems/caravan/instances/animal_instance.gd) references one of these
## by animal_type_id rather than duplicating its stats. Meant to be
## authored as one .tres file per animal type under
## systems/caravan/data/animals/, discovered by CaravanSystem's own
## future directory scan (Phase 4) -- same convention as
## WorldRegistry._load_terrain_types(), not built in this file.
##
## Vehicles & Animals Design Doc v0.4, Section 3.8, 4.4.

@export var animal_type_id: String = ""

## Additive contribution to total party carry capacity while this
## animal's role is PACK (Design Doc v0.4, Section 4.8) -- summed
## alongside per-person carry and any owned vehicle's own
## base_carry_capacity, never an override, and no longer conditional on
## "no vehicle present" the way the retired override model implied.
@export var base_carry_capacity: float = 0.0

@export var can_hitch: bool = false

## Role-independent -- an animal needs to eat regardless of whether it's
## currently working, hitched, or resting (Section 3.8). Distinct from
## fatigue below, which IS role-dependent.
@export var hunger_drain_rate: float = 0.0

## Baseline drain while HITCHED, before hitch-shortfall scaling
## (Section 3.7) is applied on top of it.
@export var fatigue_drain_rate_hitched: float = 0.0

## Placeholder, expected < 1.0 -- applied to fatigue_drain_rate_hitched
## when role is PACK or UNASSIGNED (Section 3.8). An animal not
## currently pulling still accrues fatigue, just more slowly; it does
## NOT recover -- whether unhitched fatigue should ever actively reverse
## is Section 3.8's still-open Design Doc question (Section 10, Open
## Question 1), deliberately not assumed either way by this field.
@export var fatigue_drain_rate_unhitched_multiplier: float = 1.0

## The whole atlas texture (idle + a walk cycle, right-facing only --
## same mirrored-for-left-via-scale.x convention as walkers) -- same
## "authored data stays lightweight, one shared hand-built rig plays it"
## convention as SpriteSetDefinition.texture (systems/character/
## definitions/sprite_set_definition.gd) and CharacterController.tscn.
## Every animal type is expected to share ONE hand-authored
## AnimalVisualController.tscn (VisualRoot -> AnimationPlayer +
## BodySprite, mirroring CharacterController's shape exactly) with its
## own fixed frame layout; this field only swaps which atlas plays
## through that shared rig. Null degrades to a placeholder colored shape
## (Travel Ambient Scene doc Section 3.11). An animal rig is its own
## shared scene, separate from the vehicle rig and from
## CharacterController -- body proportions differ too much to share a
## single frame layout across all three.
@export var visual_atlas: Texture2D = null
