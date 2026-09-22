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

## --- Expedition progress ---
## Fills the slot this file previously reserved for world position/
## route/visited-hex data -- see Travel System Design Doc v0.2,
## Section 6. Defaults to a fresh TravelState (AT_CAMP, Normal pace,
## empty route/history) rather than null, so a save predating this
## field or a brand-new expedition always has a valid state to read.
## Which Events have already fired will need its own field once an
## Event/Encounter system exists -- not this one's job.
@export var travel_state: TravelState = TravelState.new()

## --- Expedition Scene Routing ---
## "" = no bespoke scene active (an ambient Travel/Camp scene shows
## instead, resolved from travel_state.state on load). Restoring always
## resolves to that scene's own Gather Point, never an exact prior
## position -- consistent with Local Movement's own existing save/load
## posture. See Expedition Scene Routing design doc, Section 4.3.
@export var current_local_scene_path: String = ""

## Every location_id the player has been shown an arrival prompt for,
## regardless of whether they chose to visit -- see
## ExpeditionSceneRouter.is_discovered()'s own comment for what
## "discovered" means here and how this is expected to grow into a
## richer (unknown / known / discovered) model later without needing a
## save-format migration.
@export var discovered_location_ids: Array[String] = []
