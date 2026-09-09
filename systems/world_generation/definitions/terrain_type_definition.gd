class_name TerrainTypeDefinition
extends Resource

## Defines one of the six terrain types a HexInstance can reference by id
## (Grassland, Forest, Swamp, Desert, Mountain, Lake). Shared, not
## per-hex -- HexInstance.terrain_type_id points at one of these rather
## than duplicating travel/hazard data on every hex. Meant to be authored
## as a .tres data file per terrain type (e.g. grassland.tres).
##
## base_travel_minutes and hazard_level are baselines only. What actually
## consumes them -- wagon wear, injury odds, effective travel time once
## pace/weather/morale modifiers are stacked on -- is Travel/Assignment's
## future job via the Modifier System, not decided here. See World
## Generation / Hex Data System design doc, Section 3.3.

@export var terrain_type_id: String = ""
@export var display_name: String = ""

## Baseline minutes at Normal pace, no modifiers applied. Minutes, not
## hours, to match TimeSystem's minute-resolution clock.
@export var base_travel_minutes: int = 0

## Unitless, deliberately generic -- meant to drive a multitude of future
## things (wagon wear, injury odds), not one single fixed formula.
@export var hazard_level: float = 0.0

## true for every type except Lake. Read via WorldRegistry.is_passable(),
## not hardcoded per-terrain in consuming code -- a future impassable
## type (Cliffs, a Ravine) is then a data flip, not a code change.
@export var is_passable: bool = true
