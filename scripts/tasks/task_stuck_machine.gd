@tool
class_name StuckMachineTask
extends Task
## MEME / EASY — percussive maintenance. A machine is jammed. Walk up, look at the dent, and SLAP
## it (press E) a few times. Each whack thunks, the whole unit jolts, and a little more of it
## sputters to life — until the last hit kicks it back online with a clunk. Dumb, physical, quick,
## friendslop. Rare in the pool so it stays funny and doesn't undercut the dread.

@export_range(2, 6) var hits_required := 3
@export var model := "res://assets/bunkers/machinery_1.glb"
@export var model_scale := 1.0

var _body: Node3D
var _panel: Interactable
var _rest := Vector3.ZERO
var _shake := 0.0
var _hits := 0
var _lamp: MeshInstance3D


func _build() -> void:
	if is_default_title():
		task_title = "Whack the jammed machine"
	task_category = &"meme"
	meme_task = true
	difficulty = 1
	estimated_duration = 4.0

	_body = make_model(model, Vector3(1.0, 1.4, 0.8), Color(0.2, 0.2, 0.23), model_scale)
	add_child(_body)
	_rest = _body.position

	# A red "FAULT" lamp that goes green when you've beaten it into submission.
	_lamp = make_box(Vector3(0.14, 0.14, 0.06), Color(0.9, 0.2, 0.15), true)
	_lamp.position = Vector3(0, 1.55, 0.45)
	add_child(_lamp)

	_panel = make_interactable(Vector3(0.9, 1.0, 0.6), "Slap it", Vector3(0, 0.9, 0.4))
	add_child(_panel)


func _task_process(delta: float) -> void:
	# Settle the jolt from the last whack.
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 5.0)
		_body.position = _rest + Vector3(
			sin(Time.get_ticks_msec() * 0.06) * 0.04 * _shake,
			cos(Time.get_ticks_msec() * 0.05) * 0.03 * _shake,
			0.0)
	else:
		_body.position = _rest

	for nd in get_tree().get_nodes_in_group("players"):
		var p := nd as WPlayer
		if p == null or p._downed:
			continue
		if p.aimed == _panel and p.consume_interact():
			_whack()
			break


func _whack() -> void:
	_hits += 1
	_shake = 1.0
	play_sfx("res://assets/audio/sfx/footstep_metal_a_3.ogg", -2.0, randf_range(0.5, 0.7))
	report_progress(float(_hits) / float(hits_required))
	if _hits >= hits_required:
		var m := _lamp.material_override as StandardMaterial3D
		if m != null:
			m.albedo_color = Color(0.2, 0.95, 0.35)
			m.emission = Color(0.2, 0.95, 0.35)
		play_sfx("res://assets/audio/sfx/button_4.ogg", -3.0)
		mark_done()


func get_progress() -> float:
	return float(_hits) / float(maxi(hits_required, 1))
