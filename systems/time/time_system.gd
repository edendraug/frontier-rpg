extends Node
## TimeSystem — the game's central clock.
##
## NOT a real-time clock — nothing here runs on a timer or _process.
## Time is a resource other systems SPEND: every action that costs
## time (travel, an assignment, a dialogue exchange, resting) calls
## pass_minutes()/pass_hours()/pass_days() explicitly. Nothing
## advances on its own.
##
## SETUP: Project Settings > Autoload, add this script, name it
## "TimeSystem" — NOT "Time". Godot already has a built-in Time
## singleton (real-world/engine time); naming this the same would
## shadow it and cause confusion.
##
## Anything that needs to react to time passing (Hunger/Fatigue
## depletion, hourly random-encounter rolls, daily upkeep) should
## listen to hour_passed/day_passed below, rather than this system
## knowing about or calling into any of them directly — matches the
## "systems contribute, they don't reach into each other" philosophy
## used everywhere else in this project.
##
## Weather is deliberately NOT owned here — season is a pure function
## of elapsed time (so it belongs on this clock), but weather isn't;
## it's independently decided by something else and just correlates
## with time. That's a future Environment Manager's job, not this
## system's.
##
## DELIBERATELY OUT OF SCOPE HERE: nothing actually listens to these
## signals yet. Hunger/Fatigue depletion rates haven't been designed
## (see CharacterSheet), so wiring up a real consumer is natural
## follow-up work once those numbers exist — this system's job stops
## at "the clock exists and tells you when things change."

## ============================================================
## CALENDAR SHAPE — placeholder numbers, same as everywhere else
## in this project. Change freely; nothing else hardcodes these.
## ============================================================
const MINUTES_PER_HOUR := 60
const HOURS_PER_DAY := 24
const MINUTES_PER_DAY := MINUTES_PER_HOUR * HOURS_PER_DAY   # 1440

const DAYS_PER_WEEK := 7
const DAYS_PER_MONTH := 28      # 4 even weeks — deliberately clean, not "realistic"
const MONTHS_PER_YEAR := 12     # 3 months per season
const DAYS_PER_YEAR := DAYS_PER_MONTH * MONTHS_PER_YEAR      # 336

## Actions should generally cost multiples of this, per the design
## brief — not enforced here, just the intended smallest granularity.
const MINUTES_PER_INCREMENT := 30

## A single time-skip larger than this is almost certainly a bug in
## the calling code rather than an intentional jump — warn, don't block.
const LARGE_SKIP_WARNING_MINUTES := DAYS_PER_MONTH * MINUTES_PER_DAY

enum Season { SPRING, SUMMER, FALL, WINTER }

## Fired once for EACH hour boundary crossed by a time-skip, in
## order — pass_hours(3) fires this 3 times, not once. Lets anything
## listening (e.g. a future "roll for random encounter every hour
## of travel") react per-hour even when one action skips several at once.
signal hour_passed(hour_of_day: int, day: int)

## Fired once for EACH day boundary crossed, same reasoning.
signal day_passed(day: int)

## Source of truth. Everything else (day/hour/week/month/season) is
## derived from this — never set directly, always go through
## pass_minutes()/pass_hours()/pass_days().
var _total_minutes_elapsed: int = 0


## ============================================================
## ADVANCING TIME
## ============================================================
func pass_minutes(minutes: int) -> void:
	if minutes <= 0:
		push_warning("TimeSystem: pass_minutes() called with non-positive value (%d), ignoring." % minutes)
		return
	if minutes > LARGE_SKIP_WARNING_MINUTES:
		push_warning("TimeSystem: pass_minutes(%d) is a very large single skip — is this intentional?" % minutes)

	var old_total := _total_minutes_elapsed
	_total_minutes_elapsed += minutes

	var old_hour_index := old_total / MINUTES_PER_HOUR
	var new_hour_index := _total_minutes_elapsed / MINUTES_PER_HOUR
	for h in range(old_hour_index + 1, new_hour_index + 1):
		hour_passed.emit(h % HOURS_PER_DAY, (h / HOURS_PER_DAY) + 1)

	var old_day_index := old_total / MINUTES_PER_DAY
	var new_day_index := _total_minutes_elapsed / MINUTES_PER_DAY
	for d in range(old_day_index + 1, new_day_index + 1):
		day_passed.emit(d + 1)


func pass_hours(hours: int) -> void:
	pass_minutes(hours * MINUTES_PER_HOUR)


func pass_days(days: int) -> void:
	pass_minutes(days * MINUTES_PER_DAY)


## ============================================================
## READING TIME — everything below is derived, nothing is stored.
## ============================================================
func get_total_minutes_elapsed() -> int:
	return _total_minutes_elapsed


## 1-indexed — "Day 1" at campaign start.
func get_current_day() -> int:
	return (_total_minutes_elapsed / MINUTES_PER_DAY) + 1


func get_current_hour() -> int:
	return (_total_minutes_elapsed / MINUTES_PER_HOUR) % HOURS_PER_DAY


func get_current_minute() -> int:
	return _total_minutes_elapsed % MINUTES_PER_HOUR


func _get_day_index() -> int:
	return _total_minutes_elapsed / MINUTES_PER_DAY


func get_day_of_week() -> int:
	return _get_day_index() % DAYS_PER_WEEK


func get_current_week() -> int:
	return (_get_day_index() / DAYS_PER_WEEK) + 1


func get_current_year() -> int:
	return (_get_day_index() / DAYS_PER_YEAR) + 1


func _get_day_of_year() -> int:
	return _get_day_index() % DAYS_PER_YEAR


func get_current_month() -> int:
	return (_get_day_of_year() / DAYS_PER_MONTH) + 1


func get_day_of_month() -> int:
	return (_get_day_of_year() % DAYS_PER_MONTH) + 1


func get_current_season() -> Season:
	var month := get_current_month()
	var months_per_season := MONTHS_PER_YEAR / 4
	var season_index: int = (month - 1) / months_per_season
	return season_index
