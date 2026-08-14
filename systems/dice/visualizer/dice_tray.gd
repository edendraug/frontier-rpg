class_name DiceTray
extends Control

## Controller for the hand-authored dice_tray.tscn. This script
## builds NOTHING — every visual piece (camera, lighting, floor,
## walls, the dice themselves) is a real node you place and tune
## directly in the editor's 3D viewport. This script only knows how
## to throw the dice you've wired up and wait for them to settle.
##
## EXPECTED SCENE SHAPE (rough guide, exact names don't matter —
## wire the exported fields below to whatever you actually build):
##
##   DiceTray (Control, this script)          <- size this to taste
##   └── SubViewportContainer (stretch = true)
##       └── SubViewport (transparent_bg = true)
##           ├── Camera3D
##           ├── DirectionalLight3D
##           ├── WorldEnvironment
##           ├── Floor (StaticBody3D + CollisionShape3D)
##           ├── Walls (StaticBody3D + CollisionShape3D, x4)
##           ├── D6 dice (RigidBody3D + rolling_die.gd, x2)
##           └── D4 dice (RigidBody3D + rolling_die.gd, x2)
##
## Position the die nodes wherever looks right as their "at rest"
## spot in the tray — rolls lift them from that position and jostle
## randomly from there, so their editor placement doubles as the
## default spawn point.

@export var viewport: SubViewport

@export var d6_dice: Array[RollingDie] = []
@export var d4_dice: Array[RollingDie] = []

## Empty Node3D/Marker3D nodes placed in the editor, one per d6,
## wherever you want each settled die to line up for display.
## Slot[i] receives the i-th d6 in throw order.
@export var d6_display_slots: Array[Node3D] = []

## A SINGLE anchor node for d4 display — since there's 0-2 of them
## depending on skill rank, they're auto-centered along the anchor's
## local X axis rather than needing individually placed slots. One
## d4 sits exactly on the anchor; two are spaced symmetrically
## around it.
@export var d4_display_slot: Node3D
@export var d4_display_spacing: float = 0.5

@export var display_tween_duration: float = 0.6
@export var display_tween_trans: Tween.TransitionType = Tween.TRANS_CUBIC
@export var display_tween_ease: Tween.EaseType = Tween.EASE_OUT

## Speeds up ONLY the physics-tumbling phase of a roll (thrown ->
## settled), restored to 1.0 before the settle-to-display tween plays
## so the finish still reads at normal speed. This is a genuine
## Engine.time_scale change, not something scoped purely to this
## SubViewport -- Godot has no built-in way to scale time for just
## one scene/viewport. In practice nothing else animates during a
## roll (callers disable their Roll button for the duration), so the
## risk of this affecting anything else is low, but it's not true
## isolation. Tune to taste in the Inspector.
@export var rolling_time_scale: float = 1.5

## Auto-dismiss timing -- after a roll fully resolves (dice settled
## and tweened to display position), the tray holds the result on
## screen for hold_duration, then fades its own opacity to 0 over
## fade_out_duration and hides. Lives entirely inside DiceTray so it
## applies no matter what calls roll_and_show() -- callers never need
## to remember to dismiss the tray themselves. Tune to taste.
@export var hold_duration: float = 0.75
@export var fade_out_duration: float = 0.3

@export var d6_mapping: DieFaceMapping
@export var d4_mapping: DieFaceMapping
@export var config: DiceTrayConfig

signal roll_finished(result: SkillCheckResult)

var _active_dice: Array = []
var _pending_settles: int = 0
var _roll_id: int = 0
var _fade_tween: Tween


func _ready() -> void:
	visible = false

	if config == null:
		push_warning("DiceTray: no DiceTrayConfig assigned in the Inspector — using defaults.")
		config = DiceTrayConfig.new()

	if d6_mapping == null:
		push_warning("DiceTray: no d6_mapping assigned in the Inspector — d6 rolls will fail.")
	if d4_mapping == null:
		push_warning("DiceTray: no d4_mapping assigned in the Inspector — d4 rolls will fail.")

	for die in d6_dice:
		if d6_mapping != null:
			die.setup(d6_mapping, config)
		die.set_active(false)

	for die in d4_dice:
		if d4_mapping != null:
			die.setup(d4_mapping, config)
		die.set_active(false)


## Animates an already-resolved result. Await this to know when
## every die has physically settled. If a previous roll is still
## animating when this is called, that roll's dice are snapped
## straight to their result rather than left running concurrently
## with the new one.
func roll_and_show(result: SkillCheckResult) -> void:
	_roll_id += 1
	var this_roll := _roll_id
	_finish_active_dice_immediately()

	# A previous roll's auto-fade-out may still be running if this
	# call arrives during its hold/fade window -- kill it and snap
	# opacity back to full BEFORE showing, so it can't keep animating
	# modulate.a toward 0 underneath this fresh roll.
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	modulate.a = 1.0

	visible = true
	if viewport != null:
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	Engine.time_scale = rolling_time_scale

	_active_dice = []

	for i in result.base_dice.size():
		if i >= d6_dice.size():
			push_warning("DiceTray: check needs %d d6 but only %d are wired up." % [result.base_dice.size(), d6_dice.size()])
			break
		var die: RollingDie = d6_dice[i]
		var spawn_pos: Vector3 = die.global_position + Vector3(randf_range(-0.3, 0.3), 1.5, randf_range(-0.3, 0.3))
		die.throw_die(spawn_pos, result.base_dice[i])
		_active_dice.append(die)

	for i in d4_dice.size():
		var die: RollingDie = d4_dice[i]
		if i < result.bonus_dice.size():
			var spawn_pos: Vector3 = die.global_position + Vector3(randf_range(-0.3, 0.3), 1.8, randf_range(-0.3, 0.3))
			die.throw_die(spawn_pos, result.bonus_dice[i])
			_active_dice.append(die)
		else:
			# Not needed for this roll (Unskilled/Skilled check) —
			# fully deactivate any d4 left over from a previous
			# Expert roll, not just hide it, so it can't still be
			# bumped by dice that ARE rolling this time.
			die.set_active(false)

	_pending_settles = _active_dice.size()
	for die in _active_dice:
		die.settled.connect(_on_die_settled, CONNECT_ONE_SHOT)

	# Give physics a beat to actually start moving before polling
	# for "all settled" — avoids a same-frame false-positive.
	await get_tree().create_timer(0.1).timeout
	while _pending_settles > 0 and this_roll == _roll_id:
		await get_tree().process_frame

	# A newer roll superseded this one while we were waiting — let
	# THAT call be the one that finishes and emits roll_finished. Also
	# means THIS call must NOT touch time_scale here — a newer roll
	# may already be actively tumbling at the sped-up rate, and
	# resetting it now would incorrectly slow that one down mid-roll.
	if this_roll != _roll_id:
		return

	Engine.time_scale = 1.0

	await _tween_dice_to_display(_active_dice)
	if this_roll != _roll_id:
		return

	if viewport != null:
		viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	roll_finished.emit(result)

	# Deliberately NOT awaited -- runs as a detached background task
	# so the caller gets control back right here, exactly as before
	# this existed. The hold+fade+hide happens on its own afterward.
	_auto_hide_after_delay(this_roll)


## Settled dice usually land a little off — slightly out of position,
## and only within freeze_alignment_tolerance_degrees of their exact
## target rotation rather than dead-on. This tweens each die from
## wherever it actually landed into a clean display position with an
## exact, yaw-squared rotation — physics and collision are fully
## disabled first so nothing fights the animation.
func _tween_dice_to_display(dice: Array) -> void:
	var d6_active: Array = []
	var d4_active: Array = []
	for die in dice:
		if die in d6_dice:
			d6_active.append(die)
		elif die in d4_dice:
			d4_active.append(die)

	var tween := create_tween()
	tween.set_parallel(true)

	for i in d6_active.size():
		if i >= d6_display_slots.size():
			push_warning("DiceTray: %d d6 active but only %d d6_display_slots assigned." % [d6_active.size(), d6_display_slots.size()])
			break
		_tween_die_to_position(tween, d6_active[i], d6_display_slots[i].global_position)

	if d4_active.size() > 0:
		if d4_display_slot == null:
			push_warning("DiceTray: %d d4 active but no d4_display_slot assigned." % d4_active.size())
		else:
			var positions := _compute_centered_positions(d4_display_slot, d4_active.size())
			for i in d4_active.size():
				_tween_die_to_position(tween, d4_active[i], positions[i])

	await tween.finished


## Centers 1 or 2 (or more, if this ever grows) positions along the
## anchor's own local X axis — using the anchor's rotated basis
## rather than world X means rotating the anchor node in the editor
## tilts the whole line, for free.
func _compute_centered_positions(anchor: Node3D, count: int) -> Array:
	var positions: Array = []
	if count <= 0:
		return positions
	if count == 1:
		positions.append(anchor.global_position)
		return positions

	var axis: Vector3 = anchor.global_transform.basis.x.normalized()
	var total_width := d4_display_spacing * (count - 1)
	var start := anchor.global_position - axis * (total_width / 2.0)
	for i in count:
		positions.append(start + axis * (d4_display_spacing * i))
	return positions


func _tween_die_to_position(tween: Tween, die: RollingDie, end_pos: Vector3) -> void:
	die.disable_physics_for_display()

	var start_pos: Vector3 = die.global_position
	var start_quat: Quaternion = die.global_transform.basis.get_rotation_quaternion()
	var end_quat: Quaternion = die.get_display_target_quaternion()

	tween.tween_method(
		func(t: float) -> void:
			die.global_position = start_pos.lerp(end_pos, t)
			die.global_transform.basis = Basis(start_quat.slerp(end_quat, t)),
		0.0, 1.0, display_tween_duration
	).set_trans(display_tween_trans).set_ease(display_tween_ease)


func _finish_active_dice_immediately() -> void:
	for die in _active_dice:
		if die != null and not die.freeze:
			die.force_settle()
	_active_dice = []
	_pending_settles = 0


func _on_die_settled() -> void:
	_pending_settles -= 1


## Holds the result on screen, fades the tray out, then hides it --
## fully automatic, no caller has to remember to dismiss anything.
## Checks this_roll against _roll_id at each stage so a NEWER roll
## interrupting mid-hold or mid-fade correctly abandons this sequence
## rather than hiding or fading out dice that aren't its own.
##
## Waits out the fade with a plain timer rather than awaiting the
## tween's own `finished` signal -- killing an in-flight tween (which
## a newer roll does, see roll_and_show) does NOT fire `finished`, so
## awaiting that directly would leave this coroutine hanging forever
## if superseded mid-fade.
func _auto_hide_after_delay(this_roll: int) -> void:
	await get_tree().create_timer(hold_duration).timeout
	if this_roll != _roll_id:
		return  # a newer roll started during the hold -- leave its dice alone

	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 0.0, fade_out_duration)

	await get_tree().create_timer(fade_out_duration).timeout
	if this_roll != _roll_id:
		return  # superseded mid-fade -- the newer roll already reclaimed modulate.a

	hide_tray()


func hide_tray() -> void:
	visible = false
	modulate.a = 1.0  # reset in case this was reached via a fade-out, not a direct call
