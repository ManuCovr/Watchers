@tool
class_name ValveTask
extends TactileTask
## A physical VALVE you must crank open. Look at the wheel, HOLD E (your hand grips the rim), and
## ROTATE the mouse in circles — the wheel turns with your gesture, resists, and bleeds back if you
## let go. Crank it the required turns to open the line (counts toward the escape). Built from
## `pipe_valve_holder_large_1` (wheel = valve_1 child).

@export var turns_required := 3.0            ## full wheel revolutions to fully open
@export var model := "res://assets/psx/Large Props/pipe_valve_holder_large_1.glb"

var _wheel: Node3D
var _gauge: MeshInstance3D
var _gmat: StandardMaterial3D


func _build() -> void:
	if is_default_title():
		task_title = "Crank the valve open"
	task_category = &"physical"
	difficulty = 2
	estimated_duration = 8.0
	resistance = 0.9                         # stiff — it fights back
	gesture_per_unit = 19.0                  # several committed mouse circles to fully open
	decay_per_sec = 0.22
	done_sound = "res://assets/audio/sfx/valve_mx_1_loop.ogg"

	make_model("res://assets/bunkers/pipe_2.glb", Vector3(0.4, 0.4, 1.5), Color(0.2, 0.2, 0.22), 1.0)
	var glb := make_model(model, Vector3(0.6, 0.6, 0.3), Color(0.35, 0.3, 0.2), 3.0)
	glb.position = Vector3(0, 1.1, 0.0)
	add_child(glb)
	_wheel = find_part(glb, "valve_")
	if _wheel == null:
		_wheel = glb

	var valve := make_interactable(Vector3(0.9, 0.9, 0.5), "Crank valve")
	valve.position = Vector3(0, 1.1, 0.25)
	add_child(valve)
	setup_tactile(valve, Interactable.Kind.ROTATE, "ROTATE MOUSE")
	valve.grab_point = _wheel     # the hand grips the wheel + turns with it

	_gauge = make_box(Vector3(0.5, 0.1, 0.06), Color(0.9, 0.45, 0.1), true)
	_gauge.position = Vector3(0, 1.9, 0.1)
	_gmat = _gauge.material_override as StandardMaterial3D
	_gauge.scale.x = 0.02
	add_child(_gauge)


var _dir := 0.0   # locks to the first direction you commit; reversing un-cranks it (friction feel)

## Requires REAL rotation: the first committed direction wins; turning back subtracts. A shake nets ≈0
## (the player's virtual cursor oscillates), so you must actually circle the wheel.
func _apply_gesture(raw: float) -> float:
	if _dir == 0.0 and absf(raw) > 0.01:
		_dir = signf(raw)
	return raw * _dir


func _apply_visual(ratio: float) -> void:
	if _wheel != null:
		_wheel.rotation.z = ratio * turns_required * TAU
	if _gauge != null:
		_gauge.scale.x = maxf(0.02, ratio)
		if _gmat != null:
			_gmat.emission = Color(0.9, 0.45, 0.1).lerp(Color(0.2, 0.95, 0.3), ratio)
