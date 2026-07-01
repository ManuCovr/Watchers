class_name PlayerModelView
extends PlayerCharacter
## VISUAL-ONLY wrapper for an imported blob player GLB. This is the reusable spine of the
## player-model pipeline: paint a variant in Blender -> export .glb -> drop it under this
## wrapper -> swap it per player. It owns NOTHING about movement or networking; it only
## presents a model (face texture, body tint, outline, mouth/speaking, walk bob).
##
## WHY it extends PlayerCharacter: WPlayer (player.gd) instances `character_scene` and talks
## to it ONLY through the PlayerCharacter interface (set_tint/set_mouth_open/set_blank/...).
## By extending it, every blob variant .tscn is a drop-in body — no changes to player.gd, and
## the voice-mouth driver, lobby mirror, and downed/revive logic all work unchanged.
##
## TWO ways to give it a model (pick one, per variant scene):
##   A) EDITOR-VISIBLE: instance the variant .glb as a child named "ModelRoot" in the .tscn.
##      You see it in the editor; the script finds it by name at runtime.
##   B) DATA-DRIVEN: leave the export `model_scene` assigned and no child; it instances at run.
## Either way, materials are DUPLICATED per instance so a per-player face/tint never bleeds
## across other players.

@export_group("Model source")
## Assigned per-variant (player_blob_violet.glb, ...). Only instanced if no "ModelRoot" child
## already exists in the scene. Leave empty if you instance the GLB directly in the editor.
@export var model_scene: PackedScene
## The MeshInstance3D / material name that marks the printable face. Matched case-insensitively
## by node name OR material name, so "FacePlate" object or "M_FacePlate" material both work.
@export var face_hint := "FacePlate"
## Visual-only sideways nudge if the model's face doesn't sit on the camera axis. The current model's
## face is already centred (X=0), so this is 0. Adjust only if a future variant is off-centre.
@export var face_align_x := 0.0
## The face plate UVs sample the painted texture mirrored — flip X so what you draw reads correctly
## (a real mirror reflection still flips your OWN reflection, which is physically correct).
@export var face_flip_x := true:
	set(v): face_flip_x = v; if _face_shader != null: _face_shader.set_shader_parameter("flip_x", v)
## The plate's authored UVs are slightly rotated, so painted faces look crooked. Spin the texture back
## level here (degrees). Tune live in the Inspector — small values (±2..8) usually do it.
@export_range(-30.0, 30.0, 0.5) var face_uv_rotation := 0.0:
	set(v):
		face_uv_rotation = v
		if _face_shader != null:
			_face_shader.set_shader_parameter("uv_rot", deg_to_rad(v))

@export_group("Face")
## Default face look (off-white plate). Used by clear_face_texture() to restore after an override.
@export var face_texture: Texture2D:
	set(v): face_texture = v; _apply_face_texture(v)
## Extra emission while a face texture is shown, so painted faces read in the dark bunker.
## 0 = respect the Blender material exactly. Try ~0.3 if faces vanish in the dark.
@export_range(0.0, 2.0, 0.05) var face_base_emission := 0.0
## How bright the face glows at full speaking volume (the "who's talking" tell, no UI needed).
@export_range(0.0, 2.0, 0.05) var talk_emission := 0.7

@export_group("Body tint")
## The chosen VARIANT (the painted GLB) owns the color. WPlayer also derives a per-peer hue and
## calls set_tint(); leave this OFF so that auto-hue does NOT clobber your paint. Turn ON only if
## you want a single base GLB recolored per player instead of distinct painted variants.
@export var accept_auto_tint := false
## Strength of any tint that IS applied (multiplies the body albedo). 1 = full replace-ish.
@export_range(0.0, 1.0, 0.05) var tint_strength := 0.6

@export_group("Outline")
@export var outline_enabled := true:
	set(v): outline_enabled = v; _refresh_outline()
@export var outline_color := Color(0.04, 0.04, 0.05):
	set(v): outline_color = v; _push_outline_params()
@export_range(0.0, 0.08, 0.001) var outline_thickness := 0.02:
	set(v): outline_thickness = v; _push_outline_params()

@export_group("Motion")
## Lift the whole model off the floor a touch (blob float). Metres.
@export var ground_clearance := 0.08
## Raise the cigarette on the BODY model (what teammates + the mirror see) — the first-person POV
## cigarette in player.gd is SEPARATE and unaffected. Metres up.
@export var cig_lift := 0.09
## Subtle vertical bob + roll while walking (legless blob = waddle). 0 disables.
@export var walk_bob := 0.05
@export var walk_roll := 0.06
## How much the body tilts with the camera look (so teammates/the mirror see you look up/down).
## Negative flips the direction if it tilts the wrong way.
@export var look_pitch_amount := 0.45
## Model Y-scale when fully crouched (0.5 = cut in half). 1 = no squash.
@export_range(0.2, 1.0, 0.05) var crouch_squash := 0.5

@export_group("Detached hands")
## Spawn the floating 3-finger blob hands and attach them to LeftHandAnchor/RightHandAnchor. They
## inherit this rig's render layer, so they're hidden from the owner's own camera but visible to
## teammates + the mirror (same as the body).
@export var hands_enabled := true
@export var hands_debug := false

@export_group("Movement lean")
## Tilt the VISUAL body toward the walk direction (forward/back/strafe). Pure cosmetic — never
## touches the CharacterBody3D, collision, or camera. Driven by WPlayer via set_movement_lean().
@export var lean_enabled := true
@export_range(0.0, 20.0, 0.5) var max_lean_degrees := 7.0   ## subtle; 6-10 is the friendslop sweet spot
@export var lean_response := 8.0          ## how fast it leans into a move
@export var lean_return_speed := 10.0     ## how fast it springs back upright when you stop
## true: lean scales with actual speed (gentle when slow). false: full lean whenever moving.
@export var lean_uses_velocity := true

# --- resolved at runtime -----------------------------------------------------
var _model: Node3D                       # the instanced GLB root ("ModelRoot")
var _surfaces: Array = []                # [{ mi: MeshInstance3D, idx: int, mat: BaseMaterial3D }]
var _meshes: Array = []                  # unique MeshInstance3D under the model (for per-mesh outline)
var _face_mat: StandardMaterial3D        # the face plate's (owned) StandardMaterial (plate colour src)
var _face_shader: ShaderMaterial         # the live face material: UV-corrects + drives the talk glow
var _body_mats: Array[StandardMaterial3D] = []
var _outline_mats: Array = []            # one outline ShaderMaterial PER mesh (Body / Head centres differ)
var _model_rest_y := 0.0
var _cig: Node3D                         # cigarette mesh in the wrapper, shown only while smoking
var _body_node: Node3D                   # the "Body" mesh — squashes on crouch (split models)
var _head_node: Node3D                   # the "Head" mesh — lowers on crouch, pitches (split models)
var _head_rest_y := 0.0                  # head's resting local Y (the neck height)
var _mesh_node: Node3D                   # unified single mesh — squashes on crouch (non-split models)

# --- live state --------------------------------------------------------------
var _speaking := 0.0
var _blank := false
var _scared := 0.0
var _move := 0.0
var _lean := Vector2.ZERO        # (pitch about X = fwd/back, roll about Z = strafe), radians
var _look_pitch := 0.0           # camera look pitch -> head/body tilt
var _crouch := 0.0               # 0 standing .. 1 fully crouched
var _cig_rest_y := 0.0           # cig height when standing (lowers with crouch on the unified model)
var _hands: DetachedHandsController
var _hand_tint := Color(0.85, 0.72, 0.5)   # per-player hand colour, captured from set_tint()
var _player_color := Color.BLACK            # the chosen customization body colour (hands match it)


func _ready() -> void:
	_build()


# ---- build ------------------------------------------------------------------
func _build() -> void:
	_model = _resolve_model()
	if _model == null:
		push_warning("PlayerModelView: no model. Add a 'ModelRoot' child or assign model_scene.")
		return
	_model.position.y += ground_clearance      # float the blob a touch off the floor
	_model.position.x += face_align_x          # centre the face on the camera axis (visual only)
	_model_rest_y = _model.position.y
	_localize_and_index()
	# Body / Head split: Body squashes on crouch, Head lowers + pitches (keeps its shape).
	_body_node = _model.find_children("Body", "MeshInstance3D", true, false).pop_front()
	_head_node = _model.find_children("Head", "MeshInstance3D", true, false).pop_front()
	if _head_node != null:
		_head_rest_y = _head_node.position.y
	elif not _meshes.is_empty():
		_mesh_node = _meshes[0]            # unified mesh -> crouch squashes this (not ModelRoot, so the cig won't stretch)
	_apply_face_texture(face_texture)
	_refresh_outline()
	# A cigarette mesh dropped into the wrapper (e.g. a "cig_*" node): REPARENT it under the model so it
	# follows the head's bob + look-pitch, then hide it until smoking.
	for c in get_children():
		if c is Node3D and "cig" in str(c.name).to_lower():
			_cig = c
			break
	if _cig != null:
		var w := _cig.global_transform
		_cig.get_parent().remove_child(_cig)
		(_head_node if _head_node != null else _model).add_child(_cig)
		_cig.global_transform = w
		_cig.position.y += cig_lift            # sit it higher on the face (body model only)
		_cig.visible = false
		_cig_rest_y = _cig.position.y
	_build_hands()


## Spawn the detached 3-finger hands and hand them our owning player + anchors. Done at the END of
## _build so LeftHandAnchor/RightHandAnchor already exist. The owning WPlayer is our parent (player.gd
## add_child's this rig); the controller null-checks it, so a parentless preview rig just idle-sways.
func _build_hands() -> void:
	if not hands_enabled:
		return
	# Instantiate the SCENE (not .new()) so its Inspector-saved values (fp_rest_* etc.) actually apply.
	_hands = preload("res://actors/player_hands/detached_hands_pair.tscn").instantiate() as DetachedHandsController
	_hands.name = "DetachedHands"
	_hands.debug_draw = hands_debug
	add_child(_hands)
	_hands.setup(get_parent(), self, body_color())     # hands match the BODY colour, not the outline


## Local player only: make the hands visible to the OWNER's camera and drive them as a first-person
## viewmodel (in front of the camera, not at the wide body anchors). Called by WPlayer after the
## body's self-layer pass so it doesn't get overwritten.
func enable_first_person_hands(cam: Camera3D) -> void:
	if _hands != null:
		_hands.set_first_person(cam)


## A) existing child named "ModelRoot"; B) any existing child (an editor-instanced GLB);
## C) instance the exported model_scene. The found node is renamed/kept as "ModelRoot".
func _resolve_model() -> Node3D:
	var existing := get_node_or_null("ModelRoot")
	if existing is Node3D:
		return existing
	for c in get_children():
		if c is Node3D and not (c is Marker3D):
			c.name = "ModelRoot"
			return c
	if model_scene != null:
		var n := model_scene.instantiate()
		if n is Node3D:
			n.name = "ModelRoot"
			add_child(n)
			return n
	return null


## Duplicate every surface material (so per-player overrides are isolated) and classify each as
## FACE or BODY by node/material name. Imported GLB materials come in as StandardMaterial3D.
func _localize_and_index() -> void:
	_surfaces.clear()
	_meshes.clear()
	_body_mats.clear()
	_face_mat = null
	var want := face_hint.to_lower()
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		if inst.mesh != null:
			_meshes.append(inst)
		var surf_count: int = inst.mesh.get_surface_count() if inst.mesh != null else 0
		for i in surf_count:
			# Resolve the live material (override > surface override > mesh material).
			var src: Material = inst.get_active_material(i)
			if src == null:
				continue
			var owned := src.duplicate() as Material
			inst.set_surface_override_material(i, owned)
			var entry := { "mi": inst, "idx": i, "mat": owned }
			if owned is StandardMaterial3D:
				var std := owned as StandardMaterial3D
				var mat_name := str(std.resource_name).to_lower()
				var node_name := str(inst.name).to_lower()
				if (want != "" and (mat_name.contains(want) or node_name.contains(want))) \
						or mat_name.contains("face") or node_name.contains("face"):
					_face_mat = std
					# Swap the face surface to the UV-correcting shader (un-mirror + straighten).
					var fm := _build_face_shader(std)
					if fm != null:
						_face_shader = fm
						inst.set_surface_override_material(i, fm)
						entry["mat"] = fm
				else:
					_body_mats.append(std)
			_surfaces.append(entry)


# ---- FACE -------------------------------------------------------------------
## Print an uploaded / generated image onto the face plate. Pass null to fall back to whatever
## the GLB shipped with. Clean 0-1 UVs in Blender are what make this land undistorted.
func set_face_texture(tex: Texture2D) -> void:
	face_texture = tex                       # setter calls _apply_face_texture


func clear_face_texture() -> void:
	face_texture = null
	_apply_face_texture(null)


## Build the face-plate ShaderMaterial from the imported StandardMaterial (captures the plate colour),
## flipping + rotating the UVs so painted faces read level. Falls back to null if the shader's missing.
func _build_face_shader(std: StandardMaterial3D) -> ShaderMaterial:
	var sh := load("res://shaders/face_plate.gdshader") as Shader
	if sh == null:
		return null
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("plate_color", Color(std.albedo_color.r, std.albedo_color.g, std.albedo_color.b))
	m.set_shader_parameter("flip_x", face_flip_x)
	m.set_shader_parameter("uv_rot", deg_to_rad(face_uv_rotation))
	m.set_shader_parameter("has_tex", std.albedo_texture != null)
	if std.albedo_texture != null:
		m.set_shader_parameter("face_tex", std.albedo_texture)
	return m


func _apply_face_texture(tex: Texture2D) -> void:
	if _face_shader != null:
		_face_shader.set_shader_parameter("has_tex", tex != null)
		if tex != null:
			_face_shader.set_shader_parameter("face_tex", tex)
		return
	if _face_mat == null:
		return
	# Fallback (shader missing): StandardMaterial path.
	_face_mat.albedo_texture = tex
	if face_flip_x:
		_face_mat.uv1_scale = Vector3(-1, 1, 1)
		_face_mat.uv1_offset = Vector3(1, 0, 0)
	if tex != null:
		_face_mat.albedo_color = Color.WHITE


# ---- BODY TINT --------------------------------------------------------------
## Explicit per-player body tint (multiplies the painted albedo by `tint_strength`).
func set_body_tint(color: Color) -> void:
	for m in _body_mats:
		m.albedo_color = color.lerp(Color.WHITE, 1.0 - tint_strength)


## CUSTOMIZATION entry point: set the blob's body colour to a FULL chosen colour and make the detached
## hands match it. NEVER touches the face plate (stays white) or the outline. Per-instance materials
## (duplicated in _localize_and_index) keep this player's colour from bleeding onto others.
func set_player_color(color: Color) -> void:
	_player_color = color
	for m in _body_mats:
		if m != null:
			m.albedo_color = color
	if _hands != null:
		_hands.set_tint(color)


## PlayerCharacter hook: WPlayer auto-derives a per-peer hue and calls this. Ignored by default
## so hand-painted variants keep their paint (see `accept_auto_tint`).
func set_tint(c: Color) -> void:
	# NOTE: the detached hands do NOT use this per-player hue (that's the outline colour). They match
	# the actual BODY colour instead — sampled in _build_hands().
	if accept_auto_tint:
		set_body_tint(c)


## The body's real albedo (first body material), so the hands can match the body, not the outline.
func body_color() -> Color:
	if not _body_mats.is_empty() and _body_mats[0] != null:
		return _body_mats[0].albedo_color
	return _hand_tint


# ---- OUTLINE (inverted hull, Godot-side, NOT baked into the GLB) ------------
## A second material pass that expands the mesh along its normals and draws only back faces
## (cull_front) in a dark color -> a thin readable silhouette. Toggled per instance.
## Build ONE outline material per mesh — Body and Head are separate meshes with different local
## origins, so the hull-expansion centre must be each mesh's own AABB centre (a single shared centre
## would warp one of them). Re-expanding from the centre (not per-face normals) keeps the flat-shaded
## silhouette gap-free.
func _make_outline_materials() -> void:
	_outline_mats.clear()
	var sh := load("res://materials/player/player_outline.gdshader") as Shader
	if sh == null:
		return
	for mi in _meshes:
		var inst := mi as MeshInstance3D
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("outline_color", outline_color)
		m.set_shader_parameter("thickness", outline_thickness)
		m.set_shader_parameter("model_center", inst.mesh.get_aabb().get_center())
		_outline_mats.append({ "mi": inst, "mat": m })


func _push_outline_params() -> void:
	for o in _outline_mats:
		var m := o["mat"] as ShaderMaterial
		m.set_shader_parameter("outline_color", outline_color)
		m.set_shader_parameter("thickness", outline_thickness)


func set_outline_enabled(enabled: bool) -> void:
	outline_enabled = enabled               # setter calls _refresh_outline


func _refresh_outline() -> void:
	if _outline_mats.is_empty() and outline_enabled:
		_make_outline_materials()
	for s in _surfaces:
		var m := s["mat"] as Material
		if m == null:
			continue
		var om: ShaderMaterial = null
		if outline_enabled:
			for o in _outline_mats:                       # match the outline mat to this surface's mesh
				if o["mi"] == s["mi"]:
					om = o["mat"]; break
		m.next_pass = om


# ---- SPEAKING / MOUTH (PlayerCharacter: set_mouth_open) ---------------------
## 0..1 voice amplitude. The blob has a printed plate, not a jaw — so "talking" is read as the
## face glowing brighter (works in the dark, the project's whole "who's talking, no UI" goal).
## If your GLB has a child named "Mouth", it is also scaled. Tune the FEEL in set_speaking_amount.
func set_mouth_open(v: float) -> void:
	set_speaking_amount(v)


func set_speaking_amount(amount: float) -> void:
	_speaking = clampf(amount, 0.0, 1.0)
	# "Talking" = the printed face glows brighter (works in the dark, no UI). Drive the plate shader's
	# emission; fall back to the StandardMaterial if the shader didn't load.
	var e := face_base_emission + _speaking * talk_emission
	if _face_shader != null:
		_face_shader.set_shader_parameter("emission_amt", e)
	elif _face_mat != null:
		_face_mat.emission_enabled = e > 0.001
		if _face_mat.emission_texture == null:
			_face_mat.emission = Color.WHITE
		_face_mat.emission_energy_multiplier = e
	var mouth := _model.get_node_or_null("Mouth") if _model != null else null
	if mouth is Node3D:
		(mouth as Node3D).scale.y = lerpf(0.15, 1.4, _speaking)


# ---- EXPRESSION / STATE -----------------------------------------------------
func set_blank(b: bool) -> void:
	_blank = b
	# Downed = dead: stop the "talking" face glow. (WPlayer tips the whole body over separately.)
	if b:
		if _face_shader != null:
			_face_shader.set_shader_parameter("emission_amt", face_base_emission)
		elif _face_mat != null:
			_face_mat.emission_energy_multiplier = face_base_emission


## Show/hide the cigarette mesh on the body (mirror + teammates). WPlayer calls this from its
## smoking timer. The local POV cig (player.gd) is separate; this is the one on the model.
func set_smoking(on: bool) -> void:
	if _cig != null:
		_cig.visible = on


func set_scared(v: float) -> void:
	_scared = clampf(v, 0.0, 1.0)


func set_move(v: float) -> void:
	_move = clampf(v, 0.0, 1.0)


## VISUAL lean toward the walk direction. `local_move` is the movement in the player's LOCAL space
## (forward = -Z, right = +X); WPlayer passes velocity/walk_speed (or input). Tilts THIS node only —
## the body pivots from its base like a wobbling pin. Never affects the controller/collision/camera.
func set_movement_lean(local_move: Vector3, delta: float) -> void:
	var m := Vector2(local_move.x, local_move.z)        # x = strafe, y = fwd(-)/back(+)
	if not lean_enabled:
		m = Vector2.ZERO
	elif not lean_uses_velocity and m.length() > 0.01:
		m = m.normalized()
	m = m.limit_length(1.0)
	var max_rad := deg_to_rad(max_lean_degrees)
	# Forward (m.y<0) -> lean top toward -Z (rotation.x<0). Right (m.x>0) -> lean top toward +X (rotation.z<0).
	var target := Vector2(m.y * max_rad, -m.x * max_rad)
	var rate := lean_response if m.length() > 0.05 else lean_return_speed
	_lean = _lean.lerp(target, clampf(delta * rate, 0.0, 1.0))
	rotation.x = _lean.x
	rotation.z = _lean.y


# ---- ANCHORS (Marker3D children placed in the .tscn) ------------------------
## Public accessors for the controller / future hand & nameplate systems.
func face_anchor() -> Marker3D:    return get_node_or_null("FaceAnchor") as Marker3D
func hand_anchor(left: bool) -> Marker3D:
	return get_node_or_null("LeftHandAnchor" if left else "RightHandAnchor") as Marker3D
func nameplate_anchor() -> Marker3D: return get_node_or_null("NameplateAnchor") as Marker3D


# ---- live motion ------------------------------------------------------------
func set_look_pitch(pitch: float) -> void:
	_look_pitch = pitch


func set_crouch(amount: float) -> void:
	_crouch = clampf(amount, 0.0, 1.0)


func _process(_delta: float) -> void:
	if _model == null:
		return
	# CROUCH: squash the BODY from the bottom; LOWER the HEAD so it rides the shortened body but keeps
	# its own shape (no head squash). HEAD also PITCHES at the neck with your look.
	var sq := lerpf(1.0, crouch_squash, _crouch)
	if _body_node != null:
		_body_node.scale.y = sq                          # split: squash the body only
	elif _mesh_node != null:
		_mesh_node.scale.y = sq                          # unified: squash the whole blob (from its base)
	if _head_node != null:
		_head_node.position.y = _head_rest_y * sq
		_head_node.rotation.x = _look_pitch * look_pitch_amount
	elif _cig != null:
		_cig.position.y = _cig_rest_y * sq        # unified mesh: lower the cig with the crouch squash
	if _blank:
		return
	var t := Time.get_ticks_msec() * 0.001
	_model.position.y = _model_rest_y + sin(t * 9.0) * walk_bob * _move
	if _head_node == null:
		_model.rotation.x = _look_pitch * look_pitch_amount   # unified mesh: whole body tilts with look
	_model.rotation.z = sin(t * 9.0) * walk_roll * _move
