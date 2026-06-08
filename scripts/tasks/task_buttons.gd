@tool
class_name ButtonPanelTask
extends Task
## A bunker CONTROL-ROOM panel built from `buttons_etx_black_2` — a single meshed panel with FOUR
## separately-meshed button caps (buttons_etx_black_2_child_1..4). Each cap is individually
## targetable: you LOOK AT one button and press E, and THAT cap physically depresses (not the
## whole panel as one sloppy object). Enter the lit sequence in order to bring the system online;
## a wrong press buzzes and resets the entry. Tactile, electrical, readable.

@export var sequence_length := 4            ## how many presses in the code (clamped to available caps)
@export var model := "res://assets/tech/buttons_etx_black_2.glb"
@export var model_scale := 4.0

var _btns: Array[Interactable] = []         # one per cap
var _caps: Array[Node3D] = []               # the cap sub-mesh that depresses
var _cap_rest: Array[Vector3] = []          # rest local position of each cap
var _depress: Array[float] = []             # 0..1 press animation per cap
var _status: Array[OmniLight3D] = []        # per-button status light
var _order: Array[int] = []                 # the required press order (button indices)
var _step := 0


func _build() -> void:
	if is_default_title():
		task_title = "Key in the control sequence"
	# A slim dark backplate the buttons sit on (no monitor/console fixture).
	var plate := make_box(Vector3(1.3, 1.0, 0.12), Color(0.1, 0.1, 0.12))
	plate.position = Vector3(0, 1.25, -0.12)
	add_child(plate)

	# The button panel, mounted vertically so the caps face the player (+Z).
	var glb := make_model(model, Vector3(1.2, 0.6, 0.1), Color(0.1, 0.1, 0.12), model_scale)
	glb.position = Vector3(0, 1.25, 0.0)
	glb.rotation_degrees = Vector3(-90, 0, 0)   # flat panel -> upright, caps poke toward +Z
	add_child(glb)

	# Grab the four meshed caps and wrap each in its own targetable hit-box.
	var caps: Array[Node3D] = []
	for i in 8:
		var cap := find_part(glb, "child_%d" % (i + 1))
		if cap != null:
			caps.append(cap)
	var n := caps.size()
	if n == 0:
		# Fallback: shouldn't happen with this asset, but stay robust.
		n = 4
	for i in caps.size():
		var cap: Node3D = caps[i]
		_caps.append(cap)
		_cap_rest.append(cap.position)
		_depress.append(0.0)
		var it := make_interactable(Vector3(0.34, 0.34, 0.28), "Press button")
		add_child(it)
		it.global_position = cap.global_position
		_btns.append(it)
		# A small status light beside each cap (off until it's the active step / pressed).
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(0.85, 0.18, 0.16)
		lamp.light_energy = 0.0
		lamp.omni_range = 0.7
		lamp.position = Vector3(0, 0.26, 0.05)
		it.add_child(lamp)
		_status.append(lamp)

	# Build the required order from the available caps.
	var avail: Array = []
	for i in _btns.size():
		avail.append(i)
	avail.shuffle()
	var want: int = clampi(sequence_length, 1, _btns.size())
	for i in want:
		_order.append(avail[i])
	_light_next()


func _light_next() -> void:
	# Amber pulse on the NEXT button to press so the sequence is readable in the dark.
	for i in _status.size():
		_status[i].light_color = Color(0.85, 0.18, 0.16)
		_status[i].light_energy = 0.0
	if _step < _order.size():
		var idx: int = _order[_step]
		_status[idx].light_color = Color(1.0, 0.72, 0.15)
		_status[idx].light_energy = 1.6


func _task_process(delta: float) -> void:
	# Animate cap depress/return.
	for i in _caps.size():
		var pressed_target := 0.0
		_depress[i] = move_toward(_depress[i], pressed_target, delta * 6.0)
		# cap pushes IN along its local -Y (into the panel), scaled by the model scale.
		_caps[i].position = _cap_rest[i] - Vector3(0, _depress[i] * 0.02, 0)

	# Read presses (look at a cap + press E).
	for nd in get_tree().get_nodes_in_group("players"):
		var p := nd as WPlayer
		if p == null or p._downed:
			continue
		for i in _btns.size():
			if p.aimed == _btns[i] and p.consume_interact():
				_press(i)


func _press(i: int) -> void:
	_depress[i] = 1.0
	if _step < _order.size() and _order[_step] == i:
		play_sfx("res://assets/audio/sfx/button_4.ogg", -6.0, 1.0 + _step * 0.06)
		_status[i].light_color = Color(0.2, 0.95, 0.35)
		_status[i].light_energy = 1.4
		_step += 1
		report_progress(float(_step) / float(_order.size()))
		if _step >= _order.size():
			mark_done()
		else:
			_relight()             # keep completed ones green, light the next
	else:
		# Wrong button — buzz and reset the entry.
		play_sfx("res://assets/audio/sfx/button_10.ogg", -4.0, 0.6)
		_step = 0
		_light_next()


## Re-light the status lamps: completed steps green, the next step amber, the rest off.
func _relight() -> void:
	var done_idxs := _order.slice(0, _step)
	for i in _status.size():
		if i in done_idxs:
			_status[i].light_color = Color(0.2, 0.95, 0.35)
			_status[i].light_energy = 0.9
		else:
			_status[i].light_color = Color(0.85, 0.18, 0.16)
			_status[i].light_energy = 0.0
	if _step < _order.size():
		var idx: int = _order[_step]
		_status[idx].light_color = Color(1.0, 0.72, 0.15)
		_status[idx].light_energy = 1.6


func get_progress() -> float:
	return float(_step) / float(maxi(_order.size(), 1))
