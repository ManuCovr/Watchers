class_name HandPoseResource
extends Resource
## Data-driven HOLD / HAND pose for the detached 3-finger blob hands. One of these describes how a
## hand (and optionally the item) should sit and how the three fat fingers should curl. Used both for
## generic finger presets (relaxed/grab/fist/...) and per-item holds (crowbar/fish/...).
##
## IMPORTANT: hands have exactly THREE fingers. The curl array is always length 3:
##   index 0 = thumb / side finger
##   index 1 = main finger A (upper)
##   index 2 = main finger B (lower)
## Do not add five-finger data anywhere — the whole system is three-finger by design.

@export var pose_name: StringName = &"pose"
@export_enum("right", "left") var preferred_hand: String = "right"
@export var two_handed := false

@export_group("Hand placement (relative to the held item / hold point)")
@export var right_hand_offset := Vector3.ZERO
@export var right_hand_rotation_degrees := Vector3.ZERO
@export var left_hand_offset := Vector3.ZERO
@export var left_hand_rotation_degrees := Vector3.ZERO

@export_group("Item placement (overrides random floor rotation)")
@export var item_offset := Vector3.ZERO
@export var item_rotation_degrees := Vector3.ZERO

@export_group("Fingers (exactly 3: [thumb, fingerA, fingerB], 0=open .. 1=fully curled)")
@export var finger_curls := PackedFloat32Array([0.2, 0.2, 0.2])

@export_group("Feel")
@export var hold_distance := 1.0
@export var hold_lerp_speed := 12.0
@export var rotation_lerp_speed := 14.0


## Safe accessor — always returns 3 values even if a .tres was authored short/long.
func curls() -> PackedFloat32Array:
	var c := finger_curls
	if c.size() == 3:
		return c
	var out := PackedFloat32Array([0.2, 0.2, 0.2])
	for i in mini(c.size(), 3):
		out[i] = c[i]
	return out


## Build a pose in code (used for the built-in preset table so we don't need a .tres on disk for
## every generic grip). thumb/a/b are the three curl values.
static func make(name: StringName, thumb: float, a: float, b: float) -> HandPoseResource:
	var r := HandPoseResource.new()
	r.pose_name = name
	r.finger_curls = PackedFloat32Array([thumb, a, b])
	return r
