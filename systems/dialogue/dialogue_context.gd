class_name DialogueContext
extends RefCounted

## Everything the condition/effect resolvers and the skill-check
## pipeline need that isn't already reachable through an autoload
## (RelationsSystem, InventorySystem). Handed to a DialoguePlayer by
## whoever starts a conversation, rather than DialoguePlayer reaching
## into a party roster itself.
##
## player_character is a placeholder seam: PartyManager.gd hasn't been
## reviewed in this session, so its actual "give me the relevant
## character" API is unknown. For now the caller is responsible for
## deciding which CharacterSheet answers HAS_TRAIT checks and performs
## skill-check rolls (most likely the main character, per
## CharacterSheet.is_main_character) and passing it in directly. Swap
## how this gets populated once PartyManager's real API is in hand -
## nothing else in the resolver/runner should need to change.

var player_character: CharacterSheet
var registry: CharacterDataRegistry
var rng: RandomNumberGenerator


func _init(p_player_character: CharacterSheet, p_registry: CharacterDataRegistry, p_rng: RandomNumberGenerator = null) -> void:
	player_character = p_player_character
	registry = p_registry
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()
