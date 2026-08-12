class_name SkillProgress
extends Resource

## Tracks a single character's progress in ONE skill.
##
## The skill's definition (display name, which Stat it's tied to,
## flavor text) lives in a separate SkillDefinition data table
## elsewhere — this Resource only tracks per-character progress,
## so it stays tiny and data-driven.

@export var skill_id: String = ""   # e.g. "medicine", "tracking"
@export var xp: int = 0

enum Rank { UNSKILLED, SKILLED, EXPERT }

## TODO: tune these. Kept here as a placeholder table rather than
## scattered magic numbers, so tuning later is a one-line change.
const RANK_THRESHOLDS := {
	Rank.SKILLED: 100,
	Rank.EXPERT: 300,
}


## Rank is derived from xp, never stored directly.
func get_rank() -> Rank:
	if xp >= RANK_THRESHOLDS[Rank.EXPERT]:
		return Rank.EXPERT
	elif xp >= RANK_THRESHOLDS[Rank.SKILLED]:
		return Rank.SKILLED
	return Rank.UNSKILLED


## Bonus dice granted to a Skill Check at the current rank.
## Feeds directly into the Dice/Skill Check System's "Bonus Dice" input.
func get_bonus_dice() -> int:
	match get_rank():
		Rank.EXPERT:
			return 2
		Rank.SKILLED:
			return 1
		_:
			return 0
