class_name ModifierResolver
extends RefCounted

## Stateless aggregator — no autoload, no stored state, nothing to
## initialize. Deliberately knows nothing about Character, Trait,
## Injury, Skill Checks, Dialogue, or anything else that PRODUCES
## modifier entries; it only ever combines whatever pile of already-
## gathered ModifierEntry objects a caller hands it.
##
## Gathering is each source's own job — CharacterSheet knows how to
## collect its own Traits/Injuries/Diseases into entries (see
## CharacterSheet.get_modifier_entries()); a future Environment/
## Weather system will do the same for context-level sources. This
## keeps per-character isolation automatic: nothing here ever
## reaches across characters, because nothing here holds any
## character's data in the first place — it only ever sees whatever
## ONE caller passed in for THIS query.


static func target_for_skill(skill_id: String) -> String:
	return "skill:" + skill_id


## Uses the Stat enum's own name (via reflection) rather than a
## separate hand-maintained key list, so this can't drift out of
## sync if a stat is ever renamed.
static func target_for_stat(stat: CharacterSheet.Stat) -> String:
	return "stat:" + CharacterSheet.Stat.keys()[stat].to_lower()


static func target_for_system(system_name: String) -> String:
	return "system:" + system_name


## entries: Array[ModifierEntry] — everything gathered from every
##   relevant source for THIS query (e.g. one character's traits +
##   injuries + diseases).
## matching_targets: Array[String] — every target string relevant to
##   this specific check (e.g. ["skill:tracking", "stat:wits"] for a
##   Tracking check, so a general Wits penalty correctly cascades in
##   alongside anything targeting Tracking directly).
##
## An entry counts if ANY of its targets overlaps matching_targets —
## a multi-target entry (e.g. Broken Hand hitting both "skill:craft"
## and "skill:marksmanship") only needs ONE of those to be relevant
## to this particular check to contribute.
static func aggregate(entries: Array, matching_targets: Array) -> ModifierResult:
	var result := ModifierResult.new()

	for entry in entries:
		if entry == null:
			continue
		if not _targets_overlap(entry.targets, matching_targets):
			continue

		result.contributing_entries.append(entry)
		match entry.type:
			ModifierEntry.Type.ADDITIVE:
				result.additive_total += entry.value
			ModifierEntry.Type.MULTIPLICATIVE:
				result.multiplicative_total *= entry.value
			ModifierEntry.Type.SUPPRESS_BONUS_DICE:
				if entry.full_suppression:
					result.bonus_dice_fully_suppressed = true
				else:
					result.bonus_dice_suppression += entry.value

	return result


static func _targets_overlap(entry_targets: Array, matching_targets: Array) -> bool:
	for t in entry_targets:
		if t in matching_targets:
			return true
	return false
