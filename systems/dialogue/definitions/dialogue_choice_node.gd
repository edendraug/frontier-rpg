@tool
class_name DialogueChoiceNode
extends DialogueGraphNode

## A branch point in a dialogue graph: a list of Options the player can
## pick from. The node's own `conditions` gate the entire topic as
## unavailable, independent of any individual Option inside it also
## being gated - a Choice node can be entirely hidden while still
## containing Options that would otherwise be available.
##
## node_id and editor_position are inherited from DialogueGraphNode
## (Dialogue Graph Editor design doc, Section 4.1).

## AND-list, same mixed DialogueCondition/ConditionSet shape as
## DialogueOption.conditions - untyped for the same reason.
@export var conditions: Array = []

@export var options: Array[DialogueOption] = []
