class_name TravelPromptWindow
extends CanvasLayer

## Small, reusable, Dialogue-INDEPENDENT arrival prompt (Expedition
## Scene Routing design doc, Section 3.5/4.4) -- one message string,
## exactly two labeled choices, one result signal. Covers every arrival
## moment ExpeditionSceneRouter needs: "You see a town on the horizon.
## Visit or keep moving?", "You have reached your destination. Make
## camp?", "You see a caravan up ahead. Stop to chat?" -- no per-prompt
## customization beyond message text and button labels.
##
## CanvasLayer (matching DebugMenu's own convention for a floating
## overlay that must render above gameplay regardless of camera/
## viewport) so it reads clearly above Expedition Hub's persistent UI.
## Instantiated fresh per prompt by ExpeditionSceneRouter
## (TRAVEL_PROMPT_SCENE.instantiate(), added under get_tree().root) and
## queue_free()'d immediately after choice_made fires -- this is not a
## reused/hidden-and-shown singleton the way DebugMenu is.
##
## HAND-AUTHOR THIS SCENE with the following node tree, root script set
## to this file:
##
##   TravelPromptWindow (CanvasLayer, this script)
##   └─ PanelContainer (or similar background frame)
##      └─ MarginContainer
##         └─ VBoxContainer
##            ├─ %MessageLabel (Label, autowrap enabled)
##            └─ HBoxContainer
##               ├─ %PositiveButton (Button)
##               └─ %NegativeButton (Button)
##
## The three %-marked nodes must be unique-in-owner, same convention as
## %GatherPoint/%TerrainLayer elsewhere in this project.

signal choice_made(accepted: bool)

@export var _message_label: Label
@export var _positive_button: Button
@export var _negative_button: Button


func _ready() -> void:
	_positive_button.pressed.connect(_on_positive_pressed)
	_negative_button.pressed.connect(_on_negative_pressed)


func setup(message: String, positive_label: String, negative_label: String) -> void:
	_message_label.text = message
	_positive_button.text = positive_label
	_negative_button.text = negative_label


func _on_positive_pressed() -> void:
	choice_made.emit(true)
	queue_free()


func _on_negative_pressed() -> void:
	choice_made.emit(false)
	queue_free()
