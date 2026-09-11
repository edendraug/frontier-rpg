extends SubViewportContainer

## Embeds the real, hand-authored world map (world_map_authoring.tscn --
## actual terrain art, trail, and river layers) inside Control-based UI,
## scaled up and pannable.
##
## Displays the map, scaled and pannable, AND resolves clicks to real
## WorldRegistry coord strings -- left-click queues (via autopath, which
## correctly subsumes the plain-adjacent case too, so there's no need to
## separately detect adjacency here), right-click unqueues-and-truncates,
## per Travel System Design Doc v0.2 Section 3.4. Still NOT built:
## visual feedback (highlighting the queued route, showing which hexes
## are actually reachable) -- deliberately deferred to its own follow-up
## now that basic click-to-queue is provably working, rather than folded
## into this same step. Also not built: the Pace/playback-speed/queue
## readout/Begin-Travel controls -- a separate control panel, not part
## of the map itself.
##
## SCENE SETUP (hand-built in the editor):
##   SubViewportContainer (this script) -- set `stretch = true` in the
##   Inspector. This is what actually fixes squashing/uneven scaling:
##   with stretch = false (the default), the SubViewport renders at
##   whatever FIXED resolution it's given, and the container then
##   stretches that fixed image to fill its own real layout size --
##   non-uniformly, if the container's aspect ratio doesn't match the
##   viewport's. stretch = true instead keeps the SubViewport's internal
##   resolution locked to the container's own size at all times, so
##   there's no second scaling step left to distort anything. Size this
##   Control however you like in the editor (anchors to fill most of
##   %TravelMapOverlay, or a fixed custom_minimum_size) -- whatever size
##   you give it is exactly what gets rendered.
##   └─ SubViewport                            — %WorldMapViewport
##      ├─ [instance world_map_authoring.tscn] — %WorldMapInstance
##      └─ Camera2D                            — %MapCamera
##
## Zoom and pan are both driven by %MapCamera, not by scaling
## %WorldMapInstance itself -- keeps world_map_authoring.tscn's own
## content completely untouched regardless of how zoomed/panned the
## view currently is.

## Camera2D.zoom scales the visible world area, but which direction
## (larger vs. smaller value) actually reads as "zoomed in" didn't
## match the documented "values below 1 zoom in" claim once this was
## actually run -- the wheel mapping below is set from what Cameron
## observed in practice, not from that claim, and I haven't chased down
## why they disagreed (possibly a stretch=true interaction, possibly
## something else). Scrolling up now moves the zoom value toward
## MAX_ZOOM, confirmed to read as "zoomed in" -- that's the fact this
## code relies on, not a theory about the property in general.
## INITIAL_ZOOM (0.3) is a starting guess to make the small ~60-hex
## test patch fill most of the panel on open -- tune freely once you
## see it rendered; if the overall zoom RANGE also feels off once
## you're actually testing (can't get close enough, or too close),
## that's independent of the wheel-direction fix and just a matter of
## adjusting MIN_ZOOM/MAX_ZOOM below.
const INITIAL_ZOOM := Vector2(2.3, 2.3)

const MIN_ZOOM := 1.5  # Clamp floor.
const MAX_ZOOM := 3.0   # Clamp ceiling -- the value scrolling up moves toward.
const ZOOM_STEP := 0.9  # Multiplicative per scroll-wheel notch.

## Middle-drag pans -- deliberately not left, since left is now the
## queue-a-hex button (_on_hex_clicked() below). No threshold/ambiguity
## between the two to resolve, because they were never sharing a button
## in the first place.
var _dragging := false


func _ready() -> void:
	var bounds: Rect2 = %WorldMapInstance.get_content_bounds()
	if bounds.size == Vector2.ZERO:
		push_warning("TravelMapPanel: world_map_authoring instance has no painted content")
		return

	%MapCamera.zoom = INITIAL_ZOOM
	%MapCamera.position = bounds.position + bounds.size / 2.0
	%MapCamera.make_current()


## Drag-to-pan (middle mouse button), scroll-wheel zoom, and
## left/right-click queue editing. Deliberately simple -- no inertia,
## and panning isn't clamped to stay within the map's bounds, so
## dragging far enough just shows empty space past the edge. Revisit if
## that reads as a real problem once this is actually in front of you,
## rather than guessing at a clamp now.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		# TEMPORARY -- confirms _gui_input is receiving clicks at all,
		# independent of whether hex resolution afterward succeeds. If
		# this never prints, the problem is upstream of everything else
		# in this file (mouse_filter somewhere in the scene tree, sizing,
		# or something stealing input before it reaches this Control).
		print("TravelMapPanel: mouse button %d pressed" % event.button_index)

		match event.button_index:
			MOUSE_BUTTON_MIDDLE:
				_dragging = true
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_by(1.0 / ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_by(ZOOM_STEP)
			MOUSE_BUTTON_LEFT:
				_on_hex_clicked(false)
			MOUSE_BUTTON_RIGHT:
				_on_hex_clicked(true)

	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE:
		_dragging = false

	elif event is InputEventMouseMotion and _dragging:
		# Divide by zoom so a given screen-pixel drag distance always
		# moves the camera by the same APPARENT world distance
		# regardless of current zoom -- without this, dragging would
		# feel far too fast when zoomed in and far too slow when zoomed
		# out.
		%MapCamera.position -= event.relative / %MapCamera.zoom


## Resolution itself is delegated entirely to
## %WorldMapInstance.get_axial_coord_at_mouse() -- see that method's own
## comment for why this does NOT use Viewport.get_mouse_position()
## (the bug that made every click miss except near the camera's
## untransformed origin). Nothing about camera transforms belongs in
## this file at all; %WorldMapInstance owns that correctly on its own.
##
## TEMPORARY diagnostic prints throughout -- there's no visual feedback
## on the map itself yet (deferred per the header comment above), so
## right now a click is otherwise completely silent whether it worked,
## missed, or never reached this script at all. These three distinct
## outcomes print three distinctly different things specifically so
## that distinction is visible in the Output panel. Remove once real
## feedback (a highlighted hex, the control panel's queue readout)
## makes this redundant.
func _on_hex_clicked(is_unqueue: bool) -> void:
	var coord: String = %WorldMapInstance.get_axial_coord_at_mouse()
	if coord == "":
		print("TravelMapPanel: click resolved to no hex (miss)")
		return

	if is_unqueue:
		var removed := TravelSystem.unqueue_from(coord)
		print("TravelMapPanel: right-click '%s' -> unqueue_from() %s" % [
			coord, "removed it" if removed else "found nothing there to remove"
		])
	else:
		var queued := TravelSystem.queue_autopath_to(coord)
		print("TravelMapPanel: left-click '%s' -> queue_autopath_to() %s -- queue is now %s" % [
			coord, "succeeded" if queued else "FAILED (see warning above, if any)", TravelSystem.get_queued_route()
		])


func _zoom_by(factor: float) -> void:
	var new_zoom: Vector2 = %MapCamera.zoom * factor
	%MapCamera.zoom = new_zoom.clamp(Vector2(MIN_ZOOM, MIN_ZOOM), Vector2(MAX_ZOOM, MAX_ZOOM))
