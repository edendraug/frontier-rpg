extends Control

## Rudimentary control panel for exercising TravelSystem directly --
## Pace, playback speed, a queue/state/ETA readout, and Begin/Pause/
## Resume. Companion to travel_map_panel.gd (the map itself); NOT wired
## to the map visually in any way yet (no highlighting the queue on the
## map, no click-to-select from here) -- same "prove the pieces work
## before polishing" posture as everything else in this pass.
##
## SCENE SETUP (hand-built in the editor). Suggested placement:
## alongside the map inside %TravelMapOverlay -- e.g. a sidebar next to
## the SubViewportContainer -- rather than a separate overlay of its own.
##   %PaceOptionButton      (OptionButton)
##   %PlaybackSpeedSlider   (HSlider) — set min/max/step in the Inspector. 0.1-20 is a reasonable starting range for testing both slow-motion and heavy fast-forward.
##   %StateLabel            (Label)
##   %CurrentHexLabel       (Label)
##   %ProgressLabel         (Label) — current_hex_progress as a percentage.
##   %QueueLabel            (Label) — the queued route, joined into one line.
##   %ETALabel              (Label) — get_eta_minutes() for the current queue.
##   %BeginTravelButton     (Button)
##   %PauseButton           (Button)
##   %ResumeButton          (Button)
##
## Refreshes every label, every frame, unconditionally -- same "just
## recompute" simplicity Expedition Hub's Party/Inventory overlays
## already use rather than wiring up selective signal-based updates.
## Cheap enough at this scale (a handful of getters and label.text
## assignments); revisit only if this is ever measured as an actual
## problem, not preemptively.

const PACE_NAMES := ["Careful", "Normal", "Forced"]
const STATE_NAMES := ["At Camp", "Traveling", "Paused (Player)", "Paused (Event)"]


func _ready() -> void:
	for pace_name in PACE_NAMES:
		%PaceOptionButton.add_item(pace_name)
	%PaceOptionButton.selected = TravelSystem.get_pace()
	%PaceOptionButton.item_selected.connect(func(index: int): TravelSystem.set_pace(index))

	%PlaybackSpeedSlider.value = TravelSystem.get_playback_speed()
	%PlaybackSpeedSlider.value_changed.connect(TravelSystem.set_playback_speed)

	%BeginTravelButton.pressed.connect(_on_begin_travel_pressed)
	%PauseButton.pressed.connect(TravelSystem.pause_travel)
	%ResumeButton.pressed.connect(TravelSystem.resume_travel)

	_refresh()


func _process(_delta: float) -> void:
	_refresh()


## Explicit print on failure -- TravelSystem's own push_warning already
## explains WHY (empty queue / not at camp), but that's easy to miss in
## the Output panel scrollback; this makes a failed press impossible to
## mistake for nothing having happened.
func _on_begin_travel_pressed() -> void:
	if not TravelSystem.begin_travel():
		print("TravelControlPanel: begin_travel() refused -- see warning above")


func _refresh() -> void:
	var state := TravelSystem.get_current_state()
	%StateLabel.text = "State: %s" % STATE_NAMES[state]
	%CurrentHexLabel.text = "Current hex: %s" % TravelSystem.get_current_hex()
	%ProgressLabel.text = "Progress: %.0f%%" % (TravelSystem.get_current_hex_progress() * 100.0)

	var queue := TravelSystem.get_queued_route()
	if queue.is_empty():
		%QueueLabel.text = "Queue: (empty)"
	else:
		%QueueLabel.text = "Queue (%d): %s" % [queue.size(), ", ".join(PackedStringArray(queue))]
	%ETALabel.text = "ETA: %d min" % TravelSystem.get_eta_minutes(queue)

	# Buttons reflect what's actually LEGAL right now, per
	# TravelSystem's own state machine -- rather than letting a press
	# silently no-op with only a console warning to explain why.
	%BeginTravelButton.disabled = state != TravelState.State.AT_CAMP
	%PauseButton.disabled = state != TravelState.State.TRAVELING
	%ResumeButton.disabled = state == TravelState.State.AT_CAMP or state == TravelState.State.TRAVELING
