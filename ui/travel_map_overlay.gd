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
func _get_party_pixel_position() -> Vector2:
	var current := TravelSystem.get_current_hex()
	var queue := TravelSystem.get_queued_route()

	if queue.is_empty():
		# Defensive only -- should be genuinely unreachable now
		# (unqueue_from() refuses to remove index 0, clear_queue()
		# always preserves it), but cheap insurance costs nothing.
		return %WorldMapInstance.get_hex_center(current)

	var visited := TravelSystem.get_visited_hex_path()
	var predecessor: String = visited[-2] if visited.size() >= 2 else TravelSystem.STARTING_HEX_COORD
	var entry_point: Vector2 = %WorldMapInstance.get_shared_edge_midpoint(current, predecessor)
	var hex_center: Vector2 = %WorldMapInstance.get_hex_center(current)
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
