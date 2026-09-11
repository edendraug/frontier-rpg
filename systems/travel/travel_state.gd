class_name TravelState
extends Resource

## Save-data for the Travel System -- one instance lives on
## GameSaveData.travel_state. Precise to the current in-progress hex's
## fractional progress, since camp can be pitched at any point mid-hex.
## See Travel System Design Doc v0.2, Section 4.1.
##
## Resource, not RefCounted -- per this project's standing rule that
## anything surviving Save/Load must be a Resource.

## Which of the four travel states the party is currently in.
## See design doc Section 3.9.
enum State {
	AT_CAMP,
	TRAVELING,
	PAUSED_BY_PLAYER,
	PAUSED_BY_EVENT,
}

## Careful / Normal / Forced. Party-wide, not per-character -- lives
## here rather than on PartyManager. See design doc Section 3.1.
enum Pace {
	CAREFUL,
	NORMAL,
	FORCED,
}

@export var state: State = State.AT_CAMP

## Persists between sessions.
@export var pace: Pace = Pace.NORMAL

## UI/presentation only -- never affects in-game time math. Distinct
## from `pace`, which does affect it. See design doc Section 3.6.
@export var playback_speed: float = 1.0

## Remaining hex coords still to be traveled, in order. Edited via the
## left-click-to-add / right-click-to-remove-and-truncate rules in
## design doc Section 3.4.
@export var queued_route: Array[String] = []

## 0.0-1.0. Progress through whichever hex is currently being crossed.
@export var current_hex_progress: float = 0.0

## Ordered, may contain repeats if the party backtracks. Whether a hex
## counts as "visited" is a derived check (`coord in visited_hex_path`),
## not a separate stored flag -- see design doc Section 3.8.
@export var visited_hex_path: Array[String] = []
