extends Node

## Autoload. The only system that reaches into PartyManager,
## InventorySystem, and TimeSystem simultaneously -- none of them save
## themselves, same reasoning as why ModifierResolver gathers from
## CharacterSheet rather than the other way around.
##
## Register in Project Settings > Autoload AFTER PartyManager (and
## therefore after TimeSystem/ItemRegistry/InventorySystem too, since
## PartyManager already depends on InventorySystem).
##
## Saves are .tres -- human-readable, matches every other data file in
## this project, and there's no shipped build yet to worry about
## protecting a save file from casual editing. If/when that matters,
## revisit the format then (see the .tres/.res/encryption discussion --
## export encryption doesn't cover user:// at all regardless of format,
## so this isn't a decision that can be deferred by picking .res today).

signal save_completed(slug: String)
signal save_failed(slot_name: String, reason: String)
signal load_completed(slug: String)
signal load_failed(slug: String, reason: String)

const SAVE_DIR := "user://saves/"

## Placeholder/tunable, same treatment as everywhere else in this
## project. -1 = unlimited, which is what we want during development.
## Set to 3 for a shipped build.
const MAX_SAVE_SLOTS := -1

## Which save file THIS SESSION is tied to, if any. Set by a
## successful load_game(), or by the first successful save_game() of
## a fresh session. Once set, every later save_game() call updates
## THIS file rather than minting a new one -- one save per expedition,
## not one per Begin Expedition click. Cleared explicitly via
## clear_active_save(), which Main Menu's "New Game" calls, so a
## genuinely new expedition doesn't silently overwrite whatever the
## previous session was playing.
var _current_save_slug: String = ""
var _current_save_name: String = ""


func has_active_save() -> bool:
	return _current_save_slug != ""


func get_active_save_slug() -> String:
	return _current_save_slug


func get_active_save_name() -> String:
	return _current_save_name


## Called when starting a genuinely new expedition (Main Menu > New
## Game) so the next save_game() call establishes a fresh file
## instead of overwriting whatever the previous session had active.
func clear_active_save() -> void:
	_current_save_slug = ""
	_current_save_name = ""


func save_game(slot_name: String = "") -> String:
	# Already tied to a file this session -- every further save updates
	# THAT file, ignoring slot_name entirely. This is the one-save-per-
	# expedition rule: slot_name only matters the very first time.
	if _current_save_slug != "":
		return _write_save(_current_save_slug, _current_save_name)

	var display_name := slot_name.strip_edges()
	if display_name == "":
		display_name = _current_timestamp_string()
	var slug := _slugify(display_name)
	var path := SAVE_DIR + slug + ".tres"

	if MAX_SAVE_SLOTS > 0 and not FileAccess.file_exists(path) and list_saves().size() >= MAX_SAVE_SLOTS:
		var reason := "Save slot cap (%d) reached" % MAX_SAVE_SLOTS
		push_warning("SaveManager: %s" % reason)
		save_failed.emit(slot_name, reason)
		return ""

	var result := _write_save(slug, display_name)
	if result != "":
		_current_save_slug = slug
		_current_save_name = display_name
	return result


## Actually writes the file -- shared by both the "first save of a
## session" and "updating the already-active save" paths above, so
## there's only one place that assembles a GameSaveData from live
## state. created_at is always "now" here rather than preserved from
## a prior write, so it reads as "last saved at" -- more useful for
## sorting a load list by recency than a frozen creation timestamp
## would be, at the cost of not literally tracking when the
## expedition first began. save_name IS preserved across overwrites
## via the _current_save_name argument, though, so a save's display
## name never silently changes just because of a later re-save.
func _write_save(slug: String, display_name: String) -> String:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := SAVE_DIR + slug + ".tres"

	var data := GameSaveData.new()
	data.save_name = display_name
	data.created_at = _current_timestamp_string()
	data.party = PartyManager.get_roster()
	data.inventory_stock = InventorySystem.get_stock_snapshot()
	data.inventory_batches = InventorySystem.get_batches_snapshot()
	data.money = InventorySystem.get_money()
	data.vehicle_capacity = InventorySystem.get_vehicle_capacity()
	data.total_minutes_elapsed = TimeSystem.get_total_minutes_elapsed()

	var err := ResourceSaver.save(data, path)
	if err != OK:
		var reason := "ResourceSaver error %d" % err
		push_error("SaveManager: save failed for slot '%s' (%s)" % [slug, reason])
		save_failed.emit(display_name, reason)
		return ""

	save_completed.emit(slug)
	return slug


func load_game(slug: String) -> bool:
	var path := SAVE_DIR + slug + ".tres"

	if not FileAccess.file_exists(path):
		var reason := "File not found"
		push_warning("SaveManager: no save found for slot '%s'" % slug)
		load_failed.emit(slug, reason)
		return false

	var data := load(path) as GameSaveData
	if data == null:
		var reason := "Load failed or file is not valid GameSaveData"
		push_error("SaveManager: %s (slot '%s')" % [reason, slug])
		load_failed.emit(slug, reason)
		return false

	PartyManager.load_roster(data.party)
	InventorySystem.load_state(
		data.inventory_stock, data.inventory_batches, data.money, data.vehicle_capacity
	)
	# party_size is deliberately not a saved field -- always re-derive
	# from the loaded roster, same as begin_expedition() already does,
	# so the two can never drift apart.
	InventorySystem.set_party_size(PartyManager.get_party_size())
	TimeSystem.set_total_minutes_elapsed(data.total_minutes_elapsed)

	_current_save_slug = slug
	_current_save_name = data.save_name

	load_completed.emit(slug)
	return true


## Returns Array[Dictionary], each {slug, save_name, created_at, party_size},
## newest first. A slot-list UI reads this directly rather than scanning
## the save directory itself.
func list_saves() -> Array:
	var results: Array = []

	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return results

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var data := load(SAVE_DIR + file_name) as GameSaveData
			if data != null:
				results.append({
					"slug": file_name.trim_suffix(".tres"),
					"save_name": data.save_name,
					"created_at": data.created_at,
					"party_size": data.party.size(),
				})
		file_name = dir.get_next()
	dir.list_dir_end()

	# created_at is Godot's "YYYY-MM-DD HH:MM:SS" datetime string, which
	# sorts correctly as plain text -- no need to parse it into a real
	# date to order newest-first.
	results.sort_custom(func(a, b): return a["created_at"] > b["created_at"])
	return results


func delete_save(slug: String) -> bool:
	var path := SAVE_DIR + slug + ".tres"
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(path) == OK


func _current_timestamp_string() -> String:
	return Time.get_datetime_string_from_system(false, true)  # real-world time, "YYYY-MM-DD HH:MM:SS"


## Filename-safe slug: lowercase, spaces to underscores, anything else
## unsafe for a filename (colons from a timestamp, punctuation from a
## player-typed name) stripped outright.
func _slugify(text: String) -> String:
	var slug := text.strip_edges().to_lower().replace(" ", "_")

	var regex := RegEx.new()
	regex.compile("[^a-z0-9_\\-]")
	slug = regex.sub(slug, "", true)

	if slug == "":
		slug = "save_%d" % Time.get_unix_time_from_system()
	return slug
