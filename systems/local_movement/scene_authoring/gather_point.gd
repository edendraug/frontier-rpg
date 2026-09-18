class_name GatherPoint
extends Node2D

## Marks a scene's single staging position (Local Movement Design
## Doc, Section 3.9/4.4) — where the party spawns on scene entry.
## Position-only, hand-placed in the editor as a plain node marked
## unique-in-owner ("%GatherPoint") so LocalSceneRoot can find it.
##
## Its cell is resolved automatically via
## LocalGrid.get_coord_at_global_position() at scene setup time,
## rather than hand-typed as an axial coordinate string the way the
## design doc originally proposed (written before that reverse lookup
## existed) — place the node where you want it, the cell follows.
##
## No script logic of its own. This class exists mainly so a
## GatherPoint reads clearly in the Scene panel and so LocalSceneRoot
## (or anything else) can type-check for it if that's ever useful --
## today it's just a positioned marker.
