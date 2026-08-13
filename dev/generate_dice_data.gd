@tool
extends EditorScript

## Run ONCE from the Script Editor (File > Run, Ctrl+Shift+X) to
## generate the two DieFaceMapping resources dice rolling depends
## on. Face rotations start as Vector3.ZERO placeholders on every
## entry — they depend entirely on how your models are authored, so
## there's no way to guess correct defaults sight-unseen. See the
## calibration note at the top of die_face_mapping.gd for how to
## fill these in once you're testing rolls in the editor.
##
## Safe to re-run — existing files with the same names get
## overwritten. Re-running will NOT wipe out rotations you've
## already calibrated and saved, since it only touches these two
## specific files at these specific paths — just don't re-run this
## particular script after calibrating, or it'll reset them to zero.

const DATA_DIR := "res://systems/dice/data/"

const D6_MODEL_PATH := "res://systems/dice/models/D6.glb"
const D4_MODEL_PATH := "res://systems/dice/models/D4.glb"


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DATA_DIR)

	_make_mapping("d6", D6_MODEL_PATH, 6, DATA_DIR + "d6_face_mapping.tres")
	_make_mapping("d4", D4_MODEL_PATH, 4, DATA_DIR + "d4_face_mapping.tres")

	print("Dice face mapping data generated. Rotations are placeholders — calibrate before relying on them.")


func _make_mapping(die_id: String, model_path: String, face_count: int, save_path: String) -> void:
	var mapping := DieFaceMapping.new()
	mapping.die_id = die_id
	mapping.model_path = model_path
	mapping.face_count = face_count

	var rotations := {}
	for face in range(1, face_count + 1):
		rotations[face] = Vector3.ZERO
	mapping.face_rotations = rotations

	ResourceSaver.save(mapping, save_path)
