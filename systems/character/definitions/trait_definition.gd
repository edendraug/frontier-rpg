class_name TraitDefinition
extends Resource

## Defines what a trait IS: display info and the Modifier System
## entries it grants while active. Whether a character has it, and
## how (innate vs. earned, when), lives in TraitInstance, not here.
## Meant to be authored as a .tres data file per trait
## (e.g. natural_hunter.tres).

@export var trait_id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""

## Raw Modifier System entries — same open format as Injury/Disease
## penalties, until the Modifier System itself defines its schema.
## e.g. [{"target": "tracking_checks", "value": 2}]
@export var modifiers: Array = []
