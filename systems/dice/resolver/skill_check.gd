class_name SkillCheck
extends DiceCheck

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
##
## Extends DiceCheck -- see that file for the shared roll/aggregate/
## outcome pipeline and the full morale-dice-clamp reasoning. Everything
## below is only what's actually specific to a skill-governed check:
## looking up which stat the skill uses, and rolling bonus dice from
## the character's trained rank.

var skill_id: String

## Looked up once here rather than inside each override below --
## both _get_targets() and _get_stat_modifier() need it, and a
## skill_id that doesn't resolve to a real SkillDefinition is a
## valid, permissively-handled case (both overrides null-check this),
## not an error.
var _def: SkillDefinition


func _init(p_character: CharacterSheet, p_skill_id: String, p_difficulty: int, p_registry: CharacterDataRegistry) -> void:
	super._init(p_character, p_difficulty, p_registry)
	skill_id = p_skill_id
	_def = p_registry.skills.get(p_skill_id)


func _get_targets() -> Array:
	var targets: Array = [ModifierResolver.target_for_skill(skill_id)]
	if _def != null:
		targets.append(ModifierResolver.target_for_stat(_def.governing_stat))
	return targets


func _get_stat_modifier() -> int:
	return character.get_base_modifier(_def.governing_stat) if _def != null else 0


func _roll_bonus_dice(result: SkillCheckResult, modifier_result: ModifierResult) -> void:
	var progress: SkillProgress = character.get_skill(skill_id)
	result.base_bonus_dice = progress.get_bonus_dice() if progress != null else 0

	var bonus_die_count: int = 0
	if modifier_result.bonus_dice_fully_suppressed:
		bonus_die_count = 0
	else:
		bonus_die_count = maxi(0, result.base_bonus_dice - int(modifier_result.bonus_dice_suppression))

	for i in bonus_die_count:
		result.bonus_dice.append(randi_range(1, 4))
