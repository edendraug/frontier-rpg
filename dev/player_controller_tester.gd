extends Node2D
## Player Controller Tester (Phase 3b).
##
## SETUP: swap this in as the whitebox room's root script. Same two
## unique-named TileMapLayer children required: %TerrainLayer,
## %ObstacleLayer.
##
## Two controllers registered as "present" with one PlayerController.
## Open the Debug Menu's "Local Movement" tab to switch which one
## receives clicks -- the throwaway 1/2 keys from earlier testers are
## gone now that real switching exists (Section 3.8).

const CONTROLLER_SCENE := preload("res://systems/local_movement/actor/character_controller.tscn")

const START_A := "0,0"   ## update to match your room
const START_B := "2,0"   ## update to match your room


func _ready() -> void:
	var grid := LocalGrid.new(%TerrainLayer, %ObstacleLayer)

	var player_controller := PlayerController.new()
	add_child(player_controller)
	player_controller.setup(grid)

	_spawn(grid, player_controller, START_A, "A", 18)   ## high Agility -- faster
	_spawn(grid, player_controller, START_B, "B", 2)    ## low Agility -- slower

	print("=== Player Controller Tester (Phase 3b) ===")
	print("Open the Debug Menu -> Local Movement tab to switch characters")
	print("============================================")
	
	add_child(DebugMenu.new())


func _spawn(grid: LocalGrid, player_controller: PlayerController, start_cell: String, label: String, agility: int) -> void:
	var sheet := CharacterSheet.new()
	sheet.character_name = label
	sheet.agility = agility

	var controller: CharacterController = CONTROLLER_SCENE.instantiate()
	add_child(controller)
	controller.name = "Controller_%s" % label
	controller.setup(grid, sheet, start_cell)
	controller.arrived.connect(func(cell): print("%s arrived at %s" % [label, cell]))

	player_controller.register_controller(controller)
