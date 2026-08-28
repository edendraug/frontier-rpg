@tool
class_name DialogueSkillCheckChoiceNode
extends DialogueChoiceNode

## A dialogue choice that resolves via a skill check roll instead of
## firing immediately - retires the earlier SkillCheckGate (previously
## reachable only through an Option's skill_check field, never a real
## DialogueTree.nodes entry of its own). Now a full graph node like any
## other choice, with its own node_id (Dialogue Graph Node Restructure
## design doc, Section 7).
##
## Inherits node_id/editor_position/text/consume_once from
## DialogueChoiceNode. The inherited `effects` field is deliberately
## left unused/hidden in the editor for this subtype: taking this
## choice fires success/failure/critical_success/critical_failure's OWN
## effects once the outcome is known (Dialogue & Relations doc Section
## 5.2), never the inherited field immediately on selection - using it
## too would contradict that already-established firing-timing rule.
## The inherited `next` field goes unused the same way, for the same
## reason - this subtype has 4 outputs (one per branch's own `next`),
## not the base class's single one.
##
## Must resolve through the real SkillCheck.resolve() pipeline - same
## Vitals, Morale dice-nudge, Injury/Disease suppression, and Trait
## modifiers as any other check in the game. Never a simplified/
## separate roll (unchanged from the retired SkillCheckGate's own rule).

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


## Resolves this choice's authored DC down to the plain int SkillCheck
## actually consumes.
func get_dc() -> int:
	if dc_mode == DCMode.MANUAL:
		return dc_manual
	return DiceResolver.dc_for_tier(dc_tier)


func get_critical_success_branch() -> SkillCheckBranch:
	return critical_success if critical_success != null else success


func get_critical_failure_branch() -> SkillCheckBranch:
	return critical_failure if critical_failure != null else failure
