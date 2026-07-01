@tool
class_name BreakerPatternTask
extends Task
## PUZZLE — match the diagram. A row of breakers each sits UP or DOWN. A target diagram above the
## panel shows the pattern they SHOULD be in (a lit pip above = should be up, below = should be
## down). Press a breaker to flip it; when EVERY breaker matches its target, the bank latches and
## the task completes. No fail state — it's a think-and-set, not a memory trap. Distinct from the
## ordered-pull breakers (SwitchSequenceTask): here you read a pattern and reproduce it.

@export_range(3, 6) var breaker_count := 4
@export var spacing := 0.55

var _switches: Array[Interactable] = []
var _arms: Array[MeshInstance3D] = []      # the flip arm (rotates up/down)
var _state: Array[bool] = []               # true = up
var _target: Array[bool] = []              # desired up/down
var _match_lamp: Array[MeshInstance3D] = []  # per-breaker: green when it matches target


func _build() -> void:
	if is_default_title():
		task_title = "Match the breaker pattern"
	task_category = &"puzzle"
	puzzle_task = true
	difficulty = 2
	estimated_duration = 7.0

	var width := breaker_count * spacing + 0.4
	var plate := make_box(Vector3(width, 1.1, 0.12), Color(0.1, 0.1, 0.12))
	plate.position = Vector3(0, 1.3, -0.12)
	add_child(plate)

	var start_x := -float(breaker_count - 1) * spacing * 0.5
	for i in breaker_count:
		var x := start_x + i * spacing
		# Roll a target; randomise the starting state so it's never already solved.
		var want := randf() < 0.5
		_target.append(want)
		var start_up := want
		while start_up == want:        # guarantee at least a flip is needed somewhere
			start_up = randf() < 0.5
		_state.append(start_up)

		# Target diagram: a lit pip ABOVE (want up) or BELOW (want down) the breaker.
		var pip := make_box(Vector3(0.09, 0.09, 0.04), Color(0.55, 0.7, 1.0), true)
		pip.position = Vector3(x, 1.3 + (0.34 if want else -0.34), 0.1)
		add_child(pip)

		# The breaker housing + flip arm (only the arm rotates).
		var housing := make_box(Vector3(0.18, 0.5, 0.12), Color(0.16, 0.16, 0.18))
		housing.position = Vector3(x, 1.3, 0.02)
		add_child(housing)
		var arm := make_box(Vector3(0.1, 0.26, 0.1), Color(0.7, 0.68, 0.6))
		arm.position = Vector3(x, 1.3, 0.12)
		add_child(arm)
		_arms.append(arm)

		var it := make_interactable(Vector3(0.3, 0.5, 0.28), "Flip breaker")
		it.position = Vector3(x, 1.3, 0.14)
		add_child(it)
		it.grab_point = arm
		_switches.append(it)

		# Per-breaker match light (green when this one matches its target).
		var lamp := make_box(Vector3(0.07, 0.07, 0.04), Color(0.85, 0.18, 0.18), true)
		lamp.position = Vector3(x, 1.05, 0.12)
		add_child(lamp)
		_match_lamp.append(lamp)

	_refresh_visuals()


func _task_process(_delta: float) -> void:
	for nd in get_tree().get_nodes_in_group("players"):
		var p := nd as WPlayer
		if p == null or p._downed:
			continue
		for i in _switches.size():
			if p.aimed == _switches[i] and p.consume_interact():
				_state[i] = not _state[i]
				play_sfx("res://assets/audio/sfx/lever_1.ogg", -8.0, randf_range(0.9, 1.1))
				_refresh_visuals()
				_check_solved()
				break


func _refresh_visuals() -> void:
	var matched := 0
	for i in _arms.size():
		_arms[i].rotation.x = -0.6 if _state[i] else 0.6   # up vs down tilt
		var ok := _state[i] == _target[i]
		if ok:
			matched += 1
		var m := _match_lamp[i].material_override as StandardMaterial3D
		if m != null:
			var col := Color(0.2, 0.95, 0.35) if ok else Color(0.85, 0.18, 0.18)
			m.albedo_color = col
			m.emission = col
	report_progress(float(matched) / float(maxi(breaker_count, 1)))


func _check_solved() -> void:
	for i in _state.size():
		if _state[i] != _target[i]:
			return
	play_sfx("res://assets/audio/sfx/button_4.ogg", -3.0)
	mark_done()


func get_progress() -> float:
	if done:
		return 1.0
	var matched := 0
	for i in _state.size():
		if _state[i] == _target[i]:
			matched += 1
	return float(matched) / float(maxi(breaker_count, 1))
