@tool
class_name DialogueTree
extends Resource

## A dialogue graph: a flat, id-keyed collection of nodes plus a start
## point. Not a strict hierarchy - a repeatable Option that loops back
## to a shared hub means nodes are referenced by id from multiple
## places (design doc Section 4.1). Every node_id must be a stable,
## author-assigned string, never an array index - Actor memory (taken
## options, last-shown variants) has to survive the author reordering
## or editing the graph later.
##
## Doubles as the authored shape for Presets (Section 4.9, e.g.
## Bartering): a Preset is just an ordinary DialogueTree that gets
## discovered/registered from a separate "presets" content folder and
## invoked via a START_PRESET effect's target instead of being reached
## through an Actor's dialogue_tree_id. No separate DialoguePreset
## class - same graph shape, different registry, different entry path.
## The call-stack push/pop that implements "return to caller when the
## Preset concludes" is a DialoguePlayer/runtime concern, not something
## this class needs to know about - a Preset tree must never have
## actor-specific values baked in, so it stays a plain, reusable graph
## like any other tree.

@export var tree_id: String = ""
@export var start_node_id: String = ""

## node_id -> DialogueLineNode or DialogueChoiceNode. Left as an
## untyped Resource dictionary, same pattern CharacterDataRegistry
## uses for its definition dictionaries - whatever walks the graph
## type-checks each entry (`is DialogueLineNode` / `is DialogueChoiceNode`)
## to know which behavior to run.
@export var nodes: Dictionary = {}


func get_node(node_id: String) -> Resource:
	return nodes.get(node_id, null)
