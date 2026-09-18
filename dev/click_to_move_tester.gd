extends Node2D
## Click-to-Move Tester (Phase 2, click detection + Phase 2c re-planning).
##
## SETUP: temporarily swap this in as the whitebox room's root script.
## Same two unique-named TileMapLayer children required: %TerrainLayer,
## %ObstacleLayer.
##
## Still NOT Phase 3's real Control layer -- no modal lock, no
## queueing, no real switching contract (Section 3.8). The 1/2 keys
## below are a throwaway dev-only convenience purely so this harness
## can drive two controllers with one mouse, to actually test one
## controller walking into another's path -- not a preview of real
## character switching.
##
## Press 1 or 2 to choose which controller the next left-click drives.
## Left-click a cell to send the active controller there. Try sending
## Controller B across Controller A's current route while A is still
## mid-path -- that's the case Phase 2c's re-planning exists for.

const CONTROLLER_SCENE := preload("res://systems/local_movement/actor/character_controller.tscn")

const START_A := "0,0"   ## update to match your room
const START_B := "2,0"   ## update to match your room

var _grid: LocalGrid
var _controller_a: CharacterController
var _controller_b: CharacterController
var _active: CharacterController


func _ready() -> void:
	_grid = LocalGrid.new(%TerrainLayer, %ObstacleLayer)

	_controller_a = _spawn(START_A, "A", 18)   ## high Agility -- faster
	_controller_b = _spawn(START_B, "B", 2)    ## low Agility -- slower
	_active = _controller_a

	print("=== Click-to-Move Tester (Phase 2c) ===")
	print("A at %s, B at %s -- press 1/2 to pick who the next click drives" % [START_A, START_B])
	print("========================================")


func _spawn(start_cell: String, label: String, agility: int) -> CharacterController:
	var sheet := CharacterSheet.new()
	sheet.character_name = label
	sheet.agility = agility

	var controller: CharacterController = CONTROLLER_SCENE.instantiate()
	add_child(controller)
	controller.name = "Controller_%s" % label
	controller.setup(_grid, sheet, start_cell)
	controller.arrived.connect(func(cell): print("%s arrived at %s" % [label, cell]))
	return controller


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_1:
			_active = _controller_a
			print("Now driving A")
			return
		if event.keycode == KEY_2:
			_active = _controller_b
			print("Now driving B")
			return

	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	var click_position := get_global_mouse_position()
	var coord := _grid.get_coord_at_global_position(click_position)

	if coord == "":
		print("Clicked outside the grid (%s)" % click_position)
		return

	print("Clicked %s -- walkable: %s, occupied: %s" % [coord, _grid.is_walkable(coord), _grid.is_occupied(coord)])
	_active.move_to_cell(coord)
