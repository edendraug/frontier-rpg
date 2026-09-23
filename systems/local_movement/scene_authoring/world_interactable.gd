class_name WorldInteractable
extends Area2D

## Base class for anything in a local scene the player can click on to
## trigger something -- a signpost, a lootable, a scripted event
## trigger. Deliberately built as an Area2D + CollisionShape2D (a
## departure from the rest of Local Movement's "no physics" pattern --
## LocalGrid already tracks occupancy/movement logically, but CLICK
## DETECTION on a specific object is a genuinely different problem,
## and Area2D is the idiomatic Godot tool for it).
##
## SCENE SHAPE (hand-authored, single drag-and-drop node):
##   WorldInteractable (Area2D, this script or a subclass)
##   ├── CollisionShape2D    -- defines its clickable footprint
##   └── Sprite2D            -- whatever art represents it
## input_pickable must be enabled (default true for Area2D) for
## input_event to fire.
##
## GRID OCCUPANCY: register_with_grid(grid), called once by
## LocalSceneRoot after it builds the scene's LocalGrid (walking its
## own tree for every WorldInteractable), permanently occupies this
## node's own cell -- resolved from wherever it's actually positioned,
## same "derive from visual placement" trick GatherPoint already uses,
## not a second hand-authored coordinate. This is deliberately modeled
## as occupancy, not a painted ObstacleLayer tile: an interactable
## isn't terrain, it's much more like a permanent occupant that never
## leaves, and reusing occupancy means find_open_cells_near() already
## routes characters to an adjacent cell instead of on top of it, with
## no second authoring step.
##
## CLICK HANDLING: captures its own clicks via Area2D.input_event and
## marks them handled, so PlayerController's plain move-to-cell
## _unhandled_input() never sees the same click -- this class calls
## OUT to PlayerController (found via the "player_controller" group,
## same as everywhere else that crosses this boundary), rather than
## PlayerController holding a registry of interactables. Keeps the two
## systems decoupled in one direction only.
##
## DIALOGUE: show_dialogue_on_interact toggles whether interact()
## displays blurb_lines through the real Dialogue system before
## running any custom behavior -- reuses DialoguePlayer/DialogueWindow
## rather than a second, parallel text-display mechanism (a signpost's
## blurb is really just a one-line, no-choices dialogue tree). One
## line shown at a time; clicking to advance is DialogueWindow's own
## existing behavior, nothing new needed for that. Toggle off entirely
## for a unique interaction that shouldn't show any blurb at all.
##
## CUSTOM BEHAVIOR: the common case is dragging one or more
## InteractionBehavior .tres resources into custom_behaviors -- e.g.
## AddJournalEntryBehavior, TriggerEventBehavior -- each small and
## single-purpose, composable on one interactable, reusable across
## many without subclassing anything. Full subclassing (override
## _on_interact()) remains available for whatever a resource-slot
## genuinely can't express.
##
## CONSUMPTION (three states, not a single toggle):
##   REPEATABLE (default)   -- any number of times, nothing changes.
##   CONSUME_IN_PLACE        -- single use; the node stays in the
##                              world (a berry bush picked bare, still
##                              a solid obstacle) but interact() no-ops
##                              on every click after the first.
##   CONSUME_AND_REMOVE       -- single use; queue_free()'d entirely
##                              (a pickup added to inventory).
## texture_after_consume/visual_sprite are a separate, optional pair --
## meaningful with CONSUME_IN_PLACE (swaps visual_sprite's texture the
## moment it's consumed), simply unused if either is left blank.
##
## A CONSUME_AND_REMOVE interactable can be freed while another
## character is still mid-approach toward it (e.g. two party members
## clicked the same pickup before either arrived) -- PlayerController's
## pending-arrival callback checks is_instance_valid() before calling
## interact() specifically to guard against this.
##
## BLOCKS_MOVEMENT: defaults true (existing behavior, unchanged) --
## register_with_grid() occupies this node's own cell, so
## PlayerController.request_interact() paths to the nearest open
## NEIGHBOR, never on top of it (correct for a solid object). Set
## false for something meant to be walked ONTO instead -- a doorway or
## exit marker (e.g. LeaveLocationBehavior's own Leave interactable),
## which should never have occupied the cell in the first place.
##
## HOVER_HIGHLIGHT: opt-in, off by default, so nothing existing
## changes. When enabled, visual_sprite (the same field CONSUME_IN_PLACE
## already uses) starts at hover_opacity_default's alpha and tweens to
## hover_opacity_hovered on Area2D's own native mouse_entered/
## mouse_exited signals -- no custom hover polling needed, Godot
## already provides this for any Area2D with input_pickable on.
## Cameron's use case: a Leave marker that reads as slightly
## transparent/unobtrusive by default, brightening under the cursor to
## confirm it's clickable.

enum ConsumeMode {
	REPEATABLE,
	CONSUME_IN_PLACE,
	CONSUME_AND_REMOVE,
}

@export var show_dialogue_on_interact: bool = true
@export var blurb_lines: Array[String] = []
@export var custom_behaviors: Array[InteractionBehavior] = []

@export var consume_mode: ConsumeMode = ConsumeMode.REPEATABLE
@export var texture_after_consume: Texture2D
@export var visual_sprite: Sprite2D

@export var blocks_movement: bool = true

@export var hover_highlight: bool = false
@export var hover_opacity_default: float = 0.5
@export var hover_opacity_hovered: float = 1.0
@export var hover_tween_duration: float = 0.15

var _grid: LocalGrid
var _coord: String = ""
var _consumed: bool = false


func _ready() -> void:
	input_event.connect(_on_input_event)

	if hover_highlight:
		mouse_entered.connect(_on_mouse_entered)
		mouse_exited.connect(_on_mouse_exited)
		if visual_sprite != null:
			visual_sprite.modulate.a = hover_opacity_default


func _on_mouse_entered() -> void:
	if visual_sprite != null:
		create_tween().tween_property(visual_sprite, "modulate:a", hover_opacity_hovered, hover_tween_duration)


func _on_mouse_exited() -> void:
	if visual_sprite != null:
		create_tween().tween_property(visual_sprite, "modulate:a", hover_opacity_default, hover_tween_duration)


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		var player_controller: PlayerController = get_tree().get_first_node_in_group("player_controller")
		if player_controller != null:
			player_controller.request_interact(self)


## Called by LocalSceneRoot once, after it builds the scene's grid.
func register_with_grid(grid: LocalGrid) -> void:
	_grid = grid
	_coord = grid.get_coord_at_global_position(global_position)
	if _coord == "":
		push_warning("WorldInteractable '%s' doesn't land on any cell in this scene's grid" % name)
		return
	if blocks_movement:
		grid.set_occupant(_coord, self)


## Called by PlayerController once the approaching character arrives.
## Never override this directly -- override _on_interact() instead.
func interact(character: CharacterController) -> void:
	if _consumed:
		return  # CONSUME_IN_PLACE already used

	if show_dialogue_on_interact and not blurb_lines.is_empty():
		_show_blurb()
	_on_interact(character)
	_apply_consumption()


func _apply_consumption() -> void:
	match consume_mode:
		ConsumeMode.CONSUME_IN_PLACE:
			_consumed = true
			if texture_after_consume != null and visual_sprite != null:
				visual_sprite.texture = texture_after_consume
		ConsumeMode.CONSUME_AND_REMOVE:
			if blocks_movement and _grid != null and _coord != "":
				_grid.clear_occupant(_coord)
			queue_free()


## Override point for custom behavior beyond what custom_behaviors
## already covers -- a subclass that needs something the resource-slot
## system genuinely can't express. Default implementation just runs
## every assigned custom_behaviors entry in order; a subclass
## overriding this WITHOUT calling super._on_interact() opts out of
## resource-slot behaviors entirely in favor of pure code, while one
## that DOES call super first gets both.
func _on_interact(character: CharacterController) -> void:
	for behavior in custom_behaviors:
		if behavior != null:
			behavior.execute(character, self)


## Builds a tiny ephemeral DialogueTree from blurb_lines (chained Line
## nodes, no speaker, no choices) and shows it through the real
## Dialogue system, exactly the same door a real NPC conversation uses
## -- just via DialoguePlayer.start_with_tree()/
## DialogueWindow.open_with_tree() instead of an actor_id, since a
## signpost was never meant to be a registered Actor.
func _show_blurb() -> void:
	var dialogue_window: DialogueWindow = get_tree().get_first_node_in_group("dialogue_window")
	if dialogue_window == null:
		push_warning("WorldInteractable '%s': no DialogueWindow found (is Expedition Hub loaded?)" % name)
		return

	var tree := _build_blurb_tree()
	var context := DialogueContext.new(PartyManager.get_main_character(), PartyManager.get_registry())
	var player := DialoguePlayer.new(null, context)  # null tree_registry -- start_with_tree() never touches it
	dialogue_window.open_with_tree(player, tree)


func _build_blurb_tree() -> DialogueTree:
	var tree := DialogueTree.new()
	tree.tree_id = "__interactable_blurb__"
	tree.start_node_id = "line_0"

	for i in blurb_lines.size():
		var line := DialogueLineNode.new()
		line.node_id = "line_%d" % i
		var variant := DialogueLineVariant.new()
		variant.text = blurb_lines[i]
		line.variants = [variant]
		line.next = "line_%d" % (i + 1) if i + 1 < blurb_lines.size() else ""
		tree.nodes[line.node_id] = line

	return tree
