class_name HexPromptSource
extends Resource

## Reserved, deliberately minimal seam -- NOT an attempt at "any hex
## content can plug into the arrival flow" framework. Carries only the
## two fields ExpeditionSceneRouter's sort/prompt logic actually needs
## (_on_hex_entered()'s sort_custom, _show_next_prompt()'s setup()
## call). LocationSceneDefinition (systems/expedition/data/
## location_scene_definition.gd) extends this instead of declaring
## these two fields itself; AbandonedVehiclePromptEntry
## (systems/caravan/abandoned_vehicle_prompt_entry.gd) also extends it
## and needs nothing beyond them. A future scene-generation system
## (dynamically building local scenes from hex data -- events, camps,
## abandoned vehicles, and whatever else needs a hex-arrival prompt)
## may want to grow this into a real polymorphic contract -- e.g. a
## virtual on_approach() hook so the router stops branching on concrete
## type -- once that system is actually designed against more than
## today's one non-catalog use case. Not attempted here.
##
## Vehicles & Animals Design Doc v0.4, Section 4.9.

## Sentinel meaning "not meaningfully closer to any one side of this
## hex" -- fixed at exactly the same halfway time-cost fraction the
## existing hex-crossing model already assumes for a hex's center (see
## ExpeditionSceneRouter._sector_fraction()). Moved here from
## LocationSceneDefinition (which used to declare it directly) now that
## AbandonedVehiclePromptEntry needs the same sentinel with the same
## meaning. LocationSceneDefinition.CENTER_SECTOR still resolves
## correctly everywhere it's already referenced -- GDScript subclasses
## inherit their parent's constants.
const CENTER_SECTOR := -1

## Player-facing name -- used in arrival prompts ("You see X up
## ahead...") and, for a LocationSceneDefinition, the debug menu's
## in-hex location list.
@export var display_name: String = ""

## One of a hex's six sides -- WorldRegistry.AXIAL_DIRECTIONS index
## (0-5) -- or CENTER_SECTOR. Drives nearest-first prompt ordering
## (ExpeditionSceneRouter._on_hex_entered()'s sort_custom) when multiple
## prompt sources share a hex, and, for a LocationSceneDefinition, an
## approximate in-hex travel-time cost too (_sector_distance()/
## _sector_fraction()). Placeholder/approximate by design -- doesn't
## model a hex's real geometry, only "closer to the entry edge costs
## less."
@export var hex_sector: int = CENTER_SECTOR
