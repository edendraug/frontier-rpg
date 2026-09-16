class_name HexBakeConstants
extends RefCounted

## Shared between bake_hex_map.gd (an EditorScript) and
## world_map_authoring.gd (which runs a runtime mirror of the same
## graph-walk to resolve clicks) -- both MUST agree on these exact
## values, since a mismatch would silently resolve to the wrong hex
## rather than error, which is worse than a crash. Previously
## duplicated by hand in both files; consolidated here now that there
## are genuinely two real consumers instead of one hypothetical one.
##
## This is safe to share in a way AXIAL_DIRECTIONS (still duplicated
## separately, from WorldRegistry) is NOT: the constraint that kept
## these apart before was specifically about AUTOLOADS -- an
## EditorScript runs in the editor, not the live game, so autoloads
## like WorldRegistry aren't guaranteed to exist in that context. A
## plain class_name script with no autoload registration has no such
## restriction; it's just a class definition, available everywhere
## including editor tooling. That's the whole reason this file can
## exist where WorldRegistry.AXIAL_DIRECTIONS couldn't simply be
## imported instead.
##
## Never instantiate this -- referenced only as HexBakeConstants.X.
##
## Empirically confirmed against the real TileSet during the bake
## step's original implementation (pointy-top, per Cameron's art --
## flat-top was the original working assumption and was corrected). See
## World Generation Design Doc v0.3, Section 7. Not derived from
## documentation; verified via a diagnostic script against the actual
## painted TileSet.

## The hex painted at Godot's native offset (0,0) is always assigned
## axial "0,0" -- a fixed anchor rather than "whichever cell a walk
## happens to start from," so re-baking never shifts existing
## coordinates. Confirmed with Cameron: a hex is always kept painted
## here.
const ANCHOR_OFFSET := Vector2i(0, 0)

## A fixed, arbitrary-but-consistent pairing with WorldRegistry's own
## AXIAL_DIRECTIONS index order -- what matters is that every consumer
## agrees on the pairing, not that any particular pairing is "the"
## natural one.
const CELL_NEIGHBOR_BY_AXIAL_INDEX := [
	TileSet.CELL_NEIGHBOR_RIGHT_SIDE,        # index 0 -- AXIAL_DIRECTIONS[0] (1,0)  E
	TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE,    # index 1 -- AXIAL_DIRECTIONS[1] (1,-1) NE
	TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE,     # index 2 -- AXIAL_DIRECTIONS[2] (0,-1) NW
	TileSet.CELL_NEIGHBOR_LEFT_SIDE,         # index 3 -- AXIAL_DIRECTIONS[3] (-1,0) W
	TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE,  # index 4 -- AXIAL_DIRECTIONS[4] (-1,1) SW
	TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE, # index 5 -- AXIAL_DIRECTIONS[5] (0,1)  SE
]
