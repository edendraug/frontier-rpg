class_name DebugTab
extends Control

## Base class for one tab inside the Debug Menu. To add a new tab:
##   1. Create a new script extending DebugTab (see debug/tabs/ for examples).
##   2. Override _ready() to construct your controls, same as any
##      other Control script in this project.
##   3. Override get_tab_title() to name the tab.
##   4. Optionally override refresh() to pull live data whenever this
##      tab becomes active or the menu is reopened.
##   5. Add your script's path to DebugMenu.TAB_SCRIPTS.
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


## Shown as this tab's label in the TabContainer.
func get_tab_title() -> String:
	return "Tab"


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
