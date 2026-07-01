class_name DetachedHandsController
extends Node3D
## Spawns + drives the two detached 3-finger blob hands. VISUAL ONLY — it never owns physics; it
## reads the player's already-existing item state (held_item / aimed_item / throw / swing)
## and poses the hands to match. Lives under the blob model wrapper, so it inherits the body's render
## layer (hidden from the owner's own camera, visible to teammates + the mirror) for free.
##
## A clean idea that keeps this small: while holding/charging/swinging, the holding hand simply TRACKS
## the held item's transform. Because the item already drives itself through its hold pose and its full
## swing arc, the hand follows that arc automatically — no separate hand swing state machine needed.

const HAND_RIGHT := preload("res://actors/player_hands/detached_hand_right.tscn")
const HAND_LEFT := preload("res://actors/player_hands/detached_hand_left.tscn")

enum HandState { IDLE, REACH, HOLDING, CHARGING, SWING }

@export var enabled := true
## Use the low-poly FBX hands (5 swappable pose meshes: open / fist / grab / point / thumbs-up)
## instead of the rigged 3-finger GLBs. Flip to false to restore the hand-tuned GLB hands.
@export var pose_hands := true
@export var follow_speed := 14.0          ## idle hand catch-up toward its rest point
@export var hold_speed := 22.0            ## snappier tracking of a held item
@export var idle_sway_amount := 0.0015     ## near-zero: hands sit locked to the view, not swimming
@export var idle_sway_speed := 1.6
@export var idle_bob_amount := 0.0015      ## near-zero vertical breathing (the camera bob already moves them)
@export var idle_breathe := 0.06           ## tiny finger flex while idle (life, not stiffness)
@export var reach_amount := 0.5            ## how far the hand lifts toward a hovered pickup (0..1)
@export_group("First-person viewmodel (local player)")
## Camera-space rest positions for YOUR own hands (GWF-style): in front, low, drawn inward so it
## never reads as a T-pose. +X right, +Y up, -Z forward.
## Lower + wider + a bit further out so they sit at the bottom edges of the view (GWF feel), not
## floating dead-centre in your face.
## Raised well into view (the old values cut them off at the screen edge). GWF hands sit ~lower third
## and you see the whole mitt, fingers up.
@export var fp_right_offset := Vector3(0.40, -0.34, -0.52)
@export var fp_left_offset := Vector3(-0.40, -0.34, -0.52)
## ---- FP HAND AIM: edit these 3 numbers (degrees). Base orientation = palm OUT, fingers UP. ----
## Each dial rotates about ONE camera axis, so they do not fight each other. Reload the project after editing.
@export var fp_rest_pitch_deg := -10.0   ## fingers NOD: more negative = point up, positive = point down/forward
@export var fp_rest_spin_deg := 0.0      ## PALM facing: 0 = out (away from you), 90 = to the side, 180 = toward you
@export var fp_rest_lean_deg := 12.0     ## fingertips tip INWARD toward screen centre (0 = straight)
@export var fp_bob_amount := 0.006         ## tiny extra bob — the camera already head-bobs; keep this small
## Higher = the hands stay locked to the view (steady, don't swim). Lower = more trailing turn-lag.
## Kept fairly high so the hands DON'T slosh around while walking.
@export var fp_follow_strength := 40.0
@export var debug_draw := false:
	set(v):
		debug_draw = v
		if _left != null: _left.debug_draw = v
		if _right != null: _right.debug_draw = v

var _player: Node                          # the WPlayer that owns us
var _model: Node3D                         # the PlayerModelView wrapper (has hand_anchor())
var _left: DetachedHand
var _right: DetachedHand
var _left_anchor: Marker3D
var _right_anchor: Marker3D
var _t := 0.0
var _first := true                         # snap to anchors on the first live frame (post-spawn)
var _local := false                        # this is the owner's own player -> first-person hands
var _cam: Camera3D                          # owner camera, for the viewmodel rest pose

## item_name substring -> three-finger curl preset [thumb, A, B]. This is the data table (NOT hidden
## in player.gd); a PhysicsItem may also carry its own HandPoseResource to override per item.
const GRIP_PRESETS := {
	"crowbar": [0.85, 0.95, 0.95], "wrench": [0.85, 0.95, 0.95], "hammer": [0.85, 0.95, 0.95],
	"bat": [0.8, 0.92, 0.92], "rolling": [0.82, 0.92, 0.92], "baguette": [0.8, 0.9, 0.9],
	"cross": [0.85, 0.95, 0.95], "pipe": [0.85, 0.95, 0.95],
	"fish": [0.25, 0.32, 0.32],
	"bottle": [0.6, 0.72, 0.72], "phone": [0.55, 0.7, 0.7], "can": [0.6, 0.72, 0.72],
	"brick": [0.75, 0.86, 0.86],
	"luggage": [0.45, 0.55, 0.55], "case": [0.45, 0.55, 0.55],
}
const GRIP_DEFAULT := [0.6, 0.72, 0.72]
const RELAXED := [0.18, 0.22, 0.22]
const REACH_POSE := [0.05, 0.12, 0.12]


## Called by the model wrapper once it has built (so the anchors exist).
func setup(player: Node, model: Node3D, tint: Color) -> void:
	_player = player
	_model = model
	if model.has_method("hand_anchor"):
		_left_anchor = model.hand_anchor(true)
		_right_anchor = model.hand_anchor(false)
	# Each mesh on its matching side (left mesh = left hand).
	_left = HAND_LEFT.instantiate() as DetachedHand
	_right = HAND_RIGHT.instantiate() as DetachedHand
	for h in [_left, _right]:
		h.top_level = true                 # move in world space -> detached, smoothly trailing
		h.tint = tint
		h.pose_hands = pose_hands          # set BEFORE add_child so _build picks the pose-mesh form
		add_child(h)
	_left.debug_draw = debug_draw
	_right.debug_draw = debug_draw
	# Snap to anchors on the first frame so they don't fly in from the origin.
	if _left_anchor != null: _left.global_transform = _left_anchor.global_transform
	if _right_anchor != null: _right.global_transform = _right_anchor.global_transform


func set_tint(c: Color) -> void:
	if _left != null: _left.set_tint(c)
	if _right != null: _right.set_tint(c)


## Local player only: show our own hands to our camera and drive them as a viewmodel. The body lives
## on the self-hide layer; we put the hands back on a camera-visible layer (layer 1).
func set_first_person(cam: Camera3D) -> void:
	_local = true
	_cam = cam
	if _left != null: _left.set_render_layer(1)
	if _right != null: _right.set_render_layer(1)


func _process(delta: float) -> void:
	if not enabled or _left == null or _right == null or _model == null:
		return
	if _left_anchor == null or _right_anchor == null:
		return
	if _first:
		_first = false
		_left.global_transform = _left_anchor.global_transform
		_right.global_transform = _right_anchor.global_transform
	_t += delta

	# Button POKE: a RANDOM hand jabs out (pointing) to the pressed button for a moment.
	if _player != null and _player.has_method("poke_active") and _player.poke_active():
		var left_pokes: bool = _player.poke_is_left() if _player.has_method("poke_is_left") else false
		var poker := _left if left_pokes else _right
		var other := _right if left_pokes else _left
		_poke_hand(poker, _player.poke_point(), delta)
		_idle_hand(other, _left_anchor if left_pokes else _right_anchor, delta, RELAXED)
		return

	# Tactile gesture (lever/valve): the RIGHT hand reaches out and grips the part while you drag.
	var tac = _player.call("tactile_target") if _player != null and _player.has_method("tactile_target") else null
	if tac is Node3D:
		_tactile_hand(_right, tac as Node3D, delta)
		_idle_hand(_left, _left_anchor, delta, RELAXED)
		return

	var st := _state()
	var item := _visual_item()
	# CARGO (a recoverable) is carried REPO-style: it floats centred in front and BOTH hands stay OPEN,
	# framing it from the sides — never gripped, never a weapon.
	var cargo := item != null and item is RecoverableObject
	var holding := st == HandState.HOLDING or st == HandState.CHARGING or st == HandState.SWING

	# RIGHT hand = the active/holding hand.
	match st:
		HandState.HOLDING, HandState.CHARGING, HandState.SWING:
			if item != null and cargo:
				_carry_hand(_right, item, 1.0, delta)
			elif item != null:
				var grip := _grip_for(item)
				_track_item(_right, item, st)
				_right.set_curls(grip[0], grip[1], grip[2])
				_right.set_pose(DetachedHand.POSE_FIST if st == HandState.SWING else DetachedHand.POSE_GRAB)
			else:
				_idle_hand(_right, _right_anchor, delta, RELAXED)
		HandState.REACH:
			_reach_hand(_right, _right_anchor, delta)
		_:
			_idle_hand(_right, _right_anchor, delta, RELAXED)

	# LEFT hand: frames cargo from the other side, supports a two-handed item, else idle.
	var two_handed := item != null and ("luggage" in item.item_name.to_lower() or "case" in item.item_name.to_lower() or _item_two_handed(item))
	if cargo and holding:
		_carry_hand(_left, item, -1.0, delta)
	elif two_handed and holding:
		_support_hand(_left, item, delta)
	else:
		_idle_hand(_left, _left_anchor, delta, RELAXED)


## REPO carry: hold an OPEN hand to one SIDE of the floating cargo (palm toward it), framing it rather
## than gripping. `side` = +1 right, −1 left.
func _carry_hand(hand: DetachedHand, item: PhysicsItem, side: float, delta: float) -> void:
	var b := item.global_transform.basis
	var off := b * Vector3(side * 0.18, -0.03, 0.0)
	_move(hand, Transform3D(b, item.global_position + off), hold_speed, delta)
	hand.set_curls(0.0, 0.0, 0.0)
	hand.set_pose(DetachedHand.POSE_OPEN)


# ---- state ------------------------------------------------------------------
func _state() -> HandState:
	if _player == null or not is_instance_valid(_player):
		return HandState.IDLE
	var held = _player.get("held_item")
	if held != null and is_instance_valid(held):
		var swinging: bool = held.has_method("is_swinging") and held.is_swinging()
		var charging: bool = held.has_method("charge_ratio") and held.charge_ratio() > 0.01
		if swinging:
			return HandState.SWING
		if charging:
			return HandState.CHARGING
		return HandState.HOLDING
	# empty-handed: are we hovering a pickup?
	var aimed = _player.get("aimed_item")
	if aimed != null and is_instance_valid(aimed):
		return HandState.REACH
	return HandState.IDLE


## The item to visually attach to: the real held_item (set on the holder), else nothing.
func _visual_item() -> PhysicsItem:
	var held = _player.get("held_item") if _player != null else null
	if held != null and is_instance_valid(held):
		return held as PhysicsItem
	return null


func _item_two_handed(item: PhysicsItem) -> bool:
	return item != null and item.get("two_handed") == true


func _grip_for(item: PhysicsItem) -> Array:
	# per-item HandPoseResource override wins
	var pose = item.get("hand_pose")
	if pose is HandPoseResource:
		var c := (pose as HandPoseResource).curls()
		return [c[0], c[1], c[2]]
	var name := item.item_name.to_lower()
	for key in GRIP_PRESETS:
		if key in name:
			return GRIP_PRESETS[key]
	return GRIP_DEFAULT


# ---- hand posing ------------------------------------------------------------
## The resting transform for a hand: a camera-relative VIEWMODEL pose for the local player (so YOU
## see your hands out front, never T-posed), or the body anchor for everyone else (third-person).
func _rest_target(is_right: bool, anchor: Marker3D) -> Transform3D:
	var sway := Vector3(
		sin(_t * idle_sway_speed) * idle_sway_amount,
		sin(_t * idle_sway_speed * 1.3 + 1.0) * idle_sway_amount + sin(_t * 0.9) * idle_bob_amount,
		0.0)
	if _local and _cam != null and is_instance_valid(_cam):
		# extra hand bob while moving (cam already bobs; this adds weighty lag on top)
		var spd := 0.0
		var v = _player.get("velocity")
		if v is Vector3:
			spd = clampf((v as Vector3).length() * 0.28, 0.0, 1.0)
		var bob := Vector3(
			sin(_t * 8.0) * fp_bob_amount * spd * (1.0 if is_right else -1.0),
			-absf(sin(_t * 8.0)) * fp_bob_amount * spd,
			0.0)
		var off := (fp_right_offset if is_right else fp_left_offset) + sway + bob
		var base := Basis(Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0))   # palm OUT, fingers UP
		var pitch := Basis(Vector3(1, 0, 0), deg_to_rad(fp_rest_pitch_deg))                                   # nod (camera X)
		var spin  := Basis(Vector3(0, 1, 0), deg_to_rad(fp_rest_spin_deg) * (1.0 if is_right else -1.0))     # palm facing (camera UP)
		var lean  := Basis(Vector3(0, 0, 1), deg_to_rad(fp_rest_lean_deg) * (1.0 if is_right else -1.0))     # inward tip (camera fwd)
		var b := pitch * spin * lean * base
		return _cam.global_transform * Transform3D(b, off)
	var target := anchor.global_transform
	target.origin += _model.global_transform.basis * sway
	return target


## Idle: ease toward the rest pose, relaxed fingers with a tiny breathing flex (alive, not stiff).
func _idle_hand(hand: DetachedHand, anchor: Marker3D, delta: float, curls: Array) -> void:
	var is_right := hand == _right
	# local FP uses the softer follow (turn-lag) so the hands trail + catch up; remotes use follow_speed
	var spd := fp_follow_strength if (_local and _cam != null) else follow_speed
	_move(hand, _rest_target(is_right, anchor), spd, delta)
	var breathe := idle_breathe * (0.5 + 0.5 * sin(_t * 1.4 + (1.0 if is_right else 0.0)))
	hand.set_curls(curls[0] + breathe, curls[1] + breathe, curls[2] + breathe)
	hand.set_pose(DetachedHand.POSE_OPEN)


## Reach: lift the hand partway toward the hovered pickup, fingers opening to grab.
func _reach_hand(hand: DetachedHand, anchor: Marker3D, delta: float) -> void:
	var aimed = _player.get("aimed_item")
	var target := _rest_target(hand == _right, anchor)
	if aimed != null and is_instance_valid(aimed):
		target.origin = target.origin.lerp((aimed as Node3D).global_position, reach_amount)
	_move(hand, target, hold_speed * 0.6, delta)
	hand.set_curls(REACH_POSE[0], REACH_POSE[1], REACH_POSE[2])
	hand.set_pose(DetachedHand.POSE_POINT)


## Track a held item's transform so the hand sits on it and rides its swing arc.
func _track_item(hand: DetachedHand, item: PhysicsItem, st: int) -> void:
	var basis := item.global_transform.basis
	var grab_off := basis * Vector3(0, 0, 0.04)        # nudge palm onto the grip
	var target := Transform3D(basis, item.global_position + grab_off)
	# Hard-follow during a swing so the hand stays glued to the fast arc.
	var spd := hold_speed * (2.2 if st == HandState.SWING else 1.0)
	_move(hand, target, spd, get_process_delta_time())


## Two-handed support: park the off-hand on the far side of the item.
## Jab the right hand out to a pressed button with the pointing finger. Phase-driven (0→1→0) so it
## TRAVELS out and back instead of teleporting — position is set directly (local hands otherwise snap).
func _poke_hand(hand: DetachedHand, point: Vector3, _delta: float) -> void:
	var rest := _rest_target(hand == _right, _right_anchor)
	var ph := 0.5
	if _player.has_method("poke_phase"):
		ph = _player.poke_phase()
	var reach := sin(ph * PI)                          # 0 at rest, 1 at the button, back to 0
	var pos := rest.origin.lerp(point, reach * 0.95)
	var basis := rest.basis
	var dir := point - pos
	if dir.length() > 0.05:                            # rotate the hand to AIM the finger at the button
		basis = rest.basis.slerp(Basis.looking_at(dir.normalized(), Vector3.UP), reach)
	hand.global_transform = Transform3D(basis, pos)   # direct -> smooth out-and-back travel
	hand.set_curls(0.15, 0.0, 0.9)                    # index extended, others tucked
	hand.set_pose(DetachedHand.POSE_POINT)


## Reach the right hand to a tactile part (lever/valve handle) and grip it while the player gestures.
func _tactile_hand(hand: DetachedHand, target: Node3D, delta: float) -> void:
	var t := _rest_target(hand == _right, _right_anchor)
	t.origin = target.global_position                # ON the handle/rim (it follows the part as it moves)
	_move(hand, t, hold_speed, delta)
	hand.set_curls(0.85, 0.95, 0.95)
	hand.set_pose(DetachedHand.POSE_GRAB)


func _support_hand(hand: DetachedHand, item: PhysicsItem, delta: float) -> void:
	if item == null:
		return
	var basis := item.global_transform.basis
	var target := Transform3D(basis, item.global_position + basis * Vector3(0, -0.06, -0.18))
	_move(hand, target, hold_speed, delta)
	hand.set_curls(0.7, 0.8, 0.8)
	hand.set_pose(DetachedHand.POSE_GRAB)


func _move(hand: DetachedHand, target: Transform3D, speed: float, delta: float) -> void:
	# YOUR own (local) hands snap straight to the camera-relative target every frame, so they ride the
	# SAME transform the view is rendered from -> rigidly attached, no chase-jitter and no swim. Only
	# remote teammates' hands smooth (they interpolate from replicated state, so trailing reads fine).
	if _local:
		hand.global_transform = target
		return
	var k := clampf(delta * speed, 0.0, 1.0)
	var np := hand.global_position.lerp(target.origin, k)
	var cq := hand.global_transform.basis.get_rotation_quaternion()
	var tq := target.basis.get_rotation_quaternion()
	var nq := cq.slerp(tq, k)
	hand.global_transform = Transform3D(Basis(nq), np)
