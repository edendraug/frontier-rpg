@tool
class_name DialogueStructureNode
extends DialogueGraphNode

## A "stage" of dialogue: no content of its own, purely topology.
## Represents a point in the conversation where the player is offered
## some set of choices (Dialogue Graph Node Restructure design doc,
## Section 4).
##
## Deliberately carries no other data - no text, no conditions, no
## effects. An output slot's target is typically a DialogueChoiceNode
## or DialogueSkillCheckChoiceNode, representing "here's a choice
## available at this stage," but that isn't enforced by the data model,
## matching how `next` fields elsewhere in the project don't enforce a
## target type either.
##
## Starts with one empty output slot; the editor's "+ Add Choice"
## action appends another (same repeater pattern already used for
## Options/Variants).

@export var outputs: Array[String] = [""]
