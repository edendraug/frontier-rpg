class_name SkillCheck
extends RefCounted

## Resolves a single skill check. Mirrors the Core Systems GDD's own
## example almost exactly:
##
##   SkillCheck.new(character, "medicine", DiceResolver.dc_for_tier(
##       DiceResolver.DifficultyTier.HARD), registry).resolve()
##
## Deliberately knows nothing about dialogue, combat, hunting, or
## rendering — it only talks to CharacterSheet (for skill rank and
## stat modifier), CharacterDataRegistry (to look up which stat a
## skill uses), and ModifierResolver (to aggregate whatever Traits/
## Injuries/Diseases apply). Anything wanting a 3D dice animation
## should roll this FIRST, then hand the resulting SkillCheckResult
## to a DiceVisualizer to perform visually — the outcome is already
## decided by the time any animation plays.

var character: CharacterSheet
var skill_id: String
var difficulty: int
var registry: CharacterDataRegistry


func _init(
	p_character: CharacterSheet,
	p_skill_id: String,
	p_difficulty: int,
	p_registry: CharacterDataRegistry
) -> void:
	character = p_character
	skill_id = p_skill_id
	difficulty = p_difficulty
	registry = p_registry


func resolve() -> SkillCheckResult:
	var result := SkillCheckResult.new()
	result.difficulty = difficulty

	result.base_dice = [randi_range(1, 6), randi_range(1, 6)]

	var progress: SkillProgress = character.get_skill(skill_id)
	var bonus_die_count: int = progress.get_bonus_dice() if progress != null else 0
	for i in bonus_die_count:
		result.bonus_dice.append(randi_range(1, 4))

	_apply_morale_dice_nudge(result)

	var def: SkillDefinition = registry.skills.get(skill_id)
	result.stat_modifier = character.get_base_modifier(def.governing_stat) if def != null else 0

	# Gather every modifier-contributing source THIS character owns,
	# then aggregate only the entries relevant to this specific
	# check — the skill directly, plus its governing stat (so a
	# general stat-level penalty/bonus cascades in automatically).
	var targets: Array = [ModifierResolver.target_for_skill(skill_id)]
	if def != null:
		targets.append(ModifierResolver.target_for_stat(def.governing_stat))

	var entries := character.get_modifier_entries(registry)
	# Vitals-derived penalties (low Hunger, high Fatigue) are NOT part
	# of CharacterSheet.get_modifier_entries() -- that function only
	# concatenates arrays already sitting on sub-objects (Traits,
	# Injuries, Diseases), which is data-gathering, not decision-
	# making. Threshold evaluation ("if hunger < X, apply Y") is
	# exactly the kind of decision CharacterSheet's own design
	# explicitly stays out of -- see VitalsSystem instead, which
	# already owns "how do vitals values translate to something that
	# matters."
	entries.append_array(VitalsSystem.get_vitals_stat_modifier_entries(character))
	var modifier_result := ModifierResolver.aggregate(entries, targets)
	result.modifier_bonus = int(modifier_result.additive_total)
	result.contributing_modifiers = modifier_result.contributing_entries

	result.total = result.base_dice_total() + result.bonus_dice_total() + result.stat_modifier + result.modifier_bonus
	result.outcome = DiceResolver.determine_outcome(result.total, difficulty)

	return result


## ============================================================
## MORALE DICE CLAMP
## ============================================================
## Inspired sets an absolute FLOOR on every base/bonus die; Despairing
## sets an absolute CEILING — applied INDEPENDENTLY to each die, not
## just whichever happens to be lowest/highest in that particular
## roll. A roll of [1, 2] under Inspired becomes [3, 3], not [3, 2] —
## no individual die can ever show below the floor (or above the
## ceiling for Despairing), regardless of what any other die in the
## same roll shows. An earlier version nudged only the single
## min/max die, which meant a non-extreme low die (or a tied one)
## could still slip through showing a raw 1 or 2 despite Inspired —
## this version has no such gap, since every die is checked against
## the threshold independently.
##
## Deliberately NOT a flat bonus to the total (mathematically
## identical to a stat modifier regardless of theming, since
## DiceResolver only ever sees the final sum) and NOT full
## advantage/disadvantage (reroll-and-take-best/worst, a much harder
## swing). Only the two true extreme tiers get any effect —
## Low/Steady/High are untouched here.
##
## Mutates result.base_dice/bonus_dice directly rather than tracking
## a separate invisible bonus -- see the fields on SkillCheckResult
## for why.
const DESPAIRING_BASE_DIE_NUDGE := -2
const DESPAIRING_BONUS_DIE_NUDGE := -1
const INSPIRED_BASE_DIE_NUDGE := 2
const INSPIRED_BONUS_DIE_NUDGE := 1


func _apply_morale_dice_nudge(result: SkillCheckResult) -> void:
	var tier := character.get_morale_tier()
	if tier != CharacterSheet.MoraleTier.DESPAIRING and tier != CharacterSheet.MoraleTier.INSPIRED:
		return

	var is_inspired := tier == CharacterSheet.MoraleTier.INSPIRED
	result.morale_tier_label = "Inspired" if is_inspired else "Despairing"

	if not result.base_dice.is_empty():
		var delta: int = INSPIRED_BASE_DIE_NUDGE if is_inspired else DESPAIRING_BASE_DIE_NUDGE
		result.morale_base_die_nudge = _clamp_each_die(result.base_dice, delta, 1, 6)

	if not result.bonus_dice.is_empty():
		var delta: int = INSPIRED_BONUS_DIE_NUDGE if is_inspired else DESPAIRING_BONUS_DIE_NUDGE
		result.morale_bonus_die_nudge = _clamp_each_die(result.bonus_dice, delta, 1, 4)


## Applies an absolute floor (positive delta) or ceiling (negative
## delta) to EVERY die in the array independently. E.g. delta=2,
## min_face=1 means every die below 1+2=3 gets raised to exactly 3 --
## regardless of what any other die in the array shows. Dice already
## past the threshold are left completely untouched. Returns the SUM
## of individual deltas actually applied across every affected die
## (0 if none needed clamping), for display purposes -- when multiple
## dice each start a different distance from the threshold, they can
## receive different actual deltas, so this is a total, not a
## per-die amount.
func _clamp_each_die(dice: Array[int], delta: int, min_face: int, max_face: int) -> int:
	var total_applied := 0
	for i in dice.size():
		var before: int = dice[i]
		if delta > 0:
			dice[i] = maxi(before, min_face + delta)
		elif delta < 0:
			dice[i] = mini(before, max_face + delta)
		dice[i] = clampi(dice[i], min_face, max_face)
		total_applied += dice[i] - before
	return total_applied
