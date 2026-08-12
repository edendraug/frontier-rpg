extends Node

## Autoload. Read-only catalog of every ItemDefinition, parsed once from
## items.csv. Deliberately separate from InventorySystem: this holds static
## authored content (what items exist), InventorySystem holds mutable runtime
## state (what the party currently has). Same split as CharacterDataRegistry
## vs. an individual CharacterSheet.
##
## Register this BEFORE InventorySystem in Project Settings > Autoload, since
## InventorySystem looks items up here on every operation.

const ITEMS_CSV_PATH := "res://systems/inventory/data/items.csv"

var _items: Dictionary = {}  # item_id (String) -> ItemDefinition


func _ready() -> void:
	load_items()


func load_items() -> void:
	_items.clear()

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
	print("ItemRegistry: loaded %d items" % _items.size())


func _parse_row(headers: PackedStringArray, row: PackedStringArray) -> ItemDefinition:
	var fields := {}
	for i in headers.size():
		fields[headers[i]] = row[i] if i < row.size() else ""

	var item_id: String = fields.get("item_id", "").strip_edges()
	if item_id == "":
		return null  # skip blank/incomplete rows rather than failing the whole load

	var item := ItemDefinition.new()
	item.item_id = item_id
	item.display_name = fields.get("display_name", "")
	item.category = ItemDefinition.category_from_string(fields.get("category", ""))
	item.weight = float(fields.get("weight", "0"))
	item.value = float(fields.get("value", "0"))
	item.equippable = _to_bool(fields.get("equippable", ""))
	item.required_ammo_id = fields.get("required_ammo_id", "")
	item.perishable = _to_bool(fields.get("perishable", ""))

	var spoil_days := float(fields.get("spoil_days", "0"))
	item.spoil_minutes = int(spoil_days * TimeSystem.MINUTES_PER_DAY)

	item.meal_type = ItemDefinition.meal_type_from_string(fields.get("meal_type", ""))
	item.description = fields.get("description", "")

	return item


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
