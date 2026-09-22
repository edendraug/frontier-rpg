class_name LocalSceneRoot
extends Node2D

## Reusable per-scene setup ("template") for any real local scene
## (Local Movement Design Doc, Section 3.9) — the building block that
## lets many different real scenes (camps, forts, settlements) share
## one setup path instead of each hand-rolling grid/spawn/camera code
## the way every dev/ tester so far has. Attach as a real scene's root
## script alongside its own %TerrainLayer, %ObstacleLayer, and a
## single %GatherPoint (see GatherPoint) — nothing about this script
## is specific to any one scene's content.
##
## PARTY SELECTION: configure() may be called BEFORE this node enters
## the tree (same convention PartyCharacterCard.configure() already
## uses) to specify which party members should actually spawn here --
## empty (the default, if configure() is never called) means "spawn
## the entire current PartyManager roster." No system decides a real
## subset yet (e.g. "only the scout goes in") -- this is the seam for
## whenever one exists, not something built out further here.
##
## SPAWN PLACEMENT: every selected character spawns at or near the
## Gather Point via LocalGrid.find_open_cells_near(), so multiple
## characters spread across the Gather Point cell and its neighbors
## instead of stacking on one cell. The main character is spawned
## (and therefore registered, and therefore made PlayerController's
## default active character) first, since PartyManager.get_roster()
## always returns it at index 0.
##
## CAMERA: auto-spawns a LocalSceneCamera as part of setup, rather
## than requiring one hand-placed per scene -- one less thing to
## remember when authoring new scenes, and pairs naturally with a
## future per-scene SubViewport (each would need its own current
## camera regardless).
##
## INTERACTABLES: any WorldInteractable anywhere in the scene tree
## registers itself with the grid before party spawning happens, so an
## interactable placed near the Gather Point correctly blocks a
## character from spawning on top of it.
##
## LOCAL TIME PROGRESSION: while this scene is active, advances
## TimeSystem at a fixed real-seconds-per-in-game-minute rate -- a
## separate, simpler mechanism from Travel's distance/pace-driven time
## advancement (a room has no equivalent of terrain
## base_travel_minutes, so this doesn't touch or reuse any of Travel's
## own logic, per Cameron's call). Pauses automatically whenever
## PlayerController.is_control_locked() is true (e.g. a dialogue
## window open) -- free reuse of the same "something modal is
## happening" check everything else in this system already respects,
## rather than a second, parallel one. Set advances_time = false on a
## scene that should freeze the clock entirely (a scripted/story-only
## room, say).
##
## Update CONTROLLER_SCENE/CAMERA_SCENE below if your actual file
## paths differ.

const CONTROLLER_SCENE := preload("res://systems/local_movement/actor/character_controller.tscn")
const CAMERA_SCENE := preload("res://systems/local_movement/camera/local_scene_camera.tscn")

## Untuned placeholder, same posture as every other tunable value in
## this project -- Cameron's own example rate (1 in-game minute per
## 30 real seconds).
const REAL_SECONDS_PER_GAME_MINUTE := 10.0

@export var advances_time: bool = true

var _party_override: Array[CharacterSheet] = []
var _grid: LocalGrid
var _player_controller: PlayerController
var _time_accumulator: float = 0.0


## Call BEFORE this node enters the tree if a subset of the roster
## should spawn instead of everyone. Empty (or never called at all) =
## spawn PartyManager.get_roster() in full.
func configure(party_members: Array[CharacterSheet] = []) -> void:
	_party_override = party_members


func _ready() -> void:
	_grid = LocalGrid.new(%TerrainLayer, %ObstacleLayer)

	_player_controller = PlayerController.new()
	add_child(_player_controller)
	_player_controller.setup(_grid)

	_register_interactables()
	_spawn_party(_player_controller)
	_spawn_camera()


func _process(delta: float) -> void:
	if not advances_time:
		return
	if _player_controller != null and _player_controller.is_control_locked():
		return

	_time_accumulator += delta
	var whole_minutes := int(_time_accumulator / REAL_SECONDS_PER_GAME_MINUTE)
	if whole_minutes > 0:
		_time_accumulator -= whole_minutes * REAL_SECONDS_PER_GAME_MINUTE
		TimeSystem.pass_minutes(whole_minutes)


## Order matters: must run before _spawn_party(), so an interactable
## near the Gather Point is already occupying its cell by the time
## find_open_cells_near() looks for spawn placements.
func _register_interactables() -> void:
	for interactable in find_children("*", "WorldInteractable", true, false):
		(interactable as WorldInteractable).register_with_grid(_grid)


func _spawn_party(player_controller: PlayerController) -> void:
	var party: Array[CharacterSheet] = _party_override if not _party_override.is_empty() else PartyManager.get_roster()
	if party.is_empty():
		push_warning("LocalSceneRoot: no party members to spawn (empty roster and no configure() override)")
		return

	var gather_point: Node2D = get_node_or_null("%GatherPoint")
	if gather_point == null:
		push_warning("LocalSceneRoot: no %GatherPoint found in this scene")
		return

	var gather_cell := _grid.get_coord_at_global_position(gather_point.global_position)
	if gather_cell == "":
		push_warning("LocalSceneRoot: %GatherPoint doesn't land on any cell in this scene's grid")
		return

	var spawn_cells := _grid.find_open_cells_near(gather_cell, party.size())
	if spawn_cells.size() < party.size():
		push_warning(
			"LocalSceneRoot: only found %d open cell(s) near the Gather Point for %d character(s) -- the rest won't be spawned"
			% [spawn_cells.size(), party.size()]
		)

	var registry := PartyManager.get_registry()

	for i in spawn_cells.size():
		var sheet: CharacterSheet = party[i]
		var sprite_set: SpriteSetDefinition = registry.sprite_sets.get(sheet.sprite_id)
		var texture: Texture2D = sprite_set.texture if sprite_set != null else null

		var controller: CharacterController = CONTROLLER_SCENE.instantiate()
		add_child(controller)
		controller.setup(_grid, sheet, spawn_cells[i], texture)

		player_controller.register_controller(controller)


func _spawn_camera() -> void:
	var camera: LocalSceneCamera = CAMERA_SCENE.instantiate()
	add_child(camera)
