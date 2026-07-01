@tool
class_name TactileTask
extends Task
## Base for PHYSICAL hold-and-gesture tasks (levers you pull, valves you crank). The whole point: it's
## not an instant press. You look at the part, HOLD E (the detached hand reaches out and grips it),
## and DRAG the mouse — down for a lever, in a circle for a valve. The part follows your gesture, it
## resists (a damped climb), it bleeds back if you let go, and clunks home when you finish.
##
## Server-authoritative like every Task: the authority reads the using player's replicated
## `tactile_input` (a monotonic gesture accumulator), diffs it per frame, and advances progress.
## Subclasses provide the prop + override `_apply_gesture()` (sign/direction) and `_apply_visual()`.
##
## One active user per task (first to grab it wins for the frame) — co-op simultaneous use is a later pass.

@export var reach := 2.6
@export_range(0.0, 4.0, 0.05) var resistance := 0.5     ## higher = the gesture climbs slower (effort)
@export var gesture_per_unit := 9.0                      ## gesture units to go 0 -> 1 (tune the feel)
@export_range(0.0, 1.0, 0.01) var decay_per_sec := 0.25  ## progress lost/sec when released (if not held)
@export var hold_partial := false                        ## keep partial progress when released
@export_range(0.5, 1.0, 0.01) var completion_threshold := 0.99
@export_group("Strain")
@export var strain_enabled := true
@export var strain_sound := "res://assets/audio/sfx/footstep_metal_a_3.ogg"
@export var done_sound := ""

var _piece: Interactable
var _progress := 0.0
var _user: WPlayer = null
var _baseline := 0.0
var _strain_t := 0.0


## Subclass calls this from _build() once it has created its interactable handle.
func setup_tactile(piece: Interactable, kind: int, hold_prompt: String) -> void:
	_piece = piece
	piece.interaction_type = kind
	piece.hold_prompt = hold_prompt


func _task_process(delta: float) -> void:
	if done or _piece == null:
		return
	var user := _find_user()
	if user != null:
		if user != _user:
			_user = user
			_baseline = user.tactile_input          # grabbed: rebase so there's no jump
		var raw := user.tactile_input - _baseline
		_baseline = user.tactile_input
		var contrib := _apply_gesture(raw) / (1.0 + resistance)
		_progress = clampf(_progress + contrib / maxf(0.01, gesture_per_unit), 0.0, 1.0)
		_strain(delta, true)
	else:
		_user = null
		if not hold_partial:
			_progress = maxf(0.0, _progress - decay_per_sec * delta)
		_strain(delta, false)
	_apply_visual(_progress)
	report_progress(_progress)
	if _progress >= completion_threshold:
		if done_sound != "":
			play_sfx(done_sound, -3.0)
		_apply_visual(1.0)
		mark_done()


func _find_user() -> WPlayer:
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as WPlayer
		if p != null and p.is_using(_piece):
			return p
	return null


## Creak feedback while the gesture is actively moving the part.
func _strain(delta: float, working: bool) -> void:
	if not strain_enabled or strain_sound == "":
		return
	if working:
		_strain_t += delta
		var gap := lerpf(0.5, 0.22, _progress)        # tighter creaks as it nears the end (effort)
		if _strain_t >= gap:
			_strain_t = 0.0
			play_sfx(strain_sound, -14.0, randf_range(0.7, 0.95))
	else:
		_strain_t = 0.6


# ---- override points --------------------------------------------------------
## Map a raw gesture delta (this frame) to a forward contribution. PULL: down-only. ROTATE: signed.
func _apply_gesture(raw: float) -> float:
	return maxf(0.0, raw)


## Move the prop's part to reflect 0..1 progress (rotate a wheel, swing a lever).
func _apply_visual(_ratio: float) -> void:
	pass


func get_progress() -> float:
	return _progress
