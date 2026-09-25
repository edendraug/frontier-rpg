class_name LocationSceneDefinition
extends HexPromptSource

## One bespoke, single-use location tied to a specific hex -- a fort,
## settlement, or hand-authored special event. `location_id` matches a
## HexInstance's settlement_id or an entry in its special_event_ids
## (World Generation design doc, Section 4.2). Discovered the same
## directory-scan way every other Definition-style resource in this
## project is (see ExpeditionSceneRouter._load_locations()) -- authored
## as individual .tres files, never hand-enumerated in code.
##
## display_name/hex_sector/CENTER_SECTOR now live on HexPromptSource
## (systems/expedition/data/hex_prompt_source.gd) instead of being
## declared here directly -- Vehicles & Animals Design Doc v0.4, Section
## 4.9, once AbandonedVehiclePromptEntry needed the same two fields to
## share ExpeditionSceneRouter's arrival-prompt queue. This class's own
## catalog role, directory-scan discovery, and location_id are
## unaffected -- and existing authored .tres files still load correctly,
## since the property names themselves didn't change, only which class
## declares them.
##
## See Expedition Scene Routing design doc, Section 4.1 -- originally
## added display_name and hex_sector beyond what that doc specified, per
## the later in-hex sector/time-cost conversation (now inherited rather
## than declared here).

## Stable identifier. Matches HexInstance.settlement_id or an entry in
## HexInstance.special_event_ids.
@export var location_id: String = ""

## Path to the bespoke LocalSceneRoot-based scene.
@export var scene_path: String = ""

## Reserved, unwired -- design doc Section 9, Open Question 5. Not
## consumed by anything yet; exists only so this field doesn't need
## retrofitting onto every location once a real Event/Encounter system
## exists to actually read it. Values are a first guess at the three
## agency tiers Cameron described (optional/explorable,
## pausing-but-resumable, fully blocking) -- not confirmed, not final.
enum AgencyType { OPTIONAL, PAUSING, BLOCKING }
@export var agency_type: AgencyType = AgencyType.OPTIONAL
