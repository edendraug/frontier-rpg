class_name WorldMapAuthoring
extends Node2D

## Attach to world_map_authoring.tscn's own root node. The scene stays
## exactly what it always was -- three hand-painted TileMapLayers, no
## runtime behavior of its own -- this only ADDS one query method,
## get_content_bounds() below, used by whatever embeds this scene to
## know its real pixel-space size and position it correctly (e.g. a
## SubViewport that needs to shift negative-coordinate content into
## view). Deliberately has no _ready()/_process() and does nothing
## unless something calls get_content_bounds() explicitly -- opening
## and editing this scene directly in the 2D editor is completely
## unaffected.
##
## Lives here (on this scene's own root) rather than on whatever embeds
## it, since the bounds are intrinsic to what's actually painted on
## these TileMapLayers -- useful to any future embedding context
## (Expedition Hub's panel today, a possible full-screen World Map view
## later), not specific to one particular UI panel.
##
## Also exposes get_axial_coord()/get_axial_coord_at_local() below, for
## resolving a click on the rendered map to a real WorldRegistry coord
## string -- see their own comments for why the offset<->axial mapping
## is duplicated from bake_hex_map.gd rather than shared.

## Computes the real pixel-space bounding box of every painted terrain
## cell. %TerrainLayer is treated as the authoritative "whole map"
## extent -- %TrailLayer/%RiverLayer are sparse overlays painted only
## where a trail/river actually exists, a strict subset of Terrain's
## footprint, not a further-out boundary.
##
## Iterates every used cell rather than trusting get_used_rect()'s own
## rectangle corners -- for a hex TileSet, a cell-space rectangle
## doesn't correspond to an axis-aligned pixel rectangle once hex skew
## is accounted for. map_to_local() is what actually understands that
## geometry correctly for whatever hex layout this TileSet is
## configured with, so this defers to it entirely rather than
## reimplementing any hex math here.
##
## Returns a zero-size Rect2 if nothing is painted yet -- permissive,
## matching this project's usual handling of missing/unauthored data;
## the caller decides what an empty map means for it.
func get_content_bounds() -> Rect2:
	var cells: Array[Vector2i] = %TerrainLayer.get_used_cells()
	if cells.is_empty():
		return Rect2()

	var min_pos: Vector2 = %TerrainLayer.map_to_local(cells[0])
	var max_pos := min_pos
	for cell in cells:
		var pos: Vector2 = %TerrainLayer.map_to_local(cell)
		min_pos = min_pos.min(pos)
		max_pos = max_pos.max(pos)

	# map_to_local() gives each cell's CENTER, not its bounding box, so
	# pad by half a tile in every direction -- otherwise the outermost
	# ring of hexes would render half-clipped against these bounds.
	var padding: Vector2 = Vector2(%TerrainLayer.tile_set.tile_size) * 0.5
	return Rect2(min_pos - padding, (max_pos - min_pos) + padding * 2.0)


## ANCHOR_OFFSET and CELL_NEIGHBOR_BY_AXIAL_INDEX are duplicated
## VERBATIM from bake_hex_map.gd, for the identical reason that script
## gives for duplicating AXIAL_DIRECTIONS from WorldRegistry: an
## EditorScript can't depend on this file existing, so the values have
## to live in both places. If the bake step's empirically-confirmed
## CellNeighbor mapping or anchor cell ever changes, THIS must change
## to match, or clicks will silently resolve to the wrong hex --
## silently, because a wrong-but-valid-looking coordinate string is a
## far worse failure mode than a crash. AXIAL_DIRECTIONS itself is NOT
## duplicated a third time here -- this script runs in the live game,
## where WorldRegistry is always a real autoload, so _build_axial_lookup()
## below reads WorldRegistry.AXIAL_DIRECTIONS directly instead.
const ANCHOR_OFFSET := Vector2i(0, 0)
const CELL_NEIGHBOR_BY_AXIAL_INDEX := [
	TileSet.CELL_NEIGHBOR_RIGHT_SIDE,
	TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE,
	TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE,
	TileSet.CELL_NEIGHBOR_LEFT_SIDE,
	TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE,
	TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE,
]

## offset (Vector2i) -> axial q,r (Vector2i). Built once, lazily -- see
## _build_axial_lookup() -- not in _ready(), so opening/editing this
## scene directly, or embedding it somewhere that only ever calls
## get_content_bounds(), never pays to build a lookup nothing asked for.
var _axial_by_offset: Dictionary = {}
var _axial_lookup_built := false


## Resolves a native offset cell (e.g. from TileMapLayer.local_to_map()
## on a click) to the axial "q,r" coordinate string WorldRegistry/
## TravelSystem actually use. Returns "" for an offset with no
## corresponding baked hex -- unpainted, or painted but disconnected
## from the anchor (mirrors bake_hex_map.gd's own "unreachable" case).
func get_axial_coord(offset: Vector2i) -> String:
	if not _axial_lookup_built:
		_build_axial_lookup()
	if not _axial_by_offset.has(offset):
		return ""
	var axial: Vector2i = _axial_by_offset[offset]
	return "%d,%d" % [axial.x, axial.y]


## Convenience wrapper for the common case -- a caller with a click
## position in THIS scene's own local 2D space (i.e. %TerrainLayer's
## coordinate system) can resolve straight to a coord string without
## needing to know local_to_map() exists. Whatever embeds this scene
## (travel_map_panel.gd) is responsible for getting a click into that
## local space in the first place -- this method doesn't know or care
## whether it's sitting in a SubViewport, behind a Camera2D, or neither.
func get_axial_coord_at_local(local_pos: Vector2) -> String:
	var offset: Vector2i = %TerrainLayer.local_to_map(local_pos)
	return get_axial_coord(offset)


## Resolves whatever the mouse is CURRENTLY positioned over to an axial
## coord. Uses get_local_mouse_position() (inherited from CanvasItem),
## NOT Viewport.get_mouse_position() -- the two are easy to conflate but
## are NOT the same thing: get_mouse_position() returns raw
## screen/viewport pixels, ignoring whatever camera transform is
## currently active, while get_local_mouse_position() correctly inverts
## the full transform chain (including an active Camera2D's pan/zoom)
## to give a genuinely correct local position. Confirmed the hard way --
## an earlier version of travel_map_panel.gd used
## Viewport.get_mouse_position() directly and only happened to resolve
## correctly near the camera's untransformed origin, missing everywhere
## the camera had actually panned or zoomed to. Consolidating the fix
## here, rather than just patching that one caller, so nothing else
## needing mouse-to-hex resolution later can make the same mistake.
func get_axial_coord_at_mouse() -> String:
	return get_axial_coord_at_local(get_local_mouse_position())


## Runtime mirror of bake_hex_map.gd's Pass 1 graph-walk -- see that
## script for the full reasoning behind walking via
## get_neighbor_cell() rather than a coordinate-conversion formula.
## Deliberately walks %TerrainLayer itself rather than trusting
## WorldRegistry's already-baked data -- the whole point is confirming
## what's actually painted right now, on the very layer a click just
## hit, rather than silently trusting a bake that might be stale.
func _build_axial_lookup() -> void:
	_axial_lookup_built = true
	if %TerrainLayer.get_cell_source_id(ANCHOR_OFFSET) == -1:
		push_warning("WorldMapAuthoring: no terrain painted at anchor cell %s -- click resolution will find nothing" % ANCHOR_OFFSET)
		return

	_axial_by_offset[ANCHOR_OFFSET] = Vector2i.ZERO
	var queue: Array[Vector2i] = [ANCHOR_OFFSET]
	while not queue.is_empty():
		var current_offset: Vector2i = queue.pop_front()
		var current_axial: Vector2i = _axial_by_offset[current_offset]

		for i in 6:
			var neighbor_offset: Vector2i = %TerrainLayer.get_neighbor_cell(current_offset, CELL_NEIGHBOR_BY_AXIAL_INDEX[i])
			if %TerrainLayer.get_cell_source_id(neighbor_offset) == -1:
				continue
			if _axial_by_offset.has(neighbor_offset):
				continue
			_axial_by_offset[neighbor_offset] = current_axial + WorldRegistry.AXIAL_DIRECTIONS[i]
			queue.append(neighbor_offset)
