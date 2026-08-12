class_name RollingDie
extends RigidBody3D

## One physical die inside the tray. Pooled and reused by
## DiceVisualizer rather than freed/recreated per roll.
##
## The result is decided by RNG before any physics runs (see
## SkillCheck) — this class's only job is to make the die's fall
## convincingly ARRIVE at that already-decided value, via a late
## corrective torque rather than a hard snap. See DiceTrayConfig for
## every tunable number used here.

var face_mapping: DieFaceMapping
var target_face: int = 1
var config: DiceTrayConfig

var _correcting: bool = false
var _settle_timer: float = 0.0
var _target_basis: Basis

signal settled


func setup(p_mapping: DieFaceMapping, p_config: DiceTrayConfig) -> void:
	face_mapping = p_mapping
	config = p_config

	# Only auto-generate collision if none was hand-placed in the
	# editor already — lets you author your own if the auto-hull
	# doesn't fit a particular model well.
	if _find_collision_shape(self) == null:
		var mesh_instance := _find_mesh_instance(self)
		if mesh_instance != null and mesh_instance.mesh != null:
			var shape := mesh_instance.mesh.create_convex_shape()
			var collision := CollisionShape3D.new()
			collision.shape = shape
			add_child(collision)
		else:
			push_warning("RollingDie: no MeshInstance3D found under %s — check the model file." % face_mapping.model_path)


func _find_collision_shape(node: Node) -> CollisionShape3D:
	if node is CollisionShape3D:
		return node
	for child in node.get_children():
		var found := _find_collision_shape(child)
		if found != null:
			return found
	return null


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_mesh_instance(child)
		if found != null:
			return found
	return null


## Fully activates or deactivates this die — visibility, physics,
## AND collision together, so "inactive" never leaves a partial
## state (e.g. invisible but still collidable, which is exactly
## what was letting hidden dice bump into thrown ones).
func set_active(active: bool) -> void:
	visible = active
	freeze = not active
	for child in get_children():
		if child is CollisionShape3D:
			child.disabled = not active


## Resets physics state and throws with a randomized impulse/torque.
## Called fresh for each roll — dice are pooled, not recreated.
func throw_die(spawn_position: Vector3, p_target_face: int) -> void:
	target_face = p_target_face
	_correcting = false
	_settle_timer = 0.0
	set_active(true)
	sleeping = false

	global_position = spawn_position
	rotation = Vector3(randf_range(0, TAU), randf_range(0, TAU), randf_range(0, TAU))
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

	var throw_dir := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
	var impulse_strength := randf_range(config.throw_impulse_min, config.throw_impulse_max)
	apply_central_impulse(throw_dir * impulse_strength + Vector3.UP * 0.5)

	var torque_axis := Vector3(
		randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)
	).normalized()
	var torque_strength := randf_range(config.throw_torque_min, config.throw_torque_max)
	apply_torque_impulse(torque_axis * torque_strength)

	var target_rotation_degrees: Vector3 = face_mapping.face_rotations.get(target_face, Vector3.ZERO)
	_target_basis = Basis.from_euler(target_rotation_degrees * (PI / 180.0))


func _physics_process(delta: float) -> void:
	if freeze:
		return

	_settle_timer += delta
	if _settle_timer > config.max_settle_time:
		force_settle()
		return

	var ang_speed := angular_velocity.length()
	var lin_speed := linear_velocity.length()

	if not _correcting:
		if ang_speed < config.settle_angular_velocity_threshold \
				and lin_speed < config.settle_linear_velocity_threshold:
			_correcting = true

	if _correcting:
		var diff_basis := _target_basis * global_transform.basis.inverse()
		var diff_quat := diff_basis.get_rotation_quaternion()

		# Extracted manually rather than relying on Quaternion helper
		# methods that may not exist across engine versions — this
		# formula is standard and always correct.
		var angle := 2.0 * acos(clamp(diff_quat.w, -1.0, 1.0))
		var axis := Vector3(diff_quat.x, diff_quat.y, diff_quat.z)
		axis = axis.normalized() if axis.length() > 0.0001 else Vector3.UP

		if angle > 0.001:
			apply_torque(axis * angle * config.correction_strength)
			apply_torque(-angular_velocity * config.correction_damping)

		if rad_to_deg(angle) < config.freeze_alignment_tolerance_degrees and lin_speed < 0.05:
			force_settle()


## Immediately snaps to the target face and freezes — used both for
## the safety timeout above and, externally, when a new roll needs
## to supersede a die that's still mid-animation from a previous one.
func force_settle() -> void:
	global_transform.basis = _target_basis
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = true
	settled.emit()


## Disables physics AND collision without hiding the die — used when
## handing a settled die off to a purely kinematic display tween, so
## nothing can nudge it (or be nudged by it) while it's animating
## into position. Distinct from set_active(false), which also hides.
func disable_physics_for_display() -> void:
	freeze = true
	for child in get_children():
		if child is CollisionShape3D:
			child.disabled = true


## The target rotation, but with yaw (rotation around the vertical
## axis) zeroed out — since spinning around Y never changes which
## face is up, this gives every displayed die the same "up-facing
## and squared-off" look instead of whatever random yaw the physics
## throw happened to leave it at.
func get_display_target_quaternion() -> Quaternion:
	var target_rotation_degrees: Vector3 = face_mapping.face_rotations.get(target_face, Vector3.ZERO)
	var clean_rotation := Vector3(target_rotation_degrees.x, 0.0, target_rotation_degrees.z)
	return Basis.from_euler(clean_rotation * (PI / 180.0)).get_rotation_quaternion()
