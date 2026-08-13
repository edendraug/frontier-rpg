extends Node

## Autoload. Applies passive per-hour drift to each party member's
## Hunger and Fatigue -- the passive half of Time Interaction.
## Listens to TimeSystem.hour_passed rather than time_advanced, since
## this IS the boundary-triggered gameplay logic hour_passed exists
## for (time_advanced is for display refreshes on every raw minute,
## a different job entirely).
##
## Deliberately does NOT model eating/feeding -- Hunger only ever
## drains here. Consuming Food to restore it is a distinct, larger
## piece (the automatic-FIFO-vs-manual-feeding split designed back
## during Inventory) left for a later pass.
##
## Register in Project Settings > Autoload AFTER PartyManager, since
## every tick reads PartyManager.get_roster() and its registry.

## Placeholder/tunable rates, same treatment as the DC table and
## everywhere else marked this way -- not balanced, just a starting
## point. Hunger 100->0 over ~48 waking hours; Fatigue climbs over
## ~16 waking hours and only partially recovers over an assumed
## 8-hour overnight window, so it still creeps up day over day even
## with normal rest -- an explicit stand-in for a real Rest/Camp
## action, which doesn't exist until Assignment does. Replace this
## whole night-window mechanism once that's real.
const BASE_HUNGER_DRAIN_PER_HOUR := 2.1
const BASE_FATIGUE_ACCRUAL_PER_HOUR := 5.6
const BASE_FATIGUE_RECOVERY_PER_HOUR := 8.0
const NIGHT_START_HOUR := 22  # 22:00 through...
const NIGHT_END_HOUR := 6     # ...05:59 counts as the recovery window

## Modifier System targets external sources contribute to, aggregated
## the same way SkillCheck already aggregates skill/stat targets.
## Per-character sources (Traits, Injuries, Diseases) flow in
## automatically via CharacterSheet.get_modifier_entries() -- e.g. a
## Disease's existing `penalties` array can already target
## FATIGUE_ACCRUAL_TARGET with zero new Disease fields needed.
const HUNGER_DRAIN_TARGET := "system:hunger_drain_rate"
const FATIGUE_ACCRUAL_TARGET := "system:fatigue_accrual_rate"


func _ready() -> void:
	TimeSystem.hour_passed.connect(_on_hour_passed)


func _on_hour_passed(hour_of_day: int, _day: int) -> void:
	var registry := PartyManager.get_registry()
	var is_night := hour_of_day >= NIGHT_START_HOUR or hour_of_day < NIGHT_END_HOUR

	for sheet in PartyManager.get_roster():
		sheet.hunger = clampf(sheet.hunger - _resolve_hunger_drain(sheet, registry), 0.0, 100.0)
		sheet.fatigue = clampf(sheet.fatigue + _resolve_fatigue_delta(sheet, registry, is_night), 0.0, 100.0)

	# Same notify-after-mutating pattern the debug tools already use --
	# CharacterSheet has no change signal of its own, so anything
	# displaying live roster data (the Party overlay) needs this to
	# know a background tick just happened.
	PartyManager.notify_roster_changed()


## environmental_entries: Array[ModifierEntry], reserved for a future
## World/Hex system to supply terrain-based modifiers (e.g. a
## mountainous hex increasing drain for everyone currently traveling
## it). Nothing populates this yet -- empty default -- but the
## parameter exists now so this function doesn't need restructuring
## once World does exist, same "reserve the seam" treatment as
## InventorySystem's party_size/vehicle_capacity inputs.
func _resolve_hunger_drain(sheet: CharacterSheet, registry: CharacterDataRegistry, environmental_entries: Array = []) -> float:
	var entries := sheet.get_modifier_entries(registry)
	entries.append_array(environmental_entries)
	var result := ModifierResolver.aggregate(entries, [HUNGER_DRAIN_TARGET])
	return maxf(0.0, BASE_HUNGER_DRAIN_PER_HOUR + result.additive_total)


func _resolve_fatigue_delta(
	sheet: CharacterSheet, registry: CharacterDataRegistry, is_night: bool, environmental_entries: Array = []
) -> float:
	var base := -BASE_FATIGUE_RECOVERY_PER_HOUR if is_night else BASE_FATIGUE_ACCRUAL_PER_HOUR

	var entries := sheet.get_modifier_entries(registry)
	entries.append_array(environmental_entries)
	var result := ModifierResolver.aggregate(entries, [FATIGUE_ACCRUAL_TARGET])

	# Modifier bonus applies whether it's day or night -- a sick
	# character recovers less overnight too, not just accrues faster
	# while awake, which reads correctly for something like a fever.
	return base + result.additive_total
