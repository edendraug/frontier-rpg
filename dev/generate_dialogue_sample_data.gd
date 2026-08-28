@tool
extends EditorScript

## Generates one small but representative dialogue scenario - an Actor
## ("Silas Cobb", a prospector), his main DialogueTree, one Preset
## ("simple_trade"), and one shared ConditionSet - deliberately built
## to exercise every node/condition/effect type the restructured graph
## introduces, rather than being a realistic finished piece of content.
##
## REWRITTEN against the Dialogue Graph Node Restructure design doc -
## every "Choice contains a list of Options" shape from the earlier
## version is gone. What used to be `hub.options = [...]` is now a
## DialogueStructureNode fanning out to seven standalone
## DialogueChoiceNode/DialogueSkillCheckChoiceNode entries, each a real
## tree.nodes member with its own node_id. What used to be an Option's
## inline `.conditions` is now a wired DialogueConditionNode per gated
## choice, referenced via `condition_node_id` (Restructure doc's newly-
## added field, since the doc itself hadn't specified how the
## condition-input wire is actually represented in data).
##
## Exercises, node-by-node:
##
##   - Line node with 2 variants under STICKY variant_mode (opening)
##   - a DialogueStructureNode with 7 outputs (hub) - Cameron's own
##     original worked example, reproduced exactly
##   - a consume_once choice (ask_name) vs. a repeatable one
##   - an inline (non-ConditionSet) DialogueCondition on a
##     DialogueConditionNode (help_with_task_condition: ACTOR_KNOWN)
##   - a shared ConditionSet referenced FROM a DialogueConditionNode
##     (mention_bandits_condition: FACTION_REPUTATION_AT_LEAST) - starts
##     mention_bandits hidden, then reveals it once earned elsewhere
##   - a DialogueConditionNode with TWO conditions under OR mode
##     (trail_talk_condition: HAS_TRAIT natural_hunter OR ACTOR_KNOWN) -
##     new coverage the old data model couldn't express at all, since
##     OR support didn't exist before this restructure. Authored here
##     even though DialogueConditionResolver doesn't evaluate `mode`
##     yet (deferred alongside DialoguePlayer, Restructure doc Section
##     9) - nothing currently reads this ConditionNode at runtime
##     anyway (DialoguePlayer's choice-walking is itself stubbed), so
##     there's no incorrect-behavior risk in authoring it now.
##   - manually dual-authored FACTION_REPUTATION_DELTA effects on
##     opposing factions (Dialogue & Relations doc Section 3.3's
##     current, unconfirmed lean)
##   - a DialogueSkillCheckChoiceNode (help_with_task) - a real graph
##     node now, not reached through a synthetic side-channel - with an
##     authored critical_success branch and a deliberately unauthored
##     critical_failure (exercises the fall-back-to-failure behavior)
##   - a HAS_ITEM condition (offer_rope_condition, inside the Preset)
##   - a START_PRESET effect and the Preset's own implicit
##     return-to-caller
##   - a CUSTOM Condition and CUSTOM Effect, to validate the
##     evaluate()/apply() signature the design doc proposes but flags
##     as unconfirmed
##
## Run from the Godot editor: open this script, then File > Run (or
## right-click it in the FileSystem dock > Run). Safe to re-run - every
## resource is rebuilt from scratch and re-saved to the same paths.
##
## IDs marked below are best guesses at what already exists in your
## authored Skill/Item/Trait data - swap them for real ids if these
## don't match. Everything else (actor id, tree ids, faction ids, node
## ids) is invented fresh for this test and has no dependency on
## existing content.

# --- Swap these to match real authored content if they don't exist ---
const TEST_SKILL_ID := "medicine"            # per the Core Systems GDD's own worked example
const TEST_TRAIT_ID := "natural_hunter"      # actual trait_id - display name is "Natural Hunter"
const TEST_ITEM_GRANT_ID := "trail_rations"  # guessed - swap for a real ItemDefinition id
const TEST_ITEM_GATE_ID := "rope"            # guessed - swap for a real ItemDefinition id

const ACTOR_DIR := "res://systems/dialogue/data/actors/"
const TREE_DIR := "res://systems/dialogue/data/trees/"
const PRESET_DIR := "res://systems/dialogue/data/presets/"
const CONDITION_SET_DIR := "res://systems/dialogue/data/condition_sets/"

const ACTOR_ID := "silas_cobb"           # keep in sync with debug/tabs/dialogue_debug_tab.gd's TEST_ACTOR_ID
const TREE_ID := "silas_cobb_main"
const PRESET_ID := "simple_trade"
const CONDITION_SET_ID := "trusted_by_settlers"

const FACTION_SETTLER := "settler"
const FACTION_HIGHWAYMEN := "highwaymen"


func _run() -> void:
	for dir in [ACTOR_DIR, TREE_DIR, PRESET_DIR, CONDITION_SET_DIR]:
		DirAccess.make_dir_recursive_absolute(dir)

	var condition_set := _build_condition_set()
	var condition_set_path := CONDITION_SET_DIR + CONDITION_SET_ID + ".tres"
	ResourceSaver.save(condition_set, condition_set_path)
	# ResourceSaver.save() does NOT retroactively set resource_path on the
	# object passed in - without this, condition_set still looks like an
	# anonymous, path-less Resource to anything that embeds it afterward
	# (here, mention_bandits_condition's conditions list), so ResourceSaver
	# bakes a duplicated, disconnected copy into the tree file instead of
	# writing a real ext_resource link to this shared file. take_over_path()
	# tells the resource (and the loader's cache) it now lives at this path,
	# same as if it had been load()-ed from disk.
	condition_set.take_over_path(condition_set_path)

	var preset := _build_preset()
	ResourceSaver.save(preset, PRESET_DIR + PRESET_ID + ".tres")

	var tree := _build_main_tree(condition_set)
	ResourceSaver.save(tree, TREE_DIR + TREE_ID + ".tres")

	var actor := _build_actor()
	ResourceSaver.save(actor, ACTOR_DIR + ACTOR_ID + ".tres")

	EditorInterface.get_resource_filesystem().scan()
	print("Dialogue sample data generated: %s / %s / %s / %s" % [ACTOR_ID, TREE_ID, PRESET_ID, CONDITION_SET_ID])


# ---------------------------------------------------------------------------
# Actor
# ---------------------------------------------------------------------------

func _build_actor() -> ActorDefinition:
	var actor := ActorDefinition.new()
	actor.actor_id = ACTOR_ID
	actor.unknown_name = "Grizzled Prospector"
	actor.known_name = "Silas Cobb"
	actor.faction_alignment = {FACTION_SETTLER: 1}
	actor.dialogue_tree_id = TREE_ID
	# portraits left empty on purpose - exercises the "no portraits
	# authored at all" silent no-portrait path in ActorDefinition.get_portrait().
	return actor


# ---------------------------------------------------------------------------
# Shared ConditionSet
# ---------------------------------------------------------------------------

func _build_condition_set() -> ConditionSet:
	var rep_condition := DialogueCondition.new()
	rep_condition.type = DialogueCondition.Type.FACTION_REPUTATION_AT_LEAST
	rep_condition.target = FACTION_SETTLER
	rep_condition.threshold = 5.0

	var set := ConditionSet.new()
	set.condition_set_id = CONDITION_SET_ID
	set.conditions = [rep_condition]
	return set


# ---------------------------------------------------------------------------
# Preset: a trivial trade loop
# ---------------------------------------------------------------------------

func _build_preset() -> DialogueTree:
	var nodes: Dictionary = {}

	var intro := DialogueLineNode.new()
	intro.node_id = "trade_intro"
	intro.speaker = ACTOR_ID
	intro.variants = [_variant("\"Trade? Maybe. Depends what you got.\"")]
	intro.next = "trade_hub"
	nodes["trade_intro"] = intro

	nodes["trade_hub"] = _structure_node("trade_hub", ["buy_rope", "offer_rope", "leave_trade"])

	var buy_rope := DialogueChoiceNode.new()
	buy_rope.node_id = "buy_rope"
	buy_rope.text = "Buy some rope."
	buy_rope.effects = [_grant_item_effect(TEST_ITEM_GATE_ID, 1)]
	buy_rope.next = ""  # empty next inside a Preset pops the call stack, resuming the caller
	nodes["buy_rope"] = buy_rope

	nodes["offer_rope_condition"] = _condition_node("offer_rope_condition", [_has_item_condition(TEST_ITEM_GATE_ID, 1)])

	var offer_rope := DialogueChoiceNode.new()
	offer_rope.node_id = "offer_rope"
	offer_rope.text = "Offer him some rope you're carrying."
	offer_rope.condition_node_id = "offer_rope_condition"
	offer_rope.effects = [_grant_item_effect(TEST_ITEM_GRANT_ID, 2)]
	offer_rope.next = ""
	nodes["offer_rope"] = offer_rope

	var leave_trade := DialogueChoiceNode.new()
	leave_trade.node_id = "leave_trade"
	leave_trade.text = "Never mind."
	leave_trade.next = ""
	nodes["leave_trade"] = leave_trade

	var tree := DialogueTree.new()
	tree.tree_id = PRESET_ID
	tree.start_node_id = "trade_intro"
	tree.nodes = nodes
	return tree


# ---------------------------------------------------------------------------
# Main tree
# ---------------------------------------------------------------------------

func _build_main_tree(condition_set: ConditionSet) -> DialogueTree:
	var nodes: Dictionary = {}

	var opening := DialogueLineNode.new()
	opening.node_id = "opening"
	opening.speaker = ACTOR_ID
	opening.variants = [
		_variant("A grizzled old man looks up from his pan, squinting at you."),
		_variant("The prospector eyes you warily, sizing you up before saying anything."),
	]
	opening.variant_mode = DialogueLineNode.VariantMode.STICKY
	opening.next = "hub"
	nodes["opening"] = opening

	var after_name := DialogueLineNode.new()
	after_name.node_id = "after_name"
	after_name.speaker = ACTOR_ID
	after_name.variants = [_variant("\"Silas. Silas Cobb. Not that it's any of your business.\"")]
	after_name.next = "hub"
	nodes["after_name"] = after_name

	# The stage: fans out to all seven choices below. Matches the
	# original worked example ("in our case 7 outputs") exactly.
	nodes["hub"] = _structure_node("hub", [
		"ask_name", "ask_trade", "help_with_task", "mention_bandits",
		"trail_talk", "custom_test", "leave",
	])

	var ask_name := DialogueChoiceNode.new()
	ask_name.node_id = "ask_name"
	ask_name.text = "Ask for his name."
	ask_name.consume_once = true  # exercises "disappears entirely once taken"
	ask_name.effects = [_reveal_name_effect()]
	ask_name.next = "after_name"
	nodes["ask_name"] = ask_name

	var ask_trade := DialogueChoiceNode.new()
	ask_trade.node_id = "ask_trade"
	ask_trade.text = "Ask if he has anything to trade."
	ask_trade.effects = [_start_preset_effect(PRESET_ID)]
	ask_trade.next = "hub"  # the return point once the Preset concludes
	nodes["ask_trade"] = ask_trade

	nodes["help_with_task_condition"] = _condition_node("help_with_task_condition", [_actor_known_condition()])

	var help_with_task := _build_medicine_choice()
	help_with_task.node_id = "help_with_task"
	help_with_task.text = "Take a look at that cough of his."
	help_with_task.consume_once = true
	help_with_task.condition_node_id = "help_with_task_condition"  # must have learned his name first
	nodes["help_with_task"] = help_with_task

	nodes["mention_bandits_condition"] = _condition_node("mention_bandits_condition", [condition_set])

	var mention_bandits := DialogueChoiceNode.new()
	mention_bandits.node_id = "mention_bandits"
	mention_bandits.text = "Mention the Settlers could use help against bandits."
	mention_bandits.consume_once = true
	mention_bandits.condition_node_id = "mention_bandits_condition"  # gated behind reputation >= 5 - starts hidden, appears once earned elsewhere
	mention_bandits.effects = [
		_faction_delta_effect(FACTION_SETTLER, 5.0),
		_faction_delta_effect(FACTION_HIGHWAYMEN, -5.0),  # manually dual-authored, per Section 3.3's current (unconfirmed) lean
	]
	mention_bandits.next = "hub"
	nodes["mention_bandits"] = mention_bandits

	# OR mode, two conditions - new coverage the pre-restructure data
	# model couldn't express. A trail-savvy character either has the
	# knack (the Trait) or has spent enough time with Silas to have
	# picked it up from him (knows him) - either is enough.
	nodes["trail_talk_condition"] = _condition_node(
		"trail_talk_condition",
		[_has_trait_condition(TEST_TRAIT_ID), _actor_known_condition()],
		DialogueConditionNode.Mode.OR,
	)

	var trail_talk := DialogueChoiceNode.new()
	trail_talk.node_id = "trail_talk"
	trail_talk.text = "Ask about trail conditions ahead."
	trail_talk.condition_node_id = "trail_talk_condition"
	trail_talk.next = "hub"
	nodes["trail_talk"] = trail_talk

	nodes["custom_test_condition"] = _condition_node("custom_test_condition", [_custom_condition()])

	var custom_test := DialogueChoiceNode.new()
	custom_test.node_id = "custom_test"
	custom_test.text = "[TEST] Custom condition/effect option."
	custom_test.condition_node_id = "custom_test_condition"
	custom_test.effects = [_custom_effect()]
	custom_test.next = "hub"
	nodes["custom_test"] = custom_test

	var leave := DialogueChoiceNode.new()
	leave.node_id = "leave"
	leave.text = "Leave."
	leave.next = ""  # empty next at top level ends the conversation
	nodes["leave"] = leave

	var tree := DialogueTree.new()
	tree.tree_id = TREE_ID
	tree.start_node_id = "opening"
	tree.nodes = nodes
	return tree


func _build_medicine_choice() -> DialogueSkillCheckChoiceNode:
	var success := SkillCheckBranch.new()
	success.next = "hub"
	success.effects = [_faction_delta_effect(FACTION_SETTLER, 10.0)]

	var failure := SkillCheckBranch.new()
	failure.next = "hub"

	var crit_success := SkillCheckBranch.new()
	crit_success.next = "hub"
	crit_success.effects = [
		_faction_delta_effect(FACTION_SETTLER, 20.0),
		_grant_item_effect(TEST_ITEM_GRANT_ID, 1),
	]

	var choice := DialogueSkillCheckChoiceNode.new()
	choice.skill_id = TEST_SKILL_ID
	choice.dc_mode = DialogueSkillCheckChoiceNode.DCMode.TIER
	choice.dc_tier = DiceResolver.DifficultyTier.MEDIUM
	choice.success = success
	choice.failure = failure
	choice.critical_success = crit_success
	# critical_failure left null on purpose - exercises get_critical_failure_branch()'s fallback to `failure`
	return choice


# ---------------------------------------------------------------------------
# Small builders
# ---------------------------------------------------------------------------

func _structure_node(node_id: String, outputs: Array[String]) -> DialogueStructureNode:
	var node := DialogueStructureNode.new()
	node.node_id = node_id
	node.outputs = outputs
	return node


func _condition_node(node_id: String, conditions: Array, mode: DialogueConditionNode.Mode = DialogueConditionNode.Mode.AND) -> DialogueConditionNode:
	var node := DialogueConditionNode.new()
	node.node_id = node_id
	node.mode = mode
	node.conditions = conditions
	return node


func _variant(text: String) -> DialogueLineVariant:
	var v := DialogueLineVariant.new()
	v.text = text
	return v


func _reveal_name_effect() -> DialogueEffect:
	var e := DialogueEffect.new()
	e.type = DialogueEffect.Type.REVEAL_ACTOR_NAME
	return e  # target left empty -> defaults to the current speaking actor


func _start_preset_effect(preset_id: String) -> DialogueEffect:
	var e := DialogueEffect.new()
	e.type = DialogueEffect.Type.START_PRESET
	e.target = preset_id
	return e


func _grant_item_effect(item_id: String, quantity: int) -> DialogueEffect:
	var e := DialogueEffect.new()
	e.type = DialogueEffect.Type.GRANT_ITEM
	e.target = item_id
	e.value = float(quantity)
	return e


func _faction_delta_effect(faction_id: String, delta: float) -> DialogueEffect:
	var e := DialogueEffect.new()
	e.type = DialogueEffect.Type.FACTION_REPUTATION_DELTA
	e.target = faction_id
	e.value = delta
	return e


func _has_item_condition(item_id: String, quantity: int) -> DialogueCondition:
	var c := DialogueCondition.new()
	c.type = DialogueCondition.Type.HAS_ITEM
	c.target = item_id
	c.threshold = float(quantity)
	return c


func _has_trait_condition(trait_id: String) -> DialogueCondition:
	var c := DialogueCondition.new()
	c.type = DialogueCondition.Type.HAS_TRAIT
	c.target = trait_id
	return c


func _actor_known_condition() -> DialogueCondition:
	var c := DialogueCondition.new()
	c.type = DialogueCondition.Type.ACTOR_KNOWN
	return c  # target left empty -> defaults to the current speaking actor


func _custom_condition() -> DialogueCondition:
	var c := DialogueCondition.new()
	c.type = DialogueCondition.Type.CUSTOM
	c.custom_script = load("res://systems/dialogue/data/custom_scripts/sample_custom_dialogue_condition.gd")
	return c


func _custom_effect() -> DialogueEffect:
	var e := DialogueEffect.new()
	e.type = DialogueEffect.Type.CUSTOM
	e.custom_script = load("res://systems/dialogue/data/custom_scripts/sample_custom_dialogue_effect.gd")
	return e
