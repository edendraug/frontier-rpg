extends CanvasLayer
class_name DebugMenu

## Floating, toggleable debug/testing menu. Instantiate into any
## gameplay scene via DebugMenu.new() + add_child() — no .tscn needed,
## same "build via code" convention used everywhere except Expedition
## Hub itself.
##
## Lives in its own CanvasLayer (see LAYER below), so it always
## renders and receives input ABOVE the Party/Inventory/Escape
## overlays, regardless of what else is open. It's deliberately
## orthogonal to their "only one open at a time" rule — a dev tool
## should stay usable no matter what else is on screen.
##
## MODULAR BY DESIGN: this script should never need to grow to
## support new debug functionality. Add a tab by writing a new
## DebugTab subclass (see debug_tab.gd) and adding its path below —
## that's the entire extension point.

const LAYER := 20

const TAB_SCRIPTS: Array[String] = [
	"res://debug/tabs/time_debug_tab.gd",
	"res://debug/tabs/party_debug_tab.gd",
	"res://debug/tabs/health_debug_tab.gd",
	"res://debug/tabs/skill_check_debug_tab.gd",
	"res://debug/tabs/inventory_debug_tab.gd",
	"res://debug/tabs/save_debug_tab.gd",
]

var _panel: Panel
var _tab_container: TabContainer
var _tabs: Array[DebugTab] = []


func _ready() -> void:
	layer = LAYER
	_build_ui()
	_populate_tabs()


func _build_ui() -> void:
	# Always-visible toggle, pinned to the bottom-LEFT corner — matches
	# the panel's own position below. Fixed anchor + offset, not a
	# preset, so it stays correct without depending on sibling content
	# size.
	var toggle_button := Button.new()
	toggle_button.text = "Debug"
	toggle_button.anchor_left = 0.0
	toggle_button.anchor_right = 0.0
	toggle_button.anchor_top = 1.0
	toggle_button.anchor_bottom = 1.0
	toggle_button.offset_left = 10
	toggle_button.offset_top = -40
	toggle_button.offset_right = 80
	toggle_button.offset_bottom = -10
	toggle_button.pressed.connect(_on_toggle_pressed)
	add_child(toggle_button)

	# The floating panel itself — bottom-left, fixed size, starts hidden.
	_panel = Panel.new()
	_panel.anchor_left = 0.0
	_panel.anchor_top = 1.0
	_panel.offset_left = 10
	_panel.offset_top = -420
	_panel.offset_right = 520
	_panel.offset_bottom = -50
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 8)
	_panel.add_child(margin)

	var content := VBoxContainer.new()
	margin.add_child(content)

	var title := Label.new()
	title.text = "Debug Menu"
	title.add_theme_font_size_override("font_size", 16)
	content.add_child(title)

	_tab_container = TabContainer.new()
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_container.tab_changed.connect(_on_tab_changed)
	content.add_child(_tab_container)


func _populate_tabs() -> void:
	for path in TAB_SCRIPTS:
		var script: Script = load(path)
		var tab: DebugTab = script.new()
		_tab_container.add_child(tab)  # triggers the tab's own _ready(), building its UI
		_tab_container.set_tab_title(_tab_container.get_child_count() - 1, tab.get_tab_title())
		_tabs.append(tab)

	if not _tabs.is_empty():
		_tabs[0].refresh()


func _on_tab_changed(index: int) -> void:
	if index >= 0 and index < _tabs.size():
		_tabs[index].refresh()


func _on_toggle_pressed() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible and _tab_container.current_tab < _tabs.size():
		_tabs[_tab_container.current_tab].refresh()
