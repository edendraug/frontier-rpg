class_name HexMapData
extends Resource

## Thin wrapper so the baked Dictionary[String, HexInstance] map can be
## saved/loaded as a single Resource file. Godot can't serialize a raw
## Dictionary as a standalone .tres on its own -- it needs to live as an
## @export field on some Resource subclass. Produced by the (not yet
## built) EditorScript bake step (design doc Section 7); loaded once by
## WorldRegistry at startup.
##
## NOT specified in the World Generation design doc -- Section 4.4
## describes "the baked HexInstance dictionary Resource" but never names
## or shapes the wrapper itself. This is a first pass at filling that
## gap. Flag if a different shape/name is wanted; either way this should
## get folded into a doc revision once confirmed.

@export var hexes: Dictionary = {}  # coord (String) -> HexInstance
