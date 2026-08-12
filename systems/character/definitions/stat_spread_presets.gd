class_name StatSpreadPreset
extends Resource

## A named, pre-built allocation of the 6 core stats — a SHORTCUT
## for point buy, not a separate mechanic. Applying one just fills
## in the same point-buy spinboxes with these values; the player
## (or a Party Creator generating an NPC) can keep hand-tuning from
## there exactly like normal point buy. Meant to speed up character
## creation — especially useful for generating several NPCs without
## spending real attention on each one.
##
## `scores` should roughly sum to a valid point-buy cost (see
## PointBuyRules) so presets and manual point buy stay on equal
## footing. Not strictly enforced here — treat these as
## placeholder/example numbers pending real balance tuning, same as
## the other tunable thresholds elsewhere in this system.

@export var preset_id: String = ""
@export var display_name: String = ""       # e.g. "Balanced", "Brawler", "Scholar"
@export_multiline var description: String = ""

## Keyed by the same stat keys used elsewhere:
## "brawn", "agility", "grit", "wits", "knowledge", "presence"
@export var scores: Dictionary = {}
