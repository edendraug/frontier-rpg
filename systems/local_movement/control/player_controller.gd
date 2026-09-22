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
## systems can register a Callable() -> bool "is player control
## locked right now" check (Dialogue, in particular, once opened) via
## register_control_lock(), mirroring VitalsSystem's
## register_environmental_source() pull-hook pattern -- PlayerController
## polls outward rather than something reaching in to set a flag on
## it. Originally scoped to switching only (register_switch_lock);
## widened to also gate plain movement clicks and interact requests
## once Dialogue actually needed it -- opening a conversation should
## hijack ALL player control, not just switching, and DialogueWindow
## only covers part of the screen, so nothing was stopping clicks
## elsewhere in the scene from reaching this controller while a
## conversation was open.
##
## switched_active_character fires on every successful switch, passing
## the actual CharacterController (not just its CharacterSheet) --
## added specifically so LocalSceneCamera can cache which node to
## follow rather than polling get_active_character() every frame.
##
## Section 3.7's click-to-interact: WorldInteractable calls
## request_interact() directly (found via this same "player_controller"
## group) rather than PlayerController holding a registry of
## interactables -- one-directional coupling. Approaches the nearest
## open neighbor of the interactable (any reachable neighbor, not a
## specific pre-computed one) and fires interact() on arrival.
## _pending_interact_id invalidates a stale approach if a NEW click --
## plain move or another interact -- supersedes it before arrival, so
## an interact never fires at the wrong moment just because the player
## clicked elsewhere in between.
##
## Extends Node2D purely for get_global_mouse_position()'s convenience
## (a CanvasItem method) -- this node renders nothing and its own
## transform is irrelevant.

signal switched_active_character(controller: CharacterController)
signal interact_request_failed(interactable: WorldInteractable)

var _grid: LocalGrid
var _controllers: Array[CharacterController] = []
var _active_controller: CharacterController
var _control_lock_checks: Array[Callable] = []
var _pending_interact_id: int = 0


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
## true means "player control is currently locked" (movement,
## interacting, and switching all gated by this). Any number of
## sources can register one; ALL are polled on every attempt (see
## is_control_locked()). There is no unregister yet -- nothing in
## this project needs a lock source to stop existing mid-scene, only
## to toggle its own answer, so this hasn't been built until something
## actually needs it.
func register_control_lock(check: Callable) -> void:
	_control_lock_checks.append(check)


func is_control_locked() -> bool:
	for check in _control_lock_checks:
		if check.call():
			return true
	return false


## Returns false (and leaves the active character unchanged) if
## control is currently locked, or if character_sheet doesn't match
## any registered controller. Callers that care whether a switch
## actually happened (the debug tab, eventually real UI) should check
## the return value rather than assuming it always succeeds.
func set_active_character(character_sheet: CharacterSheet) -> bool:
	if is_control_locked():
		push_warning("PlayerController: control is locked, ignoring switch request")
		return false

	for controller in _controllers:
		if controller.character_sheet == character_sheet:
			_active_controller = controller
			switched_active_character.emit(controller)
			return true

	push_warning("PlayerController: no registered controller represents that CharacterSheet")
	return false


func get_active_controller() -> CharacterController:
	return _active_controller


func get_active_character() -> CharacterSheet:
	return _active_controller.character_sheet if _active_controller != null else null


func get_present_characters() -> Array[CharacterSheet]:
	var sheets: Array[CharacterSheet] = []
	for controller in _controllers:
		sheets.append(controller.character_sheet)
	return sheets


## Sends the active character to the nearest open neighbor of
## `interactable` and fires its interact() on arrival. Any reachable
## neighbor is acceptable (not a specific pre-computed one, per
## Cameron's call) -- find_open_cells_near() already excludes the
## interactable's own cell, since WorldInteractable permanently
## occupies it (see WorldInteractable.register_with_grid()), so this
## naturally returns the nearest free NEIGHBOR without needing to know
## that itself. Emits interact_request_failed if genuinely no
## reachable cell exists at all (Section 3.7's explicit requirement --
## something observable instead of silently doing nothing).
func request_interact(interactable: WorldInteractable) -> void:
	if _active_controller == null or _grid == null or is_control_locked():
		return

	var interactable_cell := _grid.get_coord_at_global_position(interactable.global_position)
	if interactable_cell == "":
		push_warning("PlayerController: interactable '%s' isn't in this scene's grid" % interactable.name)
		return

	var approach_cells := _grid.find_open_cells_near(interactable_cell, 1)
	if approach_cells.is_empty():
		interact_request_failed.emit(interactable)
		return

	_pending_interact_id += 1
	var this_request_id := _pending_interact_id
	var controller := _active_controller

	controller.move_to_cell(approach_cells[0])
	controller.arrived.connect(
		func(_cell: String):
			if this_request_id == _pending_interact_id and is_instance_valid(interactable):
				interactable.interact(controller),
		CONNECT_ONE_SHOT
	)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _active_controller == null or _grid == null or is_control_locked():
		return

	var coord := _grid.get_coord_at_global_position(get_global_mouse_position())
	if coord == "":
		return

	# A plain move-to-cell click invalidates any interact approach
	# still in flight, same as it would supersede any other in-progress
	# path -- see request_interact()'s own note on this counter.
	_pending_interact_id += 1
	_active_controller.move_to_cell(coord)
