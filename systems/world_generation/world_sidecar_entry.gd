class_name WorldSidecarEntry
extends Resource

## One hand-authored exception merged onto a matching HexInstance at
## bake time -- a settlement, a hand-placed special event, or a
## per-hex event-weight override. Not every field needs to be set on
## every entry; which fields the bake step actually treats as "set"
## vs. "left at default" is bake-step logic (design doc Section 7),
## not decided by this data shape alone.

## Same "q,r" axial format as HexInstance.coord -- this is how an
## entry gets matched to its hex at bake time.
@export var coord: String = ""

@export var settlement_id: String = ""
@export var special_event_ids: Array[String] = []
@export var event_frequency_multiplier: float = 1.0
