class_name CharacterSheet
extends Resource

## The full data record for one party member.
##
## Design principle carried over from the Core Systems GDD: this
## Resource only STORES data. It does not roll dice, apply weather,
## or decide what happens when Fatigue gets too high — other
## systems (Dice/Skill Check, Modifier, Time, Event) read and act
## on what's here.


## ============================================================
## IDENTITY
## ============================================================
@export var character_name: String = ""
@export var portrait: Texture2D

## Reference into an OccupationDefinition data table (not yet built).
## Applied ONCE at character creation: grants a starting Trait,
## applies stat_modifiers to the base scores below, and seeds the
## party Inventory with starting gear. The sheet keeps this id only
## for flavor/lookup afterward — none of those effects re-apply.
@export var occupation_id: String = ""

## Distinguishes the player's protagonist from NPC party members.
## NOT player-editable — determined by creation ORDER within a
## party creation flow (the first character created is always the
## main character; everyone after is an NPC). This single-character
## prototype creator has no such flow yet, so it leaves this at its
## default until the future Party Creator manages that ordering.
@export var is_main_character: bool = false


## ============================================================
## CORE STATS
## ============================================================
## Score range: 0-20+, D&D-style. Modifier = floor((score - 10) / 2).
## PERMANENT values — set at creation (base + Occupation bonus),
## occasionally adjusted by rare milestone events later (TBD).
## Temporary effects (Fatigue, Hunger, Injury, Weather, etc.) never
## touch these directly; they flow through the Modifier System at
## query time instead — see get_base_modifier() below.

enum Stat { BRAWN, AGILITY, GRIT, WITS, KNOWLEDGE, PRESENCE }

@export var brawn: int = 10
@export var agility: int = 10
@export var grit: int = 10        # Passive only — intentionally no skills use this stat.
@export var wits: int = 10
@export var knowledge: int = 10
@export var presence: int = 10


func get_base_score(stat: Stat) -> int:
	match stat:
		Stat.BRAWN:
			return brawn
		Stat.AGILITY:
			return agility
		Stat.GRIT:
			return grit
		Stat.WITS:
			return wits
		Stat.KNOWLEDGE:
			return knowledge
		Stat.PRESENCE:
			return presence
	return 10


## Base modifier derived from score alone. Does NOT include runtime
## Modifier System contributions (Fatigue, Injury, Weather, etc.) —
## callers building an "effective" modifier for a check should query
## the Modifier Manager separately and add its result to this.
func get_base_modifier(stat: Stat) -> int:
	return score_to_modifier(get_base_score(stat))


## Static so callers with just a raw score (no CharacterSheet
## instance yet — e.g. a character creator UI) can compute the same
## modifier without needing to construct a sheet first.
static func score_to_modifier(score: int) -> int:
	return int(floor((score - 10) / 2.0))


## ============================================================
## SKILLS
## ============================================================
@export var skills: Array[SkillProgress] = []


func get_skill(skill_id: String) -> SkillProgress:
	for s in skills:
		if s.skill_id == skill_id:
			return s
	return null


## ============================================================
## TRAITS
## ============================================================
## Growable: one INNATE trait granted by Occupation at creation,
## additional EARNED traits granted by Event/story triggers later.
@export var traits: Array[TraitInstance] = []


func has_trait(trait_id: String) -> bool:
	for t in traits:
		if t.trait_id == trait_id:
			return true
	return false


## ============================================================
## HEALTH & CONDITION
## ============================================================
@export_range(0.0, 100.0) var hunger: float = 100.0   # 100 = fully fed
@export_range(0.0, 100.0) var fatigue: float = 0.0     # 0 = fully rested
@export var injuries: Array[InjuryInstance] = []
@export var diseases: Array[DiseaseInstance] = []

enum ConditionTier { HEALTHY, STRAINED, WEAKENED, CRITICAL }


## Derived, never stored, never shown to the player as a raw number.
## TODO: placeholder thresholds — real weighting/tuning still pending.
func get_condition_tier() -> ConditionTier:
	var worst := 0
	for i in injuries:
		worst = max(worst, i.severity)
	for d in diseases:
		worst = max(worst, d.severity)

	if worst >= InjuryInstance.Severity.CRITICAL:
		return ConditionTier.CRITICAL
	elif worst >= InjuryInstance.Severity.SEVERE or fatigue > 80.0 or hunger < 20.0:
		return ConditionTier.WEAKENED
	elif worst >= InjuryInstance.Severity.MODERATE or fatigue > 50.0 or hunger < 50.0:
		return ConditionTier.STRAINED
	return ConditionTier.HEALTHY


## ============================================================
## MORALE
## ============================================================
@export_range(0.0, 100.0) var morale: float = 50.0

enum MoraleTier { DESPAIRING, LOW, STEADY, HIGH, INSPIRED }


## Derived, hidden from the player like Condition.
## TODO: placeholder thresholds — real tuning still pending.
func get_morale_tier() -> MoraleTier:
	if morale < 20.0:
		return MoraleTier.DESPAIRING
	elif morale < 40.0:
		return MoraleTier.LOW
	elif morale < 70.0:
		return MoraleTier.STEADY
	elif morale < 90.0:
		return MoraleTier.HIGH
	return MoraleTier.INSPIRED


## ============================================================
## RELATIONSHIPS (placeholder — not yet designed)
## ============================================================
## Likely keyed by other character ids rather than a flat value,
## since relationships are BETWEEN characters, not intrinsic to one.
@export var relationships: Dictionary = {}


## ============================================================
## MODIFIER GATHERING
## ============================================================
## Collects this character's own modifier-contributing sources
## (Traits, Injuries, Diseases) into a flat list of ModifierEntry
## objects for ModifierResolver to aggregate. The character gathers
## its OWN entries — ModifierResolver never reaches into a
## CharacterSheet directly, which is what keeps per-character
## isolation automatic rather than something enforced by convention.
func get_modifier_entries(registry: CharacterDataRegistry) -> Array:
	var entries: Array = []

	for t in traits:
		var def: TraitDefinition = registry.traits.get(t.trait_id)
		if def != null:
			entries.append_array(def.modifiers)

	for i in injuries:
		entries.append_array(i.penalties)

	for d in diseases:
		entries.append_array(d.penalties)

	return entries
