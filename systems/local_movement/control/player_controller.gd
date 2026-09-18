class_name PlayerController
extends Node2D

## Control layer (Local Movement Design Doc, Section 3.1). "PlayerController"
## is the name the doc explicitly reserves for this layer only -- grid
## and movement/actor logic don't belong here, only input.
##
## Phase 3a built point-and-click against a single active controller.
## Phase 3b adds real character switching (Section 3.8): any number of
## CharacterControllers can be registered as "present," and whichever
## one is active receives click input. Switching is keyed by
## CharacterSheet -- Section 3.8's own illustrative naming,
## set_active_character() -- rather than by controller reference,
## since callers (a debug tool today, real UI later) deal in
## "characters," not controller instances.
##
## Adds itself to the "player_controller" group so the Debug Menu's
## Local Movement tab (or, later, real game code) can find whichever
## instance is live in the CURRENT scene without a hardcoded path --
## unlike PartyManager/VitalsSystem, a PlayerController is necessarily
## scene-local, so there's no autoload to just ask directly.
##
## Switching never affects movement (Section 3.8) -- true here by
## construction: nothing in CharacterController ever checks whether
## it's the currently active one, so switching only changes which
## controller receives FUTURE clicks.
##
## Phase 3c adds modal lock registration: any number of external
## systems can register a Callable() -> bool "is switching locked
## right now" check (e.g. Dialogue, once something actually needs
## this) via register_switch_lock(), mirroring VitalsSystem's
## register_environmental_source() pull-hook pattern -- PlayerController
## polls outward at switch time rather than something reaching in to
## set a flag on it. If ANY registered check returns true,
## set_active_character() refuses the switch and returns false.
##
## Extends Node2D purely for get_global_mouse_position()'s convenience
## (a CanvasItem method) -- this node renders nothing and its own
## transform is irrelevant.

var _grid: LocalGrid
var _controllers: Array[CharacterController] = []
var _active_controller: CharacterController
var _switch_lock_checks: Array[Callable] = []


func _ready() -> void:
	add_to_group("player_controller")


func setup(grid: LocalGrid) -> void:
	_grid = grid


## Adds a controller to the set of "present" characters that can be
## switched to. The first one registered becomes active by default.
func register_controller(controller: CharacterController) -> void:
	if controller in _controllers:
		return
	_controllers.append(controller)
	if _active_controller == null:
		_active_controller = controller


## `check` is a Callable taking no arguments and returning bool --
## true means "switching is currently locked." Any number of sources
## can register one; ALL are polled on every switch attempt (see
## is_switching_locked()). There is no unregister yet -- nothing in
## this project needs a lock source to stop existing mid-scene, only
## to toggle its own answer, so this hasn't been built until something
## actually needs it.
func register_switch_lock(check: Callable) -> void:
	_switch_lock_checks.append(check)


func is_switching_locked() -> bool:
	for check in _switch_lock_checks:
		if check.call():
			return true
	return false


## Returns false (and leaves the active character unchanged) if
## switching is currently locked, or if character_sheet doesn't match
## any registered controller. Callers that care whether a switch
## actually happened (the debug tab, eventually real UI) should check
## the return value rather than assuming it always succeeds.
func set_active_character(character_sheet: CharacterSheet) -> bool:
	if is_switching_locked():
		push_warning("PlayerController: switching is locked, ignoring switch request")
		return false

	for controller in _controllers:
		if controller.character_sheet == character_sheet:
			_active_controller = controller
			return true

	push_warning("PlayerController: no registered controller represents that CharacterSheet")
	return false


func get_active_character() -> CharacterSheet:
	return _active_controller.character_sheet if _active_controller != null else null


func get_present_characters() -> Array[CharacterSheet]:
	var sheets: Array[CharacterSheet] = []
	for controller in _controllers:
		sheets.append(controller.character_sheet)
	return sheets


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _active_controller == null or _grid == null:
		return

	var coord := _grid.get_coord_at_global_position(get_global_mouse_position())
	if coord == "":
		return

	_active_controller.move_to_cell(coord)
