extends Node

## Autoload. Applies passive drift to each party member's Hunger and
## Fatigue, and processes Morale Events -- all three are "things that
## evolve character wellbeing over time," which is why Morale lives
## here rather than in a separate system.
##
## Listens to TimeSystem.time_advanced (fires on every pass_minutes()
## call) rather than hour_passed (fires only on an hour boundary
## crossing), and scales every change by the ACTUAL elapsed minutes
## since the last tick -- see _on_time_advanced. An earlier version
## used hour_passed with a flat "one hour's worth" applied per fire,
## which was correct in total but "chunky": a 90-minute skip only
## credited one full hour immediately, leaving the remaining 30
## minutes uncredited until some LATER hour boundary happened to be
## crossed. Proportional scaling closes that gap and updates on every
## tick, however small.
##
## Feeding/consumption (feed_character(), below) closes the gap this
## comment used to describe as deferred -- see
## Frontier_RPG_Food_Consumption_Design_Doc.md for the full design.
##
## Register in Project Settings > Autoload AFTER PartyManager and
## SaveManager, since _ready() connects to both.

## Placeholder/tunable rate, same treatment as the DC table and
## everywhere else marked this way. Hunger 100->0 over ~48 waking
## hours. Fatigue ONLY ever accrues -- no automatic recovery of any
## kind, including overnight. An earlier version silently recovered
## Fatigue during a defined night window as a stand-in for real rest;
## that turned out to be exactly the wrong instinct, since
## automatically resting a character because a clock crossed a
## certain hour is a disguised version of the thing that should stay
## genuinely absent until Assignment/Camp makes Rest a deliberate
## player action. Fatigue climbing to 100 and staying there is an
## intentional, visible gap until then.
const BASE_HUNGER_DRAIN_PER_HOUR := 2.1
const BASE_FATIGUE_ACCRUAL_PER_HOUR := 5.6

## Modifier System targets external sources contribute to, aggregated
## the same way SkillCheck already aggregates skill/stat targets.
## Per-character sources (Traits, Injuries, Diseases) flow in
## automatically via CharacterSheet.get_modifier_entries() -- e.g. a
## Disease's existing `penalties` array can already target
## FATIGUE_ACCRUAL_TARGET with zero new Disease fields needed. A
## modifier can reduce accrual toward zero, never past it into actual
## recovery -- see the maxf() floor below. Real recovery stays
## reserved for a deliberate Rest action, never something a passive
## modifier grants for free.
const HUNGER_DRAIN_TARGET := "system:hunger_drain_rate"
const FATIGUE_ACCRUAL_TARGET := "system:fatigue_accrual_rate"


## ============================================================
## MORALE EVENTS
## ============================================================
## Morale = MORALE_BASELINE + sum(active event magnitudes), clamped
## to [0, 100] -- recomputed every hour after decay, and immediately
## whenever a new event is applied. As events decay toward 0 and get
## pruned, Morale naturally drifts back toward the baseline unless
## something keeps refreshing it. sheet.morale stays a normal stored
## field on CharacterSheet (unchanged) -- this just overwrites it
## each tick rather than making it a derived getter, so nothing
## reading sheet.morale elsewhere needs to change.
const MORALE_BASELINE := 50.0

## Witnessing something happen to a party member is demoralizing too,
## just less than experiencing it directly -- flat fraction for now.
## NOT relationship-weighted: CharacterSheet.relationships has no
## real shape yet (an undefined placeholder), so weighting by
## closeness would be building on a field that doesn't mean anything
## yet. Revisit once Dialogue actually defines what a relationship is.
const WITNESSED_FRACTION := 0.3

## Self-hit magnitude by severity. Disease intentionally gentler than
## Injury -- being sick reads as less alarming than being hurt.
## Placeholder numbers, tune freely.
const INJURY_SELF_MAGNITUDE := {
	InjuryInstance.Severity.MINOR: -3.0,
	InjuryInstance.Severity.MODERATE: -8.0,
	InjuryInstance.Severity.SEVERE: -15.0,
	InjuryInstance.Severity.CRITICAL: -25.0,
}
const DISEASE_SELF_MAGNITUDE := {
	DiseaseInstance.Severity.MINOR: -2.0,
	DiseaseInstance.Severity.MODERATE: -6.0,
	DiseaseInstance.Severity.SEVERE: -12.0,
	DiseaseInstance.Severity.CRITICAL: -20.0,
}

## How many hours until each severity's event has fully faded --
## authored this way (rather than a raw decay-per-hour number)
## because "takes about 3 days to get over" is a more natural thing
## to tune than an abstract rate. decay_per_hour is derived from this
## at event-creation time. Severe/critical linger far longer than minor.
const INJURY_FADE_HOURS := {
	InjuryInstance.Severity.MINOR: 12.0,
	InjuryInstance.Severity.MODERATE: 48.0,
	InjuryInstance.Severity.SEVERE: 96.0,
	InjuryInstance.Severity.CRITICAL: 168.0,  # a full week
}
const DISEASE_FADE_HOURS := {
	DiseaseInstance.Severity.MINOR: 12.0,
	DiseaseInstance.Severity.MODERATE: 48.0,
	DiseaseInstance.Severity.SEVERE: 96.0,
	DiseaseInstance.Severity.CRITICAL: 168.0,
}


## ============================================================
## VITALS MORALE MODIFIER
## ============================================================
## A continuous, NON-decaying pressure on Morale from the character's
## CURRENT Hunger/Fatigue/Injury/Disease state -- distinct from
## Morale Events above. An event captures the SHOCK of something
## happening (fades over time, e.g. the initial jolt of an injury);
## this captures the ongoing WEIGHT of a condition that's still true
## right now (present exactly as long as the condition is, gone the
## instant it resolves -- no lag either direction, never stored,
## always recalculated fresh). Both layers sum together in
## _recompute_morale below.

## Comfort thresholds intentionally reuse the SAME breakpoints
## get_condition_tier() already uses for its STRAINED tier (fatigue >
## 50, hunger < 50) -- consistent rather than inventing new numbers
## that mean something slightly different.
const HUNGER_COMFORT_THRESHOLD := 50.0
const MAX_HUNGER_MORALE_PENALTY := -15.0  # reached at hunger = 0
const FATIGUE_COMFORT_THRESHOLD := 50.0
const MAX_FATIGUE_MORALE_PENALTY := -15.0  # reached at fatigue = 100

## Ongoing weight of CURRENTLY having an injury/disease, separate from
## the one-time shock already captured by apply_injury_morale_hit's
## decaying event. Only the WORST active injury/disease counts, same
## "worst wins" rule get_condition_tier() already uses across
## multiple simultaneous injuries -- not summed across all of them.
const INJURY_ONGOING_PENALTY := {
	InjuryInstance.Severity.MINOR: -1.0,
	InjuryInstance.Severity.MODERATE: -3.0,
	InjuryInstance.Severity.SEVERE: -6.0,
	InjuryInstance.Severity.CRITICAL: -12.0,
}
const DISEASE_ONGOING_PENALTY := {
	DiseaseInstance.Severity.MINOR: -1.0,
	DiseaseInstance.Severity.MODERATE: -2.0,
	DiseaseInstance.Severity.SEVERE: -4.0,
	DiseaseInstance.Severity.CRITICAL: -8.0,
}


## Tracks TimeSystem's clock as of the last tick we processed, so
## _on_time_advanced can compute how many minutes ACTUALLY elapsed
## since last time and scale everything proportionally -- rather than
## assuming a flat "one hour" per signal fire the way the old
## hour_passed-based version did. -1 means "not yet initialized."
var _last_processed_minute: int = -1


func _ready() -> void:
	TimeSystem.time_advanced.connect(_on_time_advanced)

	# set_total_minutes_elapsed() (used by SaveManager on load) fires
	# no signal at all, by design -- a load isn't time actually
	# passing, so nothing should react to it as if it were. But that
	# means _last_processed_minute would otherwise go stale across a
	# load, and the NEXT real time_advanced afterward would compute a
	# huge bogus elapsed-minutes delta against the pre-load value.
	# Resyncing here closes that gap.
	SaveManager.load_completed.connect(func(_slug): _last_processed_minute = TimeSystem.get_total_minutes_elapsed())

	_last_processed_minute = TimeSystem.get_total_minutes_elapsed()


func _on_time_advanced(total_minutes_elapsed: int) -> void:
	var elapsed_minutes := total_minutes_elapsed - _last_processed_minute
	_last_processed_minute = total_minutes_elapsed
	if elapsed_minutes <= 0:
		return

	var hours_elapsed := elapsed_minutes / 60.0
	var registry := PartyManager.get_registry()

	for sheet in PartyManager.get_roster():
		sheet.hunger = clampf(sheet.hunger - _resolve_hunger_drain(sheet, registry) * hours_elapsed, 0.0, 100.0)
		sheet.fatigue = clampf(sheet.fatigue + _resolve_fatigue_accrual(sheet, registry) * hours_elapsed, 0.0, 100.0)
		_tick_morale_events(sheet, hours_elapsed)

	# Same notify-after-mutating pattern the debug tools already use --
	# CharacterSheet has no change signal of its own, so anything
	# displaying live roster data (the Party overlay) needs this to
	# know a background tick just happened.
	PartyManager.notify_roster_changed()


## ============================================================
## HUNGER / FATIGUE
## ============================================================
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


func _resolve_fatigue_accrual(sheet: CharacterSheet, registry: CharacterDataRegistry, environmental_entries: Array = []) -> float:
	var entries := sheet.get_modifier_entries(registry)
	entries.append_array(environmental_entries)
	var result := ModifierResolver.aggregate(entries, [FATIGUE_ACCRUAL_TARGET])
	return maxf(0.0, BASE_FATIGUE_ACCRUAL_PER_HOUR + result.additive_total)


## ============================================================
## MORALE
## ============================================================
## Public entry point -- any system calls this to add a stacked
## morale effect. HealthDebugTab uses it today (via
## apply_injury_morale_hit/apply_disease_morale_hit below); feed_character()
## below is now a real caller too. Multiple calls stack as separate
## entries rather than overwriting each other. Recomputes Morale
## immediately (not just decay-per-hour), so an applied event is
## reflected right away rather than waiting up to an hour for the
## next tick.
func apply_morale_event(sheet: CharacterSheet, source_label: String, magnitude: float, decay_per_hour: float) -> void:
	if magnitude == 0.0:
		return
	sheet.morale_events.append(
		MoraleEventInstance.new(source_label, magnitude, absf(decay_per_hour), TimeSystem.get_current_day())
	)
	_recompute_morale(sheet)
	PartyManager.notify_roster_changed()


## Applies a self-hit to the injured character, plus a smaller
## witnessed-hit to every OTHER party member — watching a companion
## get hurt is demoralizing for the group too, not just the victim.
func apply_injury_morale_hit(affected: CharacterSheet, severity: InjuryInstance.Severity) -> void:
	_apply_self_and_witnessed_hit(
		affected,
		"Injury",
		INJURY_SELF_MAGNITUDE.get(severity, -5.0),
		INJURY_FADE_HOURS.get(severity, 24.0),
	)


func apply_disease_morale_hit(affected: CharacterSheet, severity: DiseaseInstance.Severity) -> void:
	_apply_self_and_witnessed_hit(
		affected,
		"Illness",
		DISEASE_SELF_MAGNITUDE.get(severity, -4.0),
		DISEASE_FADE_HOURS.get(severity, 24.0),
	)


func _apply_self_and_witnessed_hit(affected: CharacterSheet, label: String, self_magnitude: float, fade_hours: float) -> void:
	apply_morale_event(affected, label, self_magnitude, absf(self_magnitude) / fade_hours)

	var witnessed_magnitude := self_magnitude * WITNESSED_FRACTION
	for sheet in PartyManager.get_roster():
		if sheet == affected:
			continue
		apply_morale_event(sheet, "Witnessed: %s" % label, witnessed_magnitude, absf(witnessed_magnitude) / fade_hours)


func _recompute_morale(sheet: CharacterSheet) -> void:
	var event_total := 0.0
	for event in sheet.morale_events:
		event_total += event.magnitude

	sheet.morale = clampf(MORALE_BASELINE + event_total + get_vitals_morale_modifier(sheet), 0.0, 100.0)


## Public (not just used internally) so debug/UI can display this
## breakdown separately from the event total, for exactly the kind
## of testing-accuracy visibility already established elsewhere.
func get_vitals_morale_modifier(sheet: CharacterSheet) -> float:
	var total := 0.0

	if sheet.hunger < HUNGER_COMFORT_THRESHOLD:
		var fraction := (HUNGER_COMFORT_THRESHOLD - sheet.hunger) / HUNGER_COMFORT_THRESHOLD
		total += fraction * absf(MAX_HUNGER_MORALE_PENALTY) * -1.0

	if sheet.fatigue > FATIGUE_COMFORT_THRESHOLD:
		var fraction := (sheet.fatigue - FATIGUE_COMFORT_THRESHOLD) / (100.0 - FATIGUE_COMFORT_THRESHOLD)
		total += fraction * absf(MAX_FATIGUE_MORALE_PENALTY) * -1.0

	var worst_injury := -1
	for i in sheet.injuries:
		worst_injury = maxi(worst_injury, i.severity)
	if worst_injury >= 0:
		total += INJURY_ONGOING_PENALTY.get(worst_injury, 0.0)

	var worst_disease := -1
	for d in sheet.diseases:
		worst_disease = maxi(worst_disease, d.severity)
	if worst_disease >= 0:
		total += DISEASE_ONGOING_PENALTY.get(worst_disease, 0.0)

	return total


## ============================================================
## VITALS STAT MODIFIERS
## ============================================================
## Translates current Hunger/Fatigue into real ModifierEntry objects
## that feed into Skill Checks -- SkillCheck.resolve() calls
## get_vitals_stat_modifier_entries() and folds the result in
## alongside the character's own Trait/Injury/Disease entries. Two
## tiers per vital (mild/severe), reusing get_condition_tier()'s
## EXACT breakpoints (hunger < 50 / < 20, fatigue > 50 / > 80) rather
## than inventing new numbers that would mean something slightly
## different.
##
## Hunger hits the PHYSICAL axis (Brawn + Agility) — starvation saps
## the body. Fatigue hits the MENTAL/SOCIAL axis (Presence + Wits) —
## exhaustion saps clarity and charm. Same magnitude applies to BOTH
## stats per vital, not split/halved between them: each stat is a
## separate ModifierEntry with its own target, and any single roll
## only has ONE governing stat, so a given check only ever feels ONE
## of the two — this widens which rolls Hunger/Fatigue can touch,
## it doesn't stack severity onto any single roll. Placeholder
## magnitudes, tune freely.
##
## Deliberately does NOT live on CharacterSheet.get_modifier_entries()
## -- that function only concatenates arrays already sitting on
## sub-objects (Traits, Injuries, Diseases' own pre-authored
## .modifiers/.penalties), which is pure data-gathering. Evaluating
## "if hunger < X, apply Y" is a decision, and CharacterSheet's own
## design principle explicitly keeps it out of that role.
const HUNGER_SEVERE_THRESHOLD := 20.0
const HUNGER_MILD_STAT_PENALTY := -1
const HUNGER_SEVERE_STAT_PENALTY := -2

const FATIGUE_SEVERE_THRESHOLD := 80.0
const FATIGUE_MILD_STAT_PENALTY := -1
const FATIGUE_SEVERE_STAT_PENALTY := -2


func get_vitals_stat_modifier_entries(sheet: CharacterSheet) -> Array[ModifierEntry]:
	var entries: Array[ModifierEntry] = []

	if sheet.hunger < HUNGER_SEVERE_THRESHOLD:
		entries.append(_make_stat_penalty(CharacterSheet.Stat.BRAWN, HUNGER_SEVERE_STAT_PENALTY, "Starving"))
		entries.append(_make_stat_penalty(CharacterSheet.Stat.AGILITY, HUNGER_SEVERE_STAT_PENALTY, "Starving"))
	elif sheet.hunger < HUNGER_COMFORT_THRESHOLD:
		entries.append(_make_stat_penalty(CharacterSheet.Stat.BRAWN, HUNGER_MILD_STAT_PENALTY, "Hungry"))
		entries.append(_make_stat_penalty(CharacterSheet.Stat.AGILITY, HUNGER_MILD_STAT_PENALTY, "Hungry"))

	if sheet.fatigue > FATIGUE_SEVERE_THRESHOLD:
		entries.append(_make_stat_penalty(CharacterSheet.Stat.PRESENCE, FATIGUE_SEVERE_STAT_PENALTY, "Exhausted"))
		entries.append(_make_stat_penalty(CharacterSheet.Stat.WITS, FATIGUE_SEVERE_STAT_PENALTY, "Exhausted"))
	elif sheet.fatigue > FATIGUE_COMFORT_THRESHOLD:
		entries.append(_make_stat_penalty(CharacterSheet.Stat.PRESENCE, FATIGUE_MILD_STAT_PENALTY, "Tired"))
		entries.append(_make_stat_penalty(CharacterSheet.Stat.WITS, FATIGUE_MILD_STAT_PENALTY, "Tired"))

	return entries


func _make_stat_penalty(stat: CharacterSheet.Stat, value: int, source_label: String) -> ModifierEntry:
	var m := ModifierEntry.new()
	# targets (plural, Array[String]) -- ModifierEntry has no singular
	# `target` property. This was a pre-existing bug, not something
	# introduced by the Food Consumption work; see chat for how it
	# surfaced.
	m.targets = [ModifierResolver.target_for_stat(stat)]
	m.value = value
	m.type = ModifierEntry.Type.ADDITIVE
	m.source_label = source_label
	return m


## Decays each active event's magnitude toward 0 by its own
## decay_per_hour, SCALED to how many hours actually elapsed this
## tick (not assumed to always be exactly one), drops any that have
## fully decayed, then recomputes Morale from whatever's still active.
func _tick_morale_events(sheet: CharacterSheet, hours_elapsed: float) -> void:
	var still_active: Array[MoraleEventInstance] = []
	for event in sheet.morale_events:
		var event_sign := signf(event.magnitude)
		event.magnitude = event_sign * maxf(0.0, absf(event.magnitude) - event.decay_per_hour * hours_elapsed)
		if event.magnitude != 0.0:
			still_active.append(event)
	sheet.morale_events = still_active
	_recompute_morale(sheet)


## ============================================================
## FOOD CONSUMPTION
## ============================================================
## Bridges Inventory <-> Vitals. See
## Frontier_RPG_Food_Consumption_Design_Doc.md for the full design.
##
## is_at_camp is caller-supplied rather than queried from any real
## Travel/Camp state, because no such state exists anywhere in the
## project yet -- a debug toggle is the only real caller until one does
## (design doc Section 2/9).
##
## Eating does not consume game time (design doc Section 9, Q1) --
## feed_character() never touches TimeSystem's clock.

## Placeholder multipliers/penalties/DCs -- see design doc Section 5.2,
## confirmed as acceptable first-guess numbers pending playtesting.
## Applied PER UNIT consumed, not once per feed_character() call (design
## doc Section 9, Q2) -- quantity can span batches of different
## freshness, so each unit resolves independently against its own
## batch's tier.
const SPOILING_NUTRITION_MULTIPLIER := 0.5
const SPOILING_MORALE_PENALTY := -5.0
const SPOILING_MORALE_DECAY_PER_HOUR := 1.0
const SPOILING_SICKNESS_DC_TIER := DiceResolver.DifficultyTier.EASY

const SPOILED_NUTRITION_MULTIPLIER := 0.25
const SPOILED_MORALE_PENALTY := -15.0
const SPOILED_MORALE_DECAY_PER_HOUR := 2.0
const SPOILED_SICKNESS_DC_TIER := DiceResolver.DifficultyTier.MEDIUM


## quantity <= 0 is a permissive no-op, same convention
## InventorySystem.remove_item()/consume_items() already use for a
## degenerate input -- returns a default (SUCCESS, all-empty) FeedResult
## rather than doing any work or validation.
func feed_character(sheet: CharacterSheet, item_id: String, is_at_camp: bool, quantity: int = 1) -> FeedResult:
	var result := FeedResult.new()
	if quantity <= 0:
		return result

	var item := ItemRegistry.get_item(item_id)
	if not (item is FoodDefinition):
		result.outcome = FeedResult.Outcome.INSUFFICIENT_ITEM
		return result
	var food := item as FoodDefinition

	if not food.is_edible_now(is_at_camp):
		result.outcome = FeedResult.Outcome.WRONG_LOCATION
		return result

	if not InventorySystem.has_item(item_id, quantity):
		result.outcome = FeedResult.Outcome.INSUFFICIENT_ITEM
		return result

	var registry := PartyManager.get_registry()
	var current_minute := TimeSystem.get_total_minutes_elapsed()

	# Predicted consumption order, oldest batch first -- same sort
	# InventorySystem._remove_from_batches() already applies internally.
	# IMPORTANT: get_batches() only shallow-duplicates the array: the
	# InventoryBatch objects inside are the SAME live objects still
	# sitting in InventorySystem's real state. Tracking units_left_in_batch
	# as a separate local counter below (rather than decrementing
	# batch.quantity directly) is deliberate -- mutating the batch
	# objects here would corrupt real inventory state before
	# consume_items() even runs.
	var batches: Array = InventorySystem.get_batches(item_id)
	batches.sort_custom(func(a, b): return a.acquired_minute < b.acquired_minute)

	var units_left_in_batch = batches[0].quantity if not batches.is_empty() else 0
	var batch_index := 0
	var remaining := quantity

	while remaining > 0:
		# Non-perishable food (perishable = false in food_definitions.csv)
		# has no batches at all -- batch_index >= batches.size() for
		# every unit, so this just falls through to FRESH, unconditionally.
		var tier := ItemFreshness.FreshnessTier.FRESH
		if batch_index < batches.size():
			var batch: InventoryBatch = batches[batch_index]
			tier = ItemFreshness.get_freshness_tier(batch, food, current_minute)
			units_left_in_batch -= 1
			if units_left_in_batch <= 0:
				batch_index += 1
				if batch_index < batches.size():
					units_left_in_batch = batches[batch_index].quantity

		result.freshness_tiers.append(tier)
		_apply_food_unit(sheet, food, tier, registry, result)
		remaining -= 1

	# Actual removal -- one atomic call, same predicted order as above.
	InventorySystem.consume_items({item_id: quantity})

	# Guarantees roster observers hear about the hunger/disease changes
	# above even on a unit whose morale magnitude was zero (e.g. Fresh
	# Jerky) -- apply_morale_event() only notifies when it actually runs,
	# and it's skipped entirely for a zero-magnitude unit.
	PartyManager.notify_roster_changed()

	result.outcome = FeedResult.Outcome.SUCCESS
	return result


## One unit's worth of nutrition/morale/sickness, per the tier table in
## Frontier_RPG_Food_Consumption_Design_Doc.md Section 5.2. Mutates
## `result` and applies real Hunger/Morale/Disease changes directly to
## `sheet` -- called once per unit consumed (design doc Section 9, Q2).
func _apply_food_unit(sheet: CharacterSheet, food: FoodDefinition, tier: ItemFreshness.FreshnessTier, registry: CharacterDataRegistry, result: FeedResult) -> void:
	var nutrition := food.nutrition_value
	var morale_magnitude := food.morale_value
	var morale_decay := food.morale_decay_per_hour
	var morale_label := food.display_name
	var sickness_dc_tier: int = -1  # -1 means "no saving throw this tier"

	match tier:
		ItemFreshness.FreshnessTier.SPOILING:
			nutrition *= SPOILING_NUTRITION_MULTIPLIER
			morale_magnitude = SPOILING_MORALE_PENALTY
			morale_decay = SPOILING_MORALE_DECAY_PER_HOUR
			morale_label = "Spoiling Food"
			sickness_dc_tier = SPOILING_SICKNESS_DC_TIER
		ItemFreshness.FreshnessTier.SPOILED:
			nutrition *= SPOILED_NUTRITION_MULTIPLIER
			morale_magnitude = SPOILED_MORALE_PENALTY
			morale_decay = SPOILED_MORALE_DECAY_PER_HOUR
			morale_label = "Spoiled Food"
			sickness_dc_tier = SPOILED_SICKNESS_DC_TIER
		# FRESH falls through untouched -- the item's own authored
		# nutrition_value/morale_value/morale_decay_per_hour stand as-is,
		# and no saving throw is rolled at all (sickness_dc_tier stays -1).

	sheet.hunger = clampf(sheet.hunger + nutrition, 0.0, 100.0)
	result.nutrition_restored += nutrition

	if morale_magnitude != 0.0:
		# Two separate MoraleEventInstance objects by design -- one for
		# result.morale_events (reporting only), one built internally by
		# apply_morale_event() for the real sheet.morale_events append.
		# Not the same reference; both describe the same event.
		result.morale_events.append(
			MoraleEventInstance.new(morale_label, morale_magnitude, absf(morale_decay), TimeSystem.get_current_day())
		)
		apply_morale_event(sheet, morale_label, morale_magnitude, morale_decay)

	if sickness_dc_tier >= 0:
		var dc := DiceResolver.dc_for_tier(sickness_dc_tier)
		var save_result := SavingThrow.new(sheet, CharacterSheet.Stat.GRIT, dc, registry).resolve()
		result.saving_throws.append(save_result)

		var severity := -1
		if save_result.outcome == DiceResolver.Outcome.FAILURE:
			severity = DiseaseInstance.Severity.MINOR
		elif save_result.outcome == DiceResolver.Outcome.CRITICAL_FAILURE:
			severity = DiseaseInstance.Severity.MODERATE
		# SUCCESS / CRITICAL_SUCCESS: resisted, severity stays -1, nothing applied.

		if severity >= 0:
			var disease := _make_food_poisoning(severity)
			sheet.diseases.append(disease)
			result.diseases_applied.append(disease)


## No DiseaseDefinition registry exists yet, and this doesn't build one --
## a small hardcoded factory next to this file's own severity tables
## above, same treatment as INJURY_SELF_MAGNITUDE/DISEASE_SELF_MAGNITUDE.
## See design doc Section 4.6.
func _make_food_poisoning(severity: DiseaseInstance.Severity) -> DiseaseInstance:
	var disease := DiseaseInstance.new()
	disease.disease_name = "Food Poisoning"
	disease.severity = severity
	disease.contagious = false
	disease.day_contracted = TimeSystem.get_current_day()
	return disease
