class_name MovementTuning
extends Resource
## Editor-editable movement feel for WPlayer. Make a .tres from this, assign it to
## the player's `tuning` slot, and tweak everything in the Inspector — no script
## digging. You can keep multiple profiles (e.g. "tense", "arcade") and hot-swap.

@export_group("Walk")
@export var walk_speed := 4.0              ## base ground speed (m/s)
@export var acceleration := 28.0           ## reach target speed fast (responsive, REPO/PEAK-ish)
@export var deceleration := 20.0           ## stop with a touch of weight (lower than accel = slight slide)
@export var gravity := 20.0                ## pulls you down stairs / off ledges (2-floor house)

@export_group("Floor / slopes (stair feel)")
@export var floor_snap_length := 0.6       ## keeps you stuck to slopes/stairs going down (no bounce/float)
@export var floor_max_angle_deg := 50.0    ## walkable slope limit; the stair ramp is ~22°, so this is plenty
@export var floor_stop_on_slope := true    ## stand still on slopes instead of sliding

@export_group("Sprint (panic burst)")
@export var sprint_multiplier := 1.7       ## walk_speed * this while bursting
@export var sprint_max_time := 2.2         ## seconds of burst available when full
@export var sprint_recharge := 0.6         ## burst seconds regained per real second (when not sprinting)
@export var sprint_min_to_start := 0.55    ## spent the burst? must recharge to at least this (≈1s lockout) before you can sprint again
@export var sprint_fov_add := 8.0          ## FOV widens while sprinting → you cover *worse* (tradeoff)

@export_group("Look")
@export var mouse_sensitivity := 0.0024
@export var pitch_min := -1.45
@export var pitch_max := 1.45

@export_group("Camera motion")
@export var eye_height := 1.62
@export var bob_frequency := 1.9           ## head-bob steps/sec scaler
@export var bob_amplitude := 0.045
@export var breath_amplitude := 0.012      ## subtle idle breathing
@export var fov := 80.0                    ## base camera FOV (raise to widen the freeze cone)
