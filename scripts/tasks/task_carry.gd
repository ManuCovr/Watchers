@tool
class_name CarryTask
extends Task
## PHYSICAL carry: press interact near the object to grab it, then HOLD interact to keep
## hold of it — it sways and lags heavily behind you (awkward, REPO/Gang-Beasts feel), so
## you stumble it across the room while someone watches your back. Let go = you drop it.
## Get it onto the green pad to finish.

@export var zone_offset := Vector3(0, 0, 6.0)   ## drop zone, relative to task origin
@export var zone_radius := 1.8
@export var grab_range := 2.2
@export var carry_dist := 1.3                    ## how far in front it floats
@export var carry_height := 1.2
@export var rest_height := 0.5
@export var sway := 6.0                          ## follow stiffness — lower = floppier/heavier

var _obj: Node3D
var _zone: MeshInstance3D
var _carrier: WPlayer


func _build() -> void:
	if is_default_title():
		task_title = "Carry the cylinder to the loading plate"
	task_category = &"carry"
	difficulty = 2
	estimated_duration = 12.0
	# A real gas cylinder you lug around (not a block).
	_obj = make_model("res://assets/psx2/Props/gas_cylinder_mx_1.glb",
		Vector3(0.6, 1.0, 0.6), Color(0.62, 0.6, 0.66))
	_obj.position = Vector3(0, rest_height, 0)
	add_child(_obj)

	# A DIEGETIC loading plate (not a neon green disc): a dark recessed steel plate with a
	# dim amber edge strip — reads as "put it here" without arcade colours.
	_zone = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = zone_radius; cyl.bottom_radius = zone_radius; cyl.height = 0.08
	_zone.mesh = cyl
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.09, 0.09, 0.11)
	pm.metallic = 0.6
	pm.roughness = 0.5
	pm.emission_enabled = true
	pm.emission = Color(0.5, 0.36, 0.12)        # dim amber, low energy
	pm.emission_energy_multiplier = 0.5
	_zone.material_override = pm
	_zone.position = zone_offset + Vector3(0, 0.04, 0)
	add_child(_zone)


func _task_process(delta: float) -> void:
	if _carrier != null and is_instance_valid(_carrier) and not _carrier._downed:
		# Heavy spring follow: the object lags + sways behind the carrier (not glued).
		var fwd := -_carrier.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var target := _carrier.global_position + fwd * carry_dist + Vector3(0, carry_height, 0)
		_obj.global_position = _obj.global_position.lerp(target, clampf(delta * sway, 0.0, 1.0))
		# A little wobble so it reads as awkward weight.
		_obj.rotation.z = sin(Time.get_ticks_msec() * 0.004) * 0.25
		# Released the hold (or got downed) -> drop it where it is.
		if not _carrier.interact_held:
			_drop()
	else:
		_carrier = null
		for n in get_tree().get_nodes_in_group("players"):
			var p := n as WPlayer
			if p == null or p._downed:
				continue
			if p.global_position.distance_to(_obj.global_position) <= grab_range and p.consume_interact():
				_carrier = p
				play_sfx("res://assets/audio/sfx/button_15.ogg", -7.0)
				break


func _drop() -> void:
	var carried := _obj.global_position
	_carrier = null
	_obj.rotation.z = 0.0
	var flat_obj := Vector3(carried.x, 0, carried.z)
	var flat_zone := global_position + zone_offset
	flat_zone.y = 0
	if flat_obj.distance_to(flat_zone) <= zone_radius:
		_obj.global_position = (global_position + zone_offset) + Vector3(0, rest_height, 0)
		play_sfx("res://assets/audio/sfx/button_4.ogg", -3.0)
		mark_done()
	else:
		_obj.global_position = Vector3(carried.x, rest_height, carried.z)
		play_sfx("res://assets/audio/sfx/crack_1_wood.ogg", -8.0)


func get_progress() -> float:
	# Closer to the pad = more progress (nice readout on the HUD bar).
	if done:
		return 1.0
	var d := Vector2(_obj.global_position.x - (global_position.x + zone_offset.x),
		_obj.global_position.z - (global_position.z + zone_offset.z)).length()
	return clampf(1.0 - d / 14.0, 0.0, 0.95)


func _on_done() -> void:
	if _obj is MeshInstance3D:
		var m := (_obj as MeshInstance3D).material_override as StandardMaterial3D
		if m != null:
			m.emission = Color(0.2, 0.9, 0.4)
