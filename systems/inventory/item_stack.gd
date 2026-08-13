class_name ItemStack
extends Resource

## A simple (item_id, quantity) pair -- NOT a live inventory record. Used
## anywhere something needs to describe "N of item X" as authored/static
## data rather than actual party-held state. InventoryBatch (a real,
## time-stamped, mutable holding) is the analogous concept for that, and is
## deliberately RefCounted since it never gets saved on its own.
##
## ItemStack IS a Resource, not RefCounted, specifically so it can be saved
## as an @export sub-resource -- same pattern ModifierEntry already uses for
## TraitDefinition.modifiers. Primary consumer:
## OccupationDefinition.starting_gear, an Array[ItemStack], formalizing what
## was previously a loose Array[Dictionary] placeholder.
##
## Lives under systems/inventory/ despite being referenced from Character's
## OccupationDefinition -- same kind of cross-system data reference already
## established by Traits holding Array[ModifierEntry] from the Modifier
## System.

@export var item_id: String = ""
@export var quantity: int = 1

func _init(p_item_id: String = "", p_quantity: int = 1) -> void:
	item_id = p_item_id
	quantity = p_quantity
