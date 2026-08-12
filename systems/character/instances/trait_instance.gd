class_name TraitInstance
extends Resource

## A single Trait a character possesses.
##
## The trait's actual definition (name, description, and the
## Modifier System entries it grants) lives in a separate
## TraitDefinition data table elsewhere — this only records that
## the character has it, and where it came from.

enum Source { INNATE, EARNED }

@export var trait_id: String = ""            # e.g. "natural_hunter"
@export var source: Source = Source.INNATE
@export var day_acquired: int = 0            # Time System day, for flavor/history
