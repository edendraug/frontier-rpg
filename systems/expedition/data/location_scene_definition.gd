class_name LocationSceneDefinition
extends Resource

## One bespoke, single-use location tied to a specific hex -- a fort,
## settlement, or hand-authored special event. `location_id` matches a
## HexInstance's settlement_id or an entry in its special_event_ids
## (World Generation design doc, Section 4.2). Discovered the same
## directory-scan way every other Definition-style resource in this
## project is (see ExpeditionSceneRouter._load_locations()) -- authored
## as individual .tres files, never hand-enumerated in code.
##
## See Expedition Scene Routing design doc, Section 4.1 -- this adds
## display_name and hex_sector beyond what that doc originally
## specified, per the later in-hex sector/time-cost conversation.

## Sentinel for hex_sector below -- a location that isn't meaningfully
## closer to any one side of its hex, fixed at exactly the same halfway
## time-cost fraction the existing hex-crossing model already assumes
## for a hex's center (see ExpeditionSceneRouter._sector_fraction()).
const CENTER_SECTOR := -1

## Stable identifier. Matches HexInstance.settlement_id or an entry in
## HexInstance.special_event_ids.
@export var location_id: String = ""

## Player-facing name -- used in arrival prompts ("You see Fort Greeley
## up ahead...") and the debug menu's in-hex location list.
@export var display_name: String = ""

## Path to the bespoke LocalSceneRoot-based scene.
@export var scene_path: String = ""

## One of a hex's six sides -- WorldRegistry.AXIAL_DIRECTIONS index
## (0-5) -- or CENTER_SECTOR. Drives nearest-first prompt ordering and
## an approximate in-hex travel-time cost when multiple locations share
## a hex (ExpeditionSceneRouter._sector_distance()/_sector_fraction()).
## Placeholder/approximate by design -- this doesn't model a hex's real
## geometry, only "closer to the entry edge costs less time."
@export var hex_sector: int = CENTER_SECTOR

## Reserved, unwired -- design doc Section 9, Open Question 5. Not
## consumed by anything yet; exists only so this field doesn't need
## retrofitting onto every location once a real Event/Encounter system
## exists to actually read it. Values are a first guess at the three
## agency tiers Cameron described (optional/explorable,
## pausing-but-resumable, fully blocking) -- not confirmed, not final.
enum AgencyType { OPTIONAL, PAUSING, BLOCKING }
@export var agency_type: AgencyType = AgencyType.OPTIONAL
