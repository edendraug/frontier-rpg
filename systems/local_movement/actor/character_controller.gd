class_name CharacterController
extends Node2D

## Movement/Actor layer. Phase 2a built bare mechanics; Phase 2c adds
## graceful mid-traversal re-planning (Design Doc Section 3.5, steps
## 2-5).
##
## Occupies exactly one LocalGrid cell at a time (Local Movement
## Design Doc, Section 3.5: "discrete occupancy, smooth motion" —
## logical position is always exactly one cell, never a fractional
## in-between state, even though the VISUAL motion between cells is
## tweened).
##
## No real sprite/animation swapping yet (Section 3.2's sprite_id is
## wired through and queryable, but VisualRoot's Placeholder ColorRect
## stays as-is until real art exists) — that's the only piece still
## deferred. This is deliberately the bare shell: given a LocalGrid, it
## can occupy a cell and be told to walk to another one. All position
## conversion goes through the grid's own get_world_position() rather
## than this script holding a separate TileMapLayer reference —
## LocalGrid is the single source for that.
##
## Occupancy transfers the INSTANT a step begins, not when its tween
## finishes — current_cell always reflects logical position, so two
## controllers can never both claim the same destination mid-
## transition. Cancelling mid-tween (a new move_to_cell() call) does
## NOT snap the visual back to current_cell's exact position — see the
## comment in _cancel_current_path() for why that would actually be
## wrong. The new path just continues smoothly from wherever the
## visual currently is.
##
## Expected scene shape (hand-authored, not built here):
##   CharacterController (Node2D, this script)
##   └── VisualRoot (Node2D)          -- assign to `visual_root` export
##       └── Placeholder (ColorRect)  -- stand-in for real sprite art
##
## Re-planning (Section 3.5, steps 2-5): the cell right before the one
## about to be stepped onto is checked lazily -- only immediately
## before committing to it, not by continuously watching the whole
## remaining path. If it's become blocked, re-plan once from the
## current cell toward the original goal; if the goal itself is now
## fully unreachable, fall back to whichever of the goal's neighbors
## is reachable via the shortest path from here. At most ONE re-plan
## happens per move_to_cell() call (step 5) -- once a path is
## committed, either the original or a re-planned one, every
## subsequent step executes unconditionally with no further
## availability check. Known accepted gap this carries: if a second
## blocking event happens later in that same committed path, this
## controller will still attempt to claim that cell's occupancy
## outright (overwriting whatever occupant token was already there)
## rather than detecting the conflict -- per the design doc's own
## scope for this pass, not something this phase tries to guard
## against.

signal arrived(cell: String)

## px/sec at Agility score 10 (modifier 0) -- untuned, same posture as
## every other placeholder in this project.
const BASE_SPEED_PLACEHOLDER := 60.0

## +/-10% speed per point of Agility MODIFIER (score_to_modifier),
## reusing the project's existing D&D-style stat-to-modifier curve
## rather than inventing a separate one for this. Untuned. Purely
## cosmetic (Design Doc Section 3.6) -- explicitly NOT the formula
## Combat will eventually use for Agility's mechanical effect on
## action points; that's a separate, unrelated calculation.
const AGILITY_SPEED_SCALE_PLACEHOLDER := 0.1

@export var visual_root: Node2D

## Which character this controller represents (Section 3.2). Read for
## the Agility speed multiplier below; sprite_id on the sheet is
## wired through for later but has nothing to act on yet, since
## VisualRoot only holds a placeholder ColorRect for now.
var character_sheet: CharacterSheet

var current_cell: String = ""

var _grid: LocalGrid
var _path: Array[String] = []
var _path_index: int = 0
var _tween: Tween
var _goal_cell: String = ""
var _has_replanned_this_move: bool = false


## Must be called once, right after instancing, before anything else.
## `grid` is the same LocalGrid the scene already built — not looked
## up globally, since a local grid is per-scene and ephemeral.
func setup(grid: LocalGrid, sheet: CharacterSheet, start_cell: String) -> void:
	_grid = grid
	character_sheet = sheet
	current_cell = start_cell
	_grid.set_occupant(current_cell, self)
	global_position = _grid.get_world_position(current_cell)


func move_to_cell(target_cell: String) -> void:
	if _grid == null:
		push_warning("CharacterController: move_to_cell() called before setup()")
		return

	_cancel_current_path()

	var path := _grid.find_path(current_cell, target_cell)
	if path.is_empty():
		push_warning("CharacterController: no path from %s to %s" % [current_cell, target_cell])
		return

	_goal_cell = target_cell
	_has_replanned_this_move = false
	_path = path
	_path_index = 0
	_advance_path()


func is_moving() -> bool:
	return _tween != null and _tween.is_valid()


func _cancel_current_path() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	_path.clear()
	_path_index = 0
	# Deliberately NOT snapping global_position to current_cell's world
	# position here. Killing a Tween doesn't revert the property it was
	# animating -- global_position is already wherever it visually
	# interpolated to at this exact frame, which is correct. An earlier
	# version forced a snap to current_cell's center on cancel, which
	# actually caused a visible stutter: current_cell is updated to a
	# step's destination the INSTANT that step begins (see
	# _advance_path()), before the tween sliding toward it has actually
	# gotten there -- so snapping to it mid-flight meant every redirect
	# instantly finished whatever slide was in progress, then started a
	# new one. Leaving position alone lets the next tween pick up
	# smoothly from wherever it actually is.


func _advance_path() -> void:
	_path_index += 1
	if _path_index >= _path.size():
		_path.clear()
		arrived.emit(current_cell)
		return

	var next_cell: String = _path[_path_index]

	# Lazy check: only right before committing to this specific step,
	# not watching the whole remaining path continuously. At most one
	# re-plan per move (see class-level note) -- once that's already
	# happened, this check is skipped entirely for the rest of this move.
	if not _has_replanned_this_move and not _grid.is_available(next_cell):
		_has_replanned_this_move = true
		_replan()
		return

	_commit_step(next_cell)


## Re-plan from wherever we currently are toward the original goal
## (step 3), or if the goal itself is now fully unreachable, toward
## whichever of the goal's neighbors is reachable via the shortest
## path from here (step 4). If not even a neighbor is reachable, stop
## in place rather than attempting anything further.
func _replan() -> void:
	var new_path := _grid.find_path(current_cell, _goal_cell)
	if new_path.is_empty():
		new_path = _path_to_nearest_reachable_neighbor(_goal_cell)
	if new_path.is_empty():
		push_warning("CharacterController: %s is fully unreachable from %s -- goal and all its neighbors are blocked, stopping" % [_goal_cell, current_cell])
		_path.clear()
		return

	_path = new_path
	_path_index = 0
	_advance_path()


func _path_to_nearest_reachable_neighbor(goal: String) -> Array[String]:
	var best_path: Array[String] = []
	for neighbor in _grid.get_neighbors(goal):
		var candidate := _grid.find_path(current_cell, neighbor)
		if candidate.is_empty():
			continue
		if best_path.is_empty() or candidate.size() < best_path.size():
			best_path = candidate
	return best_path


func _commit_step(next_cell: String) -> void:
	_face_direction(next_cell)

	# Claim the destination and release the origin immediately -- see
	# class-level note. current_cell is logical position from this
	# instant forward, even though the tween hasn't visually caught up.
	_grid.clear_occupant(current_cell)
	_grid.set_occupant(next_cell, self)
	current_cell = next_cell

	var target_position := _grid.get_world_position(next_cell)
	var distance := global_position.distance_to(target_position)
	var duration := distance / _get_move_speed()

	_tween = create_tween()
	_tween.tween_property(self, "global_position", target_position, duration)
	_tween.finished.connect(_advance_path)


## base_speed * agility_multiplier (Section 3.6). Recomputed per step
## rather than cached, in case Agility ever changes mid-playthrough --
## negligible cost either way at this scale.
func _get_move_speed() -> float:
	if character_sheet == null:
		return BASE_SPEED_PLACEHOLDER
	var agility_modifier := character_sheet.get_base_modifier(CharacterSheet.Stat.AGILITY)
	return BASE_SPEED_PLACEHOLDER * (1.0 + agility_modifier * AGILITY_SPEED_SCALE_PLACEHOLDER)


func _face_direction(next_cell: String) -> void:
	if visual_root == null:
		return
	var target_position := _grid.get_world_position(next_cell)
	if target_position.x < global_position.x:
		visual_root.scale.x = -absf(visual_root.scale.x)
	elif target_position.x > global_position.x:
		visual_root.scale.x = absf(visual_root.scale.x)
	# Straight vertical movement (target_position.x == global_position.x)
	# keeps whichever facing was already set -- no front/back animation
	# exists yet (Design Doc Section 4.2 only defines left/right sets).
