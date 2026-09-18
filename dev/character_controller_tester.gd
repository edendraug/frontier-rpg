extends Node2D
## Character Controller Tester (Phase 2a).
##
## SETUP: temporarily swap this in as the whitebox room's root script,
## in place of local_grid_tester.gd -- Phase 1's checks already
## passed, no need to keep re-running them every time. Same two
## unique-named TileMapLayer children required: %TerrainLayer,
## %ObstacleLayer.
##
## Spawns two CharacterController instances directly into the scene
## (no click input yet -- that's Phase 3) and drives them via
## move_to_cell() calls, to visually confirm pathfinding, tweened
## movement, and live occupancy blocking between real controller
## instances (not the dummy String tokens Phase 1b's tester used).
##
## Edit START_A / START_B / BLOCKED_TARGET / FREE_TARGET below to
## match whatever's actually painted in the scene. BLOCKED_TARGET is
## deliberately set to START_B, to confirm A correctly refuses to path
## onto a cell B is standing on; FREE_TARGET should be some other
## walkable cell so you can actually watch A move.

const CONTROLLER_SCENE := preload("res://systems/local_movement/actor/character_controller.tscn")

const START_A := "0,0"
const START_B := "2,0"
const BLOCKED_TARGET := START_B
const FREE_TARGET := "0,1"   ## a confirmed real neighbor of 0,0 from Phase 1a's output -- swap if it turns out to have an obstacle on it


func _ready() -> void:
	var grid := LocalGrid.new(%TerrainLayer, %ObstacleLayer)

	var controller_a := _spawn(grid, START_A, "A", 18)   ## high Agility -- should move noticeably faster
	var controller_b := _spawn(grid, START_B, "B", 2)    ## low Agility -- should move noticeably slower

	controller_a.arrived.connect(func(cell): print("Controller A arrived at %s" % cell))
	controller_b.arrived.connect(func(cell): print("Controller B arrived at %s" % cell))

	print("=== CharacterController Tester ===")
	print("A occupying %s, B occupying %s" % [controller_a.current_cell, controller_b.current_cell])

	print("Sending A toward %s (B's cell -- expect a 'no path' warning, no movement)..." % BLOCKED_TARGET)
	_diagnose(grid, BLOCKED_TARGET)
	controller_a.move_to_cell(BLOCKED_TARGET)

	print("Sending A toward %s (should be free -- expect real movement + an arrival print)..." % FREE_TARGET)
	_diagnose(grid, FREE_TARGET)
	controller_a.move_to_cell(FREE_TARGET)
	print("========================")


## Prints WHY a target might fail before attempting it, so a "no path"
## warning doesn't leave you guessing between "doesn't exist in the
## grid," "exists but has an obstacle on it," and "exists, walkable,
## but currently occupied."
func _diagnose(grid: LocalGrid, coord: String) -> void:
	if not grid.has_cell(coord):
		print("  [diagnostic] %s is not in the grid at all (nothing painted there)" % coord)
		return
	print("  [diagnostic] %s -- walkable: %s, occupied: %s" % [coord, grid.is_walkable(coord), grid.is_occupied(coord)])


func _spawn(grid: LocalGrid, start_cell: String, label: String, agility: int) -> CharacterController:
	var sheet := CharacterSheet.new()
	sheet.character_name = label
	sheet.agility = agility

	var controller: CharacterController = CONTROLLER_SCENE.instantiate()
	add_child(controller)
	controller.name = "Controller_%s" % label
	controller.setup(grid, sheet, start_cell)
	return controller
