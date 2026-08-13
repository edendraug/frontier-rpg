extends Control

## Dev-only test harness for InventorySystem, same pattern as
## time_system_tester.gd and dice_check_tester.gd -- Control root, UI built
## via code, run as a standalone scene. Lives in dev/, not systems/.
##
## Stands in for a real Party/Travel system that doesn't exist yet: party
## size, vehicle capacity, and "equipped elsewhere" counts are all punched in
## by hand here rather than fed by anything real.

var _item_option: OptionButton
var _quantity_spin: SpinBox
var _stock_log: RichTextLabel

var _money_label: Label
var _money_spin: SpinBox

var _party_size_spin: SpinBox
var _vehicle_capacity_spin: SpinBox
var _equipped_elsewhere_spin: SpinBox
var _available_label: Label

var _weight_label: Label
var _status_label: Label

const STATUS_NAMES := ["Unencumbered", "Encumbered", "OVERLOADED"]


func _ready() -> void:
	_build_ui()
	InventorySystem.set_party_size(int(_party_size_spin.value))
	_refresh()


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	# --- Item add/remove ---
	var item_row := HBoxContainer.new()
	root.add_child(item_row)

	_item_option = OptionButton.new()
	for item in ItemRegistry.get_all_items():
		_item_option.add_item(item.display_name)
		_item_option.set_item_metadata(_item_option.item_count - 1, item.item_id)
	_item_option.item_selected.connect(func(_i): _refresh())
	item_row.add_child(_item_option)

	_quantity_spin = SpinBox.new()
	_quantity_spin.min_value = 1
	_quantity_spin.max_value = 999
	_quantity_spin.value = 1
	item_row.add_child(_quantity_spin)

	var add_btn := Button.new()
	add_btn.text = "Add"
	add_btn.pressed.connect(_on_add_pressed)
	item_row.add_child(add_btn)

	var remove_btn := Button.new()
	remove_btn.text = "Remove"
	remove_btn.pressed.connect(_on_remove_pressed)
	item_row.add_child(remove_btn)

	# --- Equipped-elsewhere override (manual stand-in for a Party roster) ---
	var equip_row := HBoxContainer.new()
	root.add_child(equip_row)

	var equip_label := Label.new()
	equip_label.text = "Equipped elsewhere (manual test value):"
	equip_row.add_child(equip_label)

	_equipped_elsewhere_spin = SpinBox.new()
	_equipped_elsewhere_spin.min_value = 0
	_equipped_elsewhere_spin.max_value = 99
	_equipped_elsewhere_spin.value_changed.connect(func(_v): _refresh())
	equip_row.add_child(_equipped_elsewhere_spin)

	_available_label = Label.new()
	equip_row.add_child(_available_label)

	root.add_child(HSeparator.new())

	# --- Money ---
	var money_row := HBoxContainer.new()
	root.add_child(money_row)

	_money_label = Label.new()
	money_row.add_child(_money_label)

	_money_spin = SpinBox.new()
	_money_spin.min_value = 0
	_money_spin.max_value = 9999
	_money_spin.value = 10
	money_row.add_child(_money_spin)

	var add_money_btn := Button.new()
	add_money_btn.text = "Add Money"
	add_money_btn.pressed.connect(func():
		InventorySystem.add_money(_money_spin.value)
		_refresh()
	)
	money_row.add_child(add_money_btn)

	var remove_money_btn := Button.new()
	remove_money_btn.text = "Remove Money"
	remove_money_btn.pressed.connect(func():
		if not InventorySystem.remove_money(_money_spin.value):
			print("Remove failed -- insufficient funds")
		_refresh()
	)
	money_row.add_child(remove_money_btn)

	root.add_child(HSeparator.new())

	# --- Party size / vehicle capacity ---
	var capacity_row := HBoxContainer.new()
	root.add_child(capacity_row)

	var party_label := Label.new()
	party_label.text = "Party Size:"
	capacity_row.add_child(party_label)

	_party_size_spin = SpinBox.new()
	_party_size_spin.min_value = 0
	_party_size_spin.max_value = 20
	_party_size_spin.value = 3
	_party_size_spin.value_changed.connect(func(v):
		InventorySystem.set_party_size(int(v))
		_refresh()
	)
	capacity_row.add_child(_party_size_spin)

	var vehicle_label := Label.new()
	vehicle_label.text = "Vehicle Capacity (-1 = none, override not additive):"
	capacity_row.add_child(vehicle_label)

	_vehicle_capacity_spin = SpinBox.new()
	_vehicle_capacity_spin.min_value = -1
	_vehicle_capacity_spin.max_value = 2000
	_vehicle_capacity_spin.value = -1
	_vehicle_capacity_spin.value_changed.connect(func(v):
		InventorySystem.set_vehicle_capacity(v)
		_refresh()
	)
	capacity_row.add_child(_vehicle_capacity_spin)

	root.add_child(HSeparator.new())

	_weight_label = Label.new()
	root.add_child(_weight_label)

	_status_label = Label.new()
	root.add_child(_status_label)

	root.add_child(HSeparator.new())

	_stock_log = RichTextLabel.new()
	_stock_log.custom_minimum_size = Vector2(520, 420)
	_stock_log.bbcode_enabled = true
	root.add_child(_stock_log)


func _selected_item_id() -> String:
	var idx := _item_option.selected
	if idx < 0:
		return ""
	return _item_option.get_item_metadata(idx)


func _on_add_pressed() -> void:
	var item_id := _selected_item_id()
	if item_id == "":
		return
	InventorySystem.add_item(item_id, int(_quantity_spin.value))
	_refresh()


func _on_remove_pressed() -> void:
	var item_id := _selected_item_id()
	if item_id == "":
		return
	if not InventorySystem.remove_item(item_id, int(_quantity_spin.value)):
		print("Remove failed -- insufficient quantity")
	_refresh()


func _refresh() -> void:
	_money_label.text = "Money: $%.2f" % InventorySystem.get_money()

	var weight := InventorySystem.get_total_weight()
	var max_cap := InventorySystem.get_max_capacity()
	_weight_label.text = "Weight: %.1f / %.1f lbs" % [weight, max_cap]

	var status := InventorySystem.get_weight_status()
	_status_label.text = "Status: %s" % STATUS_NAMES[status]

	var item_id := _selected_item_id()
	if item_id != "":
		var available := InventorySystem.get_available_quantity(
			item_id, int(_equipped_elsewhere_spin.value)
		)
		_available_label.text = "Available: %d" % available

	_stock_log.clear()
	_stock_log.append_text("[b]Party Inventory[/b]\n\n")

	for item in ItemRegistry.get_all_items():
		var qty := InventorySystem.get_quantity(item.item_id)
		if qty <= 0:
			continue

		if item.perishable:
			_stock_log.append_text("%s: %d total\n" % [item.display_name, qty])
			for batch in InventorySystem.get_batches(item.item_id):
				var freshness := InventorySystem.get_batch_freshness(batch, item.item_id)
				var label := InventorySystem.get_batch_display_name(batch, item.item_id)
				_stock_log.append_text(
					"    - %s x%d (%.0f%% fresh)\n" % [label, batch.quantity, freshness * 100.0]
				)
		else:
			_stock_log.append_text("%s: %d (%.1f lbs)\n" % [item.display_name, qty, item.weight * qty])
