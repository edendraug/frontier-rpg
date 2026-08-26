@tool
class_name SkillCheckBranch
extends Resource

## What happens for one outcome (success/failure/crit) of a
## SkillCheckGate: where the graph continues and what fires. Split out
## as its own Resource purely so SkillCheckGate doesn't need four
## parallel next/effects field pairs.

@export var next: String = ""
@export var effects: Array[DialogueEffect] = []
