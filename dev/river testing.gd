extends Node

func _ready():
	print(WorldRegistry.requires_river_crossing("-2,1", 2, 4))  # expect false
	print(WorldRegistry.requires_river_crossing("-2,1", 4, 0))  # expect true
