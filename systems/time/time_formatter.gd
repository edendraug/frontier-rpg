class_name TimeFormatter
extends RefCounted

## Pure display formatting for TimeSystem's raw values. Kept
## separate from TimeSystem itself so the clock stays pure logic —
## 12-hour vs 24-hour display and invented in-world day names are
## presentation choices, not clock facts, and shouldn't constrain
## what TimeSystem tracks. Centralized here rather than duplicated
## per-screen so every future UI (HUD, journal, dialogue timestamps)
## formats time identically without re-inventing these tables.
##
## Name lists below are placeholders, same as everywhere else
## content is still a stand-in — a good opportunity for real
## frontier-flavored day/season names once that's worth doing.

const WEEKDAY_NAMES := [
	"Monday", "Tuesday", "Wednesday", "Thursday",
	"Friday", "Saturday", "Sunday",
]

const SEASON_NAMES := ["Spring", "Summer", "Fall", "Winter"]

const MONTH_NAMES := [
	"January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December",
]


## day_of_week: 0-6, matches TimeSystem.get_day_of_week()
static func get_weekday_name(day_of_week: int) -> String:
	return WEEKDAY_NAMES[day_of_week]


static func get_season_name(season: TimeSystem.Season) -> String:
	return SEASON_NAMES[season]


## month: 1-12, matches TimeSystem.get_current_month()
static func get_month_name(month: int) -> String:
	return MONTH_NAMES[month - 1]


## hour_24: 0-23, matches TimeSystem.get_current_hour()
static func format_time_ampm(hour_24: int, minute: int) -> String:
	var period := "AM" if hour_24 < 12 else "PM"
	var hour_12 := hour_24 % 12
	if hour_12 == 0:
		hour_12 = 12
	return "%d:%02d %s" % [hour_12, minute, period]
