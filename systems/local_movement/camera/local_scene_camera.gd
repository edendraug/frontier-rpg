class_name LocalSceneCamera
extends Camera2D

## Local scene camera (Local Movement Design Doc, Section 3.11's
## "universal active-character-following camera" -- named there as a
## near-term need but not designed in the doc itself). Hand-authored,
## instanced into a local scene the same way CharacterController is --
## not an autoload, since it needs to sit in a specific scene's tree.
##
## NORMAL FOLLOWING: a continuous, framerate-independent lerp toward
## whichever CharacterController is currently active, per Cameron's
## call for "a little bit of lerp toward the active controller."
##
## SWITCHING: uses the exact same lerp, not a separate mechanism --
## the target just changes (potentially by a larger distance), and the
## same continuous smoothing naturally produces a short slide toward
## the new target rather than an instant cut. If a visually distinct
## switch transition is ever wanted, that's a deliberate follow-up,
## not something guessed at here.
##
## Finds its PlayerController via the "player_controller" group (same
## lookup the Debug Menu's Local Movement tab uses), deferred one
## frame so sibling _ready() order can't matter. Caches the active
## CharacterController directly and updates it only via
## PlayerController.switched_active_character -- per Cameron, polling
## get_active_character() every frame is an unnecessary cost.
##
## MANUAL OVERRIDE: holding middle mouse and dragging pans the camera
## and disengages following entirely until RETARGET_KEY is pressed,
## which snaps back to and resumes following the active character.
##
## ZOOM: mouse wheel, clamped. Godot's Camera2D.zoom is inverted from
## what you'd naively expect -- SMALLER values zoom IN, LARGER values
## zoom OUT -- so wheel-up (zoom in) decreases the value.
##
## Bounds/clamping to a room's edges is deliberately NOT done here --
## per Cameron's call, that's scene-specific and belongs authored in
## each real scene (e.g. via Camera2D's own limit_left/right/top/bottom,
## set per-scene), not hardcoded into this shared camera.

const FOLLOW_LERP_SPEED := 5.0    ## untuned; higher = snappier following
const RETARGET_KEY := KEY_SPACE   ## no established convention existed to match -- easily changed

const ZOOM_STEP := 0.2
const ZOOM_MIN := 1.0   ## most zoomed IN (smaller value = more magnified)
const ZOOM_MAX := 3.0   ## most zoomed OUT

var _player_controller: PlayerController
var _target_controller: CharacterController
var _manual_override: bool = false
var _dragging: bool = false


func _ready() -> void:
	call_deferred("_find_player_controller")


func _find_player_controller() -> void:
	_player_controller = get_tree().get_first_node_in_group("player_controller")
	if _player_controller == null:
		push_warning("LocalSceneCamera: no PlayerController found in this scene")
		return

	_target_controller = _player_controller.get_active_controller()
	_player_controller.switched_active_character.connect(_on_switched_active_character)


func _on_switched_active_character(controller: CharacterController) -> void:
	_target_controller = controller


func _process(delta: float) -> void:
	if _manual_override or _target_controller == null:
		return
	var weight := 1.0 - exp(-FOLLOW_LERP_SPEED * delta)
	global_position = global_position.lerp(_target_controller.global_position, weight)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
			if event.pressed:
				_manual_override = true
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_by(ZOOM_STEP)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_by(-ZOOM_STEP)
			return
		return

	if event is InputEventMouseMotion and _dragging:
		global_position -= event.relative / zoom
		return

	if event is InputEventKey and event.pressed and event.keycode == RETARGET_KEY:
		_manual_override = false
		_dragging = false


func _zoom_by(amount: float) -> void:
	var new_zoom: float = clampf(zoom.x + amount, ZOOM_MIN, ZOOM_MAX)
	zoom = Vector2(new_zoom, new_zoom)
