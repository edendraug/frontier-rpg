extends Node

## Autoload. Owns Pace, the route queue, real-time travel progress,
## and the four-state travel state machine (Design Doc v0.2, Section
## 3.9) -- the party's single "what is Travel doing right now" source
## of truth. Live in-memory state is a TravelState Resource
## (_travel_state below), the same shape GameSaveData.travel_state
## saves/loads -- SaveManager reads/writes it via get_travel_state()/
## load_travel_state() rather than TravelSystem inventing a separate
## save shape of its own.
##
## Register in Project Settings > Autoload LAST, after WorldRegistry --
## _ready() registers with VitalsSystem (must already exist), and a
## future progress tick will read WorldRegistry/PartyManager/TimeSystem,
## all of which need to be initialized first. See Section 5.1.
##
## THIS IS A STAGED BUILD. All 7 phases from the original build plan
## are now in: the state machine (including begin_travel()), Pace
## (Phase 3, with the VitalsSystem fatigue hookup), Pace/Trail's
## speed+hazard modifier contributions (Phase 4, Section 3.2), route
## queueing/pathfinding (Phase 5, Section 3.4-3.5), the real-time
## progress tick + visited-hex logging (Phase 6, Section 3.6/3.8), and
## the river-crossing stub (Phase 7, Section 3.7). What the design doc
## itself defers beyond this file's scope stays deferred here too --
## actual event triggering against computed hazard, the river-crossing
## minigame's real resolution, Assignment System integration, the
## Camp/downtime system, and all final UI/UX (Section 9) are still
## nobody's job but a later, separate design pass.

## Reserved now, consumed starting Phase 4 -- see design doc Section
## 3.2/4.2. Matches ModifierResolver's own doc-comment example for the
## system: namespace tier, so this completes an already-anticipated
## seam rather than inventing a new one.
const TRAVEL_SPEED_TARGET := "system:travel_speed"
const TRAVEL_HAZARD_TARGET := "system:travel_hazard"

## Placeholder/tunable, same treatment as every other placeholder table
## in this project -- untuned, confirmed acceptable pending playtesting
## (design doc Section 3.3). ADDITIVE, not MULTIPLICATIVE, because
## VitalsSystem._resolve_fatigue_accrual() only ever reads
## result.additive_total -- unlike Pace's speed/hazard contributions
## (Phase 4), which DO use MULTIPLICATIVE targets. Two different
## aggregation modes for two different targets; don't conflate them.
const PACE_FATIGUE_DELTA_PER_HOUR := {
	TravelState.Pace.CAREFUL: -0.2,
	TravelState.Pace.NORMAL: 0.0,
	TravelState.Pace.FORCED: 0.5,
}

const PACE_NAMES := {
	TravelState.Pace.CAREFUL: "Careful",
	TravelState.Pace.NORMAL: "Normal",
	TravelState.Pace.FORCED: "Forced",
}

## Pace's contribution to travel SPEED. MULTIPLICATIVE, targeting
## TRAVEL_SPEED_TARGET. Placeholder table, design doc Section 3.2 --
## untuned, same posture as every other placeholder table here.
const PACE_SPEED_MULTIPLIER := {
	TravelState.Pace.CAREFUL: 0.75,
	TravelState.Pace.NORMAL: 1.0,
	TravelState.Pace.FORCED: 1.5,
}

## Pace's contribution to travel HAZARD. Same MULTIPLICATIVE mechanism
## and MULTIPLICATIVE type as speed, but a genuinely separate
## aggregation against TRAVEL_HAZARD_TARGET -- see
## get_travel_hazard_multiplier() below. Computed, not consumed by
## anything yet (Section 5.4) -- reserved for a future Event/Encounter
## system.
const PACE_HAZARD_MULTIPLIER := {
	TravelState.Pace.CAREFUL: 0.75,
	TravelState.Pace.NORMAL: 1.0,
	TravelState.Pace.FORCED: 1.75,
}

## Trail's contribution to SPEED only. Deliberately no equivalent
## hazard entry -- whether/how Trail affects hazard is explicitly
## undecided (design doc Section 2), left open until a real hazard
## consumer exists to make that call meaningful. Also deliberately a
## SEPARATE number from the 0.3 pathfinding routing-cost weight
## (Phase 5, Section 5.2) -- one is a real gameplay speed effect, the
## other is a router incentive to stay on trail; don't conflate them
## in code even though both describe "trail is good."
const TRAIL_SPEED_MULTIPLIER := 1.2

## Trail's routing-preference weight for the PATHFINDER only --
## deliberately a separate number from TRAIL_SPEED_MULTIPLIER above.
## This is how much cheaper a trail hex looks to the ROUTER (so it
## reliably prefers staying on trail even when a raw-distance shortcut
## through rougher terrain might otherwise look competitive), not the
## real gameplay speed effect of walking it. Confirmed placeholder,
## design doc Section 5.2 -- a trail hex costs ~0.3x its terrain's
## normal routing cost. See _edge_cost() below.
const TRAIL_ROUTING_COST_MULTIPLIER := 0.3

## Placeholder/tunable, matching the design doc's "placeholder fixed
## time cost" framing for pack-up-camp (Section 3.5) -- the real Camp
## system, not yet designed, may replace this with something more
## granular later.
const CAMP_PACKUP_MINUTES := 30

## Confirmed by Cameron: the main starting settlement, where the
## journey west begins, is (0,0) -- and this is safe to hardcode
## rather than reserve as a seam, since World Generation's own bake
## step (World Gen doc v0.3, Section 7) already guarantees a hex is
## always painted at axial "0,0" as its fixed anchor point, or the
## bake aborts. The eventual real ~640-700 hex map gets built AROUND
## that anchor, not the other way around -- so (0,0) being the
## starting settlement is a stable assumption, not a placeholder
## guess. See get_current_hex() below.
const STARTING_HEX_COORD := "0,0"

## Confirmed by Cameron: the party stops at a hex's CENTER upon
## reaching the final hex of a queued route, rather than continuing on
## to exit through a far edge the way every other hex in the route
## does -- so the final hex's real travel cost is edge-to-center, not
## edge-to-edge, and should cost less than a fully-crossed hex. Modeled
## as a flat fraction of the hex's normal terrain cost rather than
## charging the destination hex in full. Untuned placeholder -- half
## of a full crossing is a reasonable first geometric guess (a regular
## hexagon's center sits roughly halfway between any two of its
## edges), not a value derived from real hex geometry or the
## chord-crossing math WorldRegistry uses elsewhere. Applied in
## get_eta_minutes() below, and in Phase 6's
## _get_hex_travel_minutes() for the live real-time tick -- both check
## the same condition (is this coord the current queue's actual last
## entry) independently, since get_eta_minutes() takes an arbitrary
## `route` array while _get_hex_travel_minutes() always checks against
## the live queued_route. Deliberately NOT applied inside
## _edge_cost()/_find_path() -- those operate on a generic hex that
## might end up being an intermediate step if more hexes get queued
## afterward, not necessarily the route's actual final destination;
## "final hex" is only a meaningful concept at the whole-route level.
const FINAL_HEX_ARRIVAL_FRACTION := 0.5

## How many in-game minutes one real-world second represents at
## playback_speed = 1.0. Confirmed by Cameron: roughly 15 real seconds
## to cross a 360-in-game-minute Grassland hex at Normal pace, hence
## 360.0 / 15.0 = 24.0. This is the one Phase 6 number with no design
## doc precedent at all -- pure game-feel, untuned, expect to revisit
## once actual playtesting shows travel feeling too fast/slow.
const BASE_MINUTES_PER_REAL_SECOND := 24.0

## Legal transitions per the state-machine diagram in Section 3.9.
## AT_CAMP's only legal exit is to TRAVELING, and only via
## begin_travel() below -- there's no public method that lets a caller
## jump straight to PAUSED_BY_PLAYER/PAUSED_BY_EVENT from AT_CAMP,
## since pausing something that was never moving doesn't mean anything.
const _LEGAL_TRANSITIONS := {
	TravelState.State.AT_CAMP: [TravelState.State.TRAVELING],
	TravelState.State.TRAVELING: [TravelState.State.PAUSED_BY_PLAYER, TravelState.State.PAUSED_BY_EVENT],
	TravelState.State.PAUSED_BY_PLAYER: [TravelState.State.TRAVELING],
	TravelState.State.PAUSED_BY_EVENT: [TravelState.State.TRAVELING],
}

## Fired whenever _set_state() completes a legal transition -- lets a
## future UI show a live state indicator (Section 8) without polling.
signal state_changed(new_state: TravelState.State, old_state: TravelState.State)

## Fired on every set_pace() call, even a no-op re-set to the current
## value -- simplest possible contract for a UI Pace selector to just
## re-render on this signal rather than diffing old/new itself.
signal pace_changed(new_pace: TravelState.Pace)

## Same simplest-possible-contract reasoning as pace_changed above.
signal playback_speed_changed(new_speed: float)

## Fired whenever a hex is newly logged into visited_hex_path (Section
## 3.8) -- lets a future UI react to physically arriving somewhere
## (SFX, extending the drawn path trail) without polling
## current_hex_progress every frame the way continuous progress itself
## is meant to be read.
signal hex_entered(coord: String)

## Fired specifically when queued_route empties and travel pauses as a
## direct result (Section 3.5's future "journey finished, set up camp?"
## prompt) -- distinct from state_changed, which also fires for an
## ordinary player-initiated pause_travel() mid-route. A future UI can
## listen for this alone instead of reconstructing "was this pause
## caused by running out of queue" from state_changed's arguments.
signal journey_completed

## Live, in-memory travel state. Defaults to a fresh TravelState
## (AT_CAMP / Normal / empty route) -- SaveManager overwrites this via
## load_travel_state() on an actual load; a brand-new expedition just
## keeps this default untouched.
var _travel_state: TravelState = TravelState.new()

## TimeSystem.pass_minutes() only accepts whole minutes, but each
## frame's real contribution is a fraction of a minute at any
## reasonable frame rate. Accumulated here across frames so no time is
## silently lost/gained to rounding -- only the whole-minute part ever
## gets flushed to TimeSystem, the remainder carries forward. See
## _spend_game_minutes() below. Deliberately NOT part of TravelState --
## this is pure real-time frame-timing bookkeeping, not meaningful save
## data.
var _pending_game_minutes: float = 0.0


func _ready() -> void:
	VitalsSystem.register_environmental_source(_get_pace_fatigue_entries)


## Only does real work while state == TRAVELING -- see _advance_travel()
## below for everything this actually drives.
func _process(delta: float) -> void:
	if _travel_state.state != TravelState.State.TRAVELING:
		return
	_advance_travel(delta)


# ---------------------------------------------------------------------------
# Pace
# ---------------------------------------------------------------------------

func get_pace() -> TravelState.Pace:
	return _travel_state.pace


func set_pace(pace: TravelState.Pace) -> void:
	_travel_state.pace = pace
	pace_changed.emit(pace)


## Registered with VitalsSystem in _ready() above. Ignores `_sheet` --
## Pace is party-wide (Section 3.1), so every character gets the same
## entry regardless of who's currently being ticked. Always returns an
## entry, even Normal pace's 0.0 delta, rather than special-casing the
## no-op case away -- a debug tool inspecting a character's modifier
## entries can then always see "Pace: Normal (+0.0)" instead of Pace
## silently vanishing from the list at the one tier that happens to be
## neutral.
func _get_pace_fatigue_entries(_sheet: CharacterSheet) -> Array[ModifierEntry]:
	var entry := ModifierEntry.new()
	entry.targets = [VitalsSystem.FATIGUE_ACCRUAL_TARGET]
	entry.value = PACE_FATIGUE_DELTA_PER_HOUR[_travel_state.pace]
	entry.type = ModifierEntry.Type.ADDITIVE
	entry.source_label = "Pace: %s" % PACE_NAMES[_travel_state.pace]
	return [entry]


# ---------------------------------------------------------------------------
# Speed & Hazard (Section 3.2)
# ---------------------------------------------------------------------------
# ASSUMPTION, flagging rather than guessing silently: ModifierResult
# (not seen directly -- inferred from ModifierResolver.aggregate()'s
# `result.multiplicative_total *= entry.value` line) is assumed to
# default multiplicative_total to 1.0, the only value that makes
# repeated *= composition or a zero-entries query behave sanely.
# Confirm against the real ModifierResult file if this ever produces
# an unexpected 0.0 or otherwise wrong multiplier.

func _get_pace_speed_entry() -> ModifierEntry:
	var entry := ModifierEntry.new()
	entry.targets = [TRAVEL_SPEED_TARGET]
	entry.value = PACE_SPEED_MULTIPLIER[_travel_state.pace]
	entry.type = ModifierEntry.Type.MULTIPLICATIVE
	entry.source_label = "Pace: %s" % PACE_NAMES[_travel_state.pace]
	return entry


func _get_pace_hazard_entry() -> ModifierEntry:
	var entry := ModifierEntry.new()
	entry.targets = [TRAVEL_HAZARD_TARGET]
	entry.value = PACE_HAZARD_MULTIPLIER[_travel_state.pace]
	entry.type = ModifierEntry.Type.MULTIPLICATIVE
	entry.source_label = "Pace: %s" % PACE_NAMES[_travel_state.pace]
	return entry


func _get_trail_speed_entry() -> ModifierEntry:
	var entry := ModifierEntry.new()
	entry.targets = [TRAVEL_SPEED_TARGET]
	entry.value = TRAIL_SPEED_MULTIPLIER
	entry.type = ModifierEntry.Type.MULTIPLICATIVE
	entry.source_label = "Trail"
	return entry


## Effective speed multiplier for traveling THIS hex right now, under
## current Pace. Pace always contributes; Trail contributes only if
## WorldRegistry says this hex has one. A coord WorldRegistry doesn't
## recognize (get_hex() returns null -- inferred from how
## WorldRegistry.is_passable() is documented to treat an unknown coord,
## Section 5.4) is treated as Pace-only, no Trail bonus, rather than
## assuming a trail presence that can't actually be verified. This
## returns a raw multiplier only -- combining it with
## TerrainTypeDefinition.base_travel_minutes into an actual elapsed-
## time number is Phase 5/6's job (get_eta_minutes() and the real-time
## tick), not this method's.
func get_travel_speed_multiplier(coord: String) -> float:
	var entries: Array[ModifierEntry] = [_get_pace_speed_entry()]
	var hex := WorldRegistry.get_hex(coord)
	if hex != null and hex.has_trail:
		entries.append(_get_trail_speed_entry())
	var result := ModifierResolver.aggregate(entries, [TRAVEL_SPEED_TARGET])
	return result.multiplicative_total


## Effective hazard multiplier for THIS hex under current Pace.
## `_coord` is currently unused -- Trail deliberately contributes
## nothing to hazard yet (see TRAIL_SPEED_MULTIPLIER's comment above)
## and Pace is the only real input right now -- but the parameter
## stays in the signature so a future caller iterating per-hex doesn't
## need to change once Trail's hazard contribution (or terrain's own
## hazard_level) actually gets folded in here. Exposed, not consumed
## (Section 5.4) -- nothing rolls against this yet.
func get_travel_hazard_multiplier(_coord: String) -> float:
	var entries: Array[ModifierEntry] = [_get_pace_hazard_entry()]
	var result := ModifierResolver.aggregate(entries, [TRAVEL_HAZARD_TARGET])
	return result.multiplicative_total


# ---------------------------------------------------------------------------
# Route (Section 3.4)
# ---------------------------------------------------------------------------
# RESOLVED (previously an open gap): Cameron confirmed the starting
# hex is STARTING_HEX_COORD ("0,0"), hardcoded above. This means
# get_current_hex() below always resolves to a real coord -- never "".
# queue_hex()/queue_autopath_to() no longer need an empty-starting-
# point carve-out; adjacency validation now always runs.

## The party's current physical location (Section 3.8) -- the last
## entry in visited_hex_path once Phase 6's tick starts logging real
## entries, or STARTING_HEX_COORD for a brand-new expedition that
## hasn't moved yet. The starting settlement itself is never logged as
## a "visited" entry (Section 3.8 only logs a hex the instant the
## party ENTERS it via travel, and the party didn't travel to reach
## their own starting settlement) -- this getter's fallback covers
## that gap without needing a fake log entry.
func get_current_hex() -> String:
	var path := _travel_state.visited_hex_path
	return path.back() if not path.is_empty() else STARTING_HEX_COORD


func get_queued_route() -> Array[String]:
	return _travel_state.queued_route.duplicate()


## Not explicitly named in the design doc, but a trivial and obviously
## useful pairing with queue_hex()/unqueue_from() below -- flagging the
## small scope addition rather than sneaking it in unremarked.
func clear_queue() -> void:
	_travel_state.queued_route.clear()


## Left-click add (Section 3.4). Refuses (returns false, no mutation)
## if `coord` isn't actually adjacent to wherever the queue currently
## ends -- or, if the queue is empty, to the party's real current hex
## -- since accepting a non-adjacent hex would leave the queue
## representing more than one disconnected path. get_current_hex()
## always resolves to a real coord now (see RESOLVED note above), so
## this validates unconditionally -- there's no longer a legitimate
## case where there's nothing to check adjacency against.
func queue_hex(coord: String) -> bool:
	var tail: String = _travel_state.queued_route.back() if not _travel_state.queued_route.is_empty() else get_current_hex()
	if WorldRegistry.get_direction_index(tail, coord) == -1:
		push_warning("TravelSystem: queue_hex('%s') is not adjacent to queue tail '%s'" % [coord, tail])
		return false
	if not WorldRegistry.is_passable(coord):
		push_warning("TravelSystem: queue_hex('%s') refused -- hex is not passable" % coord)
		return false

	# If the queue was empty, `coord` is about to become the NEW front
	# hex -- reset progress rather than risk carrying over stale
	# progress from whatever hex previously occupied the front (e.g.
	# unqueue_from() having removed the in-progress hex out from under
	# an active crossing).
	if _travel_state.queued_route.is_empty():
		_travel_state.current_hex_progress = 0.0
	_travel_state.queued_route.append(coord)
	return true


## Right-click a queued hex (Section 3.4) -- removes it AND everything
## queued after it, so the queue always stays one continuous path with
## no orphaned branch. No-op (returns false) if `coord` isn't actually
## in the queue.
func unqueue_from(coord: String) -> bool:
	var index := _travel_state.queued_route.find(coord)
	if index == -1:
		return false
	_travel_state.queued_route.resize(index)
	return true


## Click-to-autopath (Section 3.4) -- computes the shortest path from
## the queue's current tail (or the party's real current hex, if the
## queue is empty) to `coord`, preferring trail per
## TRAIL_ROUTING_COST_MULTIPLIER, and appends the result. Refuses
## (returns false, no mutation) only if no path exists -- there's
## always a real starting coord now (see RESOLVED note above).
func queue_autopath_to(coord: String) -> bool:
	var start: String = _travel_state.queued_route.back() if not _travel_state.queued_route.is_empty() else get_current_hex()
	var path := _find_path(start, coord)
	if path.is_empty() and start != coord:
		push_warning("TravelSystem: queue_autopath_to('%s') found no path from '%s'" % [coord, start])
		return false

	# Same reasoning as queue_hex() above -- an empty queue means
	# `path`'s first entry is about to become the new front hex.
	if _travel_state.queued_route.is_empty():
		_travel_state.current_hex_progress = 0.0
	_travel_state.queued_route.append_array(path)
	return true


## Estimated total travel time for `route`, in minutes -- Section 3.5's
## pre-travel confirmation ETA. Sums each hex's terrain
## base_travel_minutes divided by that hex's own speed multiplier
## (Phase 4's get_travel_speed_multiplier() -- higher multiplier means
## faster, hence division, not multiplication). The LAST hex in
## `route` is charged only FINAL_HEX_ARRIVAL_FRACTION of its normal
## cost -- the party stops at its center rather than exiting through a
## far edge like every other hex (see that constant's comment above).
## Silently skips any coord WorldRegistry doesn't recognize rather
## than aborting the whole estimate -- consistent with this project's
## permissive-by-default handling of missing/unauthored data elsewhere.
func get_eta_minutes(route: Array) -> int:
	var total_minutes := 0.0
	var last_index := route.size() - 1
	for i in route.size():
		var coord: String = route[i]
		var hex := WorldRegistry.get_hex(coord)
		if hex == null:
			continue
		var terrain := WorldRegistry.get_terrain(hex.terrain_type_id)
		if terrain == null:
			continue
		var hex_minutes: float = terrain.base_travel_minutes / get_travel_speed_multiplier(coord)
		if i == last_index:
			hex_minutes *= FINAL_HEX_ARRIVAL_FRACTION
		total_minutes += hex_minutes
	return int(round(total_minutes))


## Routing cost of ENTERING `coord`, per the Section 5.2 formula --
## INF for an unrecognized coord or one referencing an unknown terrain
## type, which _find_path() below treats as impassable-for-routing-
## purposes without needing a separate check.
func _edge_cost(coord: String) -> float:
	var hex := WorldRegistry.get_hex(coord)
	if hex == null:
		return INF
	var terrain := WorldRegistry.get_terrain(hex.terrain_type_id)
	if terrain == null:
		return INF
	return terrain.base_travel_minutes * (TRAIL_ROUTING_COST_MULTIPLIER if hex.has_trail else 1.0)


## Weighted shortest path from `from` to `to` (both coord strings),
## preferring trail per _edge_cost() above. Returns the path
## from-EXCLUSIVE, to-INCLUSIVE -- the caller already has `from` as
## their queue's current tail, so it shouldn't be duplicated into the
## result. Empty array means "no path exists" (unreachable, `to` is
## impassable/unrecognized) OR "from == to" (nothing to add).
##
## Plain O(V^2) Dijkstra, no priority queue -- straightforward and fast
## enough at both the current ~60-hex test-patch scale and the
## eventual ~640-700-hex full map (V^2 tops out well under a million
## operations either way). Revisit only if profiling ever actually
## shows this as a real bottleneck -- not a concern worth solving
## preemptively.
func _find_path(from: String, to: String) -> Array[String]:
	if from == to:
		return []
	if not WorldRegistry.is_passable(to):
		return []

	var dist := {from: 0.0}
	var prev := {}
	var unvisited := {from: true}

	while not unvisited.is_empty():
		var current := ""
		var current_dist := INF
		for coord in unvisited:
			if dist.get(coord, INF) < current_dist:
				current = coord
				current_dist = dist[coord]

		if current == "" or current_dist == INF:
			break  # Every remaining unvisited coord is unreachable.

		unvisited.erase(current)
		if current == to:
			break

		for neighbor in WorldRegistry.get_neighbors(current):
			if dist.has(neighbor) and not unvisited.has(neighbor):
				continue  # Already finalized.
			if not WorldRegistry.is_passable(neighbor):
				continue
			var candidate_dist: float = current_dist + _edge_cost(neighbor)
			if candidate_dist < dist.get(neighbor, INF):
				dist[neighbor] = candidate_dist
				prev[neighbor] = current
				unvisited[neighbor] = true

	if not prev.has(to):
		return []  # Unreachable.

	var path: Array[String] = []
	var step := to
	while step != from:
		path.append(step)
		step = prev[step]
	path.reverse()
	return path


# ---------------------------------------------------------------------------
# State machine (Section 3.9)
# ---------------------------------------------------------------------------

func get_current_state() -> TravelState.State:
	return _travel_state.state


## "Begin Travel" (Section 3.5) -- the one way out of AT_CAMP, per the
## _LEGAL_TRANSITIONS entry added specifically for this method. Refuses
## (returns false, no state change, no time cost) if the queue is
## empty -- there's nowhere to begin traveling TO -- or if not
## currently AT_CAMP. Unconditionally charges CAMP_PACKUP_MINUTES via
## TimeSystem when it succeeds, since AT_CAMP always means "currently
## camped" (Section 3.9) -- there's no path through this method that
## skips the pack-up cost.
func begin_travel() -> bool:
	if _travel_state.queued_route.is_empty():
		push_warning("TravelSystem: begin_travel() refused -- queue is empty")
		return false
	if _travel_state.state != TravelState.State.AT_CAMP:
		push_warning("TravelSystem: begin_travel() refused -- not currently AT_CAMP")
		return false

	TimeSystem.pass_minutes(CAMP_PACKUP_MINUTES)
	_set_state(TravelState.State.TRAVELING)
	# Logged synchronously here, not left to _advance_travel()'s own
	# _ensure_hex_logged() call -- otherwise get_current_hex() would
	# read stale for however long until this frame's _process() runs.
	_ensure_hex_logged(_travel_state.queued_route[0])
	return true


## Player-initiated pause. Only legal from TRAVELING -- see
## _LEGAL_TRANSITIONS. Mid-hex progress itself is untouched here;
## Phase 6's real-time tick is what actually stops advancing once
## state is no longer TRAVELING, not this method.
func pause_travel() -> void:
	_set_state(TravelState.State.PAUSED_BY_PLAYER)


## Resumes from either paused state back to TRAVELING. Doesn't
## distinguish which paused state it's resuming FROM -- both are
## equally resumable by player action once whatever caused
## PAUSED_BY_EVENT (Phase 7) has been dealt with.
func resume_travel() -> void:
	_set_state(TravelState.State.TRAVELING)


## Called internally by _advance_travel() now (Phase 7's
## river-crossing stub, via requires_river_crossing_now()). Still not
## exposed publicly -- nothing outside this file decides when to pause
## for an event yet. A real future Event/Encounter system may need its
## own public trigger eventually; not designed here.
func _pause_for_event() -> void:
	_set_state(TravelState.State.PAUSED_BY_EVENT)


## Single choke point for every state change -- validates against
## _LEGAL_TRANSITIONS rather than trusting callers, and is the only
## place state_changed fires from. An illegal transition (e.g. pausing
## from AT_CAMP) is a bug in the calling code, not a normal runtime
## condition -- warn, don't silently no-op or crash, same posture
## TimeSystem.pass_minutes() takes toward bad input.
func _set_state(new_state: TravelState.State) -> void:
	var old_state := _travel_state.state
	var allowed: Array = _LEGAL_TRANSITIONS.get(old_state, [])
	if new_state not in allowed:
		push_warning(
			"TravelSystem: illegal state transition %s -> %s" % [
				TravelState.State.keys()[old_state], TravelState.State.keys()[new_state]
			]
		)
		return
	_travel_state.state = new_state
	state_changed.emit(new_state, old_state)


# ---------------------------------------------------------------------------
# Real-time progress (Section 3.6, 3.8)
# ---------------------------------------------------------------------------

func get_playback_speed() -> float:
	return _travel_state.playback_speed


func set_playback_speed(speed: float) -> void:
	_travel_state.playback_speed = speed
	playback_speed_changed.emit(speed)


func get_current_hex_progress() -> float:
	return _travel_state.current_hex_progress


func get_visited_hex_path() -> Array[String]:
	return _travel_state.visited_hex_path.duplicate()


## Drives real-time progress through queued_route's front entry.
## queued_route[0] IS the hex currently being crossed -- confirmed
## reading of TravelState's data shape; there's no separate "current
## hex" field. Runs as a while-loop rather than a single step so a
## large delta (a lag spike, or a high playback_speed) can correctly
## finish crossing MULTIPLE hexes in one call without losing or
## double-spending any of this frame's time.
func _advance_travel(delta: float) -> void:
	if _travel_state.queued_route.is_empty():
		# Shouldn't happen -- begin_travel() refuses an empty queue,
		# and _complete_current_hex() below pauses the instant the
		# queue empties -- but stay defensive rather than crash on the
		# queued_route[0] access below if some other path ever leaves
		# state == TRAVELING with nothing queued.
		push_warning("TravelSystem: _advance_travel() called while TRAVELING with an empty queue")
		pause_travel()
		return

	var remaining_minutes := delta * BASE_MINUTES_PER_REAL_SECOND * _travel_state.playback_speed

	while remaining_minutes > 0.0 and _travel_state.state == TravelState.State.TRAVELING and not _travel_state.queued_route.is_empty():
		var current_coord: String = _travel_state.queued_route[0]
		if _ensure_hex_logged(current_coord) and requires_river_crossing_now():
			# Section 3.7's stub: halt, enter PAUSED_BY_EVENT, and go no
			# further -- the actual minigame/manual-input resolution is
			# out of scope here. _ensure_hex_logged() having just
			# returned true (a genuinely FRESH entry) is what stops this
			# from re-triggering every tick while paused, or immediately
			# again the instant resume_travel() is called -- the next
			# time this loop runs for this same coord, it's no longer a
			# fresh entry, so this branch is skipped and travel proceeds
			# normally through the hex.
			_pause_for_event()
			break

		var hex_total_minutes := _get_hex_travel_minutes(current_coord)
		if hex_total_minutes <= 0.0:
			# An unrecognized/unpassable hex should never have made it
			# into queued_route via queue_hex()'s own validation -- but
			# a division by zero below would hang travel silently, so
			# warn and skip past it rather than freeze.
			push_warning("TravelSystem: current hex '%s' has zero/invalid travel cost, skipping" % current_coord)
			_complete_current_hex()
			continue

		var minutes_left_in_hex := (1.0 - _travel_state.current_hex_progress) * hex_total_minutes
		var minutes_to_apply: float = minf(remaining_minutes, minutes_left_in_hex)

		_travel_state.current_hex_progress += minutes_to_apply / hex_total_minutes
		_spend_game_minutes(minutes_to_apply)
		remaining_minutes -= minutes_to_apply

		if _travel_state.current_hex_progress >= 1.0:
			_complete_current_hex()


## Section 3.8's log-on-ENTRY contract ("the party's current hex is
## always the log's last entry"), made self-correcting regardless of
## which path led here -- begin_travel() starting the first hex,
## _complete_current_hex() below advancing to the next one, or a fresh
## hex queued and resumed after the party was paused with an empty
## queue -- rather than trying to call this correctly from every
## possible mutation site. Only skips logging when `coord` is ALREADY
## the immediately-preceding entry; a true re-entry (backtracking to a
## coord visited earlier, then later, non-consecutively) still
## duplicates, per Section 3.8's own allowance for repeats.
##
## Returns true only when `coord` was a genuinely NEW entry this call --
## _advance_travel() uses this to gate the one-time-per-entry
## river-crossing check (Section 3.7) below, so resuming after a
## stubbed river pause doesn't immediately re-trigger the same check
## against the same hex it's already sitting on.
func _ensure_hex_logged(coord: String) -> bool:
	var path := _travel_state.visited_hex_path
	if path.is_empty() or path.back() != coord:
		path.append(coord)
		hex_entered.emit(coord)
		return true
	return false


## Convenience wrapper (Section 5.1) around
## WorldRegistry.requires_river_crossing(), deriving entry_edge/
## exit_edge for the CURRENT hex (queued_route[0]) from the party's
## actual path -- entry from wherever they just came from
## (visited_hex_path's second-to-last entry), exit toward wherever
## they're heading next (queued_route[1]).
##
## Returns false without querying WorldRegistry at all for either route
## endpoint -- Section 5.3 resolved this explicitly, not by omission:
## the FIRST hex of a whole journey was only ever entered (nothing
## before it to derive entry_edge from), and the LAST hex of the
## current queue is only ever exited TO, never FROM (the party stops
## at its center per FINAL_HEX_ARRIVAL_FRACTION, rather than continuing
## out through a far edge) -- neither endpoint supports or needs this
## query.
func requires_river_crossing_now() -> bool:
	if _travel_state.queued_route.is_empty():
		return false
	if _travel_state.visited_hex_path.size() < 2 or _travel_state.queued_route.size() < 2:
		return false

	var current_coord: String = _travel_state.queued_route[0]
	var entry_from: String = _travel_state.visited_hex_path[-2]
	var exit_to: String = _travel_state.queued_route[1]

	var entry_edge := WorldRegistry.get_direction_index(current_coord, entry_from)
	var exit_edge := WorldRegistry.get_direction_index(current_coord, exit_to)
	return WorldRegistry.requires_river_crossing(current_coord, entry_edge, exit_edge)


## Total in-game minutes required to fully cross `coord` at current
## Pace/Trail conditions -- the per-hex denominator current_hex_progress
## advances against. Mirrors get_eta_minutes()'s per-hex math,
## including the FINAL_HEX_ARRIVAL_FRACTION discount when `coord` is
## the LAST entry in queued_route (Cameron's center-of-hex
## clarification -- this is the consumer that constant's comment
## reserved room for). Returns 0.0 for an unrecognized coord or unknown
## terrain type -- defensive only, see the caller's own comment.
func _get_hex_travel_minutes(coord: String) -> float:
	var hex := WorldRegistry.get_hex(coord)
	if hex == null:
		return 0.0
	var terrain := WorldRegistry.get_terrain(hex.terrain_type_id)
	if terrain == null:
		return 0.0

	var minutes: float = terrain.base_travel_minutes / get_travel_speed_multiplier(coord)
	if coord == _travel_state.queued_route.back():
		minutes *= FINAL_HEX_ARRIVAL_FRACTION
	return minutes


## Feeds `minutes` (a float -- this call's share of one frame's worth
## of in-game time) into TimeSystem, which only accepts whole minutes.
## Accumulates the fractional remainder in _pending_game_minutes so
## repeated sub-minute contributions are never silently lost, no matter
## how many times this gets called within a single _advance_travel()
## while-loop iteration set.
func _spend_game_minutes(minutes: float) -> void:
	_pending_game_minutes += minutes
	var whole_minutes := floori(_pending_game_minutes)
	if whole_minutes > 0:
		_pending_game_minutes -= whole_minutes
		TimeSystem.pass_minutes(whole_minutes)


## Pops the just-finished hex off the front of queued_route and resets
## current_hex_progress to 0.0 for whatever's now at the front. Does
## NOT log the finished hex -- it was already logged by
## _ensure_hex_logged() back when it first became current, per Section
## 3.8's log-on-entry contract. If the pop empties the queue,
## transitions to PAUSED_BY_PLAYER rather than AT_CAMP -- confirmed by
## Cameron: there's no Camp system yet to actually pitch camp, and
## jumping straight to AT_CAMP would have TravelSystem silently
## pretending that happened. The eventual real flow is: alert the
## player the queued journey is finished, offer to set up camp, and
## also allow queuing more hexes and resuming travel from here without
## ever passing through AT_CAMP at all.
func _complete_current_hex() -> void:
	_travel_state.queued_route.pop_front()
	_travel_state.current_hex_progress = 0.0

	if _travel_state.queued_route.is_empty():
		pause_travel()
		journey_completed.emit()


# ---------------------------------------------------------------------------
# Save / Load
# ---------------------------------------------------------------------------

## Used only by SaveManager on load. Direct replace, same pattern as
## PartyManager.load_roster() -- a load is a restore, not gameplay
## time actually passing, so this deliberately does NOT go through
## set_pace()/_set_state() and doesn't fire their signals.
func load_travel_state(state: TravelState) -> void:
	_travel_state = state
	_pending_game_minutes = 0.0


## Duplicated on the way out, same protective reasoning as
## PartyManager.get_roster() -- the caller (SaveManager, or anything
## else) gets a snapshot, not a live reference it could mutate and
## accidentally desync from TravelSystem's own internal state.
func get_travel_state() -> TravelState:
	return _travel_state.duplicate()
