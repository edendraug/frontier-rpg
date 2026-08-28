@tool
class_name DialogueChoiceNode
extends DialogueGraphNode

## A single dialogue choice, promoted to a full graph node with its
## own node_id - this REPLACES the earlier "container holding a list
## of DialogueOptions" shape entirely (Dialogue Graph Node Restructure
## design doc, Section 6). The old option_id concept retires with it -
## ActorState.options_taken and consume_once "already taken" tracking
## now key off this node's own node_id instead (same key type, same
## lookup mechanism, just a different source field - no ActorState
## code changes expected, only what gets passed in as the key).
##
## No `conditions` field - gating is exclusively the job of a wired
## DialogueConditionNode on this node's condition input (Restructure
## doc Section 5/6): at most one incoming wire, represented by
## `condition_node_id` below (empty = unconnected, always available).
## No node authors its own conditions inline anymore.
##
## `effects` fires on selection (Dialogue & Relations doc Section 5.2:
## a plain choice's effects fire immediately) - universal across every
## choice per project direction. DialogueSkillCheckChoiceNode (this
## class's subtype) deliberately leaves this inherited field unused/
## hidden in the editor instead - see that class's own docstring for
## why.

@export var text: String = ""
@export var consume_once: bool = false
@export var effects: Array[DialogueEffect] = []

## The DialogueConditionNode wired to this choice's condition input, by
## node_id - empty means unconnected (always available). Same
## representation convention as every other wire in this data model:
## the source of a connection stores its target's node_id
## (DialogueLineNode.next, DialogueStructureNode.outputs,
## SkillCheckBranch.next) - here the "source" is this choice's
## condition-input port, and the "target" is whichever
## DialogueConditionNode feeds it. This also gets fan-out (one
## ConditionNode gating several choices) for free: multiple different
## choices can each independently reference the same condition_node_id
## without that ConditionNode needing to track its own targets.
@export var condition_node_id: String = ""

## The single output wire's target node_id (empty = end of tree/Preset,
## matching DialogueLineNode.next's own convention). Same "1 output"
## port DialogueSkillCheckChoiceNode replaces with its own 4 branch
## outputs instead - see that class's own docstring on why this
## inherited field goes unused there, matching how it already leaves
## `effects` unused too.
@export var next: String = ""

## Implicit fallback destination - see DialogueLineNode.next's own
## docstring for the full reasoning, unchanged here. On
## DialogueSkillCheckChoiceNode specifically, this ONE field (not four
## separate ones) is the fallback for whichever of its four branches
## has an empty `next` - "the last structure node," singular, per the
## Restructure follow-up addendum, not a per-branch setting.
@export var default_return_id: String = ""
