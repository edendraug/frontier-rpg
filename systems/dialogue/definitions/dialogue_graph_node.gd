@tool
class_name DialogueGraphNode
extends Resource

## Shared base for every node type the graph editor draws on its
## canvas (Dialogue Graph Editor design doc, Section 4.1):
## DialogueLineNode, DialogueChoiceNode, and SkillCheckGate.
##
## SkillCheckGate extends this too despite never being looked up by
## node_id at runtime - DialoguePlayer always reaches it directly via
## option.skill_check, never through DialogueTree.nodes. Decided
## deliberately (over a leaner, SkillCheckGate-only editor_position
## field) so the editor's own code can treat "anything it draws as a
## node" uniformly as a DialogueGraphNode, rather than special-casing
## this one type. node_id simply goes unused on SkillCheckGate
## instances; editor_position is used identically across all three.

@export var node_id: String = ""
@export var editor_position: Vector2 = Vector2.ZERO
