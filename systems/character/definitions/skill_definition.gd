class_name SkillDefinition
extends Resource

## Defines what a skill IS: display info and which Stat it's tied to.
## Character-specific progress (xp/rank) lives in SkillProgress, not
## here. Meant to be authored as a .tres data file per skill
## (e.g. medicine.tres, tracking.tres).
##
## NOTE: By design, no SkillDefinition should ever set governing_stat
## to GRIT — Grit is intentionally passive-only (see CharacterSheet).

@export var skill_id: String = ""          # e.g. "medicine" — must match SkillProgress.skill_id
@export var display_name: String = ""      # e.g. "Medicine"
@export_multiline var description: String = ""
@export var governing_stat: CharacterSheet.Stat = CharacterSheet.Stat.KNOWLEDGE
@export var icon: Texture2D
