class_name AbandonedVehiclePromptEntry
extends HexPromptSource

## Transient, constructed on demand by
## CaravanSystem.get_abandoned_vehicle_prompt_at() -- never authored as
## a .tres file, never saved. Exists only to let a rediscovered
## abandoned vehicle share ExpeditionSceneRouter's arrival-prompt queue
## with LocationSceneDefinition (Section 4.9), which needs nothing
## beyond the two fields HexPromptSource already provides. Deliberately
## carries NO coord/vehicle reference of its own -- the router already
## knows which hex it's checking (_on_hex_entered(coord)) and keeps that
## coord in _pending_prompt_coord for the whole prompt sequence, so a
## second copy of it here would just be redundant state to keep in sync.
##
## Vehicles & Animals Design Doc v0.4, Section 4.9.
