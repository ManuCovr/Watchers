@tool
class_name KeypadTask
extends Task
## PUZZLE — read the code, key it in. A short COLOUR code is displayed on a readout strip ABOVE
## the keypad (the "environment clue"); you reproduce it on the coloured keys below. Unlike the
## control panel (which lights the NEXT key for you), here NOTHING on the keys is lit — you must
## look at the readout, remember it, then enter it. A wrong key buzzes and resets your entry.
## Short (3-4 symbols), fair, readable by colour (no tiny text).

@export_range(2, 5) var code_length := 3
@export var model := "res://assets/psx/Small Props/keypad_1.glb"
@export var model_scale := 3.0

# Four distinct, colour-blind-ish readable keys.
const KEY_COLORS: Array[Color] = [
	Color(0.92, 0.22, 0.20),   # red
	Color(0.25, 0.85, 0.35),   # green
	Color(0.30, 0.55, 1.0),    # blue
	Color(0.95, 0.80, 0.18),   # amber
]

var _keys: Array[Interactable] = []
var _caps: Array[MeshInstance3D] = []
var _cap_rest: Array[Vector3] = []
var _depress: Array[float] = []
var _readout: Array[MeshInstance3D] = []   # the displayed code squares (the clue)
var _code: Array[int] = []                 # color index per step
var _step := 0


func _build() -> void:
	if is_default_title():
		task_title = "Key in the access code"
	task_category = &"puzzle"
	puzzle_task = true
	difficulty = 2
	estimated_duration = 7.0

	# Dark backplate + the keypad body.
	var plate := make_box(Vector3(1.1, 1.3, 0.12), Color(0.1, 0.1, 0.12))
	plate.position = Vector3(0, 1.3, -0.12)
	add_child(plate)
	var glb := make_model(model, Vector3(0.7, 0.7, 0.12), Color(0.12, 0.12, 0.14), model_scale)
	glb.position = Vector3(0, 1.05, 0.0)
	add_child(glb)

	# Roll the code (random colours; repeats allowed so memorising matters).
	for i in code_length:
		_code.append(randi() % KEY_COLORS.size())

	# Readout strip ABOVE — the clue you must read. N lit colour squares in order.
	var rstart := -float(code_length - 1) * 0.16 * 0.5
	for i in code_length:
		var sq := make_box(Vector3(0.13, 0.13, 0.04), KEY_COLORS[_code[i]], true)
		sq.position = Vector3(rstart + i * 0.16, 1.78, 0.08)
		add_child(sq)
		_readout.append(sq)

	# The four coloured keys in a row — NOT lit (you read the clue, then press).
	for i in KEY_COLORS.size():
		var it := make_interactable(Vector3(0.22, 0.22, 0.2), "Press key")
		it.position = Vector3(-0.3 + i * 0.2, 1.05, 0.16)
		add_child(it)
		_keys.append(it)
		var cap := make_box(Vector3(0.17, 0.17, 0.08), KEY_COLORS[i], true)
		var m := cap.material_override as StandardMaterial3D
		m.emission_energy_multiplier = 0.7   # dim until pressed
		it.add_child(cap)
		it.grab_point = cap
		_caps.append(cap)
		_cap_rest.append(cap.position)
		_depress.append(0.0)


func _task_process(delta: float) -> void:
	for i in _caps.size():
		_depress[i] = move_toward(_depress[i], 0.0, delta * 6.0)
		_caps[i].position = _cap_rest[i] - Vector3(0, 0, _depress[i] * 0.05)

	for nd in get_tree().get_nodes_in_group("players"):
		var p := nd as WPlayer
		if p == null or p._downed:
			continue
		for i in _keys.size():
			if p.aimed == _keys[i] and p.consume_interact():
				_press(i)


func _press(color_idx: int) -> void:
	_depress[color_idx] = 1.0
	if _step < _code.size() and _code[_step] == color_idx:
		play_sfx("res://assets/audio/sfx/button_4.ogg", -6.0, 1.0 + _step * 0.08)
		_dim_readout(_step)            # tick off the entered symbol
		_step += 1
		report_progress(float(_step) / float(_code.size()))
		if _step >= _code.size():
			mark_done()
	else:
		# Wrong key — buzz, reset the entry and re-light the whole clue.
		play_sfx("res://assets/audio/sfx/button_10.ogg", -4.0, 0.6)
		_step = 0
		_relight_readout()


func _dim_readout(i: int) -> void:
	var m := _readout[i].material_override as StandardMaterial3D
	if m != null:
		m.emission_energy_multiplier = 0.15


func _relight_readout() -> void:
	for sq in _readout:
		var m := sq.material_override as StandardMaterial3D
		if m != null:
			m.emission_energy_multiplier = 2.0


func get_progress() -> float:
	return float(_step) / float(maxi(_code.size(), 1))
