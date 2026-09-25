class_name AnimalVisualController
extends Node2D

## Visual/Actor layer for an animal -- the AnimalDefinition/
## AnimalInstance equivalent of systems/local_movement/actor/
## character_controller.gd, deliberately much simpler: no LocalGrid, no
## pathing, no per-instance stat driving speed -- whatever's actually
## moving the party (Travel Ambient's side-scroll, or wherever a parked
## animal just sits in a local scene) owns positioning entirely. This
## script only owns what an animal LOOKS like: which atlas is showing,
## which animation is playing, which way it's facing. Deliberately
## carries no knowledge of AnimalInstance.role (HITCHED/PACK/UNASSIGNED)
## -- if hitched-vs-unhitched ever needs to look different beyond just
## walking vs standing, that's real content-authoring work for whoever
## drives this controller to decide, not something this script should
## presume.
##
## Expected scene shape (hand-authored, not built here -- Cameron's own
## editor work, same convention CharacterController's scene already
## follows):
##   AnimalVisualController (Node2D, this script)
##   └── VisualRoot (Node2D)          -- assign to `visual_root` export; flipped for facing, same as CharacterController's
##       ├── AnimationPlayer          -- hand-authored "idle"/"walk" clips keyed on BodySprite:frame; assign to `animation_player` export
##       └── BodySprite (Sprite2D)    -- assign to `body_sprite` export; texture set at setup() time from a resolved AnimalDefinition.visual_atlas
##
## "idle" and "walk" match AnimalDefinition.visual_atlas's own comment
## exactly (idle + a walk cycle) -- same two names CharacterController
## already expects, not a new convention. Only one direction is drawn
## (right-facing); left is the same frames mirrored via
## VisualRoot.scale.x, same convention as CharacterController and
## VehicleVisualController both already use.
##
## Vehicles & Animals Design Doc v0.4, Section 4.4 (visual_atlas), per
## the "shared rig, swapped atlas" model confirmed in that conversation.

@export var visual_root: Node2D
@export var body_sprite: Sprite2D
@export var animation_player: AnimationPlayer


## Must be called once, right after instancing. `atlas` is already
## resolved (AnimalDefinition.visual_atlas, looked up by whoever's
## spawning this against the owned AnimalInstance's animal_type_id) --
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
## actually driving the animal (a future Travel Ambient scene, a local
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
