extends PlayerCharacter
## THE ORIGINAL customizable "potato guy" body — a goofy, big-eyed little dude built
## entirely in code, flat PSX-ish materials, big UNSHADED eyes (readable in the dark)
## that jitter + blink, a voice-driven jaw, stubby arms, a per-player tint, and a
## waddle when walking. Every feel value is @export so you can tweak it in the editor
## (this is the "customizable" rig). Concrete subclass of PlayerCharacter, so it drops
## straight into WPlayer like any other body and works with VoiceFaceDriver.

@export_group("Body")
@export var base_color := Color(0.85, 0.72, 0.5)   ## overridden per-player by set_tint()
@export var body_height := 1.15
@export var body_radius := 0.46
@export var head_radius := 0.40

@export_group("Eyes")
@export var eye_size := Vector3(0.3, 0.3, 0.2)     ## big & buggy (set in character.tscn)
@export var eye_spacing := 0.26
@export var eye_height := 1.32
@export var eye_forward := 0.30
@export var pupil_scale := 0.42
@export var blink_every := 3.2                     ## seconds between blinks
@export var blink_dur := 0.13                      ## how long an eye-shut lasts
@export var jitter := 0.02                         ## creepy darting-pupil amount
@export var scared_pop := 0.5                      ## extra eye scale when screaming

@export_group("Mouth")
@export var mouth_min := 0.01                       ## jaw scale when silent (set in character.tscn)
@export var mouth_max := 2.6                         ## jaw scale at full volume
@export var mouth_height := 1.14

@export_group("Limbs / motion")
@export var arm_len := 0.5
@export var waddle := 0.12                           ## body roll while walking

var _body_mat: StandardMaterial3D
var _eye_l: Node3D
var _eye_r: Node3D
var _pupil_l: MeshInstance3D
var _pupil_r: MeshInstance3D
var _mouth: MeshInstance3D
var _limbs: Node3D

var _blink_t := 0.0
var _eye_open := 1.0
var _scared := 0.0
var _move := 0.0
var _blank := false
var _mouth_amt := 0.0


func _ready() -> void:
	_build()


# ---- build ------------------------------------------------------------------
func _build() -> void:
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = base_color
	_body_mat.roughness = 1.0

	# Torso (squashed capsule = potato).
	var torso := _mesh(CapsuleMesh.new(), _body_mat, Vector3(0, body_height * 0.5, 0))
	(torso.mesh as CapsuleMesh).height = body_height
	(torso.mesh as CapsuleMesh).radius = body_radius
	torso.name = "Torso"

	# Head bump on top.
	var head := _mesh(SphereMesh.new(), _body_mat, Vector3(0, body_height - 0.05, 0))
	(head.mesh as SphereMesh).radius = head_radius
	(head.mesh as SphereMesh).height = head_radius * 2.0
	head.name = "Head"

	# Eyes — big white UNSHADED spheres with dark pupils so they read in the dark.
	_eye_l = _make_eye(-eye_spacing)
	_eye_r = _make_eye(eye_spacing)

	# Mouth — a dark box that scales with voice (jaw flap).
	var mmat := StandardMaterial3D.new()
	mmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mmat.albedo_color = Color(0.05, 0.02, 0.03)
	_mouth = _mesh(BoxMesh.new(), mmat, Vector3(0, mouth_height, head_radius + 0.02))
	(_mouth.mesh as BoxMesh).size = Vector3(0.22, 0.06, 0.04)
	_mouth.name = "Mouth"

	# Stubby arms + feet, grouped so we can waddle them.
	_limbs = Node3D.new()
	_limbs.name = "Limbs"
	add_child(_limbs)
	_arm(-body_radius - 0.04)
	_arm(body_radius + 0.04)
	_foot(-0.18)
	_foot(0.18)

	# The face is built on +Z, but a character's FORWARD is -Z (pressing forward moves
	# toward -Z). Flip the rig so the eyes face the way the player walks/looks.
	rotation.y = PI

	set_mouth_open(0.0)


func _mesh(m: Mesh, mat: Material, pos: Vector3, parent: Node = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _make_eye(dx: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(dx, eye_height, eye_forward)
	add_child(pivot)
	var white := StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.albedo_color = Color(0.95, 0.95, 0.92)
	var eye := _mesh(SphereMesh.new(), white, Vector3.ZERO, pivot)
	eye.scale = eye_size
	eye.name = "Eyeball"
	var dark := StandardMaterial3D.new()
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dark.albedo_color = Color(0.03, 0.03, 0.04)
	var pupil := _mesh(SphereMesh.new(), dark, Vector3(0, 0, eye_size.z * 0.5), pivot)
	pupil.scale = eye_size * pupil_scale
	pupil.name = "Pupil"
	if dx < 0.0:
		_pupil_l = pupil
	else:
		_pupil_r = pupil
	return pivot


func _arm(dx: float) -> void:
	var arm := _mesh(CapsuleMesh.new(), _body_mat, Vector3(dx, body_height * 0.55, 0), _limbs)
	(arm.mesh as CapsuleMesh).height = arm_len
	(arm.mesh as CapsuleMesh).radius = 0.12
	arm.rotation.z = 0.25 if dx < 0.0 else -0.25
	arm.name = "Arm"


func _foot(dx: float) -> void:
	var foot := _mesh(BoxMesh.new(), _body_mat, Vector3(dx, 0.08, 0.05), _limbs)
	(foot.mesh as BoxMesh).size = Vector3(0.22, 0.16, 0.34)
	foot.name = "Foot"


# ---- PlayerCharacter interface ---------------------------------------------
func set_tint(c: Color) -> void:
	base_color = c
	if _body_mat != null:
		_body_mat.albedo_color = c


func set_mouth_open(v: float) -> void:
	_mouth_amt = clampf(v, 0.0, 1.0)
	if _mouth != null:
		_mouth.scale.y = lerpf(mouth_min, mouth_max, _mouth_amt)


func set_blank(b: bool) -> void:
	_blank = b                                  # downed -> dead, half-lidded eyes, no jitter


func set_scared(v: float) -> void:
	_scared = clampf(v, 0.0, 1.0)


func set_move(v: float) -> void:
	_move = clampf(v, 0.0, 1.0)


# ---- live expression --------------------------------------------------------
func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001

	# Blink (skipped when downed — dead eyes stay half-shut).
	if _blank:
		_eye_open = lerpf(_eye_open, 0.25, clampf(delta * 8.0, 0.0, 1.0))
	else:
		_blink_t += delta
		var shut := _blink_t > blink_every and _blink_t < blink_every + blink_dur
		if _blink_t >= blink_every + blink_dur:
			_blink_t = 0.0
		_eye_open = lerpf(_eye_open, 0.06 if shut else 1.0, clampf(delta * 26.0, 0.0, 1.0))

	# Scream pops the eyes wide.
	var sc := 1.0 + _scared * scared_pop
	_apply_eye(_eye_l, _pupil_l, sc, t, delta)
	_apply_eye(_eye_r, _pupil_r, sc, t, delta, 1.7)

	# Waddle: roll the body + swing the limbs while walking.
	var roll := sin(t * 9.0) * waddle * _move
	rotation.z = lerpf(rotation.z, roll, clampf(delta * 10.0, 0.0, 1.0))
	if _limbs != null:
		_limbs.rotation.x = sin(t * 9.0) * 0.4 * _move


func _apply_eye(pivot: Node3D, pupil: MeshInstance3D, sc: float, t: float, delta: float, ph := 0.0) -> void:
	if pivot == null:
		return
	var eye := pivot.get_node("Eyeball") as MeshInstance3D
	if eye != null:
		eye.scale = Vector3(eye_size.x * sc, eye_size.y * sc * _eye_open, eye_size.z * sc)
	if pupil != null:
		var j := jitter if not _blank else 0.0
		var off := Vector3(sin(t * 5.0 + ph) * j, cos(t * 4.3 + ph) * j, eye_size.z * 0.5)
		pupil.position = pupil.position.lerp(off, clampf(delta * 12.0, 0.0, 1.0))
		var psc := pupil_scale * (1.0 - _scared * 0.4)      # pupils shrink when scared
		pupil.scale = eye_size * psc
