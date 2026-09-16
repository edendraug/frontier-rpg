class_name TravelState
extends Resource

## Save-data for the Travel System -- one instance lives on
## GameSaveData.travel_state. Precise to the current in-progress hex's
## fractional progress, since camp can be pitched at any point mid-hex.
## See Travel System Design Doc v0.2, Section 4.1.
##
## Resource, not RefCounted -- per this project's standing rule that
## anything surviving Save/Load must be a Resource.
##
## "0,0" appears hardcoded twice below (queued_route and, implicitly,
## wherever STARTING_HEX_COORD is used) rather than shared from one
## place -- a plain Resource's default value can't reliably reference
## TravelSystem (an autoload) at construction time. Must stay in sync
## with TravelSystem.STARTING_HEX_COORD by hand if that ever changes.

## Which state the party is currently in. AT_CAMP/TRAVELING/
## PAUSED_BY_PLAYER/PAUSED_BY_EVENT match design doc Section 3.9.
## ROUTE_COMPLETE is a later addition (Cameron): distinct from
## PAUSED_BY_PLAYER specifically so begin_travel() -- not resume_travel()
## -- is the way out of it. Conceptually, PAUSED_BY_PLAYER/
## PAUSED_BY_EVENT mean "a crossing got interrupted, continue it";
## AT_CAMP/ROUTE_COMPLETE both mean "at a standstill, need a queue to
## start moving" -- collapsing ROUTE_COMPLETE into PAUSED_BY_PLAYER
## made that distinction impossible to express (e.g. begin_travel()'s
## camp pack-up cost only makes sense leaving AT_CAMP, never
## ROUTE_COMPLETE, since no camp was ever pitched there). Appended
## at the end, not inserted alongside the others, so existing saves'
## stored int values for the earlier four don't shift.
enum State {
	AT_CAMP,
	TRAVELING,
	PAUSED_BY_PLAYER,
	PAUSED_BY_EVENT,
	ROUTE_COMPLETE,
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

## Remaining hex coords still to be traveled, starting with whichever
## hex is CURRENTLY being crossed (or rested in) at index 0 -- this is
## NEVER empty under normal play, even at the very start or after a
## route runs out. "At camp" and "route complete, nothing queued yet"
## are the SAME underlying shape now: one hex, frozen at its own
## center, waiting for a real destination. Defaults to the starting
## settlement itself -- see current_hex_progress's own comment for why
## that's paired with 0.5, not 0.0. Edited via the left-click-to-add /
## right-click-to-remove-and-truncate rules in design doc Section 3.4.
@export var queued_route: Array[String] = ["0,0"]

## 0.0-1.0. Progress through whichever hex is currently being crossed
## (queued_route[0]). Defaults to 0.5, not 0.0 -- the party starts
## RESTING at the starting settlement's own center, which under the
## entry->center->exit crossing model (Cameron) is exactly the halfway
## point of a crossing that hasn't been given a real destination yet.
## This is what lets leaving the starting settlement be an ordinary
## hex crossing (finish the center->exit half at the settlement's own
## terrain cost) rather than a special case -- the same reasoning
## applies to resuming after ANY route runs out, not just the very
## start.
@export var current_hex_progress: float = 0.5

## Ordered, may contain repeats if the party backtracks. Whether a hex
## counts as "visited" is a derived check (`coord in visited_hex_path`),
## not a separate stored flag -- see design doc Section 3.8.
@export var visited_hex_path: Array[String] = []

## The neighbor hex that current_hex_progress's "beyond center" half
## (progress > 0.5) is measured TOWARD -- mirrors queued_route[1]
## whenever one exists, but FREEZES (keeps its last value) once it
## doesn't, rather than being cleared. This is what lets a hex frozen
## partway past center, then dequeued, still render at its true
## position instead of snapping to center: current_hex_progress alone
## is ambiguous past 0.5 without knowing which direction it's relative
## to, and that direction shouldn't disappear just because the queue
## entry that supplied it did. Reset to "" only when the CURRENT hex
## itself changes (a fresh hex has no direction yet) -- see
## TravelSystem._complete_current_hex().
@export var last_known_exit_hex: String = ""

## True while the party is walking BACKWARD (current_hex_progress
## decreasing) from wherever it committed toward last_known_exit_hex,
## back to center -- because a genuinely DIFFERENT direction got queued
## instead. Cameron: switching direction isn't free -- distance already
## walked toward one exit doesn't magically count toward a different
## one, so reversing it costs the same real time, at the same terrain
## rate, as walking it did in the first place. Cleared the instant
## progress reaches exactly 0.5 (see TravelSystem._advance_travel()),
## at which point last_known_exit_hex adopts the new direction and
## ordinary forward progress resumes.
@export var reversing_to_center: bool = false

## Whether the Section 3.7 river-crossing check has already run for
## whichever direction last_known_exit_hex currently names. Previously
## a private runtime var on TravelSystem, reconstructed on load by
## guessing from progress/queue-size -- promoted to real saved state
## because that guess had a genuine blind spot: it can't distinguish
## "checked, for the current direction" from "checked, for a direction
## that's since been replaced." Concretely, a river-crossing pause
## always freezes progress at exactly 0.5; if the player then swaps the
## queued direction WHILE paused (allowed -- the hex that triggered the
## crossing is queued_route[1], a cancellable destination, not the
## current hex), the inference had no way to know the check needs to
## run again for the new direction. Explicit state removes the guess
## entirely -- TravelSystem._on_new_exit_direction_known() resets this
## directly whenever the direction actually changes, whether or not
## that change also triggers a reversal.
@export var midpoint_event_checked: bool = false
