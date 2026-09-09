class_name HexInstance
extends Resource

## One placed hex on the overworld map. Entirely static/authored -- baked
## from the terrain/trail/river TileMapLayers plus the settlement/
## special-event sidecar by the EditorScript bake step (World Generation
## / Hex Data System design doc, Section 7). Not hand-created
## individually -- WorldRegistry loads one baked
## Dictionary[String, HexInstance], keyed by `coord`, produced by that
## bake step.
##
## No live/dynamic hex state exists yet (a washed-out bridge, a one-time
## landmark consumed) -- this is authored-only data for this pass. See
## Section 2.

## Axial "q,r" coordinate, e.g. "3,-2". Also the dictionary key in the
## baked map -- stored redundantly here for convenience when a
## HexInstance is passed around independently of the dictionary.
@export var coord: String = ""

## Reference into TerrainTypeDefinition.
@export var terrain_type_id: String = ""

@export var has_trail: bool = false

## Sparse list of direction indices (0-5, into WorldRegistry's
## AXIAL_DIRECTIONS ordering) where a river connects to that specific
## neighbor. Empty = no river on this hex. See design doc Section 3.5.
@export var river_edges: Array[int] = []

## Empty = none. Populated from the sidecar at bake time, not paintable.
@export var settlement_id: String = ""

## Hand-authored, guaranteed content tied to this specific hex --
## distinct from the terrain-keyed random event pool a future Event/
## Encounter system will roll against dynamically. Populated from the
## sidecar.
@export var special_event_ids: Array[String] = []

## Reserved knob for a future Event/Encounter system's per-hex event
## weighting -- not consumed by anything yet. Populated from the
## sidecar.
@export var event_frequency_multiplier: float = 1.0
