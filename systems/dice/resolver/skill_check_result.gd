class_name SkillCheckResult
extends RefCounted

## The full breakdown of one resolved check — kept granular (not
## just the final outcome) so a future DiceVisualizer can show
## exactly what each die rolled, and so debugging/balancing doesn't
## require re-deriving the math from a single number.

var base_dice: Array[int] = []       # the 2d6, individually
var bonus_dice: Array[int] = []      # 0-2 d4s, from skill rank
var stat_modifier: int = 0

## Aggregated additive total from ModifierResolver — every Trait/
## Injury/Disease entry that applied to this check, already summed.
var modifier_bonus: int = 0
var contributing_modifiers: Array = []   # Array[ModifierEntry], for a future breakdown/tooltip

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
