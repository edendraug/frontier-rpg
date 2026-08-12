class_name InjuryInstance
extends Resource

## A single named wound (e.g. "Sprained Ankle", "Gunshot Wound").
## Injuries are the game's primary "damage" mechanic — inflicted by
## failed/critically-failed Skill Checks and dangerous Events,
## rather than an abstract HP pool.

enum Severity { MINOR, MODERATE, SEVERE, CRITICAL }

@export var injury_name: String = ""
@export var severity: Severity = Severity.MINOR
@export var treated: bool = false
@export var day_acquired: int = 0

## Left flexible on purpose — could resolve to a flat day count, a
## Rest requirement, a Medicine treatment flag, or some combination.
## Structure TBD once the Event/Encounter System defines exactly how
## injuries get inflicted and resolved.
## e.g. {"requires_treatment": true, "min_days": 3}
@export var recovery_requirement: Dictionary = {}

## Modifier System entries this injury contributes while active.
## Left as raw data until the Modifier System's own format is
## defined — this is just a slot for it to read from.
## e.g. [{"target": "agility_checks", "value": -2}]
@export var penalties: Array = []
