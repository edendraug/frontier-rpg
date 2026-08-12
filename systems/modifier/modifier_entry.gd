class_name ModifierEntry
extends Resource

## A single modifier contribution — from a Trait, Injury, Disease,
## or (later) Weather/Terrain/Wagon state. Targets use a three-tier
## namespace so a stat-level entry can cascade to every skill under
## that stat without needing a separate entry per skill:
##
##   "skill:<skill_id>"   — affects one specific Skill Check
##   "stat:<stat_key>"    — affects every skill governed by that stat
##   "system:<name>"      — affects something outside the stat/skill
##                          model entirely (e.g. "system:travel_speed")
##
## Build target strings via ModifierResolver's helpers rather than
## typing them by hand, so the format can't drift.
##
## ADDITIVE entries sum together (+2, +1, -1 → net +2). MULTIPLICATIVE
## entries compose as factors (0.9 × 0.85, not 90 - 85) — the two
## never mix, which is why aggregation tracks them separately rather
## than folding everything into one number.

enum Type { ADDITIVE, MULTIPLICATIVE }

@export var target: String = ""
@export var value: float = 0.0
@export var type: Type = Type.ADDITIVE

## Display only — never used in the aggregation math. Lets a future
## breakdown/tooltip show WHY a roll got what it got (e.g. "Natural
## Hunter +2") rather than just a final opaque number.
@export var source_label: String = ""
