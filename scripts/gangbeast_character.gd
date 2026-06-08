extends PlayerCharacter
## The Gang Beast (Sketchfab, Mixamo rig) used AS the player body. It has NO baked animation, so we
## pose the arms ourselves: gang-beasts style — upper arms raised forward, floppy sway, reaching
## further while interacting. The mesh/skeleton are authored in gangbeast_character.tscn; this just
## drives the bones. set_first_person_layer() is inherited (hides your own body, keeps it in mirrors).

@export_group("Gang-Beasts arms")
@export var arms_enabled := true
@export var arm_raise := 0.8       ## baseline forward raise (radians) — arms are always up
@export var reach_extra := 0.7     ## extra raise while interacting
@export var arm_axis := Vector3(1, 0, 0)   ## parent-space axis the upper arm pitches around
@export var arm_sway := 0.2        ## floppy sway amount
@export var arm_lerp := 7.0        ## follow speed (lower = floppier)

var _skel: Skeleton3D
var _ua_l := -1
var _ua_r := -1
var _reach := 0.0
var _arm_amt := 0.0


func _ready() -> void:
	_skel = find_child("Skeleton3D", true, false) as Skeleton3D
	if _skel != null:
		_ua_l = _skel.find_bone("mixamorig_LeftArm_20")
		_ua_r = _skel.find_bone("mixamorig_RightArm_35")
	process_priority = 50          # run late (no anim here, but stay consistent)


func set_reach(v: float) -> void:
	_reach = clampf(v, 0.0, 1.0)


func _process(delta: float) -> void:
	if not arms_enabled or _skel == null:
		return
	var want := arm_raise + _reach * reach_extra
	_arm_amt = lerpf(_arm_amt, want, clampf(delta * arm_lerp, 0.0, 1.0))
	var t := Time.get_ticks_msec() * 0.003
	var ax := arm_axis.normalized()
	if _ua_l >= 0:
		var sw := Quaternion(Vector3(0, 1, 0), sin(t) * arm_sway)
		_skel.set_bone_pose_rotation(_ua_l,
			Quaternion(ax, _arm_amt) * sw * _skel.get_bone_rest(_ua_l).basis.get_rotation_quaternion())
	if _ua_r >= 0:
		var sw2 := Quaternion(Vector3(0, 1, 0), sin(t + 1.3) * arm_sway)
		_skel.set_bone_pose_rotation(_ua_r,
			Quaternion(ax, _arm_amt) * sw2 * _skel.get_bone_rest(_ua_r).basis.get_rotation_quaternion())
