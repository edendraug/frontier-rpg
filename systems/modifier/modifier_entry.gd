class_name ModifierEntry
extends Resource

## A single modifier contribution — from a Trait, Injury, Disease,
## or (later) Weather/Terrain/Wagon state. Targets use a three-tier
## namespace so a stat-level entry can cascade to every skill under
## that stat without needing a separate entry per skill:
##
##   "skill:<skill_id>"   — affects one specific Skill Check
##   "stat:<stat_key>"    — affects every skill governed by that stat
##   "system:<n>"      — affects something outside the stat/skill
##                          model entirely (e.g. "system:travel_speed")
##
## Build target strings via ModifierResolver's helpers rather than
## typing them by hand, so the format can't drift.
##
## One entry can affect MULTIPLE targets at once — e.g. a "Broken
## Hand" injury suppressing both "skill:craft" and
## "skill:marksmanship" in one instance. This is still ONE
## conceptual penalty (same type, same value/full_suppression, same
## source_label), just relevant in more than one place, rather than
## requiring a near-duplicate entry per target. If two targets
## genuinely need different magnitudes, that's still two separate
## entries — targets only collapses the case where they're identical.
##
## ADDITIVE entries sum together (+2, +1, -1 → net +2). MULTIPLICATIVE
## entries compose as factors (0.9 × 0.85, not 90 - 85) — the two
## never mix, which is why aggregation tracks them separately rather
## than folding everything into one number. SUPPRESS_BONUS_DICE
## reduces a Skill Check's bonus dice pool at roll time, BEFORE any
## dice are actually rolled — a different pipeline stage than the
## other two types, which only ever affect a check's final total.
## See full_suppression below for how `value` is interpreted for it.

enum Type { ADDITIVE, MULTIPLICATIVE, SUPPRESS_BONUS_DICE }

@export var targets: Array[String] = []
@export var value: float = 0.0
@export var type: Type = Type.ADDITIVE

## Only meaningful when type == SUPPRESS_BONUS_DICE. False (default):
## `value` is a partial reduction, subtracted from the check's bonus
## dice count and floored at 0 (e.g. value=1 drops one bonus die).
## True: full suppression — bonus dice go to 0 outright, treating the
## skill as Unskilled for this roll regardless of actual rank. `value`
## is ignored when this is true. If a check has both a partial and a
## full suppression entry contributing at once, full wins outright —
## see ModifierResolver.aggregate()/ModifierResult.
@export var full_suppression: bool = false

## Display only — never used in the aggregation math. Lets a future
## breakdown/tooltip show WHY a roll got what it got (e.g. "Natural
## Hunter +2") rather than just a final opaque number.
@export var source_label: String = ""
