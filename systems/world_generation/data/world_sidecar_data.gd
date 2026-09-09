class_name WorldSidecarData
extends Resource

## Wrapper so every WorldSidecarEntry can be authored in one
## Inspector-editable Resource file rather than one file per
## settlement/special event. Same role HexMapData plays for the baked
## hex map -- Godot needs a Resource subclass to hold the collection,
## a bare Array can't be its own .tres file. Authoring-time input to
## the bake step (design doc Section 4.3), never read at runtime.
##
## NOT specified in the design doc -- Section 4.3 describes the
## sidecar as "a small, separately Inspector-editable Resource"
## holding "an array of entries" but doesn't name the wrapper, same
## gap HexMapData filled for the baked hex map. Flag if a different
## shape/name is wanted.

@export var entries: Array[WorldSidecarEntry] = []
