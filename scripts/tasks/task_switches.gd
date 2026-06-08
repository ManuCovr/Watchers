@tool
class_name SwitchSequenceTask
extends Task
## PHYSICAL breaker LEVERS. You LOOK AT a lever and HOLD E to drag it down; ONLY the lever's
## handle swings (the housing stays bolted to the panel — no more dumb whole-body rotation). It
## resists at the top and commits as it goes, with a strain shake, then springs back if you let
## go early. Pull them in the lit order; a wrong pull trips the whole bank back up. You're
## committed and exposed while you pull, so someone has to cover the dark.

@export var switch_count := 3
@export var spacing := 1.0
@export var pull_time := 0.7                ## seconds of committed holding to fully throw a lever
@export var resistance := 1.0               ## global heaviness (game.gd sets from GameConfig.lever_resistance)
@export var lever_model := "res://assets/tech/lever_etx_1.glb"

var _levers: Array[Interactable] = []       # targetable lever bodies
var _handles: Array[Node3D] = []            # the GLB handle sub-mesh (the ONLY part that moves)
var _inds: Array[MeshInstance3D] = []       # status light per lever
var _pull: Array[float] = []                # 0 up .. 1 fully down
var _locked: Array[bool] = []               # thrown correctly, stays down
var _order: Array[int] = []                 # required step (1..n) per lever
var _next := 1


func _build() -> void:
	if is_default_title():
		task_title = "Throw the breakers in order"
	var steps: Array = []
	for i in switch_count:
		steps.append(i + 1)
	steps.shuffle()

	var start_x := -float(switch_count - 1) * spacing * 0.5
	# Just a slim dark breaker backplate for the levers to mount on (no monitor/console).
	var plate := make_box(Vector3(switch_count * spacing + 0.5, 0.9, 0.12),
		Color(0.1, 0.1, 0.12))
	plate.position = Vector3(0, 1.35, -0.12)
	add_child(plate)

	for i in switch_count:
		# Targetable lever body (you aim at this).
		var lev := make_interactable(Vector3(0.5, 0.7, 0.5), "Pull breaker", Vector3(0, 0.1, 0.1))
		lev.position = Vector3(start_x + i * spacing, 1.3, 0.15)
		add_child(lev)
		# The real lever model; ONLY its handle child will rotate.
		var glb := make_model(lever_model, Vector3(0.2, 0.5, 0.2), Color(0.7, 0.16, 0.16), 3.0)
		lev.add_child(glb)
		var handle := find_part(glb, "child")
		if handle == null:
			handle = glb                # fallback: whole model (shouldn't happen with lever_etx)
		_handles.append(handle)
		# Status light (red = not thrown, green = locked).
		var ind := make_box(Vector3(0.1, 0.1, 0.05), Color(0.85, 0.18, 0.18), true)
		ind.position = Vector3(0, 0.42, 0.16)
		lev.add_child(ind)
		_inds.append(ind)
		_levers.append(lev)
		_pull.append(0.0)
		_locked.append(false)
		_order.append(steps[i])

		# Diegetic order readout: N glowing pips above the lever (no floating text).
		var order_n: int = steps[i]
		for k in order_n:
			var pip := make_box(Vector3(0.045, 0.045, 0.03), Color(0.95, 0.85, 0.2), true)
			pip.position = Vector3(-0.1 + k * 0.1, 0.62, 0.16)
			lev.add_child(pip)


func _task_process(delta: float) -> void:
	# Which lever (if any) is each living player LOOKING AT and holding?
	var being_pulled := {}
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as WPlayer
		if p == null:
			continue
		for i in _levers.size():
			if not _locked[i] and p.is_using(_levers[i]):
				being_pulled[i] = true

	for i in _levers.size():
		if _locked[i]:
			continue
		var before := _pull[i]
		var pt := pull_time * maxf(resistance, 0.1)
		if being_pulled.has(i):
			# Heavy to break free at the top, eases as it commits (you fight the lever).
			var resist := lerpf(0.45, 1.4, _pull[i])
			_pull[i] = minf(1.0, _pull[i] + (delta / pt) * resist)
		else:
			_pull[i] = maxf(0.0, _pull[i] - (delta / pt) * 1.7)   # springs back fast
		# Swing ONLY the handle on its hinge; add a strain shake mid-pull.
		# NEGATIVE so the handle throws UP (was going down).
		var angle := -_pull[i] * 1.5
		var shake := 0.0
		if being_pulled.has(i) and _pull[i] > 0.02 and _pull[i] < 0.98:
			shake = sin(Time.get_ticks_msec() * 0.04 + i) * 0.06 * (1.0 - _pull[i])
		_handles[i].rotation.x = angle + shake
		if _pull[i] >= 1.0 and before < 1.0:
			_thrown(i)


func _thrown(i: int) -> void:
	if _order[i] == _next:
		_locked[i] = true
		_recolor(i, Color(0.2, 0.95, 0.35))
		play_sfx("res://assets/audio/sfx/lever_1.ogg", -4.0, 1.0)
		_next += 1
		report_progress(float(_next - 1) / float(switch_count))
		if _next > switch_count:
			mark_done()
	else:
		# Wrong order — the whole bank trips back up.
		play_sfx("res://assets/audio/sfx/lever_2.ogg", -3.0, 0.7)
		_next = 1
		for j in _levers.size():
			_locked[j] = false
			_pull[j] = 0.0
			_recolor(j, Color(0.85, 0.18, 0.18))


func get_progress() -> float:
	return float(_next - 1) / float(switch_count)


func _recolor(i: int, col: Color) -> void:
	var m := _inds[i].material_override as StandardMaterial3D
	if m != null:
		m.albedo_color = col
		m.emission = col
