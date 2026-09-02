extends Node

## Autoload. Read-only catalog of every ItemDefinition, parsed once from
## items.csv (universal fields, every category) and food_definitions.csv
## (food-only fields, merged in a second pass onto whichever items.csv rows
## are category FOOD). Deliberately separate from InventorySystem: this
## holds static authored content (what items exist), InventorySystem holds
## mutable runtime state (what the party currently has). Same split as
## CharacterDataRegistry vs. an individual CharacterSheet.
##
## Register this BEFORE InventorySystem in Project Settings > Autoload, since
## InventorySystem looks items up here on every operation.

const ITEMS_CSV_PATH := "res://systems/inventory/data/items.csv"
const FOOD_DEFINITIONS_CSV_PATH := "res://systems/inventory/data/food_definitions.csv"

var _items: Dictionary = {}  # item_id (String) -> ItemDefinition (or FoodDefinition)


func _ready() -> void:
	load_items()


func load_items() -> void:
	_items.clear()
	_load_base_items()
	_load_food_definitions()
	print("ItemRegistry: loaded %d items" % _items.size())


func _load_base_items() -> void:
	if not FileAccess.file_exists(ITEMS_CSV_PATH):
		push_warning("ItemRegistry: no items.csv found at %s" % ITEMS_CSV_PATH)
		return

	var file := FileAccess.open(ITEMS_CSV_PATH, FileAccess.READ)
	if file == null:
		push_error("ItemRegistry: failed to open items.csv")
		return

	var headers := file.get_csv_line()
	while not file.eof_reached():
		var row := file.get_csv_line()
		# Godot returns a single empty-string element for trailing blank lines.
		if row.size() <= 1 and (row.is_empty() or row[0] == ""):
			continue
		var item := _parse_row(headers, row)
		if item != null:
			if _items.has(item.item_id):
				push_warning("ItemRegistry: duplicate item_id '%s', overwriting" % item.item_id)
			_items[item.item_id] = item

	file.close()


func _parse_row(headers: PackedStringArray, row: PackedStringArray) -> ItemDefinition:
	var fields := {}
	for i in headers.size():
		fields[headers[i]] = row[i] if i < row.size() else ""

	var item_id: String = fields.get("item_id", "").strip_edges()
	if item_id == "":
		return null  # skip blank/incomplete rows rather than failing the whole load

	var category := ItemDefinition.category_from_string(fields.get("category", ""))

	# FOOD-category rows get the FoodDefinition subtype -- its food-only
	# fields are filled in by _load_food_definitions() below, in a second
	# pass over food_definitions.csv. See
	# Frontier_RPG_Food_Consumption_Design_Doc.md, Section 4.3.
	var item: ItemDefinition
	if category == ItemDefinition.Category.FOOD:
		item = FoodDefinition.new()
	else:
		item = ItemDefinition.new()

	item.item_id = item_id
	item.display_name = fields.get("display_name", "")
	item.category = category
	item.weight = float(fields.get("weight", "0"))
	item.value = float(fields.get("value", "0"))
	item.equippable = _to_bool(fields.get("equippable", ""))
	item.required_ammo_id = fields.get("required_ammo_id", "")
	item.description = fields.get("description", "")

	return item


## Second pass: fills in FoodDefinition's own fields by item_id. Permissive
## by default, same convention as every other missing-reference case in
## this project -- an unmatched row on either side gets a push_warning,
## never a hard failure.
func _load_food_definitions() -> void:
	if not FileAccess.file_exists(FOOD_DEFINITIONS_CSV_PATH):
		push_warning("ItemRegistry: no food_definitions.csv found at %s" % FOOD_DEFINITIONS_CSV_PATH)
		return

	var file := FileAccess.open(FOOD_DEFINITIONS_CSV_PATH, FileAccess.READ)
	if file == null:
		push_error("ItemRegistry: failed to open food_definitions.csv")
		return

	var headers := file.get_csv_line()
	var matched_ids := {}  # item_id -> true, used only to find the unmatched leftovers below

	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() <= 1 and (row.is_empty() or row[0] == ""):
			continue

		var fields := {}
		for i in headers.size():
			fields[headers[i]] = row[i] if i < row.size() else ""

		var item_id: String = fields.get("item_id", "").strip_edges()
		if item_id == "":
			continue

		var item: ItemDefinition = _items.get(item_id, null)
		if item == null:
			push_warning("ItemRegistry: food_definitions.csv row '%s' has no matching items.csv item" % item_id)
			continue
		if not (item is FoodDefinition):
			push_warning("ItemRegistry: food_definitions.csv row '%s' matches a non-FOOD item, ignoring" % item_id)
			continue

		var food := item as FoodDefinition
		food.nutrition_value = float(fields.get("nutrition_value", "0"))
		food.morale_value = float(fields.get("morale_value", "0"))
		food.morale_decay_per_hour = float(fields.get("morale_decay_per_hour", "0"))
		food.perishable = _to_bool(fields.get("perishable", ""))

		var spoil_days := float(fields.get("spoil_days", "0"))
		food.spoil_minutes = int(spoil_days * TimeSystem.MINUTES_PER_DAY)

		food.meal_type = FoodDefinition.meal_type_from_string(fields.get("meal_type", ""))
		matched_ids[item_id] = true

	file.close()

	# Reverse direction: a FOOD-category item with no food_definitions.csv
	# row at all keeps its zeroed defaults (harmless -- feed_character()
	# would restore 0 nutrition and apply no morale) but is still worth a
	# warning, since it likely means content was forgotten rather than
	# intentionally left blank.
	for item_id in _items:
		var item: ItemDefinition = _items[item_id]
		if item is FoodDefinition and not matched_ids.has(item_id):
			push_warning("ItemRegistry: FOOD item '%s' has no food_definitions.csv row" % item_id)


static func _to_bool(raw: String) -> bool:
	return raw.strip_edges().to_lower() in ["true", "1", "yes"]


func get_item(item_id: String) -> ItemDefinition:
	return _items.get(item_id, null)


func has_item_id(item_id: String) -> bool:
	return _items.has(item_id)


func get_all_items() -> Array[ItemDefinition]:
	var result: Array[ItemDefinition] = []
	for item in _items.values():
		result.append(item)
	return result


func get_items_by_category(category: ItemDefinition.Category) -> Array[ItemDefinition]:
	var result: Array[ItemDefinition] = []
	for item in _items.values():
		if item.category == category:
			result.append(item)
	return result
