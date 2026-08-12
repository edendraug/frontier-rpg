class_name DiceTrayConfig
extends Resource

## Runtime physics/behavior tuning for dice rolls. Deliberately does
## NOT include screen size, tray bounds, camera framing, or physics
## materials anymore — those are now real properties on real nodes
## in the hand-authored dice_tray.tscn, tunable visually in the
## editor (drag the camera, scale a die, watch it happen) rather
## than as numbers you have to guess and re-run to check.
##
## Every value below is still a placeholder pending real tuning —
## same caveat as everywhere else in this project.

## --- Throw physics ---
@export var throw_impulse_min: float = 2.5
@export var throw_impulse_max: float = 4.5
@export var throw_torque_min: float = 3.0
@export var throw_torque_max: float = 6.0

## --- Settling / corrective nudge ---
## A die starts correcting toward its target face once BOTH its
## angular and linear speed drop below these thresholds — i.e. it's
## slowing down naturally, not still mid-tumble.
@export var settle_angular_velocity_threshold: float = 1.5
@export var settle_linear_velocity_threshold: float = 0.3

## Proportional/derivative gains for the corrective torque — higher
## correction_strength turns faster toward the target, higher
## correction_damping resists overshoot/wobble.
@export var correction_strength: float = 8.0
@export var correction_damping: float = 2.0

## Once within this many degrees of the target AND nearly still, the
## die is frozen exactly on-target rather than left to keep drifting.
@export var freeze_alignment_tolerance_degrees: float = 3.0

## Safety timeout — if a die somehow never settles cleanly, force it
## to the target after this long rather than hanging the roll.
@export var max_settle_time: float = 5.0
