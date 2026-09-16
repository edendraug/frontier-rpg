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
## Also exposes get_axial_coord()/get_axial_coord_at_local()/
## get_axial_coord_at_mouse() below, for resolving a click on the
## rendered map to a real WorldRegistry coord string, and
## get_hex_center()/get_shared_edge_midpoint() for the reverse
## direction -- turning a coord back into a real pixel position, for a
## Travel-side overlay to draw against. See HexBakeConstants
## (hex_bake_constants.gd) for the offset<->axial mapping these share
## with bake_hex_map.gd.

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


## ANCHOR_OFFSET and CELL_NEIGHBOR_BY_AXIAL_INDEX now live in
## HexBakeConstants (hex_bake_constants.gd), shared with
## bake_hex_map.gd's own graph-walk -- previously duplicated by hand in
## both files. See that file's own comment for why sharing these two
## specifically (unlike AXIAL_DIRECTIONS, still duplicated separately)
## is safe. If the bake step's empirically-confirmed CellNeighbor
## mapping or anchor cell ever changes, it changes there and both
## consumers pick it up automatically -- no second file to remember.

## offset (Vector2i) -> axial q,r (Vector2i), and its reverse, axial
## "q,r" (String) -> offset (Vector2i) -- both built in the SAME walk
## by _build_axial_lookup() below, since computing one is already
## computing the other. The reverse direction is what get_hex_center()
## needs: given an axial coord, find its real pixel position via the
## offset cell map_to_local() actually understands. Built once, lazily
## -- not in _ready(), so opening/editing this scene directly, or
## embedding it somewhere that only ever calls get_content_bounds(),
## never pays to build a lookup nothing asked for.
var _axial_by_offset: Dictionary = {}
var _offset_by_coord: Dictionary = {}
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


## GLOBAL 2D position of the center of the hex at `coord` -- the exact
## inverse direction of get_axial_coord(). Deliberately GLOBAL, not
## local to this scene: a caller drawing this (e.g. a Travel-side
## overlay, which is a SEPARATE sibling node, not this one) would
## otherwise need this scene's position/scale/rotation to exactly match
## its own for the result to land in the right place -- fragile, and
## exactly the bug this fixes. to_global() makes the result correct
## regardless of either node's transform; the caller converts back via
## to_local() on ITSELF before drawing. Returns Vector2.INF (not
## Vector2.ZERO -- a hex really could be centered near world origin, so
## ZERO isn't a safe "not found" signal) for a coord with no
## corresponding painted hex.
func get_hex_center(coord: String) -> Vector2:
	if not _axial_lookup_built:
		_build_axial_lookup()
	if not _offset_by_coord.has(coord):
		return Vector2.INF
	return %TerrainLayer.to_global(%TerrainLayer.map_to_local(_offset_by_coord[coord]))


## GLOBAL 2D midpoint of the shared edge between two ADJACENT hexes --
## geometrically just the midpoint between their two (now global)
## centers, true for any regular hex grid regardless of orientation, so
## no separate edge-geometry math is needed beyond get_hex_center()
## above. Trusts the caller that `coord`/`neighbor_coord` are actually
## adjacent -- doesn't verify via WorldRegistry.get_direction_index()
## itself, since every real caller (TravelSystem's visited_hex_path/
## queued_route sequences) is adjacent by construction already; a
## non-adjacent pair would silently produce a geometrically meaningless
## but plausible-looking point rather than an error. Returns
## Vector2.INF if either coord has no corresponding painted hex.
func get_shared_edge_midpoint(coord: String, neighbor_coord: String) -> Vector2:
	var a := get_hex_center(coord)
	var b := get_hex_center(neighbor_coord)
	if a == Vector2.INF or b == Vector2.INF:
		return Vector2.INF
	return (a + b) / 2.0


## Runtime mirror of bake_hex_map.gd's Pass 1 graph-walk -- see that
## script for the full reasoning behind walking via
## get_neighbor_cell() rather than a coordinate-conversion formula.
## Deliberately walks %TerrainLayer itself rather than trusting
## WorldRegistry's already-baked data -- the whole point is confirming
## what's actually painted right now, on the very layer a click just
## hit, rather than silently trusting a bake that might be stale.
func _build_axial_lookup() -> void:
	_axial_lookup_built = true
	if %TerrainLayer.get_cell_source_id(HexBakeConstants.ANCHOR_OFFSET) == -1:
		push_warning("WorldMapAuthoring: no terrain painted at anchor cell %s -- click resolution will find nothing" % HexBakeConstants.ANCHOR_OFFSET)
		return

	_axial_by_offset[HexBakeConstants.ANCHOR_OFFSET] = Vector2i.ZERO
	_offset_by_coord["0,0"] = HexBakeConstants.ANCHOR_OFFSET
	var queue: Array[Vector2i] = [HexBakeConstants.ANCHOR_OFFSET]
	while not queue.is_empty():
		var current_offset: Vector2i = queue.pop_front()
		var current_axial: Vector2i = _axial_by_offset[current_offset]

		for i in 6:
			var neighbor_offset: Vector2i = %TerrainLayer.get_neighbor_cell(current_offset, HexBakeConstants.CELL_NEIGHBOR_BY_AXIAL_INDEX[i])
			if %TerrainLayer.get_cell_source_id(neighbor_offset) == -1:
				continue
			if _axial_by_offset.has(neighbor_offset):
				continue
			var neighbor_axial: Vector2i = current_axial + WorldRegistry.AXIAL_DIRECTIONS[i]
			_axial_by_offset[neighbor_offset] = neighbor_axial
			_offset_by_coord["%d,%d" % [neighbor_axial.x, neighbor_axial.y]] = neighbor_offset
			queue.append(neighbor_offset)
