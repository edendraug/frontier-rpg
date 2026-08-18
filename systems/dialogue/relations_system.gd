extends Node

## Autoload. Owns two internally-separated jobs, directly mirroring
## VitalsSystem tracking Hunger and Fatigue under one roof because
## they're used together while keeping their internal data cleanly
## distinct (design doc Section 6):
##
##   - Actor-keyed state: authored ActorDefinitions (discovered the
##     same way CharacterDataRegistry discovers Skills/Traits/
##     Occupations) plus per-playthrough ActorState (known/unknown,
##     per-Option memory).
##   - Faction-keyed state: player Faction Reputation floats. NOT
##     actor-keyed - a handful of global values shared across every
##     Actor belonging to that faction (Section 3.3). Do not confuse
##     this with ActorDefinition.faction_alignment, which is a static
##     per-NPC fact, not a dynamic player-facing score.
##
## Register in Project Settings > Autoload.

signal actor_known(actor_id: String)
signal faction_reputation_changed(faction_id: String, new_value: float)

const ACTOR_DIR := "res://systems/dialogue/data/actors/"

var _actor_definitions: Dictionary = {}   # actor_id -> ActorDefinition
var _actor_states: Dictionary = {}        # actor_id -> ActorState, created lazily
var _faction_reputation: Dictionary = {}  # faction_id -> float, absent = 0.0


func _ready() -> void:
	_load_actor_definitions(ACTOR_DIR)


# ---------------------------------------------------------------------------
# Actor discovery / definitions
# ---------------------------------------------------------------------------

## Mirrors CharacterDataRegistry._load_all()'s DirAccess scan exactly,
## per the design doc's note (Section 6) that Actor discovery should
## match whatever convention CharacterDataRegistry already uses rather
## than inventing a second one. Kept here rather than delegated to
## CharacterDataRegistry itself since Actors are a Dialogue-owned
## concept, not a Character one.
func _load_actor_definitions(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("RelationsSystem: could not open %s" % dir_path)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var res: Resource = load(dir_path + file_name)
			if res is ActorDefinition:
				_actor_definitions[res.actor_id] = res
			else:
				push_warning("RelationsSystem: '%s' is not an ActorDefinition, skipping" % file_name)
		file_name = dir.get_next()
	dir.list_dir_end()


func get_actor_definition(actor_id: String) -> ActorDefinition:
	return _actor_definitions.get(actor_id, null)


func has_actor_definition(actor_id: String) -> bool:
	return _actor_definitions.has(actor_id)


# ---------------------------------------------------------------------------
# Actor live state
# ---------------------------------------------------------------------------

## Lazily creates state on first access rather than pre-populating one
## ActorState per discovered Actor - most Actors in a given
## playthrough are never spoken to, so this avoids allocating state
## that never gets used.
func get_actor_state(actor_id: String) -> ActorState:
	if not _actor_states.has(actor_id):
		_actor_states[actor_id] = ActorState.new(actor_id)
	return _actor_states[actor_id]


func is_actor_known(actor_id: String) -> bool:
	return _actor_states.has(actor_id) and _actor_states[actor_id].is_known


## General-purpose, per design doc Section 3.1 - anything can call this
## (a trader mentioning someone's name, a letter, a journal entry), not
## only a dialogue node reaching an "introduce yourself" branch. No-ops
## (with a warning) for an actor_id with no discovered definition, per
## the missing-reference convention in Section 5.4.
func reveal_actor_name(actor_id: String) -> void:
	if not has_actor_definition(actor_id):
		push_warning("RelationsSystem: reveal_actor_name() called for unknown actor_id '%s'" % actor_id)
		return
	var state := get_actor_state(actor_id)
	if state.is_known:
		return
	state.mark_known()
	actor_known.emit(actor_id)


## Known name once revealed, unknown name before that. Falls back to
## the raw actor_id if no definition can be found at all (missing-
## reference failsafe, Section 5.4) so a broken reference degrades to
## a visible placeholder string for whatever's trying to render it,
## rather than crashing.
func get_display_name(actor_id: String) -> String:
	var def := get_actor_definition(actor_id)
	if def == null:
		push_warning("RelationsSystem: get_display_name() called for unknown actor_id '%s'" % actor_id)
		return actor_id
	return def.known_name if is_actor_known(actor_id) else def.unknown_name


# ---------------------------------------------------------------------------
# Faction Reputation (player-level, NOT actor-keyed)
# ---------------------------------------------------------------------------

func get_faction_reputation(faction_id: String) -> float:
	return _faction_reputation.get(faction_id, 0.0)


## The only mutator - matches FACTION_REPUTATION_DELTA's shape (Section
## 4.8) directly, so DialoguePlayer's effect resolver can call this
## with an effect's target/value with no translation in between. Per
## Section 3.3, whether one event's delta should also apply an
## opposing-faction delta is an authoring decision (dual-author both
## effects), not something this method resolves automatically - see
## the doc's open question 1, not yet confirmed.
func apply_faction_reputation_delta(faction_id: String, delta: float) -> void:
	var new_value: float = get_faction_reputation(faction_id) + delta
	_faction_reputation[faction_id] = new_value
	faction_reputation_changed.emit(faction_id, new_value)


# ---------------------------------------------------------------------------
# Save / Load
# ---------------------------------------------------------------------------

## Same snapshot/load_state split InventorySystem uses: duplicated
## reads so a saved copy can't be mutated later through a shared
## reference.
func get_actor_states_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	for actor_id in _actor_states:
		snapshot[actor_id] = _actor_states[actor_id].to_dict()
	return snapshot


func get_faction_reputation_snapshot() -> Dictionary:
	return _faction_reputation.duplicate()


## Direct restore, used only by SaveManager on load - deliberately not
## routed through reveal_actor_name()/apply_faction_reputation_delta(),
## since those model something happening during play, not restoring a
## prior state. Still emits faction_reputation_changed for each
## restored faction so anything listening (a reputation HUD) reacts to
## a load the same way it would to gameplay, matching InventorySystem's
## load_state() convention.
##
## Missing-actor failsafe (Section 5.4): an actor_id the current
## registry can no longer find (removed/renamed content) is restored
## anyway as inert, ignorable state - every other method here already
## checks has_actor_definition() before doing anything with an actor_id,
## so a dangling entry simply never surfaces. push_warning for dev
## visibility; never a hard failure.
func load_state(actor_states: Dictionary, faction_reputation: Dictionary) -> void:
	_actor_states.clear()
	for actor_id in actor_states:
		if not has_actor_definition(actor_id):
			push_warning("RelationsSystem: save data references unknown actor_id '%s', loading as inert state" % actor_id)
		_actor_states[actor_id] = ActorState.from_dict(actor_states[actor_id])

	_faction_reputation = faction_reputation.duplicate()
	for faction_id in _faction_reputation:
		faction_reputation_changed.emit(faction_id, _faction_reputation[faction_id])


## Clears per-playthrough state back to defaults for a new expedition.
## Does NOT clear _actor_definitions - those are authored content,
## rediscovered once at _ready(), same lifecycle split as everywhere
## else in this project.
func reset() -> void:
	_actor_states.clear()
	_faction_reputation.clear()
