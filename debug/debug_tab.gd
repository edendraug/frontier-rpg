class_name DebugTab
extends Control

## Base class for one tab inside the Debug Menu. To add a new tab:
##   1. Create a new script extending DebugTab (see debug/tabs/ for examples).
##   2. Override _ready() to construct your controls, same as any
##      other Control script in this project.
##   3. Override get_tab_title() to name the tab.
##   4. Optionally override refresh() to pull live data whenever this
##      tab becomes active or the menu is reopened.
##   5. Optionally override on_deactivated() for cleanup that
##      shouldn't linger once this tab is no longer the one showing
##      (e.g. hiding a 3D dice tray a roll spawned).
##   6. Add your script's path to DebugMenu.TAB_SCRIPTS.
## That's the whole extension point — DebugMenu itself never needs
## editing to add a tab. This is the modularity the menu was
## explicitly built for: as systems get deeper, new tabs bolt on
## independently rather than growing one increasingly tangled script.

## Called once immediately after the tab is built, and again every
## time it becomes the active tab or the menu is reopened — override
## to pull fresh data (e.g. re-read PartyManager's roster) rather than
## relying on whatever was true when the tab was first constructed.
func refresh() -> void:
	pass


## Called when this tab STOPS being the active one — either the user
## switched to a different tab, or closed the Debug Menu panel
## entirely. Override for cleanup that shouldn't outlive this tab
## being visible. Default no-op.
func on_deactivated() -> void:
	pass


## Shown as this tab's label in the TabContainer.
func get_tab_title() -> String:
	return "Tab"


## DebugTab is a plain Control, not a Container, so Godot never
## automatically sizes it to fit its content the way it would for a
## VBoxContainer -- it reports (0,0) by default regardless of how
## much is actually inside. That's invisible as long as a tab is a
## direct TabContainer child (TabContainer just stretches it to the
## available area, clipping whatever doesn't fit), but it breaks a
## wrapping ScrollContainer, which needs an honest minimum size to
## know there's overflow to scroll in the first place (see
## DebugMenu._populate_tabs()). This just forwards whatever the tab's
## own root container already computes correctly on its own.
##
## Every existing tab's _ready() builds a root VBoxContainer via
## set_anchors_preset(PRESET_FULL_RECT) -- that's a no-op once this
## tab sits under a Container (ScrollContainer/TabContainer both
## ignore child anchors and size children directly instead), so no
## individual tab file needs to change for this to work.
func _get_minimum_size() -> Vector2:
	if get_child_count() == 0:
		return Vector2.ZERO
	return get_child(0).get_combined_minimum_size()


## Small shared helper so tabs don't each reimplement it.
func _make_label(text: String, font_size: int = 13) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	return l


## ============================================================
## Shared party-member picker — several tabs (Party, Health, Skill
## Check) all need "pick one party member" as their first control.
## Kept here so that's one implementation, not three.
## ============================================================
func _build_member_option() -> OptionButton:
	var option := OptionButton.new()
	_refresh_member_option(option)
	return option


## Preserves the current selection by index across a refresh where
## possible, rather than always snapping back to the first member —
## matters if you're mid-testing a specific NPC and something else
## (an inflicted injury elsewhere) triggers a refresh.
func _refresh_member_option(option: OptionButton) -> void:
	var previous_index := option.selected
	option.clear()
	for sheet in PartyManager.get_roster():
		option.add_item(sheet.character_name)
	if option.item_count > 0:
		option.select(clampi(previous_index, 0, option.item_count - 1))


func _selected_member(option: OptionButton) -> CharacterSheet:
	var idx := option.selected
	var roster := PartyManager.get_roster()
	if idx < 0 or idx >= roster.size():
		return null
	return roster[idx]


## Consistent sign formatting, used anywhere a modifier/stat delta is
## shown — GDScript's % string formatting doesn't support a "+" flag
## the way C's printf does, so this is the manual equivalent.
func _signed(n) -> String:
	return ("+%s" % n) if n >= 0 else str(n)
