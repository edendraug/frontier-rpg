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
##
## SIZING: the panel used to be a hardcoded 510x370 Panel, which
## clipped several tabs' content with no way to reach it. Fixed two
## ways now: each tab is wrapped in a vertical-only ScrollContainer
## (see _populate_tabs()) so genuine overflow scrolls instead of
## clipping, and the panel's WIDTH is measured against the widest
## tab's actual content and sized to fit it (see
## _resize_panel_to_content()) rather than guessed at. Height stays a
## fixed value (just a bigger one than before) rather than also being
## content-driven -- unlike width, tab content height varies a lot
## between tabs, and letting the panel grow to fit the tallest one
## would make every OTHER tab needlessly tall. The ScrollContainer is
## what actually absorbs that difference.

const LAYER := 20

const TAB_SCRIPTS: Array[String] = [
	"res://debug/tabs/time_debug_tab.gd",
	"res://debug/tabs/party_debug_tab.gd",
	"res://debug/tabs/health_debug_tab.gd",
	"res://debug/tabs/skill_check_debug_tab.gd",
	"res://debug/tabs/inventory_debug_tab.gd",
	"res://debug/tabs/dialogue_debug_tab.gd",
	"res://debug/tabs/relations_debug_tab.gd",
	"res://debug/tabs/save_debug_tab.gd",
]

const PANEL_LEFT_MARGIN := 10.0
const PANEL_BOTTOM_MARGIN := 50.0    # leaves room for the toggle button below it
const PANEL_TOP_SAFETY_MARGIN := 40.0  # never let the panel run past the top of a short window

const MIN_PANEL_WIDTH := 320.0
const MAX_PANEL_WIDTH_FRACTION := 0.9  # of viewport width -- a hard ceiling regardless of content
const CONTENT_WIDTH_PADDING := 32.0    # MarginContainer's 8px/side (see _build_ui) plus a little slack

const DEFAULT_PANEL_HEIGHT := 450.0    # up from the old fixed 370 -- "expand vertical slightly"
const MIN_PANEL_HEIGHT := 240.0

var _panel: Panel
var _tab_container: TabContainer
var _tabs: Array[DebugTab] = []
var _last_active_tab_index: int = -1


func _ready() -> void:
	layer = LAYER
	_build_ui()
	_populate_tabs()
	_resize_panel_to_content()


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

	# The floating panel itself — bottom-left. anchor_bottom is now set
	# explicitly to 1.0 alongside anchor_top (it previously defaulted
	# to 0.0, which inverted the vertical box math -- both edges need
	# to anchor to the SAME reference point, the viewport bottom, for
	# offset_top/offset_bottom to describe a sane height below it).
	# Actual width/height offsets are placeholders here and get
	# overwritten by _resize_panel_to_content() once tab content
	# exists -- these just avoid a zero-size flash before that runs.
	_panel = Panel.new()
	_panel.anchor_left = 0.0
	_panel.anchor_right = 0.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = PANEL_LEFT_MARGIN
	_panel.offset_right = PANEL_LEFT_MARGIN + MIN_PANEL_WIDTH
	_panel.offset_top = -(DEFAULT_PANEL_HEIGHT + PANEL_BOTTOM_MARGIN)
	_panel.offset_bottom = -PANEL_BOTTOM_MARGIN
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

		# Wrapped in a ScrollContainer rather than added to the
		# TabContainer directly, so a tab whose content is taller than
		# the panel scrolls instead of clipping off the bottom.
		# Horizontal scroll stays disabled on purpose -- the panel's
		# WIDTH is sized to fit the widest tab (see
		# _resize_panel_to_content()), so horizontal overflow shouldn't
		# occur; SIZE_EXPAND_FILL just lets narrower tabs stretch to
		# fill that width rather than sitting left-aligned and cramped.
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.add_child(tab)

		_tab_container.add_child(scroll)  # this is what actually triggers the tab's own _ready(), building its UI
		_tab_container.set_tab_title(_tab_container.get_child_count() - 1, tab.get_tab_title())
		_tabs.append(tab)

	if not _tabs.is_empty():
		_last_active_tab_index = 0
		_tabs[0].refresh()


## Measures the widest tab's real minimum width (now that DebugTab
## reports one honestly -- see debug_tab.gd) and sizes the panel to
## fit it, clamped between a sane floor and a fraction of the actual
## viewport width so it can never run off both edges of the screen.
## Deliberately a ONE-TIME measurement at startup, not something that
## re-runs every refresh -- content that changes width at runtime
## (e.g. a longer roster widening the member dropdown) won't trigger
## a resize. Fine for now; revisit if that turns out to matter.
func _resize_panel_to_content() -> void:
	# Godot's minimum-size cache can lag a frame behind construction in
	# some cases (theme/font metric resolution), so this waits one
	# frame before measuring rather than trusting a same-frame read.
	await get_tree().process_frame

	var viewport_size := get_viewport().get_visible_rect().size

	var content_width := 0.0
	for tab in _tabs:
		content_width = maxf(content_width, tab.get_combined_minimum_size().x)

	var panel_width := content_width + CONTENT_WIDTH_PADDING
	panel_width = clampf(panel_width, MIN_PANEL_WIDTH, viewport_size.x * MAX_PANEL_WIDTH_FRACTION)

	var panel_height := clampf(
		DEFAULT_PANEL_HEIGHT, MIN_PANEL_HEIGHT, viewport_size.y - PANEL_BOTTOM_MARGIN - PANEL_TOP_SAFETY_MARGIN
	)

	_panel.offset_right = PANEL_LEFT_MARGIN + panel_width
	_panel.offset_top = -(panel_height + PANEL_BOTTOM_MARGIN)
	_panel.offset_bottom = -PANEL_BOTTOM_MARGIN


func _on_tab_changed(index: int) -> void:
	if _last_active_tab_index >= 0 and _last_active_tab_index < _tabs.size() and _last_active_tab_index != index:
		_tabs[_last_active_tab_index].on_deactivated()

	_last_active_tab_index = index
	if index >= 0 and index < _tabs.size():
		_tabs[index].refresh()


func _on_toggle_pressed() -> void:
	_panel.visible = not _panel.visible

	if _panel.visible:
		if _tab_container.current_tab < _tabs.size():
			_tabs[_tab_container.current_tab].refresh()
	else:
		# Closing the panel deactivates whatever tab was showing, even
		# though the TabContainer's current_tab index doesn't itself
		# change -- the tab is no longer VISIBLE, which is what matters.
		if _last_active_tab_index >= 0 and _last_active_tab_index < _tabs.size():
			_tabs[_last_active_tab_index].on_deactivated()
