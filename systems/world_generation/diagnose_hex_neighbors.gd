@tool
extends EditorScript

## ONE-OFF DIAGNOSTIC, not part of the real bake step -- delete this file
## once you've reported the results back.
##
## Checks all 16 TileSet.CellNeighbor values against a painted "flower"
## test pattern (one center cell + all 6 real neighbors painted, nothing
## else nearby) to determine empirically which 6 directions are the real
## hex neighbors for a flat-top TileSet, rather than trusting a guess
## from documentation. Run via File > Run (or right-click in the
## FileSystem dock > Run) with the scene closed in the editor.

const SCENE_PATH := "res://systems/world_generation/scenes/world_map_authoring.tscn"

# Swap this to the center cell's coordinates from your painted flower
# pattern (Step 5 of the setup).
const TEST_COORD := Vector2i(0, 0)

const ALL_DIRECTIONS := {
	"RIGHT_SIDE": TileSet.CELL_NEIGHBOR_RIGHT_SIDE,
	"RIGHT_CORNER": TileSet.CELL_NEIGHBOR_RIGHT_CORNER,
	"BOTTOM_RIGHT_SIDE": TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE,
	"BOTTOM_RIGHT_CORNER": TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER,
	"BOTTOM_SIDE": TileSet.CELL_NEIGHBOR_BOTTOM_SIDE,
	"BOTTOM_CORNER": TileSet.CELL_NEIGHBOR_BOTTOM_CORNER,
	"BOTTOM_LEFT_SIDE": TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE,
	"BOTTOM_LEFT_CORNER": TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER,
	"LEFT_SIDE": TileSet.CELL_NEIGHBOR_LEFT_SIDE,
	"LEFT_CORNER": TileSet.CELL_NEIGHBOR_LEFT_CORNER,
	"TOP_LEFT_SIDE": TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE,
	"TOP_LEFT_CORNER": TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER,
	"TOP_SIDE": TileSet.CELL_NEIGHBOR_TOP_SIDE,
	"TOP_CORNER": TileSet.CELL_NEIGHBOR_TOP_CORNER,
	"TOP_RIGHT_SIDE": TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE,
	"TOP_RIGHT_CORNER": TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER,
}


func _run() -> void:
	var scene: PackedScene = load(SCENE_PATH)
	var root: Node = scene.instantiate()
	var terrain_layer: TileMapLayer = root.get_node("%TerrainLayer")

	var center_source_id := terrain_layer.get_cell_source_id(TEST_COORD)
	print("Center cell %s source_id: %d (-1 means not painted -- check TEST_COORD)" % [TEST_COORD, center_source_id])
	print("--- Checking all 16 CellNeighbor directions ---")

	var painted_count := 0
	for direction_name in ALL_DIRECTIONS:
		var direction: int = ALL_DIRECTIONS[direction_name]
		var neighbor_coord: Vector2i = terrain_layer.get_neighbor_cell(TEST_COORD, direction)
		var source_id := terrain_layer.get_cell_source_id(neighbor_coord)
		var painted := source_id != -1
		if painted:
			painted_count += 1
		print("  %-22s -> %-12s %s" % [direction_name, neighbor_coord, "PAINTED" if painted else "empty"])

	print("--- %d of 16 directions led to a painted cell (should be exactly 6) ---" % painted_count)
	root.queue_free()
