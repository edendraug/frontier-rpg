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
## stat modifier) and CharacterDataRegistry (to look up which stat a
## skill uses). Anything wanting a 3D dice animation should roll
## this FIRST, then hand the resulting SkillCheckResult to a
## DiceVisualizer to perform visually — the outcome is already
## decided by the time any animation plays.
##
## flat_bonus is a stand-in for what the Modifier System will
## eventually supply (Traits, Injuries, Weather, etc.) — pass a
## precomputed total in for now.

var character: CharacterSheet
var skill_id: String
var difficulty: int
var registry: CharacterDataRegistry
var flat_bonus: int


func _init(
	p_character: CharacterSheet,
	p_skill_id: String,
	p_difficulty: int,
	p_registry: CharacterDataRegistry,
	p_flat_bonus: int = 0
) -> void:
	character = p_character
	skill_id = p_skill_id
	difficulty = p_difficulty
	registry = p_registry
	flat_bonus = p_flat_bonus


func resolve() -> SkillCheckResult:
	var result := SkillCheckResult.new()
	result.difficulty = difficulty
	result.flat_bonus = flat_bonus

	result.base_dice = [randi_range(1, 6), randi_range(1, 6)]

	var progress: SkillProgress = character.get_skill(skill_id)
	var bonus_die_count: int = progress.get_bonus_dice() if progress != null else 0
	for i in bonus_die_count:
		result.bonus_dice.append(randi_range(1, 4))

	var def: SkillDefinition = registry.skills.get(skill_id)
	result.stat_modifier = character.get_base_modifier(def.governing_stat) if def != null else 0

	result.total = result.base_dice_total() + result.bonus_dice_total() + result.stat_modifier + flat_bonus
	result.outcome = DiceResolver.determine_outcome(result.total, difficulty)

	return result
