@tool
class_name DialogueConditionNode
extends DialogueGraphNode

## Self-contained gate - reopens the Condition-as-graph-node approach
## explicitly rejected in the Dialogue & Relations doc (Section 4.7,
## and "Explicitly out of scope," Section 2), now for a different
## reason: readability within one tree's graph, not cross-tree reuse
## (that's still ConditionSet's job, unchanged - see the Restructure
## design doc Section 1/5 for the full reasoning on why the two don't
## compete).
##
## Nothing wires INTO this node - its own condition list is authored
## directly here, reusing the exact mixed inline-DialogueCondition/
## ConditionSet-reference repeater shape already built for the earlier
## per-Option conditions list. Its single output can fan out to any
## number of DialogueChoiceNode/DialogueSkillCheckChoiceNode condition
## inputs, gating all of them off the same authored list at once.
##
## `mode` governs how THIS node's own direct entries combine with each
## other. A ConditionSet entry always evaluates internally as AND
## regardless of this node's mode, since ConditionSet is an AND-list by
## its own definition (condition_set.gd) - mode only applies to how
## this node's top-level entries combine.
##
## DialogueConditionResolver currently only implements AND (implicit,
## no mode concept) - supporting `mode` at evaluation time is deferred
## alongside the DialoguePlayer refactor (Restructure doc Section 9),
## a small, isolated resolver change, not something this class itself
## needs to worry about.

enum Mode {
	AND,
	OR,
}

@export var mode: Mode = Mode.AND

## Mixed Array of DialogueCondition / ConditionSet entries - untyped
## for the same reason the earlier per-Option conditions list was.
@export var conditions: Array = []
