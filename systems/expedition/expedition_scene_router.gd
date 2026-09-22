extends Node

## Autoload. Owns the decision of what Expedition Hub's
## LocalSceneViewport should be showing at any given moment, and drives
## LocalSceneManager accordingly -- the connective layer between
## TravelSystem and the Local Movement System that neither owns on its
## own. See Expedition Scene Routing design doc.
##
## Register in Project Settings > Autoload LAST (after
## LocalSceneManager). Order doesn't actually matter for correctness --
## same reasoning already used for LocalSceneManager's own placement --
## since nothing here runs until real gameplay begins; last just reads
## naturally as "the thing that coordinates everything else."
##
## DEVIATIONS FROM THE ORIGINAL DESIGN DOC, confirmed with Cameron after
## reviewing the real travel_system.gd:
## - Bespoke-location arrival is detected on TravelSystem.hex_entered
##   (hex ENTRY, progress 0.0), not hex CENTER (progress 0.5) as
##   originally assumed -- no signal for the latter exists, and it reads
##   better against "You see X up ahead" anyway.
## - TravelState.State.ROUTE_COMPLETE (added to TravelSystem after the
##   design doc was written) is a no-op here, same as
##   PAUSED_BY_PLAYER/PAUSED_BY_EVENT -- the Travel ambient scene stays
##   showing; only AT_CAMP swaps to the Camp scene. The Travel scene
##   itself is responsible for pausing its own animation/behavior on
##   ROUTE_COMPLETE, not this router.
## - Save/load restoration is a direct call from SaveManager
##   (restore_from_save()), matching how SaveManager already restores
##   every other system, rather than a load_completed signal listener.
## - Later addition beyond the original doc: locations carry a
##   hex_sector (LocationSceneDefinition) so multiple POIs in one hex
##   can be prompted nearest-first and cost a real, approximate in-hex
##   travel-time fraction rather than being free/instant.
## - Real bug found during testing: boot_new_expedition() (and, almost
##   certainly, restore_from_save()) can run BEFORE Expedition Hub's
##   content viewport exists -- PartyManager.begin_expedition() fires
##   from the Party Creator screen, ahead of whatever scene transition
##   actually loads Expedition Hub. _load_scene() now remembers a
##   failed attempt and retries it once LocalSceneManager's new
##   content_viewport_ready signal fires (see that file's own comment).
## - Later addition beyond the original doc: "Approach" walks an
##   animated, real-time in-hex detour toward the location's sector
##   (Cameron's confirmed model) before loading its scene, rather than
##   an instant teleport -- see _begin_detour()/_advance_detour() below.
##   Committed once started; no cancel path exists. NOT persisted across
##   save/load (see _detour_active's own comment) -- an accepted gap,
##   not a decision. The debug tab's "Travel To" (visit_location())
##   deliberately keeps the OLD instant behavior, per Cameron.

## Placeholder paths -- these ambient scenes don't exist yet (design doc
## Section 2: hand-authored placeholders for now, procedural later).
## Update once real files exist.
const TRAVEL_SCENE_PATH := "res://systems/expedition/scenes/travel_ambient.tscn"
const CAMP_SCENE_PATH := "res://systems/expedition/scenes/camp_ambient.tscn"

## Same discovery convention as WorldRegistry._load_terrain_types() /
## CharacterDataRegistry._load_all() -- directory scan, not
## hand-enumerated.
const LOCATIONS_DIR := "res://systems/expedition/data/locations/"

## Hand-authored contract scene (design doc Section 3.5/4.4) -- message
## + two labeled buttons + a choice_made(accepted) signal. Cameron
## builds the .tscn; this script only needs its root type and setup()
## contract (see travel_prompt_window.gd).
const TRAVEL_PROMPT_SCENE := preload("res://ui/travel_prompt/travel_prompt_window.tscn")

## A hex has 6 sides, so the farthest two apart (directly opposite) are
## 3 steps around the boundary -- this is what maps to "costs the FULL
## hex crossing time" in _sector_fraction() below. Placeholder/
## approximate, same posture as every other untuned value in this
## project -- not modeling a hex's real geometry, just "closer to the
## entry edge costs less time."
const OPPOSITE_SECTOR_DISTANCE := 3

var _locations: Dictionary = {}  # location_id (String) -> LocationSceneDefinition
var _discovered_location_ids: Array[String] = []

## Path of whatever LocalSceneManager currently has loaded (ambient or
## bespoke) -- LocalSceneManager itself exposes no getter for this, so
## it's tracked here for save purposes (get_current_scene_path()).
var _current_scene_path: String = ""

## Set whenever _load_scene() fails because Expedition Hub's content
## viewport doesn't exist yet -- boot_new_expedition() and
## restore_from_save() can both run before any scene transition into
## Expedition Hub has happened (from Party Creator's "Begin Expedition"
## button, or a Main Menu "Continue"). Retried once
## LocalSceneManager.content_viewport_ready fires. Cleared on any
## successful load.
var _pending_scene_path: String = ""

## Non-empty exactly while a real hex-arrival prompt sequence (Section
## 3.4) is in progress. Distinguishes "leaving a bespoke scene should
## continue the SAME pending sequence, or resume Travel once it's
## empty" (leave_current_location()) from "leaving a scene the debug
## tab jumped to directly, where Travel's state was never touched and
## shouldn't be resumed."
var _pending_prompt_queue: Array[LocationSceneDefinition] = []
var _pending_prompt_coord: String = ""
var _pending_entry_edge: int = -1

## In-hex sector detour (Cameron's confirmed model: "Approach" walks
## the party toward the location's actual sector, visually and over
## real time, rather than an instant teleport). Owned here, not on
## TravelState -- TravelSystem's own state stays PAUSED_BY_EVENT,
## untouched, for the whole detour; current_hex_progress/
## last_known_exit_hex keep meaning exactly what they already mean
## (progress toward a NEIGHBORING hex), which this deliberately does
## not repurpose. Committed once started, per Cameron -- no cancel path
## exists. NOT saved -- see visit_location()'s neighboring comment for
## why that's an accepted gap, not an oversight.
var _detour_active: bool = false
var _detour_def: LocationSceneDefinition = null
var _detour_coord: String = ""
var _detour_progress: float = 0.0
var _detour_total_minutes: float = 0.0
var _detour_pending_minutes: float = 0.0


func _ready() -> void:
	_load_locations()
	TravelSystem.state_changed.connect(_on_travel_state_changed)
	TravelSystem.hex_entered.connect(_on_hex_entered)
	LocalSceneManager.content_viewport_ready.connect(_on_content_viewport_ready)


## Only does real work while a detour (see _detour_active's own
## comment) is in progress -- same "only active during the relevant
## state" posture as TravelSystem._process()'s own guard.
func _process(delta: float) -> void:
	if _detour_active:
		_advance_detour(delta)


# ---------------------------------------------------------------------------
# Catalog discovery
# ---------------------------------------------------------------------------

func _load_locations() -> void:
	_locations.clear()
	var dir := DirAccess.open(LOCATIONS_DIR)
	if dir == null:
		push_warning("ExpeditionSceneRouter: could not open %s" % LOCATIONS_DIR)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var res: Resource = load(LOCATIONS_DIR + file_name)
			if res is LocationSceneDefinition:
				if _locations.has(res.location_id):
					push_warning("ExpeditionSceneRouter: duplicate location_id '%s', overwriting" % res.location_id)
				_locations[res.location_id] = res
			else:
				push_warning("ExpeditionSceneRouter: '%s' is not a LocationSceneDefinition, skipping" % file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	print("ExpeditionSceneRouter: loaded %d location definitions" % _locations.size())


## Every catalog entry belonging to `coord` -- both its settlement_id
## (if any) and every entry in its special_event_ids (design doc
## Section 3.4 step 1-2). Unresolved catalog ids are silently skipped
## with a warning. Used by both the real arrival flow and the debug
## tab's "locations in this hex" list.
func get_locations_in_hex(coord: String) -> Array[LocationSceneDefinition]:
	var hex := WorldRegistry.get_hex(coord)
	if hex == null:
		return []

	var candidate_ids: Array[String] = []
	if hex.settlement_id != "":
		candidate_ids.append(hex.settlement_id)
	candidate_ids.append_array(hex.special_event_ids)

	var resolved: Array[LocationSceneDefinition] = []
	for id in candidate_ids:
		var def: LocationSceneDefinition = _locations.get(id)
		if def != null:
			resolved.append(def)
		else:
			push_warning("ExpeditionSceneRouter: hex '%s' references unknown location_id '%s'" % [coord, id])
	return resolved


# ---------------------------------------------------------------------------
# Discovery tracking
# ---------------------------------------------------------------------------

## "Discovered" means the player has been shown this location's arrival
## prompt at least once -- not that they chose to visit it (spotting it
## is what makes it known, per "You see X up ahead"). Cameron's eventual
## trinary discovery model (unknown / known-by-name / physically
## visited) is a deliberate future refinement, not built here -- this
## flat list reads correctly as "fully discovered" under that later
## model with no save-migration needed, since that's genuinely what a
## flat membership check already means today.
func is_discovered(location_id: String) -> bool:
	return location_id in _discovered_location_ids


func get_discovered_location_ids() -> Array[String]:
	return _discovered_location_ids.duplicate()


func _mark_discovered(location_id: String) -> void:
	if location_id not in _discovered_location_ids:
		_discovered_location_ids.append(location_id)


# ---------------------------------------------------------------------------
# Ambient scene swapping (design doc Section 3.2, 5.4)
# ---------------------------------------------------------------------------

func _on_travel_state_changed(new_state: TravelState.State, _old_state: TravelState.State) -> void:
	# Already handled by whatever caused it -- either the real arrival
	# sequence below (which shows a prompt, not an ambient scene change),
	# or the river-crossing stub, which needs no scene reaction from
	# this router at all.
	if new_state == TravelState.State.PAUSED_BY_EVENT:
		return
	# Per Cameron: no scene change on ROUTE_COMPLETE -- the Travel scene
	# stays showing and is responsible for pausing its own
	# animation/behavior on this state itself.
	if new_state == TravelState.State.ROUTE_COMPLETE:
		return

	_load_scene(CAMP_SCENE_PATH if new_state == TravelState.State.AT_CAMP else TRAVEL_SCENE_PATH)


func _load_scene(path: String) -> void:
	if LocalSceneManager.load_local_scene(path):
		_current_scene_path = path
		_pending_scene_path = ""
	else:
		push_warning("ExpeditionSceneRouter: failed to load '%s'" % path)
		# Most likely cause: Expedition Hub's content viewport doesn't
		# exist yet (see _pending_scene_path's own comment) -- remember
		# this and retry once it announces readiness, rather than the
		# request just being lost. A failure for some OTHER reason (a
		# genuinely bad path) will retry harmlessly too and fail again
		# with the same warning -- this project's permissive-by-default
		# posture toward missing/bad data elsewhere, not a special case.
		_pending_scene_path = path


func _on_content_viewport_ready() -> void:
	if _pending_scene_path != "":
		var path := _pending_scene_path
		_pending_scene_path = ""
		_load_scene(path)


# ---------------------------------------------------------------------------
# Bespoke arrival flow (design doc Section 3.4)
# ---------------------------------------------------------------------------

func _on_hex_entered(coord: String) -> void:
	var candidates := get_locations_in_hex(coord)
	if candidates.is_empty():
		return

	var visited := TravelSystem.get_visited_hex_path()
	if visited.size() < 2:
		# No real entry edge to derive -- same "first hex has no real
		# entry" case World Generation's own design doc names (Section
		# 5.3). This is the expedition's starting hex, already handled
		# directly by boot_new_expedition() below, not a fresh arrival
		# to prompt for.
		return

	var entry_edge := WorldRegistry.get_direction_index(coord, visited[-2])

	# Nearest-first (Cameron's confirmed ordering) -- ascending cyclic
	# distance from the edge the party actually walked in through.
	candidates.sort_custom(
		func(a: LocationSceneDefinition, b: LocationSceneDefinition) -> bool:
			return _sector_distance(entry_edge, a.hex_sector) < _sector_distance(entry_edge, b.hex_sector)
	)

	_pending_prompt_coord = coord
	_pending_entry_edge = entry_edge
	_pending_prompt_queue = candidates
	TravelSystem.pause_for_event()
	_show_next_prompt()


func _show_next_prompt() -> void:
	if _pending_prompt_queue.is_empty():
		_pending_prompt_coord = ""
		_pending_entry_edge = -1
		TravelSystem.resume_travel()  # fires state_changed -> ambient scene swap handles itself above
		return

	var def: LocationSceneDefinition = _pending_prompt_queue.pop_front()
	_mark_discovered(def.location_id)

	# add_child() MUST happen before setup() -- @onready vars (including
	# %MessageLabel etc.) are only resolved once a node actually enters
	# the tree, which instantiate() alone does not do. Calling setup()
	# first hits them while they're still null.
	var prompt: TravelPromptWindow = TRAVEL_PROMPT_SCENE.instantiate()
	get_tree().root.add_child(prompt)
	prompt.choice_made.connect(_on_prompt_choice.bind(def), CONNECT_ONE_SHOT)
	prompt.setup("You see %s up ahead. Approach or keep moving?" % def.display_name, "Approach", "Keep Moving")


func _on_prompt_choice(accepted: bool, def: LocationSceneDefinition) -> void:
	if accepted:
		_begin_detour(def)
	else:
		_show_next_prompt()


# ---------------------------------------------------------------------------
# In-hex sector detour (Cameron's confirmed "Approach" model)
# ---------------------------------------------------------------------------

## Deliberately does NOT clear _pending_prompt_coord/_pending_entry_edge --
## those stay set for the whole detour (and the bespoke scene visit that
## follows it), so leave_current_location() still correctly resumes the
## SAME pending prompt sequence afterward (further locations at this
## hex, or resuming Travel once none remain), exactly as it already does
## for a plain (non-detour) visit.
func _begin_detour(def: LocationSceneDefinition) -> void:
	_detour_active = true
	_detour_def = def
	_detour_coord = _pending_prompt_coord
	_detour_progress = 0.0
	_detour_pending_minutes = 0.0
	_detour_total_minutes = _sector_fraction(_pending_entry_edge, def.hex_sector) * TravelSystem.get_hex_travel_minutes(_detour_coord)


## Mirrors TravelSystem._advance_travel()'s single-step timing math --
## same BASE_MINUTES_PER_REAL_SECOND/playback_speed conversion -- but
## deliberately simpler: a detour is always one short, uninterruptible
## leg (no reversal, no multi-hex while-loop, no river-crossing check),
## so a single capped step per frame is all this needs.
func _advance_detour(delta: float) -> void:
	if _detour_total_minutes <= 0.0:
		_finish_detour()
		return

	var remaining_minutes := delta * TravelSystem.BASE_MINUTES_PER_REAL_SECOND * TravelSystem.get_playback_speed()
	var minutes_to_target := (1.0 - _detour_progress) * _detour_total_minutes
	var minutes_to_apply: float = minf(remaining_minutes, minutes_to_target)

	_detour_progress += minutes_to_apply / _detour_total_minutes
	_spend_detour_minutes(minutes_to_apply)

	if _detour_progress >= 1.0:
		_detour_progress = 1.0
		_finish_detour()


## Same fractional-minute accumulation pattern as
## TravelSystem._spend_game_minutes() -- TimeSystem only accepts whole
## minutes, so a short detour's sub-minute-per-frame contributions
## still all land correctly rather than being silently lost to
## rounding. Feeding TimeSystem progressively (not one lump sum at the
## end) is what makes VitalsSystem's hunger/fatigue drain track the
## walk in real time, same as ordinary hex travel already does.
func _spend_detour_minutes(minutes: float) -> void:
	_detour_pending_minutes += minutes
	var whole_minutes := floori(_detour_pending_minutes)
	if whole_minutes > 0:
		_detour_pending_minutes -= whole_minutes
		TimeSystem.pass_minutes(whole_minutes)


func _finish_detour() -> void:
	_detour_active = false
	var def := _detour_def
	_detour_def = null
	_load_scene(def.scene_path)


## Whether a sector detour is currently in progress -- travel_map_overlay.gd
## uses this to render the party marker walking toward the location's
## sector instead of the normal hex-crossing target.
func is_detouring() -> bool:
	return _detour_active


func get_detour_coord() -> String:
	return _detour_coord


## CENTER_SECTOR or 0-5 -- see LocationSceneDefinition.hex_sector's own
## comment for what these mean and how they map onto
## WorldRegistry.AXIAL_DIRECTIONS.
func get_detour_sector() -> int:
	return _detour_def.hex_sector if _detour_def != null else LocationSceneDefinition.CENTER_SECTOR


func get_detour_progress() -> float:
	return _detour_progress


## Cyclic distance between two of a hex's six sides (0-5), the shorter
## way around -- e.g. sides 0 and 5 are 1 apart, not 5. Uses absi()
## rather than the generic abs() specifically -- abs() is overloaded
## across int/float, and GDScript's static analyzer can't resolve which
## one applies from `a - b` alone, so `var raw :=` was inferring as
## Variant instead of int. absi() is the unambiguous integer-only
## overload, so raw (and therefore this function's own return type)
## stays a real int throughout.
func _sector_distance(a: int, b: int) -> int:
	var raw: int = absi(a - b)
	return mini(raw, 6 - raw)


## Fraction of a hex's full crossing time this sector should cost to
## reach from `entry_edge` -- 0.0 at the entry edge itself, 1.0 at the
## directly-opposite side (a full crossing), CENTER_SECTOR fixed at 0.5
## (matching the existing hex-crossing model's own assumption that a
## hex's center sits at exactly the halfway point regardless of which
## edge you're measuring from -- see travel_system.gd's own comments on
## a hexagon's apothem being identical for every edge). Placeholder/
## approximate, same posture as every other untuned formula in this
## project.
func _sector_fraction(entry_edge: int, sector: int) -> float:
	if sector == LocationSceneDefinition.CENTER_SECTOR:
		return 0.5
	if entry_edge < 0:
		return 0.5  # shouldn't normally happen -- see get_travel_minutes_to()'s own fallback below
	return float(_sector_distance(entry_edge, sector)) / float(OPPOSITE_SECTOR_DISTANCE)


## In-game minutes to reach `location_id` from wherever the party
## actually entered its hex. Falls back to TravelSystem's CURRENT hex
## and a freshly-derived entry edge when called outside a live arrival
## sequence (e.g. the debug tab's "Travel To", which has no
## _pending_prompt_coord of its own) -- and to CENTER_SECTOR's neutral
## 0.5 fraction if even that can't be derived (no visited-hex history
## yet, per _sector_fraction()'s own comment).
func get_travel_minutes_to(location_id: String) -> int:
	var def: LocationSceneDefinition = _locations.get(location_id)
	if def == null:
		return 0

	var coord := _pending_prompt_coord if _pending_prompt_coord != "" else TravelSystem.get_current_hex()
	var entry_edge := _pending_entry_edge
	if _pending_prompt_coord == "":
		var visited := TravelSystem.get_visited_hex_path()
		entry_edge = WorldRegistry.get_direction_index(coord, visited[-2]) if visited.size() >= 2 else -1

	var fraction := _sector_fraction(entry_edge, def.hex_sector)
	return int(round(fraction * TravelSystem.get_hex_travel_minutes(coord)))


## The debug tab's "Travel To" instant-jump path (Cameron: keep this
## one instant for testing convenience, unlike the real "Approach"
## choice, which now walks an animated detour instead -- see
## _begin_detour() below). Spends the real in-game time cost in one
## lump sum (which, via VitalsSystem already ticking hunger/fatigue
## purely off TimeSystem's own minute-advancement, applies real vitals
## drain too with no separate formula needed), marks `location_id`
## discovered, and loads its scene directly. Deliberately does NOT
## touch TravelSystem's state machine -- Travel's state is left exactly
## as it was, same as any other debug shortcut in this project.
func visit_location(location_id: String) -> bool:
	var def: LocationSceneDefinition = _locations.get(location_id)
	if def == null:
		push_warning("ExpeditionSceneRouter: visit_location() -- unknown location_id '%s'" % location_id)
		return false

	_mark_discovered(location_id)

	var minutes := get_travel_minutes_to(location_id)
	if minutes > 0:
		TimeSystem.pass_minutes(minutes)

	_load_scene(def.scene_path)
	return true


## Called by a bespoke scene's "Leave" interactable (hand-authored,
## Cameron's own convention -- same shape as WorldInteractable's
## existing behaviors). Continues whatever arrival-prompt sequence is
## still pending for this hex (further locations, or resuming Travel
## once none remain) -- or, if this visit came from the debug tab
## instead (no pending sequence, Travel's state never touched), just
## reloads whichever ambient scene matches Travel's CURRENT (unchanged)
## state directly, since nothing will fire state_changed to do that for
## us in that case.
func leave_current_location() -> void:
	LocalSceneManager.unload_current_scene()
	_current_scene_path = ""

	if not _pending_prompt_queue.is_empty() or _pending_prompt_coord != "":
		_show_next_prompt()
	else:
		_load_scene(CAMP_SCENE_PATH if TravelSystem.get_current_state() == TravelState.State.AT_CAMP else TRAVEL_SCENE_PATH)


# ---------------------------------------------------------------------------
# Boot / New Game (design doc Section 3.8)
# ---------------------------------------------------------------------------

## Call this once, from wherever "Begin Expedition" currently calls
## TravelSystem.reset_to_fresh_expedition() -- I don't have that call
## site in front of me (likely PartyManager.begin_expedition()), so
## this needs to be wired in by hand rather than guessed at here. Loads
## the starting settlement's bespoke scene directly -- bypasses the
## arrival-prompt flow entirely, since there's nothing to "discover,"
## the player simply starts there.
func boot_new_expedition() -> void:
	var coord := TravelSystem.STARTING_HEX_COORD
	var candidates := get_locations_in_hex(coord)
	if candidates.is_empty():
		push_warning("ExpeditionSceneRouter: boot_new_expedition() -- no bespoke location catalogued at starting hex '%s'" % coord)
		_load_scene(TRAVEL_SCENE_PATH)
		return

	var def := candidates[0]
	_mark_discovered(def.location_id)
	_load_scene(def.scene_path)


# ---------------------------------------------------------------------------
# Save / Load
# ---------------------------------------------------------------------------

## Called directly by SaveManager._write_save() -- matches how every
## other system's save data is pulled (direct getter calls), not a
## signal.
func get_current_scene_path() -> String:
	return _current_scene_path


## Called directly by SaveManager.load_game(), same direct-call
## convention as TravelSystem.load_travel_state() etc. AFTER
## TravelSystem has already restored its own state -- an empty
## `scene_path` falls back to whichever ambient scene matches the
## just-restored TravelState.state.
func restore_from_save(scene_path: String, discovered_ids: Array[String]) -> void:
	_discovered_location_ids = discovered_ids.duplicate()

	if scene_path != "":
		_load_scene(scene_path)
	else:
		_load_scene(CAMP_SCENE_PATH if TravelSystem.get_current_state() == TravelState.State.AT_CAMP else TRAVEL_SCENE_PATH)
