@tool
class_name DialogueLineNode
extends DialogueGraphNode

## A single narration/speech beat in a dialogue graph. Usually leads
## into a Choice node via `next`, but may chain straight into another
## Line for an uninterrupted beat.
##
## node_id and editor_position are inherited from DialogueGraphNode
## (Dialogue Graph Editor design doc, Section 4.1).

enum VariantMode {
	STICKY,  ## Repeat visits show the same variant as last time.
	REROLL,  ## Repeat visits roll fresh among the pool each time.
}

## Actor id. Empty for narration or group scenes with no single speaker.
@export var speaker: String = ""

@export var variants: Array[DialogueLineVariant] = []
@export var variant_mode: VariantMode = VariantMode.STICKY

## Applies across ALL of this Line's variants, not per-variant. Empty
## means "use the speaker's default portrait" - see
## ActorDefinition.get_portrait() for the actual fallback/warning rules.
@export var emotion_tag: String = ""

## Node id this Line leads into. Usually a Choice node; may point to
## another Line directly.
@export var next: String = ""


## Decides which variant index to show, given the last index shown (or
## -1 if this Line has never been shown before) and an rng to roll
## with. Takes last_index as a plain int rather than an ActorState so
## this stays decoupled from RelationsSystem - the caller (DialoguePlayer)
## is responsible for reading/writing that through ActorState.
func pick_variant_index(last_index: int, rng: RandomNumberGenerator) -> int:
	if variants.is_empty():
		return -1
	if variant_mode == VariantMode.STICKY and last_index >= 0 and last_index < variants.size():
		return last_index
	return rng.randi_range(0, variants.size() - 1)


func get_text(variant_index: int) -> String:
	if variant_index < 0 or variant_index >= variants.size():
		return ""
	return variants[variant_index].text
