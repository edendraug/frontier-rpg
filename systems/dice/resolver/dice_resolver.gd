class_name DiceResolver
extends RefCounted

## The rulebook for skill check resolution: difficulty tiers, their DC
## values, and the margin bands that turn a total-vs-DC comparison
## into one of 5 outcome tiers. No dice-rolling logic lives here —
## see SkillCheck for that. Splitting rules from rolling means the DC
## table can be tuned (or exposed to an editor tool later) without
## touching how a check is actually resolved.
##
## DC values are derived from the check math, not playtested yet:
## base 2d6 averages 7, bonus dice add 0/2.5/5 (Unskilled/Skilled/
## Expert), stat modifiers commonly run +1 to +3. Realistic totals
## span roughly 7-15 across builds — these tiers are placed inside
## that range on purpose. Treat every number here as a tunable
## placeholder, same as everywhere else in this project.

## Outcome meanings (for anything consuming a SkillCheckResult):
##   CRITICAL_SUCCESS — succeeds, with an extra bonus
##   SUCCESS          — succeeds, the expected result
##   FAILURE          — fails, no punishment beyond lost time
##   CRITICAL_FAILURE — fails, with a minor setback/complication
enum Outcome { CRITICAL_FAILURE, FAILURE, SUCCESS, CRITICAL_SUCCESS }

enum DifficultyTier { VERY_EASY, EASY, MEDIUM, HARD, VERY_HARD, NEARLY_IMPOSSIBLE }

const DIFFICULTY_DC := {
	DifficultyTier.VERY_EASY: 5,
	DifficultyTier.EASY: 7,
	DifficultyTier.MEDIUM: 9,
	DifficultyTier.HARD: 12,
	DifficultyTier.VERY_HARD: 15,
	DifficultyTier.NEARLY_IMPOSSIBLE: 18,
}

## Margins are measured from the DC. E.g. CRIT_SUCCESS_MARGIN = 4
## means "total >= DC + 4" is a Critical Success. FAILURE_MARGIN
## marks where plain Failure becomes Critical Failure.
const CRIT_SUCCESS_MARGIN := 4
const FAILURE_MARGIN := 7


## Editor-friendly entry point: authors pick a named tier (renders as
## a dropdown via the DifficultyTier enum) rather than typing raw DC
## numbers everywhere a check is configured.
static func dc_for_tier(tier: DifficultyTier) -> int:
	return DIFFICULTY_DC[tier]


static func determine_outcome(total: int, dc: int) -> Outcome:
	if total >= dc + CRIT_SUCCESS_MARGIN:
		return Outcome.CRITICAL_SUCCESS
	elif total >= dc:
		return Outcome.SUCCESS
	elif total >= dc - FAILURE_MARGIN:
		return Outcome.FAILURE
	else:
		return Outcome.CRITICAL_FAILURE
