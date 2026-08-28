@tool
extends EditorScript

## Standalone verification of DialogueConditionResolver's AND/OR
## support (Dialogue Graph Node Restructure follow-up addendum,
## Section 5) - not tied to the actual sample data, since
## DialoguePlayer's walking logic is still stubbed and can't exercise
## this end to end yet.
##
## Deliberately isolated from every OTHER system (RelationsSystem,
## InventorySystem, CharacterSheet): uses ONLY PREVIOUS_OPTION_TAKEN
## conditions against a single, hand-constructed ActorState, since
## that's the one condition type whose result depends purely on a
## parameter this script already controls directly
## (state.has_taken_option()), rather than an autoload or a fully-
## populated DialogueContext/CharacterSheet this test would otherwise
## need to stand up correctly just to get a reliable true/false.
##
## Prints PASS/FAIL per case to the Output panel. Reads and writes
## nothing on disk; touches no real save data.

func _run() -> void:
	var state := ActorState.new()
	state.mark_option_taken("known_true")
	# "known_false" is deliberately never marked - has_taken_option()
	# for it will always be false.

	var t := _option_taken_condition("known_true")    # always evaluates true against `state`
	var f := _option_taken_condition("known_false")   # always evaluates false against `state`

	var all_passed := true

	var cases := [
		["AND, all true", [t, t, t], DialogueConditionNode.Mode.AND, true],
		["AND, one false", [t, f, t], DialogueConditionNode.Mode.AND, false],
		["AND, all false", [f, f], DialogueConditionNode.Mode.AND, false],
		["AND, empty list", [], DialogueConditionNode.Mode.AND, true],
		["OR, all false", [f, f, f], DialogueConditionNode.Mode.OR, false],
		["OR, one true", [f, t, f], DialogueConditionNode.Mode.OR, true],
		["OR, all true", [t, t], DialogueConditionNode.Mode.OR, true],
		["OR, empty list", [], DialogueConditionNode.Mode.OR, false],
	]
	for case in cases:
		var label: String = case[0]
		var entries: Array = case[1]
		var mode: DialogueConditionNode.Mode = case[2]
		var expected: bool = case[3]
		var actual := DialogueConditionResolver.evaluate_all(entries, "", state, null, mode)
		var ok := actual == expected
		all_passed = all_passed and ok
		print("[%s] %s (expected %s, got %s)" % ["PASS" if ok else "FAIL", label, expected, actual])

	# Nested ConditionSet inside an OR-mode list - confirms a
	# ConditionSet's own list stays AND internally regardless of the
	# outer mode (the key rule from Section 5), not just that top-level
	# OR works on its own.
	var and_false_set := ConditionSet.new()
	and_false_set.condition_set_id = "_test_and_false_set"
	and_false_set.conditions = [t, f]   # AND-internally -> false, one entry is false
	var nested_1 := DialogueConditionResolver.evaluate_all([f, and_false_set], "", state, null, DialogueConditionNode.Mode.OR)
	var ok1 := nested_1 == false
	all_passed = all_passed and ok1
	print("[%s] OR with a false top-level entry + an internally-AND-false ConditionSet (expected false, got %s)" % ["PASS" if ok1 else "FAIL", nested_1])

	var and_true_set := ConditionSet.new()
	and_true_set.condition_set_id = "_test_and_true_set"
	and_true_set.conditions = [t, t]    # AND-internally -> true, both entries true
	var nested_2 := DialogueConditionResolver.evaluate_all([f, and_true_set], "", state, null, DialogueConditionNode.Mode.OR)
	var ok2 := nested_2 == true
	all_passed = all_passed and ok2
	print("[%s] OR with a false top-level entry + an internally-AND-true ConditionSet (expected true, got %s)" % ["PASS" if ok2 else "FAIL", nested_2])

	print("")
	print("ALL CASES PASSED" if all_passed else "SOME CASES FAILED - see above")


func _option_taken_condition(target_id: String) -> DialogueCondition:
	var c := DialogueCondition.new()
	c.type = DialogueCondition.Type.PREVIOUS_OPTION_TAKEN
	c.target = target_id
	return c
