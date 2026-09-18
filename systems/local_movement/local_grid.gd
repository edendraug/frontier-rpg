class_name LocalGrid
extends RefCounted

## Scene-local hex grid — geometry, occupancy, and pathfinding.
## Built fresh at scene load from a scene's own two painted
## TileMapLayers; nothing here persists between scene loads (Local
## Movement Design Doc, Section 3.3).
##
## Two-layer model, confirmed with Cameron:
##   TerrainLayer  — the room's walkable floor footprint. Anchors the
##                    graph-walk, same role as the overworld's terrain
##                    layer.
##   ObstacleLayer — sparse overlay. A painted cell here is a floor
##                    cell that's blocked (a crate, a wall segment
##                    standing inside the room's bounds).
##
## Reuses HexBakeConstants' CellNeighbor<->axial pairing and
## WorldRegistry.AXIAL_DIRECTIONS — safe because HexBakeConstants is a
## plain class_name (not autoload-bound), PROVIDED this scene's TileSet
## is configured with the same orientation/offset settings as the
## overworld's. If that's ever not true, this mapping needs its own
## empirically-confirmed constants, same as the original bake step
## needed.
##
## Phase 1b adds occupancy + pathfinding on top of Phase 1a's pure
## geometry. Occupancy is keyed by an arbitrary Variant token rather
## than hardcoding CharacterSheet (Design Doc Section 4.1's stated
## shape) — LocalGrid doesn't need to know what a "character" is, only
## that a cell is or isn't free. The real controller (Phase 2) will
## pass its own CharacterSheet in as that token; the dummy tester below
## uses plain Strings.
##
## Pathfinding is plain BFS, not Dijkstra/A* — every walkable,
## unoccupied cell costs the same to enter (unlike the overworld's
## terrain-weighted travel time), so uniform-cost search is sufficient.
## Graceful mid-traversal re-planning and "path to nearest reachable
## neighbor if the goal itself is unreachable" (Design Doc Section 3.5,
## steps 2-4) are Movement/Actor-layer orchestration, not built here —
## find_path() only ever answers "is there a path right now," and
## leaves what to do with "no" to whatever calls it.

var _offset_by_coord: Dictionary = {}   # String "q,r" -> Vector2i (offset)
var _coord_by_offset: Dictionary = {}   # Vector2i (offset) -> String "q,r"
var _walkable: Dictionary = {}          # String "q,r" -> bool
var _occupants: Dictionary = {}         # String "q,r" -> Variant (occupant token)

## Kept for get_world_position()/get_coord_at_global_position() (Phase
## 2's click-to-move support) — LocalGrid is the single source for
## coord<->position conversion now, so callers (CharacterController,
## click handlers) don't each need their own TileMapLayer reference.
var _terrain_layer: TileMapLayer


func _init(terrain_layer: TileMapLayer, obstacle_layer: TileMapLayer) -> void:
	_terrain_layer = terrain_layer
	_build(terrain_layer, obstacle_layer)


## Same graph-walk shape as WorldMapAuthoring._build_axial_lookup() /
## bake_hex_map.gd's Pass 1 — walks via get_neighbor_cell() from a
## fixed anchor rather than a coordinate-conversion formula, so this
## works correctly regardless of the TileSet's exact layout config.
func _build(terrain_layer: TileMapLayer, obstacle_layer: TileMapLayer) -> void:
	if terrain_layer.get_cell_source_id(HexBakeConstants.ANCHOR_OFFSET) == -1:
		push_warning("LocalGrid: no floor painted at anchor cell %s -- grid will be empty" % HexBakeConstants.ANCHOR_OFFSET)
		return

	var axial_by_offset: Dictionary = {HexBakeConstants.ANCHOR_OFFSET: Vector2i.ZERO}
	_register_cell(Vector2i.ZERO, HexBakeConstants.ANCHOR_OFFSET, obstacle_layer)

	var queue: Array[Vector2i] = [HexBakeConstants.ANCHOR_OFFSET]
	while not queue.is_empty():
		var current_offset: Vector2i = queue.pop_front()
		var current_axial: Vector2i = axial_by_offset[current_offset]

		for i in 6:
			var neighbor_offset: Vector2i = terrain_layer.get_neighbor_cell(
				current_offset, HexBakeConstants.CELL_NEIGHBOR_BY_AXIAL_INDEX[i]
			)
			if terrain_layer.get_cell_source_id(neighbor_offset) == -1:
				continue
			if axial_by_offset.has(neighbor_offset):
				continue

			var neighbor_axial: Vector2i = current_axial + WorldRegistry.AXIAL_DIRECTIONS[i]
			axial_by_offset[neighbor_offset] = neighbor_axial
			_register_cell(neighbor_axial, neighbor_offset, obstacle_layer)
			queue.append(neighbor_offset)


func _register_cell(axial: Vector2i, offset: Vector2i, obstacle_layer: TileMapLayer) -> void:
	var coord := "%d,%d" % [axial.x, axial.y]
	_offset_by_coord[coord] = offset
	_coord_by_offset[offset] = coord
	_walkable[coord] = obstacle_layer.get_cell_source_id(offset) == -1


## Only returns neighbors that actually exist WITHIN this walked grid
## (unlike WorldRegistry.get_neighbors(), which always returns all 6
## mathematically — the overworld is unbounded, a room isn't). A
## future pathfinder shouldn't have to separately filter out neighbors
## that don't exist in this scene at all.
func get_neighbors(coord: String) -> Array[String]:
	var origin := _parse_coord(coord)
	var neighbors: Array[String] = []
	for direction in WorldRegistry.AXIAL_DIRECTIONS:
		var candidate := "%d,%d" % [origin.x + direction.x, origin.y + direction.y]
		if _offset_by_coord.has(candidate):
			neighbors.append(candidate)
	return neighbors


func get_distance(a: String, b: String) -> int:
	var av := _parse_coord(a)
	var bv := _parse_coord(b)
	var dq := av.x - bv.x
	var dr := av.y - bv.y
	return (abs(dq) + abs(dr) + abs(dq + dr)) / 2


func is_walkable(coord: String) -> bool:
	return _walkable.get(coord, false)


## Whether `coord` exists in this grid at all — a cell can be painted
## on ObstacleLayer without ever having been reachable from the
## anchor (e.g. a disconnected splash of tiles), in which case it was
## never registered in the first place and is neither walkable nor
## meaningfully "in" this scene's grid.
func has_cell(coord: String) -> bool:
	return _offset_by_coord.has(coord)


## Native Godot offset coordinate a given axial coord resolved to
## during the graph-walk -- lets you cross-reference this system's
## axial output against exactly what the Godot editor's own
## coordinate readout shows for that same physical cell. Debug/
## verification use only; nothing in this system should route logic
## through offset coordinates. Returns Vector2i.ZERO with a warning if
## `coord` isn't in the grid -- check has_cell() first if ZERO would be
## ambiguous with a genuine offset of (0,0).
func get_offset_coord(coord: String) -> Vector2i:
	if not _offset_by_coord.has(coord):
		push_warning("LocalGrid: get_offset_coord() called with unknown coord '%s'" % coord)
		return Vector2i.ZERO
	return _offset_by_coord[coord]


# --- Position conversion (Phase 2, click-to-move support) --------------

## Global-space position of a cell's center. The single place this
## conversion happens now — CharacterController and any future click
## handler both go through here instead of each holding their own
## TileMapLayer reference and doing the map_to_local()/to_global() call
## themselves.
func get_world_position(coord: String) -> Vector2:
	if not has_cell(coord):
		push_warning("LocalGrid: get_world_position() called with unknown coord '%s'" % coord)
		return Vector2.ZERO
	return _terrain_layer.to_global(_terrain_layer.map_to_local(_offset_by_coord[coord]))


## Reverse of get_world_position() — resolves a global-space position
## (e.g. get_global_mouse_position()) to whichever cell it falls
## inside. Returns "" if the position doesn't correspond to any cell
## this grid knows about (clicked outside the room, or a genuine gap
## in what got painted/walked).
func get_coord_at_global_position(global_pos: Vector2) -> String:
	var offset := _terrain_layer.local_to_map(_terrain_layer.to_local(global_pos))
	return _coord_by_offset.get(offset, "")


# --- Occupancy ---------------------------------------------------------

func set_occupant(coord: String, occupant: Variant) -> void:
	_occupants[coord] = occupant


func clear_occupant(coord: String) -> void:
	_occupants.erase(coord)


func get_occupant(coord: String) -> Variant:
	return _occupants.get(coord, null)


func is_occupied(coord: String) -> bool:
	return _occupants.has(coord)


## Walkable, in-grid, and not currently occupied. This is the check
## pathfinding uses for every cell except the start (Section below).
func is_available(coord: String) -> bool:
	return has_cell(coord) and is_walkable(coord) and not is_occupied(coord)


# --- Pathfinding ---------------------------------------------------------

## Plain BFS from start to goal, treating every available cell as
## equal cost. `start` itself is exempted from the occupancy check
## (whoever's asking for a path is, definitionally, standing there),
## but every other cell along the way must be is_available(). Returns
## an empty array if start/goal aren't in the grid, aren't walkable, or
## no path exists — callers decide what "no path" means for them
## (Movement/Actor layer's future fallback-to-nearest-neighbor
## behavior, Design Doc Section 3.5 step 4, is not built here).
func find_path(start: String, goal: String) -> Array[String]:
	var empty: Array[String] = []
	if not has_cell(start) or not has_cell(goal):
		return empty
	if not is_walkable(start) or not is_walkable(goal):
		return empty
	if start == goal:
		return [start]

	var came_from: Dictionary = {start: ""}
	var queue: Array[String] = [start]

	while not queue.is_empty():
		var current: String = queue.pop_front()
		if current == goal:
			return _reconstruct_path(came_from, start, goal)

		for neighbor in get_neighbors(current):
			if came_from.has(neighbor):
				continue
			if neighbor != goal and not is_available(neighbor):
				continue
			if neighbor == goal and is_occupied(neighbor):
				continue
			came_from[neighbor] = current
			queue.append(neighbor)

	return empty


func _reconstruct_path(came_from: Dictionary, start: String, goal: String) -> Array[String]:
	var path: Array[String] = [goal]
	var current := goal
	while current != start:
		current = came_from[current]
		path.push_front(current)
	return path


static func _parse_coord(coord: String) -> Vector2i:
	var parts := coord.split(",")
	if parts.size() != 2:
		push_warning("LocalGrid: malformed coord '%s'" % coord)
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))
