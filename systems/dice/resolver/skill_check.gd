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
	var modifier_result := ModifierResolver.aggregate(entries, targets)
	result.modifier_bonus = int(modifier_result.additive_total)
	result.contributing_modifiers = modifier_result.contributing_entries

	result.total = result.base_dice_total() + result.bonus_dice_total() + result.stat_modifier + result.modifier_bonus
	result.outcome = DiceResolver.determine_outcome(result.total, difficulty)

	return result
