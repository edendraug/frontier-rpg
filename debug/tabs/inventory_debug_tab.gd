class_name InventoryDebugTab
extends DebugTab

var _item_option: OptionButton
var _quantity_spin: SpinBox
var _money_spin: SpinBox
var _vehicle_spin: SpinBox
var _readout: Label


func get_tab_title() -> String:
	return "Inventory"


func _ready() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	_readout = _make_label("")
	root.add_child(_readout)
	root.add_child(HSeparator.new())

	var item_row := HBoxContainer.new()
	_item_option = OptionButton.new()
	for item in ItemRegistry.get_all_items():
		_item_option.add_item(item.display_name)
		_item_option.set_item_metadata(_item_option.item_count - 1, item.item_id)
	item_row.add_child(_item_option)

	_quantity_spin = SpinBox.new()
	_quantity_spin.min_value = 1
	_quantity_spin.max_value = 999
	_quantity_spin.value = 1
	item_row.add_child(_quantity_spin)
	root.add_child(item_row)

	var item_button_row := HBoxContainer.new()
	var add_button := Button.new()
	add_button.text = "Add"
	add_button.pressed.connect(_on_add_item_pressed)
	item_button_row.add_child(add_button)

	var remove_button := Button.new()
	remove_button.text = "Remove"
	remove_button.pressed.connect(_on_remove_item_pressed)
	item_button_row.add_child(remove_button)
	root.add_child(item_button_row)

	root.add_child(HSeparator.new())

	var money_row := HBoxContainer.new()
	money_row.add_child(_make_label("Money:", 12))
	_money_spin = SpinBox.new()
	_money_spin.min_value = 0
	_money_spin.max_value = 99999
	_money_spin.value = 50
	money_row.add_child(_money_spin)

	var add_money_button := Button.new()
	add_money_button.text = "Add Money"
	add_money_button.pressed.connect(func():
		InventorySystem.add_money(_money_spin.value)
		refresh()
	)
	money_row.add_child(add_money_button)
	root.add_child(money_row)

	root.add_child(HSeparator.new())

	var vehicle_row := HBoxContainer.new()
	vehicle_row.add_child(_make_label("Vehicle Capacity:", 12))
	_vehicle_spin = SpinBox.new()
	_vehicle_spin.min_value = 0
	_vehicle_spin.max_value = 5000
	_vehicle_spin.value = 400
	vehicle_row.add_child(_vehicle_spin)

	var set_vehicle_button := Button.new()
	set_vehicle_button.text = "Set Vehicle"
	set_vehicle_button.pressed.connect(func():
		InventorySystem.set_vehicle_capacity(_vehicle_spin.value)
		refresh()
	)
	vehicle_row.add_child(set_vehicle_button)

	var clear_vehicle_button := Button.new()
	clear_vehicle_button.text = "Clear Vehicle"
	clear_vehicle_button.pressed.connect(func():
		InventorySystem.clear_vehicle()
		refresh()
	)
	vehicle_row.add_child(clear_vehicle_button)
	root.add_child(vehicle_row)

	refresh()


func _selected_item_id() -> String:
	var idx := _item_option.selected
	if idx < 0:
		return ""
	return _item_option.get_item_metadata(idx)


func _on_add_item_pressed() -> void:
	var item_id := _selected_item_id()
	if item_id == "":
		return
	InventorySystem.add_item(item_id, int(_quantity_spin.value))
	refresh()


func _on_remove_item_pressed() -> void:
	var item_id := _selected_item_id()
	if item_id == "":
		return
	InventorySystem.remove_item(item_id, int(_quantity_spin.value))
	refresh()


func refresh() -> void:
	if _readout == null:
		return
	var status_names := ["Unencumbered", "Encumbered", "OVERLOADED"]
	var vehicle_text := "none"
	if InventorySystem.has_vehicle():
		vehicle_text = "%.0f lbs" % InventorySystem.get_vehicle_capacity()

	_readout.text = "Money: $%.2f\nWeight: %.1f / %.1f lbs (%s)\nVehicle: %s" % [
		InventorySystem.get_money(),
		InventorySystem.get_total_weight(),
		InventorySystem.get_max_capacity(),
		status_names[InventorySystem.get_weight_status()],
		vehicle_text,
	]
