class_name ModifierResult
extends RefCounted

## The output of ModifierResolver.aggregate() — every relevant
## ModifierEntry for one query, already combined by type. Kept as its
## own class (rather than a Dictionary) so callers get typed fields
## instead of magic string keys.
##
## RECONSTRUCTION NOTICE: this file was never actually attached or
## reviewed this project — every prior use of ModifierResult was
## inferred from how ModifierResolver.aggregate() and SkillCheck
## consume it (additive_total, multiplicative_total,
## contributing_entries). Diff this against whatever's really on
## disk before overwriting it; if the real file already has other
## fields or methods in use elsewhere, those need to be preserved
## alongside the two new ones below.

## Sum of every contributing ADDITIVE entry's value.
var additive_total: float = 0.0

## Product of every contributing MULTIPLICATIVE entry's value. Starts
## at 1.0 (the multiplicative identity) so a query with no
## multiplicative entries leaves whatever it's multiplied against
## unchanged.
var multiplicative_total: float = 1.0

## Sum of every contributing SUPPRESS_BONUS_DICE entry's value, for
## entries where full_suppression is false (partial reduction).
## Ignored if bonus_dice_fully_suppressed is true below.
var bonus_dice_suppression: float = 0.0

## True if ANY contributing SUPPRESS_BONUS_DICE entry had
## full_suppression set. Full suppression always wins over any
## partial entries also present in the same query — e.g. a Broken
## Hand overrides a merely-Tired penalty rather than the two either
## cancelling out or stacking.
var bonus_dice_fully_suppressed: bool = false

## Every ModifierEntry that actually matched this query's targets,
## regardless of type — for a future breakdown/tooltip showing WHY a
## roll got what it got.
var contributing_entries: Array = []
