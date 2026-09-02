class_name DiceCheck
extends RefCounted

## Shared base for SkillCheck and SavingThrow -- NOT meant to be
## instantiated directly (GDScript has no `abstract` keyword to enforce
## this, so treat it as a documentation-only constraint). Owns everything
## that was, until now, independently duplicated between the two: the
## 2d6 roll, gathering + aggregating ModifierResolver entries (including
## folding in Vitals-derived stat penalties), the Inspired/Despairing
## dice nudge, and DiceResolver outcome determination.
##
## Consolidation of SkillCheck and SavingThrow, deferred until
## SavingThrow had a real proven use (Food Poisoning resistance) rather
## than being unified in the abstract -- see
## Frontier_RPG_Food_Consumption_Design_Doc.md, Section 3.4/4.7/8.
##
## Subclasses override three methods for whatever's actually different
## about their kind of check:
##   _get_targets()       -- the ModifierResolver target list to
##                            aggregate against (e.g. [skill, stat] or
##                            just [stat])
##   _get_stat_modifier()  -- the character's base modifier for
##                            whichever stat this check cares about
##   _roll_bonus_dice()    -- populate result.base_bonus_dice/bonus_dice,
##                            or leave both at their SkillCheckResult
##                            defaults (0 / empty) if this kind of check
##                            has no bonus-dice concept at all -- the
##                            default implementation here does exactly
##                            that, and SavingThrow relies on it
##                            unchanged rather than overriding it.

var character: CharacterSheet
var difficulty: int
var registry: CharacterDataRegistry


func _init(p_character: CharacterSheet, p_difficulty: int, p_registry: CharacterDataRegistry) -> void:
	character = p_character
	difficulty = p_difficulty
	registry = p_registry


func resolve() -> SkillCheckResult:
	var result := SkillCheckResult.new()
	result.difficulty = difficulty

	result.base_dice = [randi_range(1, 6), randi_range(1, 6)]

	# Gather + aggregate modifiers BEFORE rolling bonus dice -- suppression
	# needs to know how many bonus dice to remove before any of them
	# exist, unlike the additive/multiplicative totals below, which only
	# ever apply to the final sum. One gather+aggregate call serves both
	# needs; no need to do this twice.
	var targets := _get_targets()
	var entries := character.get_modifier_entries(registry)
	# Vitals-derived penalties (low Hunger, high Fatigue) are NOT part of
	# CharacterSheet.get_modifier_entries() -- that function only
	# concatenates arrays already sitting on sub-objects (Traits,
	# Injuries, Diseases), which is data-gathering, not decision-making.
	# Threshold evaluation ("if hunger < X, apply Y") is exactly the kind
	# of decision CharacterSheet's own design explicitly stays out of --
	# see VitalsSystem instead, which already owns "how do vitals values
	# translate to something that matters." Applies equally to a
	# SavingThrow as to a trained SkillCheck -- Hunger/Fatigue don't care
	# whether a roll happens to involve a skill.
	entries.append_array(VitalsSystem.get_vitals_stat_modifier_entries(character))
	var modifier_result := ModifierResolver.aggregate(entries, targets)

	_roll_bonus_dice(result, modifier_result)

	_apply_morale_dice_nudge(result)

	result.stat_modifier = _get_stat_modifier()

	# Additive/multiplicative totals reuse the SAME gathered entries and
	# aggregated result computed above for suppression -- nothing needs
	# to be gathered a second time.
	result.modifier_bonus = int(modifier_result.additive_total)
	result.contributing_modifiers = modifier_result.contributing_entries

	result.total = result.base_dice_total() + result.bonus_dice_total() + result.stat_modifier + result.modifier_bonus
	result.outcome = DiceResolver.determine_outcome(result.total, difficulty)

	return result


## Override: the ModifierResolver target list to aggregate against.
func _get_targets() -> Array:
	push_error("DiceCheck._get_targets() not overridden -- this base class is not meant to be instantiated directly")
	return []


## Override: the character's base stat modifier for this check.
func _get_stat_modifier() -> int:
	push_error("DiceCheck._get_stat_modifier() not overridden -- this base class is not meant to be instantiated directly")
	return 0


## Override: populate result.base_bonus_dice/result.bonus_dice. Default
## (used as-is by SavingThrow): does nothing, leaving both at their
## SkillCheckResult defaults (0 / empty) -- correct behavior for any
## check with no bonus-dice concept, not just an unfinished stub.
func _roll_bonus_dice(_result: SkillCheckResult, _modifier_result: ModifierResult) -> void:
	pass


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
##
## Shared unmodified across every DiceCheck subtype -- the bonus_dice
## branch below is naturally a no-op whenever _roll_bonus_dice() left
## bonus_dice empty (SavingThrow, or anything else with no bonus-dice
## concept), since is_empty() short-circuits it. No override needed.
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
