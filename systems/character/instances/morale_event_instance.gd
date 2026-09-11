class_name MoraleEventInstance
extends Resource

## One stacked morale effect -- a witnessed injury, a good meal, an
## uplifting encounter, etc. Multiple can be active on a character at
## once; each decays independently toward 0 rather than morale being
## a single flat accumulator. VitalsSystem sums whatever's currently
## active, on top of a neutral baseline, to get the character's
## actual Morale each hour -- see VitalsSystem._recompute_morale().
##
## Resource, not RefCounted -- same reasoning as ItemStack/
## InventoryBatch: this needs to serialize as part of CharacterSheet
## through Save/Load, which RefCounted objects can't do.

@export var source_label: String = ""
@export var magnitude: float = 0.0       # positive = uplifting, negative = demoralizing
@export var decay_per_hour: float = 0.0  # how fast |magnitude| shrinks toward 0 each hour
@export var day_applied: int = 0         # for display/debugging only, not used in decay math

func _init(p_source_label: String = "", p_magnitude: float = 0.0, p_decay_per_hour: float = 0.0, p_day_applied: int = 0) -> void:
	source_label = p_source_label
	magnitude = p_magnitude
	decay_per_hour = p_decay_per_hour
	day_applied = p_day_applied
