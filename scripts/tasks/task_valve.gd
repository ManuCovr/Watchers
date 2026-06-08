@tool
class_name ValveTask
extends Task
## A physical VALVE you must crank open. Look at the wheel and HOLD E; only the WHEEL turns (on
## its axle — the pipe housing stays put). It resists, so it climbs slowly and bleeds back down
## when you let go: a committed maintenance turn, not a button press. Cranking it full opens the
## line (counts toward the escape). Built from `pipe_valve_holder_large_1` (wheel = valve_1 child).

@export var reach := 2.4
@export var turns_required := 3.0            ## full wheel revolutions to fully open
@export var turn_rate := 1.1                 ## revolutions/sec while cranking at full commitment
@export var decay := 0.35                    ## revolutions/sec lost when nobody's cranking
@export var model := "res://assets/psx/Large Props/pipe_valve_holder_large_1.glb"

var _wheel: Node3D
var _valve: Interactable
var _gauge: MeshInstance3D
var _gmat: StandardMaterial3D
var _turns := 0.0
var _spin := 0.0                             # current commitment (eases in for resistance feel)


func _build() -> void:
	if is_default_title():
		task_title = "Crank the valve open"
	# Some pipework so it reads as a maintenance fixture, plus the valve itself.
	make_model("res://assets/bunkers/pipe_2.glb", Vector3(0.4, 0.4, 1.5), Color(0.2, 0.2, 0.22), 1.0)
	var glb := make_model(model, Vector3(0.6, 0.6, 0.3), Color(0.35, 0.3, 0.2), 3.0)
	glb.position = Vector3(0, 1.1, 0.0)
	glb.rotation_degrees = Vector3(0, 0, 0)
	add_child(glb)
	_wheel = find_part(glb, "valve_")
	if _wheel == null:
		_wheel = glb

	_valve = make_interactable(Vector3(0.9, 0.9, 0.5), "Crank valve")
	_valve.position = Vector3(0, 1.1, 0.25)
	add_child(_valve)

	# A small pressure gauge bar that fills as the line opens.
	_gauge = make_box(Vector3(0.5, 0.1, 0.06), Color(0.9, 0.45, 0.1), true)
	_gauge.position = Vector3(0, 1.9, 0.1)
	_gmat = _gauge.material_override as StandardMaterial3D
	_gauge.scale.x = 0.02
	add_child(_gauge)


func _task_process(delta: float) -> void:
	if _turns >= turns_required:
		return
	var cranking := false
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as WPlayer
		if p != null and p.is_using(_valve):
			cranking = true
			break

	if cranking:
		_spin = move_toward(_spin, 1.0, delta * 2.2)        # resistance: commitment eases in
		_turns = minf(turns_required, _turns + turn_rate * _spin * delta)
		_wheel.rotation.z += turn_rate * _spin * delta * TAU
	else:
		_spin = move_toward(_spin, 0.0, delta * 3.0)
		_turns = maxf(0.0, _turns - decay * delta)

	report_progress(_turns / turns_required)
	_update_gauge()
	if _turns >= turns_required:
		play_sfx("res://assets/audio/sfx/valve_mx_1_loop.ogg", -4.0)
		mark_done()


func _update_gauge() -> void:
	var r := _turns / turns_required
	_gauge.scale.x = maxf(0.02, r)
	if _gmat != null:
		_gmat.emission = Color(0.9, 0.45, 0.1).lerp(Color(0.2, 0.95, 0.3), r)


func get_progress() -> float:
	return _turns / turns_required


func _on_done() -> void:
	_turns = turns_required
	_update_gauge()
