@tool
extends EditorScript

## Bake step for the World Generation / Hex Data System (design doc
## Section 7). Reads the three TileMapLayers in the authoring scene plus
## the sidecar, converts Godot's native offset coordinates to this
## project's canonical axial "q,r" coordinates, computes river_edges by
## checking real painted-cell adjacency, and writes the single baked
## HexMapData Resource WorldRegistry loads at runtime.
##
## Non-destructive to re-run -- no live/divergent hex state exists to
## lose (design doc Section 2), so re-running after further painting is
## always safe, same posture as generate_dialogue_sample_data.gd.
##
## ASSUMPTION, flagging rather than assuming silently: all three
## TileMapLayers must share the same hex geometry (Tile Shape, Offset
## Axis, Tile Size, Layout) even though they hold different art/tiles.
## To reduce risk from that, every geometric neighbor lookup below goes
## through terrain_layer.get_neighbor_cell() specifically -- trail_layer
## and river_layer are only ever asked "is this exact offset coord
## painted," never asked for their own neighbor computation.
##
## Run via File > Run with this script open, or right-click it in the
## FileSystem dock > Run.

const SCENE_PATH := "res://systems/world_generation/scenes/world_map_authoring.tscn"

# GUESSED PATHS -- not confirmed against your actual project layout.
# SIDECAR_PATH: create a WorldSidecarData resource at this path once you
# have settlements/special events to author; a missing file is treated
# as "none yet," not an error. OUTPUT_PATH must exactly match
# WorldRegistry.BAKED_HEX_MAP_PATH or WorldRegistry won't find this.
const SIDECAR_PATH := "res://systems/world_generation/data/world_sidecar.tres"
const OUTPUT_PATH := "res://systems/world_generation/data/baked_hex_map.tres"

# The hex painted at Godot's native offset (0,0) is always assigned
# axial "0,0", and CELL_NEIGHBOR_BY_AXIAL_INDEX pairs Godot's native
# CellNeighbor enum with this project's own AXIAL_DIRECTIONS index
# order -- both now live in HexBakeConstants (hex_bake_constants.gd),
# shared with world_map_authoring.gd's runtime click-resolution mirror
# of this same graph-walk. See that file's own comment for why sharing
# these two specifically (unlike AXIAL_DIRECTIONS below) is safe.

# Must match WorldRegistry.AXIAL_DIRECTIONS exactly -- duplicated here
# rather than imported so this script has no runtime dependency on the
# autoload (EditorScripts run in the editor, not the running game, and
# autoloads aren't guaranteed instantiated in that context).
const AXIAL_DIRECTIONS := [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]


func _run() -> void:
	var scene: PackedScene = load(SCENE_PATH)
	var root: Node = scene.instantiate()
	var terrain_layer: TileMapLayer = root.get_node("%TerrainLayer")
	var trail_layer: TileMapLayer = root.get_node("%TrailLayer")
	var river_layer: TileMapLayer = root.get_node("%RiverLayer")

	if terrain_layer.get_cell_source_id(HexBakeConstants.ANCHOR_OFFSET) == -1:
		push_error("Bake aborted: no terrain painted at anchor cell %s. A hex must always be painted here so axial coordinates stay stable across re-bakes." % HexBakeConstants.ANCHOR_OFFSET)
		root.queue_free()
		return

	# --- Pass 1: graph-walk from the anchor, assigning every reachable
	# painted terrain cell a stable axial coordinate. ---
	var axial_by_offset: Dictionary = {}  # Vector2i (offset) -> Vector2i (axial q,r)
	axial_by_offset[HexBakeConstants.ANCHOR_OFFSET] = Vector2i.ZERO

	var queue: Array[Vector2i] = [HexBakeConstants.ANCHOR_OFFSET]
	while not queue.is_empty():
		var current_offset: Vector2i = queue.pop_front()
		var current_axial: Vector2i = axial_by_offset[current_offset]

		for i in 6:
			var neighbor_offset: Vector2i = terrain_layer.get_neighbor_cell(current_offset, HexBakeConstants.CELL_NEIGHBOR_BY_AXIAL_INDEX[i])
			if terrain_layer.get_cell_source_id(neighbor_offset) == -1:
				continue  # not painted -- no hex here
			if axial_by_offset.has(neighbor_offset):
				continue  # already assigned via another path
			axial_by_offset[neighbor_offset] = current_axial + AXIAL_DIRECTIONS[i]
			queue.append(neighbor_offset)

	print("--- offset -> axial mapping (temporary debug dump) ---")
	for offset in axial_by_offset:
		var a: Vector2i = axial_by_offset[offset]
		print("  offset %s -> axial \"%d,%d\"" % [offset, a.x, a.y])

	var total_painted := terrain_layer.get_used_cells().size()
	var unreachable := total_painted - axial_by_offset.size()
	if unreachable > 0:
		push_warning("Bake: %d painted terrain cell(s) are disconnected from the anchor and were excluded. Check for stray painted cells." % unreachable)
	print("Bake: %d terrain cells reachable from anchor %s" % [axial_by_offset.size(), HexBakeConstants.ANCHOR_OFFSET])

	# --- Load sidecar. Missing file means no settlements/special
	# events authored yet -- not an error. ---
	var sidecar_by_coord: Dictionary = {}  # "q,r" (String) -> WorldSidecarEntry
	if FileAccess.file_exists(SIDECAR_PATH):
		var sidecar: WorldSidecarData = load(SIDECAR_PATH)
		for entry in sidecar.entries:
			if sidecar_by_coord.has(entry.coord):
				push_warning("Bake: duplicate sidecar entry for coord '%s', keeping the last one" % entry.coord)
			sidecar_by_coord[entry.coord] = entry
	else:
		push_warning("Bake: no sidecar found at %s -- proceeding with no settlements/special events" % SIDECAR_PATH)

	# --- Pass 2: build one HexInstance per reachable terrain cell. ---
	var hexes: Dictionary = {}  # "q,r" (String) -> HexInstance

	for offset_coord in axial_by_offset:
		var axial: Vector2i = axial_by_offset[offset_coord]
		var coord_string := "%d,%d" % [axial.x, axial.y]

		var hex := HexInstance.new()
		hex.coord = coord_string

		var tile_data := terrain_layer.get_cell_tile_data(offset_coord)
		if tile_data == null:
			push_warning("Bake: hex '%s' has no tile data despite being painted -- terrain_type_id left empty" % coord_string)
		else:
			hex.terrain_type_id = tile_data.get_custom_data("terrain_type_id")
			if hex.terrain_type_id == "":
				push_warning("Bake: hex '%s' has no terrain_type_id set on its source tile" % coord_string)

		hex.has_trail = trail_layer.get_cell_source_id(offset_coord) != -1

		var river_edges: Array[int] = []
		if river_layer.get_cell_source_id(offset_coord) != -1:
			for i in 6:
				var river_neighbor_offset: Vector2i = terrain_layer.get_neighbor_cell(offset_coord, HexBakeConstants.CELL_NEIGHBOR_BY_AXIAL_INDEX[i])
				if river_layer.get_cell_source_id(river_neighbor_offset) != -1:
					river_edges.append(i)
		hex.river_edges = river_edges

		var sidecar_entry: WorldSidecarEntry = sidecar_by_coord.get(coord_string, null)
		if sidecar_entry != null:
			hex.settlement_id = sidecar_entry.settlement_id
			hex.special_event_ids = sidecar_entry.special_event_ids
			hex.event_frequency_multiplier = sidecar_entry.event_frequency_multiplier

		hexes[coord_string] = hex

	# --- Save. ---
	var map_data := HexMapData.new()
	map_data.hexes = hexes

	var dir_path := OUTPUT_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var err := ResourceSaver.save(map_data, OUTPUT_PATH)
	if err != OK:
		push_error("Bake failed: could not save %s (error %d)" % [OUTPUT_PATH, err])
		root.queue_free()
		return

	EditorInterface.get_resource_filesystem().scan()
	print("Bake complete: %d hexes written to %s" % [hexes.size(), OUTPUT_PATH])

	root.queue_free()
