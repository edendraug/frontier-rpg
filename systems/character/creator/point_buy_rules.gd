class_name PointBuyRules
extends RefCounted

## Rules for spending points across the 6 core stats at creation.
## Shape borrowed from D&D 5e point buy, since we use the identical
## modifier formula (floor((score - 10) / 2)) — a proven, balanced
## cost curve rather than inventing new numbers from scratch.
##
## All values here are placeholders — tune freely. Nothing else in
## the codebase depends on these specific numbers, only on this
## file's public functions.

const BASELINE_SCORE := 8
const MIN_SCORE := 8
const MAX_SCORE := 20          # cap BEFORE Occupation modifiers apply
const POINT_POOL := 27

## Costs escalate steeply above 18 on purpose: the pool alone tops
## out around 18-19 in a single stat, and true 20 realistically
## requires stacking an Occupation's stat bonus on top. That tension
## is intentional — tune away if it doesn't feel right in practice.
const COST_TABLE := {
	8: 0, 9: 1, 10: 2, 11: 3, 12: 4, 13: 5, 14: 7, 15: 9,
	16: 12, 17: 15, 18: 19, 19: 23, 20: 28,
}


static func cost_for_score(score: int) -> int:
	return COST_TABLE.get(score, 0)


## scores: Dictionary of stat_key -> int score (e.g. {"brawn": 12, ...})
static func total_cost(scores: Dictionary) -> int:
	var total := 0
	for stat_key in scores:
		total += cost_for_score(scores[stat_key])
	return total


static func points_remaining(scores: Dictionary) -> int:
	return POINT_POOL - total_cost(scores)
