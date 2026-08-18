class_name DialogueOption
extends Resource

## A single selectable entry inside a DialogueChoiceNode. Memory
## (taken/not-taken) is tracked per option_id on ActorState, independent
## of the parent Choice node's id.

@export var option_id: String = ""
@export var text: String = ""

## AND-list. May contain a mix of inline DialogueCondition entries and
## ConditionSet references - untyped so both can sit in the same list;
## the resolver expands each ConditionSet in place and evaluates
## everything as one flat AND either way.
@export var conditions: Array = []

## false (default): repeatable - once taken, stays selectable but
## should be shown with an "already picked" treatment (presentation
## detail, deferred - see design doc Section 9).
## true: once taken, disappears entirely from future presentation.
@export var consume_once: bool = false

## When set, this Option resolves via a roll instead of firing
## immediately - `next`/`effects` below are unused and the branches
## live on skill_check instead (see design doc Section 4.6).
@export var skill_check: SkillCheckGate = null

## Unused when skill_check is set.
@export var effects: Array[DialogueEffect] = []
@export var next: String = ""


func has_skill_check() -> bool:
	return skill_check != null
