class_name DieFaceMapping
extends Resource

## Maps each face value of a die to the local rotation (in degrees)
## that shows that face pointing straight up (+Y). This is what lets
## a die "arrive" at an RNG-decided result convincingly instead of
## actually needing true physics to determine the outcome.
##
## CALIBRATION (do this once your model is in the project):
## 1. Run the dice tester and trigger a roll — with all rotations
##    still at the Vector3.ZERO placeholder, every die will settle
##    showing whatever face the placeholder happens to leave facing
##    up. That's expected, not a bug.
## 2. Rotate the model by hand (in a test scene, or by editing the
##    rotation_degrees in this resource directly and re-testing)
##    until each specific face is the one pointing up, and note the
##    Vector3 that got you there.
## 3. Fill in face_rotations with those values, one per face.
##
## These values are entirely dependent on how YOUR model is
## authored (which local axis you modeled "up" against) — there's
## no way to guess correct defaults without the actual mesh, so
## every entry below starts as an explicit placeholder.

@export var die_id: String = ""              # e.g. "d6", "d4"
@export var model_path: String = ""          # e.g. "res://systems/dice/models/D6.glb"
@export var face_count: int = 6

## face value (int) -> Vector3 rotation_degrees that shows it face-up.
@export var face_rotations: Dictionary = {}
