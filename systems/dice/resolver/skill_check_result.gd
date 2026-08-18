class_name SkillCheckResult
extends RefCounted

## The full breakdown of one resolved check — kept granular (not
## just the final outcome) so a future DiceVisualizer can show
## exactly what each die rolled, and so debugging/balancing doesn't
## require re-deriving the math from a single number.

var base_dice: Array[int] = []       # the 2d6, individually
var bonus_dice: Array[int] = []      # 0-2 d4s, from skill rank, AFTER suppression

## Bonus dice count BEFORE suppression -- i.e. what
## SkillProgress.get_bonus_dice() actually returned for this
## character's rank. bonus_dice.size() can be smaller than this if a
## Trait/Injury/Disease (or later, Vitals) SUPPRESS_BONUS_DICE entry
## applied. Kept separate purely for debug/breakdown visibility, so a
## suppressed roll can show "2 → 0, Broken Hand" rather than the
## suppression being invisible.
var base_bonus_dice: int = 0

var stat_modifier: int = 0

## Aggregated additive total from ModifierResolver — every Trait/
## Injury/Disease entry that applied to this check, already summed.
var modifier_bonus: int = 0
var contributing_modifiers: Array = []   # Array[ModifierEntry], for a future breakdown/tooltip

## Morale's dice-nudge effect (Despairing/Inspired only) — raises the
## floor (lowest base/bonus die pushed up) or lowers the ceiling
## (highest pushed down), rather than a flat bonus to the total.
## base_dice/bonus_dice above already hold the POST-nudge values (so
## a future DiceVisualizer's existing corrective-nudge settling shows
## the correct face with no extra work) — these fields record the
## ACTUAL delta applied (which can be smaller than the nominal amount
## near a die's min/max) purely for a debug breakdown or on-die
## indicator.
var morale_tier_label: String = ""    # "Inspired" / "Despairing" / "" if neither
var morale_base_die_nudge: int = 0
var morale_bonus_die_nudge: int = 0

var difficulty: int = 0
var total: int = 0
var outcome: DiceResolver.Outcome = DiceResolver.Outcome.FAILURE


func base_dice_total() -> int:
	var sum := 0
	for d in base_dice:
		sum += d
	return sum


func bonus_dice_total() -> int:
	var sum := 0
	for d in bonus_dice:
		sum += d
	return sum


func outcome_name() -> String:
	return DiceResolver.Outcome.keys()[outcome]
