class_name SavingThrow
extends DiceCheck

## Resolves a single saving throw -- a stat-only check with no associated
## skill, for cases SkillCheck can't express. SkillCheck always derives
## its stat by looking one up THROUGH a matched SkillDefinition.governing_stat;
## there's no path there to hand it a stat directly. Resisting Food
## Poisoning isn't a trained skill, it's raw physical toughness --
## CharacterSheet.grit is already commented "Passive only -- intentionally
## no skills use this stat," which is exactly the gap this fills.
##
## Same usage pattern SkillCheck.resolve() already established:
##
##   SavingThrow.new(character, CharacterSheet.Stat.GRIT,
##       DiceResolver.dc_for_tier(DiceResolver.DifficultyTier.EASY),
##       registry).resolve()
##
## VitalsSystem.feed_character() is the first real caller (Food Poisoning
## resistance), but this is a general Dice/Skill Check System primitive,
## not something owned by Vitals or Food -- anything needing a raw stat
## check (poison, fear, cold exposure, etc.) later can use this the same
## way.
##
## Extends DiceCheck -- see that file for the shared roll/aggregate/
## outcome pipeline. No _roll_bonus_dice() override -- the base class
## default (do nothing) is exactly correct here: there's no SkillProgress
## concept for "trained at resisting poison."

var stat: CharacterSheet.Stat


func _init(p_character: CharacterSheet, p_stat: CharacterSheet.Stat, p_difficulty: int, p_registry: CharacterDataRegistry) -> void:
	super._init(p_character, p_difficulty, p_registry)
	stat = p_stat


func _get_targets() -> Array:
	# No skill target at all -- SkillCheck contributes
	# [skill_target, stat_target]; a SavingThrow only ever has the stat
	# half, since there's no skill_id here in the first place.
	return [ModifierResolver.target_for_stat(stat)]


func _get_stat_modifier() -> int:
	return character.get_base_modifier(stat)
