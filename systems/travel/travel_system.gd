extends Node

## Autoload. Owns Pace, the route queue, real-time travel progress,
## and the travel state machine (originally four states, design doc
## Section 3.9; a fifth, ROUTE_COMPLETE, was added after -- see
## TravelState.State's own comment) -- the party's single "what is
## Travel doing right now" source of truth. Live in-memory state is a
## TravelState Resource (_travel_state below), the same shape
## GameSaveData.travel_state saves/loads -- SaveManager reads/writes it
## via get_travel_state()/load_travel_state() rather than TravelSystem
## inventing a separate save shape of its own.
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
## the river-crossing stub (Phase 7, Section 3.7). Beyond the original 7
## phases, Cameron's later additions: ROUTE_COMPLETE as a standstill
## state distinct from PAUSED_BY_PLAYER (TravelState.State's own
## comment), and direction-reversal when a genuinely different exit
## gets queued after progress already committed past center toward
## another one (TravelState.reversing_to_center, _advance_travel()).
## What the design doc itself defers beyond this file's scope stays
## deferred here too -- actual event triggering against computed
## hazard, the river-crossing minigame's real resolution, Assignment
## System integration, the Camp/downtime system, and all final UI/UX
## (Section 9) are still nobody's job but a later, separate design pass.

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

## How many in-game minutes one real-world second represents at
## playback_speed = 1.0. Confirmed by Cameron: roughly 15 real seconds
## to cross a 360-in-game-minute Grassland hex at Normal pace, hence
## 360.0 / 15.0 = 24.0. This is the one Phase 6 number with no design
## doc precedent at all -- pure game-feel, untuned, expect to revisit
## once actual playtesting shows travel feeling too fast/slow.
const BASE_MINUTES_PER_REAL_SECOND := 24.0

## Legal transitions per the state-machine diagram in Section 3.9, plus
## ROUTE_COMPLETE (Cameron's later addition -- see TravelState.State's
## own comment). AT_CAMP's and ROUTE_COMPLETE's only legal exit is to
## TRAVELING, and only via begin_travel() below -- there's no public
## method that lets a caller jump straight to PAUSED_BY_PLAYER/
## PAUSED_BY_EVENT from either, since pausing something that was never
## moving doesn't mean anything.
const _LEGAL_TRANSITIONS := {
	TravelState.State.AT_CAMP: [TravelState.State.TRAVELING],
	TravelState.State.TRAVELING: [TravelState.State.PAUSED_BY_PLAYER, TravelState.State.PAUSED_BY_EVENT, TravelState.State.ROUTE_COMPLETE],
	TravelState.State.PAUSED_BY_PLAYER: [TravelState.State.TRAVELING],
	TravelState.State.PAUSED_BY_EVENT: [TravelState.State.TRAVELING],
	TravelState.State.ROUTE_COMPLETE: [TravelState.State.TRAVELING],
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
## entry in visited_hex_path, or STARTING_HEX_COORD as a fallback for
## the brief window before that's true. Under the current model
## (queued_route defaults to ["0,0"], current_hex_progress to 0.5 --
## see TravelState's own comments), the starting settlement DOES get
## logged like any other hex, the first time _advance_travel()'s own
## _ensure_hex_logged() call runs for it -- which only happens once
## begin_travel() actually transitions to TRAVELING. Before that (still
## AT_CAMP, nothing queued beyond the settlement itself), this getter's
## fallback is what covers the gap.
func get_current_hex() -> String:
	var path := _travel_state.visited_hex_path
	return path.back() if not path.is_empty() else STARTING_HEX_COORD


func get_queued_route() -> Array[String]:
	return _travel_state.queued_route.duplicate()


## Not explicitly named in the design doc, but a trivial and obviously
## useful pairing with queue_hex()/unqueue_from() below -- flagging the
## small scope addition rather than sneaking it in unremarked.
##
## Truncates back to JUST the current hex (index 0) rather than fully
## emptying the array -- queued_route should never actually be empty
## under normal play (see its own comment). unqueue_from() now refuses
## to remove index 0 for exactly this reason; clear_queue() has to get
## it right too, or it would reopen the same hole from a different
## angle. Equivalent to "cancel every queued destination, keep resting
## where I already am."
func clear_queue() -> void:
	_travel_state.queued_route = [_travel_state.queued_route[0]] if not _travel_state.queued_route.is_empty() else []


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

	# queued_route should never actually be empty under normal play --
	# with unqueue_from() now refusing to remove index 0, and
	# clear_queue() always preserving it, this branch should genuinely
	# be UNREACHABLE rather than merely unlikely. Kept as cheap
	# insurance, not because a real path to it is known.
	if _travel_state.queued_route.is_empty():
		_travel_state.current_hex_progress = 0.0

	# queued_route[1] can only ever CHANGE VALUE by this append if it
	# didn't exist before -- append() only touches the end of the
	# array, so an ALREADY-existing index 1 is never touched by this
	# call. That's exactly the case _on_new_exit_direction_known() needs
	# to know about (see its own comment).
	var gaining_first_real_destination := _travel_state.queued_route.size() < 2
	_travel_state.queued_route.append(coord)
	if gaining_first_real_destination and _travel_state.queued_route.size() >= 2:
		_on_new_exit_direction_known(coord)
	return true


## Right-click a queued hex (Section 3.4) -- removes it AND everything
## queued after it, so the queue always stays one continuous path with
## no orphaned branch. No-op (returns false) if `coord` isn't actually
## in the queue.
##
## Refuses (returns false, warns) if `coord` is queued_route[0] --
## the hex CURRENTLY being crossed, not a future destination that can
## be cancelled. "Unqueue" was only ever meant for plans not yet
## walked; queued_route[0] is where the party physically IS, possibly
## mid-crossing with real, already-walked progress. Removing it would
## make queued_route empty, which nothing in this system can recover
## a truthful position from afterward -- the very next queue_hex()
## call would treat whatever gets queued next as a BRAND NEW index 0,
## silently discarding the real progress/direction data that still
## correctly describes where the party actually is. What the player
## almost certainly wants instead -- "don't go anywhere past where I
## am right now" -- is already fully expressible: unqueue index 1
## (the actual next destination), which correctly truncates the queue
## back to just the current hex, preserving its position exactly.
func unqueue_from(coord: String) -> bool:
	var index := _travel_state.queued_route.find(coord)
	if index == -1:
		return false
	if index == 0:
		push_warning("TravelSystem: unqueue_from('%s') refused -- that's the current hex, not a queued destination. To stop after the current crossing, unqueue the NEXT hex instead." % coord)
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

	# Purely defensive now, same reasoning as queue_hex() above --
	# should be genuinely unreachable, not just unlikely.
	if _travel_state.queued_route.is_empty():
		_travel_state.current_hex_progress = 0.0

	var gaining_first_real_destination := _travel_state.queued_route.size() < 2
	_travel_state.queued_route.append_array(path)
	if gaining_first_real_destination and _travel_state.queued_route.size() >= 2:
		_on_new_exit_direction_known(_travel_state.queued_route[1])
	return true


## Called whenever a queue that had NO real destination (just the
## current hex) gains its first one -- new_exit is that hex.
##
## If current_hex_progress is still <= 0.5 (hasn't committed to any
## direction yet), or last_known_exit_hex already agrees with new_exit
## (the SAME direction, re-queued), this is a completely ordinary
## assignment -- adopt new_exit immediately.
##
## But if progress is ALREADY past center toward a DIFFERENT remembered
## direction, that distance was genuinely walked toward the OLD exit --
## it doesn't transfer to a new one for free. Cameron: reversing it
## costs real time, at the hex's own terrain rate, same as walking it
## did. So last_known_exit_hex is deliberately NOT updated here in that
## case -- it stays pointing at the OLD direction throughout the
## reversal (current_hex_progress DECREASING is what a reversal IS; see
## _advance_travel()), and only adopts new_exit once progress actually
## reaches center. reversing_to_center is the flag that tells the tick
## loop which mode it's in.
##
## Either way, whenever the direction is ACTUALLY changing (not a
## same-direction re-queue), midpoint_event_checked gets reset here too
## -- a river-crossing check already run was evaluated against the OLD
## direction, and a genuinely different one needs its own, independent
## check. This matters even outside the reversal case: a river-crossing
## pause always freezes progress at EXACTLY 0.5, not past it, so
## swapping the queued destination while paused (allowed -- the
## triggering hex is queued_route[1], a cancellable destination, not
## the current hex) hits this non-reversal branch, not the one above --
## missing the reset here specifically would have let a real crossing
## check for the new direction go silently unevaluated.
func _on_new_exit_direction_known(new_exit: String) -> void:
	var direction_changing := _travel_state.last_known_exit_hex != "" and _travel_state.last_known_exit_hex != new_exit
	var committed_elsewhere := _travel_state.current_hex_progress > 0.5 and direction_changing

	if committed_elsewhere:
		_travel_state.reversing_to_center = true
	else:
		if direction_changing:
			_travel_state.midpoint_event_checked = false
		_travel_state.last_known_exit_hex = new_exit


## Estimated total travel time for `route`, in minutes -- Section 3.5's
## pre-travel confirmation ETA. Sums each hex's terrain
## base_travel_minutes divided by that hex's own speed multiplier
## (Phase 4's get_travel_speed_multiplier() -- higher multiplier means
## faster, hence division, not multiplication).
##
## No longer discounts the last hex -- there IS no "final hex" anymore
## as a special case (Cameron): every hex costs its full entry->center-
## >exit crossing time, whether or not a next hex is currently known.
## Running out of route just freezes progress at the halfway (center)
## point rather than skipping the second half's cost entirely.
##
## Does NOT account for `route[0]` possibly already being partway
## through its own crossing (a resumed rest hex, typically frozen at
## progress 0.5) -- this sums each hex's FULL cost regardless of
## current_hex_progress, so it can overstate remaining time for
## whichever hex is currently in progress. Pre-existing limitation, not
## something this pass fixes; flagged rather than silently accepted.
##
## Silently skips any coord WorldRegistry doesn't recognize rather
## than aborting the whole estimate -- consistent with this project's
## permissive-by-default handling of missing/unauthored data elsewhere.
func get_eta_minutes(route: Array) -> int:
	var total_minutes := 0.0
	for coord in route:
		var hex := WorldRegistry.get_hex(coord)
		if hex == null:
			continue
		var terrain := WorldRegistry.get_terrain(hex.terrain_type_id)
		if terrain == null:
			continue
		total_minutes += terrain.base_travel_minutes / get_travel_speed_multiplier(coord)
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


## "Begin Travel" (Section 3.5) -- the way out of a standstill, either
## AT_CAMP or ROUTE_COMPLETE (Cameron's later addition -- both mean
## "not moving, need a destination to start"; PAUSED_BY_PLAYER/
## PAUSED_BY_EVENT are a DIFFERENT kind of "not moving" -- an
## interrupted crossing -- and use resume_travel() instead, never this
## method). Refuses (returns false, no state change, no time cost) if
## there's no real destination beyond the resting hex, or if not
## currently in one of the two standstill states.
##
## The empty-queue check is `size() < 2`, not `is_empty()` --
## queued_route[0] is ALWAYS the hex currently being rested in or
## crossed now (Cameron: this is never actually empty under normal
## play, even at the very start), so an "empty" queue in the old sense
## now looks like a single entry with nowhere further to go.
##
## CAMP_PACKUP_MINUTES is charged ONLY when leaving AT_CAMP specifically
## -- AT_CAMP always means "currently camped" (Section 3.9), so leaving
## it always means breaking camp, but ROUTE_COMPLETE never means a camp
## was pitched (Cameron: no auto-camping until a real Camp system
## exists), so there's nothing to pack up leaving THAT state.
##
## Does NOT need to log queued_route[0] -- unlike the old model, that
## hex was ALREADY current (and already logged, whenever it first
## became so) before this method ever runs; nothing new becomes current
## here. The first genuinely NEW hex only appears once
## _complete_current_hex() pops the resting hex after it's fully
## crossed, and that already calls _ensure_hex_logged() on the next
## iteration of _advance_travel()'s own loop.
func begin_travel() -> bool:
	if _travel_state.queued_route.size() < 2:
		push_warning("TravelSystem: begin_travel() refused -- no destination queued beyond the current hex")
		return false
	if _travel_state.state != TravelState.State.AT_CAMP and _travel_state.state != TravelState.State.ROUTE_COMPLETE:
		push_warning("TravelSystem: begin_travel() refused -- not currently AT_CAMP or ROUTE_COMPLETE")
		return false

	if _travel_state.state == TravelState.State.AT_CAMP:
		TimeSystem.pass_minutes(CAMP_PACKUP_MINUTES)
	_set_state(TravelState.State.TRAVELING)
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


## The neighbor hex current_hex_progress's "beyond center" half is
## measured toward -- see TravelState.last_known_exit_hex's own
## comment. This is the consumer-facing getter for it; "" means no
## direction has ever been established for whichever hex is current
## right now (it hasn't advanced past center yet, or never had a next
## hex queued at all).
func get_last_known_exit_hex() -> String:
	return _travel_state.last_known_exit_hex


## Whether the current hex is currently being walked BACKWARD toward
## center, having committed progress toward a direction that got
## replaced by a genuinely different one -- see
## TravelState.reversing_to_center's own comment.
func is_reversing_to_center() -> bool:
	return _travel_state.reversing_to_center


## Drives real-time progress through queued_route's front entry.
## queued_route[0] IS the hex currently being crossed (or rested in) --
## confirmed reading of TravelState's data shape; there's no separate
## "current hex" field, and it's never actually empty under normal play
## now (see TravelState.queued_route's own comment). Runs as a
## while-loop rather than a single step so a large delta (a lag spike,
## or a high playback_speed) can correctly finish crossing MULTIPLE
## hexes in one call without losing or double-spending any of this
## frame's time.
##
## Each hex has a CAP on how far progress can advance: 1.0 (full
## crossing) if a next hex is currently known (queued_route.size() >= 2),
## or 0.5 (center) if not. Cameron: every hex crossing always routes
## through its own center, and represents the SAME geometric distance
## either way (a regular hexagon's center-to-edge-midpoint distance,
## the apothem, is identical for every edge) -- so there's no more
## "final hex" discount. A hex that runs out of road just has progress
## FROZEN at 0.5 rather than being popped and reset; the moment a real
## next hex gets queued and travel resumes, the SAME hex picks up
## exactly where it left off and continues normally toward that hex's
## actual exit edge, at that hex's own full, undiscounted terrain cost.
## This is what makes leaving a rest stop (including the very start of
## the whole expedition) an ordinary crossing rather than a special
## case needing its own visual/timing hack.
##
## Each step ALSO targets progress 0.5 specifically (not straight to
## whatever the cap is) whenever the midpoint river-crossing check
## hasn't run yet for this hex -- this is what guarantees the check
## actually fires at the midpoint rather than being silently skipped
## over by a single large step. If no next hex is known yet when
## progress reaches 0.5, the check is correctly DEFERRED (not skipped,
## not marked done) until a real exit edge is actually knowable --
## requires_river_crossing_now() already returns false with no next hex
## known, so evaluating it too early would silently skip a real
## crossing once the true destination is finally queued.
##
## REVERSAL (Cameron): if a genuinely different direction gets queued
## while progress is already past center toward a remembered one
## (TravelState.reversing_to_center, set by _on_new_exit_direction_known()),
## this is checked and handled FIRST, before any of the forward logic
## above even runs -- progress DECREASES back toward 0.5 at the same
## per-hex terrain rate forward movement uses (reversing costs real
## time too, it isn't free), and only once it reaches exactly 0.5 does
## last_known_exit_hex adopt the new direction and ordinary forward
## processing resume. The overlay needs no changes at all for this --
## it already just renders whatever current_hex_progress says, and a
## decreasing value already reads as walking backward toward center.
func _advance_travel(delta: float) -> void:
	if _travel_state.queued_route.is_empty():
		# Should be genuinely unreachable now, not just unlikely --
		# unqueue_from() refuses to remove index 0 and clear_queue()
		# always preserves it, so nothing left should be able to empty
		# this out. Kept as cheap insurance against crashing on the
		# queued_route[0] access below, not because a real path here
		# is known.
		push_warning("TravelSystem: _advance_travel() called while TRAVELING with an empty queue")
		pause_travel()
		return

	var remaining_minutes := delta * BASE_MINUTES_PER_REAL_SECOND * _travel_state.playback_speed

	while remaining_minutes > 0.0 and _travel_state.state == TravelState.State.TRAVELING and not _travel_state.queued_route.is_empty():
		var current_coord: String = _travel_state.queued_route[0]
		_ensure_hex_logged(current_coord)

		var hex_total_minutes := _get_hex_travel_minutes(current_coord)
		if hex_total_minutes <= 0.0:
			# An unrecognized/unpassable hex should never have made it
			# into queued_route via queue_hex()'s own validation -- but
			# a division by zero below (in EITHER the reversal or the
			# forward branch) would hang travel silently, so warn and
			# bail out unconditionally, before either branch runs.
			# Clearing reversing_to_center here too -- there's no
			# meaningful way to reverse through data this broken either.
			push_warning("TravelSystem: current hex '%s' has zero/invalid travel cost, skipping" % current_coord)
			_travel_state.reversing_to_center = false
			if _travel_state.queued_route.size() >= 2:
				_complete_current_hex()
				continue
			else:
				_halt_at_route_end()
				break

		if _travel_state.reversing_to_center:
			var minutes_to_center := (_travel_state.current_hex_progress - 0.5) * hex_total_minutes
			var minutes_to_apply_rev: float = minf(remaining_minutes, minutes_to_center)

			_travel_state.current_hex_progress -= minutes_to_apply_rev / hex_total_minutes
			_spend_game_minutes(minutes_to_apply_rev)
			remaining_minutes -= minutes_to_apply_rev

			if _travel_state.current_hex_progress <= 0.5:
				_travel_state.current_hex_progress = 0.5  # clamp exactly -- avoid float drift past the threshold
				_travel_state.reversing_to_center = false
				_travel_state.midpoint_event_checked = false  # a new direction needs its own crossing check
				if _travel_state.queued_route.size() >= 2:
					_travel_state.last_known_exit_hex = _travel_state.queued_route[1]
			continue

		var has_next_hex := _travel_state.queued_route.size() >= 2
		var cap := 1.0 if has_next_hex else 0.5

		if _travel_state.current_hex_progress >= cap:
			if has_next_hex:
				_complete_current_hex()
				continue
			else:
				# Reached the cap (center) with nothing further queued
				# -- nowhere to go until more hexes are added. Freeze
				# here: don't pop, don't touch progress, just stop
				# ticking against this same dead end.
				_halt_at_route_end()
				break

		var target_progress: float = 0.5 if not _travel_state.midpoint_event_checked else cap
		var minutes_to_target := (target_progress - _travel_state.current_hex_progress) * hex_total_minutes
		var minutes_to_apply: float = minf(remaining_minutes, minutes_to_target)

		_travel_state.current_hex_progress += minutes_to_apply / hex_total_minutes
		_spend_game_minutes(minutes_to_apply)
		remaining_minutes -= minutes_to_apply

		if not _travel_state.midpoint_event_checked and _travel_state.current_hex_progress >= 0.5 and has_next_hex:
			# Section 3.7's stub, fired at the geometric midpoint
			# (Cameron: every crossing routes through center) rather
			# than on entry. Only actually runs -- and only gets marked
			# done -- once a real next hex is known; see this
			# function's own header comment for why deferring instead
			# of skipping matters here.
			_travel_state.midpoint_event_checked = true
			if requires_river_crossing_now():
				_pause_for_event()
				break


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
func _ensure_hex_logged(coord: String) -> void:
	var path := _travel_state.visited_hex_path
	if path.is_empty() or path.back() != coord:
		path.append(coord)
		hex_entered.emit(coord)


## Convenience wrapper (Section 5.1) around
## WorldRegistry.requires_river_crossing(), deriving entry_edge/
## exit_edge for the CURRENT hex (queued_route[0]) from the party's
## actual path -- entry from wherever they just came from
## (visited_hex_path's second-to-last entry), exit toward wherever
## they're heading next (queued_route[1]).
##
## Returns false without querying WorldRegistry at all when either edge
## isn't known yet -- Section 5.3 resolved the "first hex of a journey"
## case explicitly, not by omission: it was only ever entered, nothing
## before it to derive entry_edge from. The "no next hex queued yet"
## case is different in kind, not just in name: _advance_travel()'s own
## deferred-check logic means this returning false here doesn't mean
## "never check" the way it used to when a final hex was a genuinely
## separate, discounted case -- it means "not yet," and the real check
## still runs later, once a real exit edge actually exists to test.
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
## advances against. Mirrors get_eta_minutes()'s per-hex math. No
## longer discounted for a "final" hex (Cameron) -- there is no special
## final-hex case anymore; a hex that runs out of road just freezes at
## progress 0.5 (see _advance_travel()'s own header comment) rather
## than being charged half price for a shortened crossing. Returns 0.0
## for an unrecognized coord or unknown terrain type -- defensive only,
## see the caller's own comment.
func _get_hex_travel_minutes(coord: String) -> float:
	var hex := WorldRegistry.get_hex(coord)
	if hex == null:
		return 0.0
	var terrain := WorldRegistry.get_terrain(hex.terrain_type_id)
	if terrain == null:
		return 0.0
	return terrain.base_travel_minutes / get_travel_speed_multiplier(coord)


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
## 3.8's log-on-entry contract.
##
## Only ever called from _advance_travel() when a next hex is ALREADY
## known (has_next_hex true) -- "the queue ran out" is no longer this
## function's concern at all; see _halt_at_route_end() below for that
## case instead. Popping unconditionally is safe here specifically
## because the caller already confirmed there's something left after
## the pop.
func _complete_current_hex() -> void:
	_travel_state.queued_route.pop_front()
	_travel_state.current_hex_progress = 0.0
	_travel_state.midpoint_event_checked = false
	# The new current hex's exit reference should reflect whatever's
	# ALREADY known to come next (queued_route[1], if any) -- NOT
	# unconditionally reset to "". A multi-hex route queued all at once
	# (B and C both queued before travel even began) already has C
	# sitting at queued_route[1] well before B ever becomes current --
	# _on_new_exit_direction_known() only fires once per BATCH (the
	# queue transitioning from no-real-destination to having one), not
	# once per hex, so a later hex in the same batch never got a chance
	# to have its own exit captured. Blindly resetting to "" here threw
	# that already-known answer away, which is what made the overlay
	# treat progress past 0.5 as "no exit known" and clamp the render to
	# center for the entire back half of the crossing -- current_hex_
	# progress itself was never wrong, only what the overlay had to
	# render it against.
	_travel_state.last_known_exit_hex = _travel_state.queued_route[1] if _travel_state.queued_route.size() >= 2 else ""
	# Defensive only -- _advance_travel()'s reversal branch always
	# `continue`s, so this function should never actually be reached
	# while reversing_to_center is true. Reset anyway, same hygiene as
	# midpoint_event_checked above.
	_travel_state.reversing_to_center = false


## Halts travel with the current hex FROZEN exactly where it is -- no
## next hex is known, so there's nowhere further to advance toward.
## Deliberately does NOT touch queued_route or current_hex_progress at
## all: the whole point is that the SAME hex, at the SAME progress,
## picks back up the instant a real destination gets queued and
## begin_travel() is called again -- no popping, no resetting, nothing
## to reconstruct later. Distinct from _complete_current_hex() above,
## which pops a FULLY-crossed hex and moves on; this one freezes an
## INCOMPLETE crossing in place. ROUTE_COMPLETE rather than AT_CAMP --
## there's no Camp system yet to actually pitch camp, and jumping
## straight to AT_CAMP would have TravelSystem silently pretending that
## happened. The eventual real flow is: alert the player the queued
## journey is finished, offer to set up camp, and also allow queuing
## more hexes and calling begin_travel() again from here without ever
## passing through AT_CAMP at all.
func _halt_at_route_end() -> void:
	_set_state(TravelState.State.ROUTE_COMPLETE)
	journey_completed.emit()


# ---------------------------------------------------------------------------
# Save / Load
# ---------------------------------------------------------------------------

## Used only by SaveManager on load. Direct replace, same pattern as
## PartyManager.load_roster() -- a load is a restore, not gameplay
## time actually passing, so this deliberately does NOT go through
## set_pace()/_set_state() and doesn't fire their signals.
##
## No inference needed for midpoint_event_checked/reversing_to_center/
## last_known_exit_hex -- all three are now real fields on TravelState
## itself, loaded correctly along with everything else. This used to
## guess midpoint_event_checked from progress/queue-size, which had a
## genuine blind spot (couldn't tell "checked for the CURRENT direction"
## from "checked for one that's since been replaced") -- see
## TravelState.midpoint_event_checked's own comment for the scenario
## that exposed it.
## Used only by SaveManager on load. Direct replace, same pattern as
## PartyManager.load_roster() -- a load is a restore, not gameplay
## time actually passing, so this deliberately does NOT go through
## set_pace()/_set_state() and doesn't fire their signals.
##
## Duplicates `state` before adopting it -- TravelState is a Resource
## (a reference type), and load() on a .tres path isn't guaranteed to
## re-read the file from disk each time: Godot can hand back an
## already-cached instance from an earlier load of the SAME path,
## still alive because something (this very field, before the fix)
## kept holding a reference to it. Without duplicating, every tick
## afterward would mutate that shared instance directly -- so quitting
## without saving, then reloading the SAME save file, would silently
## hand back your own in-memory, unsaved mutations instead of what's
## actually on disk. Loading a DIFFERENT save first happened to "fix"
## this by reassigning _travel_state elsewhere, dropping the only
## reference and letting the stale instance get collected -- a real
## symptom of the underlying reference-aliasing bug, not a coincidence.
## get_travel_state() already duplicates on the way OUT for the exact
## same reason; this was the missing other half of that same principle.
func load_travel_state(state: TravelState) -> void:
	_travel_state = state.duplicate()
	_pending_game_minutes = 0.0


## Called from PartyManager.begin_expedition() -- TravelSystem is a
## process-lifetime autoload, same as every other system here; without
## this, starting a new expedition without closing the game window
## first would inherit whatever travel state (position, queue,
## progress) is left over from a moment ago, the same class of bug
## load_travel_state()/get_travel_state() not being wired into
## SaveManager was -- just triggered by "New Game" instead of "Load."
func reset_to_fresh_expedition() -> void:
	_travel_state = TravelState.new()
	_pending_game_minutes = 0.0


## Duplicated on the way out, same protective reasoning as
## PartyManager.get_roster() -- the caller (SaveManager, or anything
## else) gets a snapshot, not a live reference it could mutate and
## accidentally desync from TravelSystem's own internal state.
func get_travel_state() -> TravelState:
	return _travel_state.duplicate()
