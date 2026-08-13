extends Control
## Time System Tester (Prototype).
##
## SETUP: create a new empty scene with a Control node as the root,
## attach this script, and run it. Requires TimeSystem to already be
## registered as an autoload.
##
## Shows the full derived calendar readout, buttons for common time
## skips, a custom-minute input for edge-case testing, and a live
## log of every hour_passed/day_passed signal TimeSystem fires. The
## log is the important part — it's the easiest way to confirm a
## multi-hour/multi-day skip fires the right NUMBER of boundary
## signals (e.g. pass_hours(3) should log hour_passed exactly 3
## times), not just that the readout updated correctly.

var readout_label: RichTextLabel
var log_output: RichTextLabel
var custom_minutes_spin: SpinBox


func _ready() -> void:
	TimeSystem.hour_passed.connect(_on_hour_passed)
	TimeSystem.day_passed.connect(_on_day_passed)

	_build_ui()
	_refresh_readout()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 12)
	add_child(root)

	root.add_child(_make_label("Time System Tester (Prototype)", 20))

	readout_label = RichTextLabel.new()
	readout_label.bbcode_enabled = true
	readout_label.fit_content = true
	readout_label.custom_minimum_size = Vector2(0, 140)
	root.add_child(readout_label)

	root.add_child(_make_label("Quick Skips", 14))
	var quick_row := HBoxContainer.new()
	quick_row.add_theme_constant_override("separation", 8)
	quick_row.add_child(_make_skip_button("+30 min", func(): TimeSystem.pass_minutes(30)))
	quick_row.add_child(_make_skip_button("+1 hour", func(): TimeSystem.pass_hours(1)))
	quick_row.add_child(_make_skip_button("+8 hours", func(): TimeSystem.pass_hours(8)))
	quick_row.add_child(_make_skip_button("+1 day", func(): TimeSystem.pass_days(1)))
	quick_row.add_child(_make_skip_button("+1 week", func(): TimeSystem.pass_days(7)))
	root.add_child(quick_row)

	root.add_child(_make_label("Custom Skip (minutes) — good for edge-case testing", 14))
	var custom_row := HBoxContainer.new()
	custom_row.add_theme_constant_override("separation", 8)

	custom_minutes_spin = SpinBox.new()
	custom_minutes_spin.min_value = 1
	custom_minutes_spin.max_value = 100000
	custom_minutes_spin.value = 90
	custom_row.add_child(custom_minutes_spin)

	var custom_button := Button.new()
	custom_button.text = "Advance"
	custom_button.pressed.connect(func():
		TimeSystem.pass_minutes(int(custom_minutes_spin.value))
		_refresh_readout()
	)
	custom_row.add_child(custom_button)
	root.add_child(custom_row)

	var clear_button := Button.new()
	clear_button.text = "Clear Log"
	clear_button.pressed.connect(func(): log_output.text = "")
	root.add_child(clear_button)

	root.add_child(_make_label("Signal Log", 14))
	log_output = RichTextLabel.new()
	log_output.bbcode_enabled = true
	log_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_output.custom_minimum_size = Vector2(0, 260)
	root.add_child(log_output)


func _make_label(text: String, font_size: int = 14) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	return l


func _make_skip_button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func():
		on_pressed.call()
		_refresh_readout()
	)
	return b


func _refresh_readout() -> void:
	var season_name: String = TimeFormatter.get_season_name(TimeSystem.get_current_season())
	var weekday_name: String = TimeFormatter.get_weekday_name(TimeSystem.get_day_of_week())
	var month_name: String = TimeFormatter.get_month_name(TimeSystem.get_current_month())
	var time_str: String = TimeFormatter.format_time_ampm(TimeSystem.get_current_hour(), TimeSystem.get_current_minute())

	var lines: Array = []
	lines.append("[b]Total minutes elapsed:[/b] %d" % TimeSystem.get_total_minutes_elapsed())
	lines.append("[b]Time:[/b] %s" % time_str)
	lines.append("[b]Day:[/b] %d — %s, %s %d  (Week %d)" % [
		TimeSystem.get_current_day(),
		weekday_name,
		month_name,
		TimeSystem.get_day_of_month(),
		TimeSystem.get_current_week(),
	])
	lines.append("[b]Year:[/b] %d" % TimeSystem.get_current_year())
	lines.append("[b]Season:[/b] %s" % season_name)

	readout_label.text = "\n".join(lines)


func _on_hour_passed(hour_of_day: int, day: int) -> void:
	log_output.append_text("[color=#88CCFF]hour_passed[/color] → hour %02d, day %d\n" % [hour_of_day, day])


func _on_day_passed(day: int) -> void:
	log_output.append_text("[color=#FFD700]day_passed[/color] → day %d\n" % day)
