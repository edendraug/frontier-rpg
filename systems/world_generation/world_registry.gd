extends Node

## Autoload (proposed name: WorldRegistry). Owns terrain type
## definitions and the baked hex map, and exposes axial hex geometry +
## world queries other systems build on. See World Generation / Hex
## Data System design doc.
##
## Discovery/loading conventions matched from ItemRegistry (autoload,
## public load_*() entry point called from _ready(), permissive
## missing-file handling) and CharacterDataRegistry (DirAccess
## directory scan for .tres files, per-file class check).
##
## NOTE: no class_name is declared here, matching ItemRegistry's own
## autoload script, which also declares none.

const TERRAIN_TYPES_DIR := "res://systems/world_generation/data/terrain_types/"
const BAKED_HEX_MAP_PATH := "res://systems/world_generation/data/baked_hex_map.tres"

const AXIAL_DIRECTIONS := [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

var _terrain_types: Dictionary = {}  # terrain_type_id (String) -> TerrainTypeDefinition
var _hexes: Dictionary = {}          # coord (String) -> HexInstance


func _ready() -> void:
	load_world_data()


## Public entry point, mirroring ItemRegistry.load_items() -- callable
## again later (e.g. from a future debug tab's reload button) without
## restarting the game.
func load_world_data() -> void:
	_load_terrain_types()
	_load_hex_map()


## Discovers every TerrainTypeDefinition .tres file in
## TERRAIN_TYPES_DIR. Same DirAccess scan pattern as
## CharacterDataRegistry._load_all().
func _load_terrain_types() -> void:
	_terrain_types.clear()
	var dir := DirAccess.open(TERRAIN_TYPES_DIR)
	if dir == null:
		push_warning("WorldRegistry: could not open %s" % TERRAIN_TYPES_DIR)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var res: Resource = load(TERRAIN_TYPES_DIR + file_name)
			if res is TerrainTypeDefinition:
				if _terrain_types.has(res.terrain_type_id):
					push_warning("WorldRegistry: duplicate terrain_type_id '%s', overwriting" % res.terrain_type_id)
				_terrain_types[res.terrain_type_id] = res
			else:
				push_warning("WorldRegistry: '%s' is not a TerrainTypeDefinition, skipping" % file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	print("WorldRegistry: loaded %d terrain types" % _terrain_types.size())


## Loads the single baked HexMapData Resource produced by the
## EditorScript bake step. A missing file is expected and non-fatal
## until a bake has been run -- degrades to an empty map with a
## warning, same permissive-by-default posture as ItemRegistry's
## missing-CSV handling, rather than a hard failure.
func _load_hex_map() -> void:
	_hexes.clear()
	if not FileAccess.file_exists(BAKED_HEX_MAP_PATH):
		push_warning("WorldRegistry: no baked hex map found at %s" % BAKED_HEX_MAP_PATH)
		return

	var map_data: HexMapData = load(BAKED_HEX_MAP_PATH)
	if map_data == null:
		push_error("WorldRegistry: failed to load baked hex map at %s" % BAKED_HEX_MAP_PATH)
		return

	_hexes = map_data.hexes
	print("WorldRegistry: loaded %d hexes" % _hexes.size())


func get_terrain(terrain_type_id: String) -> TerrainTypeDefinition:
	return _terrain_types.get(terrain_type_id, null)


func get_hex(coord: String) -> HexInstance:
	return _hexes.get(coord, null)


## Enumerates every baked hex's coord string. Added for the
## player-facing Travel map renderer, which needs to iterate the whole
## baked map rather than look up one hex at a time -- nothing before
## this needed that. Order is Dictionary key order (bake/insertion
## order), not geometrically meaningful; a caller needing a specific
## order (e.g. for deterministic rendering) should sort it themselves.
func get_all_hex_coords() -> Array[String]:
	var coords: Array[String] = []
	for coord in _hexes.keys():
		coords.append(coord)
	return coords


## Thin wrapper -- looks up the hex's terrain type and returns its
## is_passable (design doc Section 5.4).
##
## An unknown coord, or a hex referencing an unknown terrain_type_id,
## returns false ("impassable") rather than crashing or defaulting to
## passable -- the safer default for a query future pathfinding will
## rely on.
func is_passable(coord: String) -> bool:
	var hex := get_hex(coord)
	if hex == null:
		return false

	var terrain := get_terrain(hex.terrain_type_id)
	if terrain == null:
		push_warning("WorldRegistry: hex '%s' references unknown terrain_type_id '%s'" % [coord, hex.terrain_type_id])
		return false

	return terrain.is_passable


## Whether a straight path through `coord`, entering via `entry_edge`
## and exiting via `exit_edge` (both AXIAL_DIRECTIONS indices, 0-5),
## crosses the hex's river.
##
## SUPERSEDES the original hex-to-hex signature (design doc Section
## 5.3, v0.1/v0.2) -- that model measured the wrong thing entirely.
## A river's actual path runs THROUGH a hex's interior between two of
## its edges, so whether a crossing occurs depends on which two edges
## the traveler is using to cross that specific hex, not on which
## neighbor hex they're heading toward next. Confirmed against real
## examples, not just reasoned through -- see conversation history.
##
## Determined by a cyclic chord-interleaving test: two chords of a
## hexagon (each a pair of its 6 edges) cross inside the shape exactly
## when their endpoints alternate around the boundary rather than
## sharing the same arc. Pure index arithmetic, no trigonometry.
##
## river_edges with more than 2 entries (a confluence) is handled by
## checking every pair of touching edges, not just a single assumed
## pair. This is an explicit simplifying assumption, unverified against
## any real confluence hex since none currently exists on the map --
## flag if a real confluence ever produces a wrong-looking result.
func requires_river_crossing(coord: String, entry_edge: int, exit_edge: int) -> bool:
	if entry_edge < 0 or entry_edge > 5 or exit_edge < 0 or exit_edge > 5:
		push_warning("WorldRegistry: requires_river_crossing() called with out-of-range edge (%d, %d)" % [entry_edge, exit_edge])
		return false
	if entry_edge == exit_edge:
		push_warning("WorldRegistry: requires_river_crossing() called with identical entry/exit edge %d -- not a valid path through a hex" % entry_edge)
		return false

	var hex := get_hex(coord)
	if hex == null:
		push_warning("WorldRegistry: requires_river_crossing() called with unknown coord '%s'" % coord)
		return false

	var edges: Array = hex.river_edges
	for i in edges.size():
		for j in range(i + 1, edges.size()):
			if _chords_cross(entry_edge, exit_edge, edges[i], edges[j]):
				return true
	return false


## True if chord (a,b) and chord (c,d) -- each a pair of distinct
## positions on a 6-position cycle -- cross each other, i.e. their
## endpoints alternate around the cycle rather than sharing an arc.
static func _chords_cross(a: int, b: int, c: int, d: int) -> bool:
	return _is_between_cyclic(a, b, c) != _is_between_cyclic(a, b, d)


## True if x lies strictly on the forward arc from a to b (mod 6),
## exclusive of a and b themselves.
static func _is_between_cyclic(a: int, b: int, x: int) -> bool:
	if a < b:
		return a < x and x < b
	else:
		return x > a or x < b


# --- Axial hex geometry (Phase 2) ---

## Parses an axial "q,r" coordinate string into a Vector2i. Malformed
## input pushes a warning and returns Vector2i.ZERO rather than
## crashing -- matches the project's permissive-by-default convention
## for degrading gracefully on bad/missing data.
static func _parse_coord(coord: String) -> Vector2i:
	var parts := coord.split(",")
	if parts.size() != 2:
		push_warning("WorldRegistry: malformed coord '%s'" % coord)
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))


## Formats a Vector2i back into the canonical "q,r" coord string.
static func _format_coord(v: Vector2i) -> String:
	return "%d,%d" % [v.x, v.y]


## Computes which AXIAL_DIRECTIONS index points from `from` toward
## `to`. Returns -1 if the two coordinates aren't adjacent.
static func _direction_index(from: Vector2i, to: Vector2i) -> int:
	var delta := to - from
	return AXIAL_DIRECTIONS.find(delta)


## Public wrapper over _direction_index() taking coord strings.
## Exposed as a utility because a future Travel system will need
## exactly this to convert a route's sequence of hex coordinates into
## the entry_edge/exit_edge pair requires_river_crossing() now
## requires -- e.g. for a hex reached from A and left toward B,
## entry_edge = get_direction_index(coord, A) and
## exit_edge = get_direction_index(coord, B).
func get_direction_index(from: String, to: String) -> int:
	return _direction_index(_parse_coord(from), _parse_coord(to))


## Returns the axial coordinate strings of all 6 neighbors of coord, in
## AXIAL_DIRECTIONS order. That ordering is load-bearing --
## HexInstance.river_edges indexes directly into AXIAL_DIRECTIONS by
## position, so the two stay consistent by construction (design doc
## Section 5.2).
func get_neighbors(coord: String) -> Array[String]:
	var origin := _parse_coord(coord)
	var neighbors: Array[String] = []
	for direction in AXIAL_DIRECTIONS:
		neighbors.append(_format_coord(origin + direction))
	return neighbors


## Axial hex distance between two coordinates.
func get_distance(a: String, b: String) -> int:
	var av := _parse_coord(a)
	var bv := _parse_coord(b)
	var dq := av.x - bv.x
	var dr := av.y - bv.y
	return (abs(dq) + abs(dr) + abs(dq + dr)) / 2
