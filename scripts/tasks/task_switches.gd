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
@export var pull_drag := 4.0                ## heaviness divisor (higher = more body weight to throw it)
@export var max_pull_rate := 2.5            ## cap useful drag speed (units/sec) — forces a slow committed heave
@export var resistance := 1.0               ## global heaviness (game.gd sets from GameConfig.lever_resistance)
@export var lever_model := "res://assets/tech/lever_etx_2_1.glb"
var _active_user: WPlayer = null
var _active_lever := -1
var _active_baseline := 0.0
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
	task_category = &"puzzle"
	puzzle_task = true
	difficulty = 2 if switch_count <= 3 else 3   # longer ordered pulls = harder
	estimated_duration = 4.0 + switch_count * 2.0
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
		# Targetable lever body (you aim at this). HOLD E + drag the mouse DOWN to throw it.
		var lev := make_interactable(Vector3(0.5, 0.7, 0.5), "Grab breaker", Vector3(0, 0.1, 0.1))
		lev.interaction_type = Interactable.Kind.PULL
		lev.hold_prompt = "PULL MOUSE DOWN"
		lev.position = Vector3(start_x + i * spacing, 1.3, 0.15)
		add_child(lev)
		# The real lever model; ONLY its handle child will rotate.
		var glb := make_model(lever_model, Vector3(0.2, 0.5, 0.2), Color(0.7, 0.16, 0.16), 3.0)
		lev.add_child(glb)
		var handle := find_part(glb, "child")
		if handle == null:
			handle = glb                # fallback: whole model (shouldn't happen with lever_etx)
		_handles.append(handle)
		lev.grab_point = handle      # the hand grips the actual handle sub-mesh + follows it as it swings
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
	# Which lever is a living player gripping (HOLD E aimed)? One active puller at a time.
	var puller: WPlayer = null
	var pull_lever := -1
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as WPlayer
		if p == null:
			continue
		for i in _levers.size():
			if not _locked[i] and p.is_using(_levers[i]):
				puller = p
				pull_lever = i
				break
		if puller != null:
			break

	# Rebase the gesture accumulator whenever the active puller/lever changes (no progress jump).
	if puller != _active_user or pull_lever != _active_lever:
		_active_user = puller
		_active_lever = pull_lever
		if puller != null:
			_active_baseline = puller.tactile_input

	for i in _levers.size():
		if _locked[i]:
			continue
		var before := _pull[i]
		if i == pull_lever and puller != null:
			var raw := puller.tactile_input - _active_baseline   # downward mouse drag this frame
			_active_baseline = puller.tactile_input
			# FRICTION: cap the useful drag RATE (units/sec, FPS-independent) so a flick can't cheat — you
			# must keep heaving a steady downward drag. Heavier near the bottom, but always achievable.
			var drag := clampf(raw, 0.0, max_pull_rate * delta)
			var heavy := lerpf(1.0, 1.8, _pull[i]) * maxf(resistance, 0.1)
			_pull[i] = clampf(_pull[i] + drag / maxf(0.1, pull_drag * heavy), 0.0, 1.0)
		else:
			_pull[i] = maxf(0.0, _pull[i] - delta * 1.4)         # springs back when released
		# Swing ONLY the handle on its hinge; add a strain shake mid-pull.
		var angle := -_pull[i] * 1.5
		var shake := 0.0
		if i == pull_lever and _pull[i] > 0.02 and _pull[i] < 0.98:
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
