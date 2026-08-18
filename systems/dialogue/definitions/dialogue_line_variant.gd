class_name DialogueLineVariant
extends Resource

## One entry in a DialogueLineNode's variant pool. Deliberately a thin
## wrapper around a single String rather than a raw Array[String] - if
## a per-variant knob (weighting, a one-off condition, etc.) ever turns
## out to be needed, it has somewhere to live without reshaping every
## authored Line. Today it only holds text.

@export var text: String = ""
