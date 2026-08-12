class_name InventoryBatch
extends RefCounted

## One acquisition of a perishable item. Non-perishable items never use this --
## they're stored as flat int counts directly in InventorySystem. Batches with
## the same item_id and the same acquired_minute are merged on add rather than
## kept separate (see InventorySystem._add_batch), so this only proliferates
## when food is actually picked up at different times.

var quantity: int = 0
var acquired_minute: int = 0

func _init(p_quantity: int = 0, p_acquired_minute: int = 0) -> void:
	quantity = p_quantity
	acquired_minute = p_acquired_minute
