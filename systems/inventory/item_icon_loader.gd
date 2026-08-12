class_name ItemIconLoader
extends RefCounted

## Resolves an item's icon by filename convention: icons/<item_id>.png.
## Kept separate from ItemDefinition/ItemRegistry, same reasoning as
## TimeFormatter being split out from TimeSystem -- presentation concerns
## stay out of the data/logic layer.
##
## Falls back to a placeholder so art can lag behind data entry: adding a row
## to the CSV should never produce a broken UI just because nobody's drawn
## the sprite yet. Drop a _placeholder.png in the icons/ folder.

const ICON_DIR := "res://systems/inventory/icons/"
const PLACEHOLDER_ICON_PATH := ICON_DIR + "_placeholder.png"


static func get_icon(item_id: String) -> Texture2D:
	var path := "%s%s.png" % [ICON_DIR, item_id]
	if ResourceLoader.exists(path):
		return load(path)

	if ResourceLoader.exists(PLACEHOLDER_ICON_PATH):
		return load(PLACEHOLDER_ICON_PATH)

	return null
