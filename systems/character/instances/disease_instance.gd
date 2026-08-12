class_name DiseaseInstance
extends Resource

## A single named disease (e.g. "Dysentery", "Fever").
## Shares the same shape as InjuryInstance, plus contagion data.
##
## NOTE: This Resource only stores WHETHER a disease can spread.
## The actual transmission logic (checking party proximity, rolling
## spread chance each day) does not belong here — it lives in
## whatever system runs daily ticks (Time System / a party-health
## checker), consistent with "no feature owns its own dice logic."

enum Severity { MINOR, MODERATE, SEVERE, CRITICAL }

@export var disease_name: String = ""
@export var severity: Severity = Severity.MINOR
@export var contagious: bool = false
@export_range(0, 100) var virulence: int = 0   # how readily it spreads, if contagious
@export var day_contracted: int = 0

@export var recovery_requirement: Dictionary = {}
@export var penalties: Array = []
