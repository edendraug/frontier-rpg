class_name DialogueChoiceNode
extends Resource

## A branch point in a dialogue graph: a list of Options the player can
## pick from. The node's own `conditions` gate the entire topic as
## unavailable, independent of any individual Option inside it also
## being gated - a Choice node can be entirely hidden while still
## containing Options that would otherwise be available.

@export var node_id: String = ""

## AND-list, same mixed DialogueCondition/ConditionSet shape as
## DialogueOption.conditions - untyped for the same reason.
@export var conditions: Array = []

@export var options: Array[DialogueOption] = []
