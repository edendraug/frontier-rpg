extends CanvasLayer
## DiceVisualizer — thin global autoload. Instantiates the
## hand-authored dice_tray.tscn once and forwards roll requests to
## it, so any system can call:
##
##   await DiceVisualizer.roll_and_show(result)
##
## from anywhere, without needing to know the tray is a real scene
## or where it lives. All the actual visual/physics work happens
## inside DiceTray — this file is deliberately almost empty.
##
## SETUP: Project Settings > Autoload, add this script, name it
## "DiceVisualizer". Update TRAY_SCENE_PATH below once
## dice_tray.tscn exists at its real location.

const TRAY_SCENE_PATH := "res://systems/dice/visualizer/dice_tray.tscn"

signal roll_finished(result: SkillCheckResult)

var _tray: DiceTray


func _ready() -> void:
	if not ResourceLoader.exists(TRAY_SCENE_PATH):
		push_warning("DiceVisualizer: %s not found — build the tray scene first." % TRAY_SCENE_PATH)
		return

	var packed: PackedScene = load(TRAY_SCENE_PATH)
	_tray = packed.instantiate()
	add_child(_tray)
	_tray.roll_finished.connect(func(result: SkillCheckResult): roll_finished.emit(result))


func roll_and_show(result: SkillCheckResult) -> void:
	if _tray == null:
		push_warning("DiceVisualizer: tray not loaded, skipping visual roll.")
		return
	await _tray.roll_and_show(result)


func hide_tray() -> void:
	if _tray != null:
		_tray.hide_tray()
