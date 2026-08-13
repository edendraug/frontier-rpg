class_name TimeDebugTab
extends DebugTab

var _readout: Label
var _minutes_spin: SpinBox


func get_tab_title() -> String:
	return "Time"


func _ready() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	_readout = _make_label("")
	root.add_child(_readout)

	root.add_child(HSeparator.new())

	var quick_row := HBoxContainer.new()
	for entry in [["+30 min", 30], ["+1 hr", 60], ["+6 hr", 360], ["+1 day", 1440]]:
		var btn := Button.new()
		btn.text = entry[0]
		var minutes: int = entry[1]
		btn.pressed.connect(func(): _advance(minutes))
		quick_row.add_child(btn)
	root.add_child(quick_row)

	var custom_row := HBoxContainer.new()
	custom_row.add_child(_make_label("Custom (minutes):", 12))
	_minutes_spin = SpinBox.new()
	_minutes_spin.min_value = 1
	_minutes_spin.max_value = 100000
	_minutes_spin.value = 30
	custom_row.add_child(_minutes_spin)

	var advance_button := Button.new()
	advance_button.text = "Advance"
	advance_button.pressed.connect(func(): _advance(int(_minutes_spin.value)))
	custom_row.add_child(advance_button)
	root.add_child(custom_row)

	refresh()


func _advance(minutes: int) -> void:
	TimeSystem.pass_minutes(minutes)
	refresh()


func refresh() -> void:
	if _readout == null:
		return
	_readout.text = "%s\n%s, Day %d — %s, Year %d\nTotal minutes elapsed: %d" % [
		TimeFormatter.format_time_ampm(TimeSystem.get_current_hour(), TimeSystem.get_current_minute()),
		TimeFormatter.get_weekday_name(TimeSystem.get_day_of_week()),
		TimeSystem.get_day_of_month(),
		TimeFormatter.get_season_name(TimeSystem.get_current_season()),
		TimeSystem.get_current_year(),
		TimeSystem.get_total_minutes_elapsed(),
	]
