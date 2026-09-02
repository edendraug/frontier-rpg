class_name FeedResult
extends RefCounted

## Returned by VitalsSystem.feed_character() -- everything a caller (the
## debug tab today, a real feed-button UI later) needs without re-deriving
## state. See Frontier_RPG_Food_Consumption_Design_Doc.md, Section 4.5.
##
## `outcome` only reports whether the feeding ATTEMPT itself was legal
## (item existed, location was valid) -- it is SUCCESS whether or not any
## unit consumed made the character sick. Sickness is reported separately
## via diseases_applied, never via outcome.

enum Outcome { SUCCESS, INSUFFICIENT_ITEM, WRONG_LOCATION }

var outcome: Outcome = Outcome.SUCCESS

## Summed across every unit consumed.
var nutrition_restored: float = 0.0

## One entry per unit consumed, oldest batch first. Can span more than one
## tier when quantity > 1 draws from batches of different freshness -- see
## VitalsSystem.feed_character().
var freshness_tiers: Array[ItemFreshness.FreshnessTier] = []

## One entry per unit whose tier produced a nonzero morale magnitude.
var morale_events: Array[MoraleEventInstance] = []

## One entry per unit whose freshness tier actually rolled a saving
## throw (Spoiling/Spoiled only -- a Fresh unit never rolls one at all,
## and contributes no entry here). Includes RESISTED throws, not just
## ones that caused sickness -- see VitalsSystem._apply_food_unit().
## Not index-aligned with freshness_tiers/nutrition (which include
## every unit); this only holds the subset that actually rolled.
var saving_throws: Array[SkillCheckResult] = []

## One entry per failed saving throw.
var diseases_applied: Array[DiseaseInstance] = []
