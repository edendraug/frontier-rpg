class_name SkillCheckGate
extends Resource

## Attached to a DialogueOption when it needs to resolve via a roll
## rather than firing immediately. Resolution itself (Vitals, Morale
## dice-nudge, Injury/Disease suppression, Trait modifiers) is a
## DialoguePlayer/runtime concern - this class only holds the authored
## shape of the check and its branches. See design doc Section 4.6:
## this must run through the real SkillCheck.resolve() pipeline, never
## a simplified/separate roll.

enum DCMode {
	TIER,    ## Use dc_tier - the normal, recommended path.
	MANUAL,  ## Use dc_manual - escape hatch for a genuine one-off DC.
}

@export var skill_id: String = ""

@export var dc_mode: DCMode = DCMode.TIER

## The normal path: reference a named tier rather than baking in its
## current numeric DC, so retuning DiceResolver's DIFFICULTY_DC table
## later doesn't silently desync already-authored dialogue.
@export var dc_tier: DiceResolver.DifficultyTier = DiceResolver.DifficultyTier.MEDIUM

## Only read when dc_mode == MANUAL.
@export var dc_manual: int = 10

@export var success: SkillCheckBranch = null
@export var failure: SkillCheckBranch = null

## Optional - falls back to `success`/`failure` if unauthored (null).
@export var critical_success: SkillCheckBranch = null
@export var critical_failure: SkillCheckBranch = null


## Resolves this gate's authored DC down to the plain int SkillCheck
## actually consumes.
func get_dc() -> int:
	if dc_mode == DCMode.MANUAL:
		return dc_manual
	return DiceResolver.dc_for_tier(dc_tier)


func get_critical_success_branch() -> SkillCheckBranch:
	return critical_success if critical_success != null else success


func get_critical_failure_branch() -> SkillCheckBranch:
	return critical_failure if critical_failure != null else failure
