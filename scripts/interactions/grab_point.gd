class_name GrabPoint
extends Node3D
## A reusable SNAP-TO-POSE environment grab anchor — the seed for later PEAK-style hand grabs
## (elevator handles, railings, levers, valves, doors, task handles, teammate assist). It is NOT
## physics chaos: a hand simply snaps its target to this point's HandSocket and holds the configured
## pose. v1 is data + a clean API; gameplay wiring comes in a later pass.

enum InteractionType { HOLD, PRESS, PULL, CLIMB, ASSIST }

@export var grab_id: StringName = &"grab"
@export_enum("any", "left", "right") var allowed_hand: String = "any"
## Finger/hand pose the hand should adopt while grabbing here (falls back to a tool grip if unset).
@export var pose: HandPoseResource
@export var interaction_type: InteractionType = InteractionType.HOLD
@export var hold_required := true          ## must keep the interact button held to stay grabbed
@export var release_on_input := false      ## tap to toggle release instead of hold
@export var use_duration := 0.0            ## >0 = a timed "use" (crank/valve) before it completes

@export_group("Debug")
@export var debug_draw := false:
	set(v): debug_draw = v; _refresh_debug()

var _occupant: Node = null                 # the hand/player currently grabbing (null = free)
var _dbg: MeshInstance3D


func _ready() -> void:
	add_to_group("grab_points")
	if get_node_or_null("HandSocket") == null:
		var s := Marker3D.new()
		s.name = "HandSocket"
		add_child(s)
	_refresh_debug()


## Where a hand should snap to when grabbing here (global). Used by the hands controller later.
func hand_target() -> Transform3D:
	var s := get_node_or_null("HandSocket") as Marker3D
	return s.global_transform if s != null else global_transform


func is_free() -> bool:
	return _occupant == null or not is_instance_valid(_occupant)


func can_use_hand(is_left: bool) -> bool:
	match allowed_hand:
		"left": return is_left
		"right": return not is_left
		_: return true


## Claim / release — minimal occupancy so two hands can't fight over one handle (full wiring later).
func claim(by: Node) -> bool:
	if not is_free():
		return false
	_occupant = by
	return true


func release(by: Node) -> void:
	if _occupant == by:
		_occupant = null


func _refresh_debug() -> void:
	if not is_inside_tree():
		return
	if _dbg != null:
		_dbg.queue_free(); _dbg = null
	if not debug_draw:
		return
	_dbg = MeshInstance3D.new()
	var m := SphereMesh.new(); m.radius = 0.06; m.height = 0.12
	_dbg.mesh = m
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.2, 0.9, 0.5)
	_dbg.material_override = mat
	add_child(_dbg)
