class_name PortraitDisplay
extends Control

## Displays the current speaking Actor's portrait. Deliberately thin -
## DialogueWindow just calls set_portrait(); no Actor/dialogue
## knowledge lives here.
##
## Root is a frame container (Panel/PanelContainer with a StyleBoxFlat
## border) wrapping a TextureRect - reached via %PortraitTexture rather
## than acting as the TextureRect directly, so the frame's styling
## stays entirely hand-built in the scene with nothing for this script
## to know about.
##
## new_texture == null is a fully valid, silent state - not an error.
## Per ActorDefinition.get_portrait()'s own contract (design doc
## Section 4.4), "no portraits authored" and "no default for this
## Line's emotion_tag" both resolve to null, and TextureRect already
## renders nothing for a null texture - no special-casing needed here.
## If a fallback placeholder image (rather than true emptiness) is
## ever wanted for that case, that's a presentation-layer decision -
## add it here as a default @export texture rather than changing what
## ActorDefinition/RelationsSystem return.

@onready var texture_rect: TextureRect = %PortraitTexture


func set_portrait(new_texture: Texture2D) -> void:
	texture_rect.texture = new_texture
