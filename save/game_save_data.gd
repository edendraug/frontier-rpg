class_name GameSaveData
extends Resource

## The single root object for one save file. Built and consumed only by
## SaveManager -- no other system reads or writes this directly.
##
## Named generically rather than "PartySaveData" because this will grow:
## expedition progress (world position, which events have already
## happened, etc.) belongs here too once those systems exist. Nothing
## about the shape below should need to change to accommodate that --
## new fields just get added alongside these.

## Display name shown in a save-slot list, and the real-world timestamp
## used to default it when the player leaves the name blank. Both are
## real-world wall-clock strings (via Godot's Time singleton), NOT the
## in-game calendar date -- this is "when was this save created,"
## same as any other game's save list.
@export var save_name: String = ""
@export var created_at: String = ""

## --- Party ---
@export var party: Array[CharacterSheet] = []

## --- Inventory ---
@export var inventory_stock: Dictionary = {}      # item_id -> int
@export var inventory_batches: Dictionary = {}     # item_id -> Array[InventoryBatch]
@export var money: float = 0.0
@export var vehicle_capacity: float = -1.0         # -1 = no vehicle, matches InventorySystem's own convention

## --- Time ---
@export var total_minutes_elapsed: int = 0

## --- Expedition progress (not yet implemented) ---
## World position, visited locations, which Events have already
## fired, etc. will live here once World Generation / Event System
## exist. Deliberately left unadded rather than stubbed with guessed
## fields -- easier to add real fields later than to guess wrong now
## and carry dead ones.
