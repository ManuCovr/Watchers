@tool
class_name RelayTask
extends Task
## PHYSICAL hand-crank relay. Stand at the wheel and HOLD interact to crank it — the
## wheel spins and the charge climbs. Let go and it slowly winds back down, so you have
## to commit a long, exposed hold (or tag-team it) while someone covers the dark.

@export var reach := 2.2
@export var charge_rate := 0.22            ## charge/sec while cranking (~4.5s solo)
@export var decay_rate := 0.10             ## charge/sec lost when nobody's cranking
@export var spin_speed := 9.0              ## wheel spin (rad/s) while cranking

var charge := 0.0
var _wheel: MeshInstance3D
var _fill: MeshInstance3D
var _mat: StandardMaterial3D
var _cranking := false


func _build() -> void:
	if is_default_title():
		task_title = "Crank the relay (hold E)"
	task_category = &"physical"
	difficulty = 2
	estimated_duration = 6.0
	# A real fuel-drum generator base (not a block); the crank wheel sits on top.
	var housing := make_model("res://assets/fpskit/metal_barrel_fps_2.glb",
		Vector3(1.2, 1.4, 0.6), Color(0.1, 0.1, 0.12))
	housing.position = Vector3(0, 0, 0)
	add_child(housing)

	# The crank wheel (a flattened cylinder with a handle nub) — spins while held.
	_wheel = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.45
	cyl.bottom_radius = 0.45
	cyl.height = 0.12
	_wheel.mesh = cyl
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.5, 0.32, 0.12)
	wm.metallic = 0.3
	_wheel.material_override = wm
	_wheel.rotation.x = PI * 0.5            # face the player
	_wheel.position = Vector3(0, 1.1, 0.4)
	add_child(_wheel)
	var nub := make_box(Vector3(0.1, 0.1, 0.22), Color(0.2, 0.2, 0.22))
	nub.position = Vector3(0.3, 0, 0)
	_wheel.add_child(nub)

	# Charge bar up the side of the housing.
	_fill = make_box(Vector3(0.2, 1.2, 0.1), Color(1.0, 0.55, 0.05), true)
	_fill.position = Vector3(0.7, 0.9, 0.0)
	_fill.scale.y = 0.001
	_mat = _fill.material_override as StandardMaterial3D
	add_child(_fill)


func _task_process(delta: float) -> void:
	if charge >= 1.0:
		return
	var cranking := false
	for n in get_tree().get_nodes_in_group("players"):
		if _holding(n as WPlayer, global_position, reach):
			cranking = true
			break

	if cranking:
		charge = minf(1.0, charge + charge_rate * delta)
		_wheel.rotate_y(spin_speed * delta)         # local spin = visible cranking
		if not _cranking:
			_cranking = true
			play_sfx("res://assets/audio/sfx/button_22.ogg", -8.0)
	else:
		charge = maxf(0.0, charge - decay_rate * delta)
		_cranking = false

	report_progress(charge)
	_update_visual()
	if charge >= 1.0:
		play_sfx("res://assets/audio/sfx/button_4.ogg", -3.0)
		mark_done()


func get_progress() -> float:
	return charge


func _update_visual() -> void:
	_fill.scale.y = maxf(0.001, charge * 1.2)
	_fill.position.y = 0.3 + (charge * 1.2) * 0.5
	_mat.emission = Color(1.0, 0.55, 0.05).lerp(Color(0.1, 1.0, 0.25), charge)
	_mat.emission_energy_multiplier = 2.5 + charge * 2.0


func _on_done() -> void:
	charge = 1.0
	_update_visual()
