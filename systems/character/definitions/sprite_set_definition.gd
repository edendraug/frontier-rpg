class_name SpriteSetDefinition
extends Resource

## Defines one selectable character appearance (Local Movement Design
## Doc, Section 3.2/4.2). Meant to be authored as a .tres data file
## per option (e.g. char_1.tres, char_2.tres), each pointing at its
## own atlas texture -- same "authored once, referenced by id"
## pattern as SkillDefinition/OccupationDefinition.
##
## Deliberately minimal: no frame-count/region data here. Every
## sprite set is expected to follow one shared, fixed frame layout
## (idle + a 2-frame walk cycle, right-facing only, mirrored for left
## via VisualRoot.scale.x) -- that convention lives in the hand-authored
## CharacterController scene's Sprite2D/AnimationPlayer setup, not per-
## resource here. If a future sprite set ever needs to break that
## shared convention (a different frame count, say), that's the point
## to add fields here -- not preemptively now.

@export var sprite_set_id: String = ""   # e.g. "char_1" -- must match CharacterSheet.sprite_id
@export var display_name: String = ""    # e.g. "Traveler" -- shown in the character creator's picker
@export var texture: Texture2D           # the whole atlas (idle + walk frames), per the shared layout convention above
