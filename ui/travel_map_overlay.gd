extends Node2D

## Rudimentary visual telegraph for TravelSystem state, drawn ON TOP of
## the real authored map: the current hex, the remaining queue, and the
## party's own real-time position -- interpolated WITHIN the hex
## currently being crossed, via current_hex_progress, not just "which
## hex." Placeholder visuals throughout (flat circles, not real
## markers/icons) -- the point of this pass is confirming the DATA is
## right, not how it looks.
##
## SCENE SETUP (hand-built in the editor): a plain Node2D, sibling to
## %WorldMapInstance and %MapCamera, INSIDE the same %WorldMapViewport
## SubViewport -- not inside the SubViewportContainer, and not inside
## world_map_authoring.tscn itself. Being inside the SubViewport (not
## the Container) is what makes every marker below automatically
## inherit %MapCamera's current pan/zoom for free, the same way the
## real map art does -- no separate transform math needed here.
##
## Deliberately lives OUTSIDE world_map_authoring.tscn -- that scene's
## whole purpose is staying gameplay-agnostic (it doubles as the bake
## step's own source data), and drawing "where the party is" is
## inescapably a Travel-System concern. This script depends on
## TravelSystem freely; world_map_authoring.gd never should, and
## nothing here changes that.

const CURRENT_HEX_COLOR := Color(1.0, 0.9, 0.2, 0.9)
const QUEUED_HEX_COLOR := Color(1.0, 0.9, 0.2, 0.4)
const PARTY_COLOR := Color(0.9, 0.1, 0.1, 1.0)

const HEX_MARKER_RADIUS := 6.0
const PARTY_MARKER_RADIUS := 5.0


## Redraws every frame, unconditionally -- same "just recompute"
## simplicity travel_control_panel.gd already uses, rather than
## wiring up selective signal-based redraws. Cheap enough at this
## scale (a handful of circle draws); revisit only if actually
## measured as a problem.
func _process(_delta: float) -> void:
	queue_redraw()


## Draws every queued hex EXCEPT whichever one is actually current
## (drawn separately below, more prominently). queue[0] IS always the
## current hex now (TravelState's own comment -- it's never actually
## empty, and index 0 is always whichever hex is being rested in or
## crossed), so this loop only ever skips exactly one entry -- but it's
## still written as "skip whatever matches current" rather than
## hardcoding index 0, since that's the actual invariant being relied
## on, not an assumption about array position.
func _draw() -> void:
	var queue := TravelSystem.get_queued_route()
	var current := TravelSystem.get_current_hex()

	for coord in queue:
		if coord != current:
			_draw_hex_marker(coord, QUEUED_HEX_COLOR)

	_draw_hex_marker(current, CURRENT_HEX_COLOR)
	_draw_party_marker()


func _draw_hex_marker(coord: String, color: Color) -> void:
	var global_center: Vector2 = %WorldMapInstance.get_hex_center(coord)
	if global_center == Vector2.INF:
		return  # No painted hex at this coord -- silent, not an error.
	draw_circle(to_local(global_center), HEX_MARKER_RADIUS, color)


func _draw_party_marker() -> void:
	var global_pos := _get_party_pixel_position()
	if global_pos == Vector2.INF:
		return
	draw_circle(to_local(global_pos), PARTY_MARKER_RADIUS, PARTY_COLOR)


## Returns a GLOBAL position (see get_hex_center()'s own comment for
## why) -- callers convert to their own local space via to_local()
## before drawing, same as _draw_hex_marker()/_draw_party_marker()
## above do.
##
## Confirmed by Cameron: a hex crossing ALWAYS routes through its own
## center -- entry edge -> center -> exit edge -- rather than a direct
## entry->exit chord. This isn't cosmetic: for a regular hexagon the
## center-to-edge-midpoint distance (the apothem) is identical for
## every edge, so routing through center makes every hex represent the
## SAME geometric distance regardless of which two edges are actually
## used -- consistent with base_travel_minutes being a flat per-terrain
## cost that doesn't vary by entry/exit angle. A direct chord does NOT
## have that property (its length depends on the angle between the two
## edges), which is exactly what made the old straight-line lerp wrong.
##
## No more special-casing needed for "standstill" or "resumed from
## rest" -- TravelState itself now represents a rest stop as an
## ordinary, incomplete crossing (queued_route[0] frozen at progress
## 0.5, never popped just because no next hex is known yet -- see
## TravelState's own comments and _advance_travel() in travel_system.gd)
## rather than something that gets reset and needs reconstructing
## later. So the SAME formula below is correct in every state: resting
## at the very start of the expedition, resting after a route
## completed, actively crossing, or paused mid-crossing.
##
## predecessor is visited_hex_path's second-to-last entry, or
## STARTING_HEX_COORD if there isn't one yet (the true first hex of the
## whole expedition). When predecessor == current -- the very start,
## before visited_hex_path has two distinct entries -- the shared-edge
## call below naturally degenerates to the hex's own center, which is
## exactly right: there's nowhere to have entered FROM yet.
##
## The exit reference is TravelSystem.get_last_known_exit_hex(), NOT
## queued_route[1] directly -- the two usually agree, but
## last_known_exit_hex FREEZES instead of disappearing the moment a
## known next hex gets dequeued mid-crossing. Without that, progress
## past 0.5 with no currently-queued next hex would be geometrically
## ambiguous (which direction is it 60% of the way toward?), and
## clamping toward center would silently discard a real, already-
## walked distance rather than displaying it truthfully.
##
## The overall shape has two cases, matching the same distinction
## _get_hex_travel_minutes() makes:
##   - No exit direction known yet (progress hasn't passed center, or
##     never had a next hex at all): only the entry->center half is
##     ever needed.
##   - An exit direction IS known (current or remembered): progress
##     0.0-0.5 covers entry->center, 0.5-1.0 covers center->exit -- the
##     full three-sector crossing.
## Expedition Scene Routing addition: while ExpeditionSceneRouter is
## walking an in-hex sector detour ("Approach" -- Cameron's confirmed
## model, walked over real time rather than an instant teleport), the
## party marker renders that walk instead of the normal hex-crossing
## position below. Checked FIRST since a detour only ever happens while
## TravelSystem is already PAUSED_BY_EVENT with current_hex_progress
## frozen -- the two are mutually exclusive, never blended. A SECOND,
## separate addition below: once a detour finishes, the resumed
## crossing's first half renders from the visited location's real
## position (ExpeditionSceneRouter.get_hex_position_override()), not
## the geometric entry point -- see that method's own comment. Real bug
## fixed here: this MUST check against NO_POSITION_OVERRIDE explicitly,
## not `>= 0` -- CENTER_SECTOR is -1, so a sign check silently treated a
## center-sector visit as "no visit happened at all" and rendered the
## stale geometric entry point for as long as the override was active
## (visibly wrong the whole time the player was inside the visited
## scene, not just a one-frame glitch).
func _get_party_pixel_position() -> Vector2:
	if ExpeditionSceneRouter.is_detouring():
		return _get_detour_pixel_position()

	var current := TravelSystem.get_current_hex()
	var queue := TravelSystem.get_queued_route()

	if queue.is_empty():
		# Defensive only -- should be genuinely unreachable now
		# (unqueue_from() refuses to remove index 0, clear_queue()
		# always preserves it), but cheap insurance costs nothing.
		return %WorldMapInstance.get_hex_center(current)

	var hex_center: Vector2 = %WorldMapInstance.get_hex_center(current)

	# Expedition Scene Routing addition: if a visit at THIS hex already
	# moved the party (Cameron's confirmed "hex_sector is real position"
	# model), the resumed crossing's first half starts from THERE, not
	# the geometric entry point -- same neighbor-lookup trick
	# _get_detour_pixel_position() already uses below. Checked against
	# the actual NO_POSITION_OVERRIDE sentinel, NOT `>= 0` -- CENTER_SECTOR
	# is -1, which would otherwise be indistinguishable from
	# NO_POSITION_OVERRIDE's own -2 and silently fall through to the
	# "no visit happened" branch, which was exactly the bug: a
	# real-edge override rendered correctly (>= 0 caught it), but a
	# CENTER_SECTOR override was being treated as if no visit had
	# occurred at all.
	var entry_point: Vector2
	var position_override := ExpeditionSceneRouter.get_hex_position_override()
	if position_override != ExpeditionSceneRouter.NO_POSITION_OVERRIDE:
		if position_override == LocationSceneDefinition.CENTER_SECTOR:
			entry_point = hex_center
		else:
			var neighbors := WorldRegistry.get_neighbors(current)
			entry_point = %WorldMapInstance.get_shared_edge_midpoint(current, neighbors[position_override]) if position_override < neighbors.size() else Vector2.INF
	else:
		var visited := TravelSystem.get_visited_hex_path()
		var predecessor: String = visited[-2] if visited.size() >= 2 else TravelSystem.STARTING_HEX_COORD
		entry_point = %WorldMapInstance.get_shared_edge_midpoint(current, predecessor)

	var progress := TravelSystem.get_current_hex_progress()

	if entry_point == Vector2.INF or hex_center == Vector2.INF:
		return Vector2.INF

	var exit_hex := TravelSystem.get_last_known_exit_hex()
	if progress <= 0.5 or exit_hex == "":
		return entry_point.lerp(hex_center, minf(progress * 2.0, 1.0))

	var exit_point: Vector2 = %WorldMapInstance.get_shared_edge_midpoint(current, exit_hex)
	if exit_point == Vector2.INF:
		return Vector2.INF
	return hex_center.lerp(exit_point, (progress - 0.5) * 2.0)


## Entry point uses the exact same get_shared_edge_midpoint(coord,
## predecessor) call as the normal crossing above -- a detour always
## starts from progress 0.0 (the arrival prompt fires the instant a hex
## is entered, before any further ticking), so this is the party's real
## on-screen position the moment "Approach" was chosen, not an
## approximation. The degenerate case (predecessor == coord, the very
## first hex of the expedition) is handled the same way it already is
## there -- get_shared_edge_midpoint() itself collapses to the hex's
## own center.
##
## Target point reuses WorldRegistry.get_neighbors() rather than any
## new map-instance API: LocationSceneDefinition.hex_sector is defined
## to match AXIAL_DIRECTIONS' own index order (same convention
## river_edges already uses), so the neighbor AT that index's shared
## edge midpoint IS the sector's on-screen position -- even though that
## neighbor hex plays no other role here. CENTER_SECTOR skips this
## entirely and targets the hex's own center instead.
func _get_detour_pixel_position() -> Vector2:
	var coord := ExpeditionSceneRouter.get_detour_coord()
	var sector := ExpeditionSceneRouter.get_detour_sector()
	var progress := ExpeditionSceneRouter.get_detour_progress()

	var visited := TravelSystem.get_visited_hex_path()
	var predecessor: String = visited[-2] if visited.size() >= 2 else TravelSystem.STARTING_HEX_COORD
	var entry_point: Vector2 = %WorldMapInstance.get_shared_edge_midpoint(coord, predecessor)
	if entry_point == Vector2.INF:
		return Vector2.INF

	var target_point: Vector2
	if sector == LocationSceneDefinition.CENTER_SECTOR:
		target_point = %WorldMapInstance.get_hex_center(coord)
	else:
		var neighbors := WorldRegistry.get_neighbors(coord)
		if sector < 0 or sector >= neighbors.size():
			return Vector2.INF
		target_point = %WorldMapInstance.get_shared_edge_midpoint(coord, neighbors[sector])

	if target_point == Vector2.INF:
		return Vector2.INF
	return entry_point.lerp(target_point, progress)
