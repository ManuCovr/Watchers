@tool
class_name DialCalibrationTask
extends Task
## PUZZLE / TACTILE — calibrate the gauge. Grip the dial (HOLD E) and ROTATE the mouse to swing the
## needle; ease it into the lit GREEN target band and hold it there until the reading settles. Let
## go and the needle drifts off-band (the system is unstable), so you must commit a steady hand —
## scary when a figure is closing and you can't look away from the gauge. Fair: a wide-ish band and
## a forgiving settle, the tension is the hold, not pixel precision.

@export var model := "res://assets/tech/gauge_etx_1.glb"
@export var model_scale := 3.0
@export_range(0.1, 0.5, 0.01) var band_halfwidth := 0.28   ## radians; smaller = harder
@export var settle_time := 0.9                              ## seconds in-band to lock
@export var sensitivity := 0.06                             ## gesture units -> radians
@export var drift_speed := 0.6                              ## rad/sec the needle wanders when released

const SWEEP := 2.0   # needle clamps to +/- this (radians)

var _piece: Interactable
var _needle: MeshInstance3D
var _band: MeshInstance3D
var _bmat: StandardMaterial3D
var _angle := 0.0
var _target := 0.0
var _settle := 0.0
var _drift := 1.0
var _user: WPlayer = null
var _baseline := 0.0
var _hum_t := 0.0


func _build() -> void:
	if is_default_title():
		task_title = "Calibrate the gauge"
	task_category = &"puzzle"
	puzzle_task = true
	difficulty = 2
	estimated_duration = 9.0

	var plate := make_box(Vector3(0.9, 0.9, 0.12), Color(0.1, 0.1, 0.12))
	plate.position = Vector3(0, 1.4, -0.1)
	add_child(plate)
	var glb := make_model(model, Vector3(0.6, 0.6, 0.12), Color(0.15, 0.15, 0.17), model_scale)
	glb.position = Vector3(0, 1.4, 0.0)
	add_child(glb)

	# Random target band somewhere in the sweep (not dead-centre, not at a limit).
	_target = randf_range(-SWEEP * 0.6, SWEEP * 0.6)
	_angle = -_target            # start the needle away from the band so there's work to do
	_drift = 1.0 if randf() < 0.5 else -1.0

	# The lit target band marker (a short green wedge at the target angle).
	_band = make_box(Vector3(0.06, 0.34, 0.03), Color(0.2, 0.9, 0.35), true)
	_band.position = Vector3(0, 1.4, 0.1)
	_bmat = _band.material_override as StandardMaterial3D
	add_child(_band)
	_place_at_angle(_band, _target, 0.36)

	# The needle (pivots at the gauge centre).
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 1.4, 0.12)
	add_child(pivot)
	_needle = make_box(Vector3(0.04, 0.4, 0.03), Color(0.95, 0.85, 0.2), true)
	_needle.position = Vector3(0, 0.18, 0)
	pivot.add_child(_needle)
	_needle_pivot = pivot

	var it := make_interactable(Vector3(0.7, 0.7, 0.4), "Calibrate")
	it.position = Vector3(0, 1.4, 0.2)
	it.interaction_type = Interactable.Kind.ROTATE
	it.hold_prompt = "ROTATE MOUSE"
	it.grab_point = _needle
	add_child(it)
	_piece = it


var _needle_pivot: Node3D


func _task_process(delta: float) -> void:
	var user := _find_user()
	if user != null:
		if user != _user:
			_user = user
			_baseline = user.tactile_input
		_angle = clampf(_angle + (user.tactile_input - _baseline) * sensitivity, -SWEEP, SWEEP)
		_baseline = user.tactile_input
	else:
		_user = null
		# Unstable: drift, and bounce off the limits.
		_angle += _drift * drift_speed * delta
		if _angle > SWEEP or _angle < -SWEEP:
			_angle = clampf(_angle, -SWEEP, SWEEP)
			_drift = -_drift

	var in_band := absf(_angle - _target) <= band_halfwidth
	if in_band:
		_settle = minf(settle_time, _settle + delta)
		_hum(delta)
	else:
		_settle = maxf(0.0, _settle - delta * 1.5)

	if _needle_pivot != null:
		_needle_pivot.rotation.z = -_angle
	if _bmat != null:
		# Band glows hotter as it settles in.
		_bmat.emission_energy_multiplier = 1.5 + (_settle / maxf(0.01, settle_time)) * 3.0
	report_progress(_settle / maxf(0.01, settle_time))

	if _settle >= settle_time:
		play_sfx("res://assets/audio/sfx/button_4.ogg", -3.0)
		mark_done()


func _find_user() -> WPlayer:
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as WPlayer
		if p != null and not p._downed and p.is_using(_piece):
			return p
	return null


func _hum(delta: float) -> void:
	_hum_t += delta
	if _hum_t >= 0.4:
		_hum_t = 0.0
		play_sfx("res://assets/audio/sfx/footstep_metal_a_3.ogg", -18.0, 1.3)


## Position a marker around the gauge face at `ang` radians from straight-up, at radius r.
func _place_at_angle(n: Node3D, ang: float, r: float) -> void:
	n.position = Vector3(sin(ang) * r, 1.4 + cos(ang) * r, 0.1)
	n.rotation.z = -ang


func get_progress() -> float:
	return _settle / maxf(0.01, settle_time)
