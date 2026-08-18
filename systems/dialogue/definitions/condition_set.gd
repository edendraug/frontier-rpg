class_name ConditionSet
extends Resource

## A small, named, shared list of DialogueConditions, authored once and
## referenced by id from any Option or Choice node's gate list, anywhere
## in the game - not scoped to a single tree. This is the accepted reuse
## mechanism for a condition combination (e.g. "Settler reputation >= 5")
## likely to gate many different Options across many different Actors'
## trees, without hand-copying it or introducing a graph-node-based
## condition mechanism (rejected - see design doc Section 4.7).
##
## An Option/Choice's gate list may mix inline DialogueCondition entries
## with ConditionSet references. Whatever resolver evaluates the list
## should expand each ConditionSet's conditions in place rather than
## treating the two differently - the fully expanded list is still a
## plain AND either way.

@export var condition_set_id: String = ""
@export var conditions: Array[DialogueCondition] = []
