class_name VehicleVisualController
extends Node2D

## Visual/Actor layer for a vehicle -- the VehicleDefinition/
## VehicleInstance equivalent of systems/local_movement/actor/
## character_controller.gd, deliberately much simpler: a vehicle has no
## LocalGrid, no pathing, no per-instance stat driving its speed --
## whatever's actually moving the party (Travel Ambient's side-scroll,
## or wherever a parked vehicle just sits in a local scene) owns
## positioning entirely. This script only owns what a vehicle LOOKS
## like: which atlas is showing, which animation is playing, which way
## it's facing.
##
## Expected scene shape (hand-authored, not built here -- Cameron's own
## editor work, same convention CharacterController's scene already
## follows):
##   VehicleVisualController (Node2D, this script)
##   └── VisualRoot (Node2D)          -- assign to `visual_root` export; flipped for facing, same as CharacterController's
##       ├── AnimationPlayer          -- hand-authored "idle"/"roll" clips keyed on BodySprite:frame; assign to `animation_player` export
##       └── BodySprite (Sprite2D)    -- assign to `body_sprite` export; texture set at setup() time from a resolved VehicleDefinition.visual_atlas
##
## Animation names: "idle" and "roll" are this script's own pick, not
## confirmed content -- VehicleDefinition.visual_atlas's own comment
## only ever said "idle + whatever animation states a vehicle actually
## needs (e.g. a rolling-wheels clip)," never settling on a literal
## name. Hand-author clips under these two names to match play_animation()
## calls below as a starting point; renaming later costs nothing since
## every call site just passes a String.
##
## Only one direction is drawn (right-facing); left is the same frames
## mirrored via VisualRoot.scale.x -- same "save on art" convention
## CharacterController/AnimalVisualController both already use.
##
## Vehicles & Animals Design Doc v0.4, Section 4.2 (visual_atlas), per
## the "shared rig, swapped atlas" model confirmed in that conversation.

@export var visual_root: Node2D
@export var body_sprite: Sprite2D
@export var animation_player: AnimationPlayer


## Must be called once, right after instancing. `atlas` is already
## resolved (VehicleDefinition.visual_atlas, looked up by whoever's
## spawning this against the owned VehicleInstance's vehicle_type_id) --
## same "caller resolves once, this just applies it" posture
## CharacterController.setup() already uses for body_texture; this
## script never needs to know CaravanSystem or its definitions exist.
func setup(atlas: Texture2D) -> void:
	if body_sprite != null and atlas != null:
		body_sprite.texture = atlas

	play_animation("idle")


## Public, unlike CharacterController's private _play_animation() --
## that script decides for itself when to walk (it owns its own
## pathing); this one has no movement logic of its own, so whatever's
## actually driving the vehicle (a future Travel Ambient scene, a local
## scene) has to tell it when to switch state. No-ops entirely if
## animation_player was never assigned. Guards against restarting an
## already-playing clip from frame 0 every call, same reason
## CharacterController's own version does.
func play_animation(anim_name: String) -> void:
	if animation_player == null:
		return
	if animation_player.current_animation != anim_name:
		animation_player.play(anim_name)


## Explicit, unlike CharacterController._face_direction(), which derives
## facing from its own next-cell math -- this controller has no path of
## its own to derive a direction from, so whatever's driving it (Travel
## Ambient's direction of travel, most likely) decides and tells it
## directly.
func set_facing(facing_right: bool) -> void:
	if visual_root == null:
		return
	visual_root.scale.x = absf(visual_root.scale.x) if facing_right else -absf(visual_root.scale.x)
