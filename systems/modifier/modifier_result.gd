class_name ModifierResult
extends RefCounted

## The output of ModifierResolver.aggregate() — kept granular (not
## just a final number) for the same reason SkillCheckResult is:
## a future breakdown/tooltip needs to show which specific sources
## contributed, not just the total.

var additive_total: float = 0.0

## Neutral factor (1.0 = "no change") when no multiplicative entries
## are present, so callers can always safely multiply by this
## without a special case for "nothing applied."
var multiplicative_total: float = 1.0

var contributing_entries: Array = []   # Array[ModifierEntry]
