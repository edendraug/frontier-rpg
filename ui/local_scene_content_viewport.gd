extends SubViewport

## Tags this SubViewport as Expedition Hub's current slot for
## locally-loaded scene content (a room built on LocalSceneRoot).
## LocalSceneManager finds it via this group rather than a hardcoded
## path, so expedition_hub.gd never needs to know LocalSceneManager
## exists -- deliberate, since expedition_hub is flagged as a
## temporary/dev-only screen likely to be reworked or replaced later,
## and this keeps the coupling one-directional.
##
## Attach directly to the %LocalSceneViewport node in expedition_hub.tscn.

func _ready() -> void:
	add_to_group("local_scene_content_viewport")
