extends Node2D
## Local Grid Tester (Phase 1a + 1b).
##
## SETUP: attach to the root Node2D of the hand-authored whitebox
## scene (Test Scenes/LocalMovementPlayground.tscn). Expects two
## child TileMapLayers marked unique-in-owner:
##   %TerrainLayer  — hand-painted walkable floor footprint
##   %ObstacleLayer — hand-painted sparse overlay (crates/walls)
##
## Builds a LocalGrid from those two layers at _ready() and prints
## geometry (1a), then occupancy + pathfinding (1b) checks to the
## console. This is a validation harness, not gameplay code — no UI,
## no real characters. Occupancy uses plain String tokens as stand-ins
## for CharacterSheet, since no controller exists yet.
##
## Edit CHECK_COORD / CHECK_A / CHECK_B / BLOCK_COORD below to match
## whatever's actually painted in the scene — there's no way to know
## real coordinates until the room is authored. For the pathfinding
## check to be meaningful, BLOCK_COORD should sit somewhere on the
## direct route between CHECK_A and CHECK_B, with at least one other
## walkable route around it.

const CHECK_COORD := "0,0"   # a cell expected to be walkable
const CHECK_A := "0,0"
const CHECK_B := "2,0"       # pick a cell a few hexes away
const BLOCK_COORD := "1,0"   # ideally on the direct path between A and B


func _ready() -> void:
	var grid := LocalGrid.new(%TerrainLayer, %ObstacleLayer)

	print("=== LocalGrid Tester ===")
	_check_geometry(grid)
	_check_pathfinding(grid)
	print("========================")


func _check_geometry(grid: LocalGrid) -> void:
	if not grid.has_cell(CHECK_COORD):
		push_warning("LocalGridTester: '%s' isn't in the grid at all -- check CHECK_COORD against what's actually painted" % CHECK_COORD)
		return

	# Prints each neighbor's Godot offset coordinate alongside its axial
	# label, so you can go find that literal cell in the editor (via its
	# own [x,y] offset readout) and visually confirm it's actually
	# adjacent -- rather than eyeballing axial digits against Godot's
	# offset display, which aren't directly comparable (see chat).
	print("Axial %s -> Godot offset %s" % [CHECK_COORD, grid.get_offset_coord(CHECK_COORD)])
	print("Neighbors of %s:" % CHECK_COORD)
	for neighbor in grid.get_neighbors(CHECK_COORD):
		print("  axial %s -> Godot offset %s" % [neighbor, grid.get_offset_coord(neighbor)])
	print("Is %s walkable? %s" % [CHECK_COORD, grid.is_walkable(CHECK_COORD)])

	if grid.has_cell(CHECK_A) and grid.has_cell(CHECK_B):
		print("Distance %s -> %s: %d" % [CHECK_A, CHECK_B, grid.get_distance(CHECK_A, CHECK_B)])
	else:
		push_warning("LocalGridTester: CHECK_A or CHECK_B not in the grid -- update them to match what's painted")


func _check_pathfinding(grid: LocalGrid) -> void:
	if not grid.has_cell(CHECK_A) or not grid.has_cell(CHECK_B):
		push_warning("LocalGridTester: skipping pathfinding checks -- CHECK_A/CHECK_B not in the grid")
		return

	var open_path := grid.find_path(CHECK_A, CHECK_B)
	print("Path %s -> %s (unblocked): %s" % [CHECK_A, CHECK_B, open_path])

	if not grid.has_cell(BLOCK_COORD):
		push_warning("LocalGridTester: BLOCK_COORD '%s' not in the grid -- update it to test blocking" % BLOCK_COORD)
		return

	grid.set_occupant(BLOCK_COORD, "dummy_a")
	print("Is %s occupied now? %s" % [BLOCK_COORD, grid.is_occupied(BLOCK_COORD)])

	var rerouted_path := grid.find_path(CHECK_A, CHECK_B)
	print("Path %s -> %s (with %s blocked): %s" % [CHECK_A, CHECK_B, BLOCK_COORD, rerouted_path])

	if rerouted_path == open_path and not open_path.is_empty():
		push_warning("LocalGridTester: blocking %s didn't change the path -- it may not actually sit on the direct route" % BLOCK_COORD)

	grid.clear_occupant(BLOCK_COORD)
	print("Is %s occupied after clearing? %s" % [BLOCK_COORD, grid.is_occupied(BLOCK_COORD)])
