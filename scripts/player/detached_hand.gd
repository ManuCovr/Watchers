class_name DetachedHand
extends Node3D
## A single detached, chunky CARTOON hand with exactly THREE fat fingers. Primary form is a RIGGED
## blobby GLB built in Blender (tools/blender/build_hands.py) — skinned mesh + a tiny armature
## (root/palm/finger_a/finger_b/finger_thumb). Curling a finger rotates its BONE. If the GLB is
## missing it falls back to a simple code-built mesh so the system never hard-breaks.
##
## Three fingers only — curl index 0 = thumb, 1 = main finger A, 2 = main finger B. No five-finger
## data anywhere.

@export var is_left := false
@export_group("Model")
@export var pose_hands := false               ## use the low-poly FBX (5 swappable pose meshes)
@export var pose_scale := 0.215                ## the FBX poses import huge — shrink to hand size (1.65x)
@export var pose_euler := Vector3(0, 0, 0)      ## orients the FBX (fingers up, palm out); tune live
@export var simple_blob := false              ## skip the rigged GLB — one rounded-cube blob, no fingers
@export var model_scale := 0.34               ## sized so the hands read clearly without dominating
@export var model_euler_degrees := Vector3.ZERO
@export_group("Curl")
@export var max_finger_curl_deg := 100.0
@export var max_thumb_curl_deg := 80.0
@export var curl_axis := Vector3(1, 0, 0)     ## bone-local bend axis (tune if a finger bends sideways)
@export var curl_sign := 1.0
@export var curl_lerp_speed := 16.0
@export_group("Look")
@export var tint := Color(0.85, 0.72, 0.5)
@export var debug_draw := false:
	set(v): debug_draw = v; _refresh_debug()

const GLB_RIGHT := "res://assets/models/hands/hand_right.glb"
const GLB_LEFT := "res://assets/models/hands/hand_left.glb"

var _mat: StandardMaterial3D
var _visual: Node3D
var _skel: Skeleton3D
var _bone := {"thumb": -1, "a": -1, "b": -1, "c": -1}   # finger bone indices (4 digits)
var _rest := {}                                    # bone idx -> rest rotation quaternion
# fallback (no-GLB) pivots:
var _thumb_pivot: Node3D
var _finger_a_pivot: Node3D
var _finger_b_pivot: Node3D
# low-poly pose meshes (suffix -> MeshInstance3D), and which is shown
var _poses := {}
var _cur_pose := ""

var _palm_socket: Marker3D
var _grab_socket: Marker3D
var _hit_socket: Marker3D
var _debug_root: Node3D

var _target := PackedFloat32Array([0.2, 0.2, 0.2])
var _cur := PackedFloat32Array([0.2, 0.2, 0.2])


func _ready() -> void:
	_build()


func _build() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = tint
	_mat.roughness = 1.0

	_visual = Node3D.new()
	_visual.name = "VisualRoot"
	_visual.scale = Vector3.ONE * model_scale
	_visual.rotation_degrees = model_euler_degrees
	add_child(_visual)

	if pose_hands and _build_pose_hands():
		pass
	elif simple_blob:
		_build_simple_blob()
	elif not _load_glb():
		_build_fallback_mesh()

	# Sockets used for held-item alignment / hit tests / debug (in hand-local space, unscaled).
	_palm_socket = _marker("PalmSocket", Vector3(0, -0.03, 0.06))
	_grab_socket = _marker("GrabSocket", Vector3(0, 0, 0.12))
	_hit_socket = _marker("HitSocket", Vector3(0, 0, 0.16))

	set_tint(tint)
	_apply_curls(_cur)
	_refresh_debug()


# ---- rigged GLB -------------------------------------------------------------
func _load_glb() -> bool:
	var ps := load(GLB_LEFT if is_left else GLB_RIGHT) as PackedScene
	if ps == null:
		return false
	var model := ps.instantiate()
	if model == null:
		return false
	_visual.add_child(model)
	_skel = model.find_children("*", "Skeleton3D", true, false).pop_front() as Skeleton3D
	if _skel != null:
		_bone["a"] = _skel.find_bone("finger_a")
		_bone["b"] = _skel.find_bone("finger_b")
		_bone["c"] = _skel.find_bone("finger_c")
		_bone["thumb"] = _skel.find_bone("finger_thumb")
		for k in _bone:
			var idx: int = _bone[k]
			if idx >= 0:
				_rest[idx] = _skel.get_bone_rest(idx).basis.get_rotation_quaternion()
	# own the SKIN material so per-player tint never bleeds between instances, but leave the dark
	# crease marks (CreaseMat) untinted so they stay readable.
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		if inst.mesh == null:
			continue
		for i in inst.mesh.get_surface_count():
			var src := inst.get_active_material(i)
			var nm := str(src.resource_name).to_lower() if src != null else ""
			if "crease" in nm:
				continue                       # keep the dark crease colour
			inst.set_surface_override_material(i, _mat)
	return true


# ---- low-poly pose hands (Kickin It Studios FBX: 5 swappable pose meshes) ----
const POSE_FBX := "res://assets/models/hands_lowpoly/low_poly_hands.fbx"
const POSE_DEFAULT := "Open_Hand"
# canonical pose keys (suffix after the L_/R_ side prefix)
const POSE_OPEN := "Open_Hand"
const POSE_FIST := "Closed_Fist"
const POSE_GRAB := "Grabbing_Hand"
const POSE_POINT := "Pointing_Hand"
const POSE_THUMB := "Thumbs_Up"

## Instance the FBX, keep only THIS side's 5 pose meshes (tinted), and show one at a time. Returns
## false if the FBX is missing so _build can fall through to the blob/GLB.
func _build_pose_hands() -> bool:
	var ps := load(POSE_FBX) as PackedScene
	if ps == null:
		return false
	var model := ps.instantiate() as Node3D
	if model == null:
		return false
	# Rotate/scale via a WRAPPER so we don't clobber the FBX import root's own transform (coordinate
	# conversion). pose_euler is our correction ON TOP of the imported orientation.
	var holder := Node3D.new()
	holder.scale = Vector3.ONE * pose_scale
	holder.rotation_degrees = pose_euler
	_visual.add_child(holder)
	holder.add_child(model)
	var prefix := "L_" if is_left else "R_"
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		var nm := str(inst.name)
		if not nm.begins_with(prefix):
			inst.visible = false
			inst.queue_free()
			continue
		if inst.mesh == null:
			continue
		var key := nm.substr(2)                 # strip "L_"/"R_"
		for i in inst.mesh.get_surface_count():
			inst.set_surface_override_material(i, _mat)   # tint = body colour (per-instance)
		inst.visible = false
		_poses[key] = inst
	if _poses.is_empty():
		return false
	set_pose(POSE_DEFAULT)
	return true


## Show a single pose mesh by key (e.g. "Grabbing_Hand"); hides the rest. Cheap no-op if unchanged.
func set_pose(key: String) -> void:
	if not pose_hands or key == _cur_pose or not _poses.has(key):
		return
	if _poses.has(_cur_pose):
		(_poses[_cur_pose] as MeshInstance3D).visible = false
	(_poses[key] as MeshInstance3D).visible = true
	_cur_pose = key


# ---- simple blob hand (a rounded cube, no fingers/rig) ----------------------
const BLOB_BLEND := "res://assets/models/hands/hand.blend"
@export var blob_scale := 0.62      ## extra shrink on the blend blob (it reads big at native size)

## One "mitten" blob hand: the authored hand.blend (a cube + subdivision-surface). The simplest hand —
## curls are no-ops (no pivots/skel), it just rides the item state and tints to match the body. Falls
## back to a procedural spherified cube if the blend can't load.
func _build_simple_blob() -> void:
	var ps := load(BLOB_BLEND) as PackedScene
	if ps != null:
		var model := ps.instantiate() as Node3D
		_visual.add_child(model)
		model.scale *= blob_scale
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var inst := mi as MeshInstance3D
			if inst.mesh == null:
				continue
			for i in inst.mesh.get_surface_count():
				inst.set_surface_override_material(i, _mat)   # tint = body colour (per-instance)
		return
	# fallback: procedural rounded cube
	var blob := MeshInstance3D.new()
	blob.name = "Blob"
	blob.mesh = _make_rounded_cube(7, 0.62)
	blob.material_override = _mat
	blob.scale = Vector3(0.55, 0.44, 0.62)
	_visual.add_child(blob)


## A "spherified cube": a subdivided cube whose vertices are blended toward a sphere — the shape a
## subdivision-surface modifier converges a cube toward. roundness 0 = cube, 1 = sphere.
func _make_rounded_cube(res: int, roundness: float) -> ArrayMesh:
	var box := BoxMesh.new()
	box.size = Vector3(2, 2, 2)                 # vertices span [-1, 1]
	box.subdivide_width = res
	box.subdivide_height = res
	box.subdivide_depth = res
	var arrays := box.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for i in verts.size():
		var c := verts[i]
		var x := c.x
		var y := c.y
		var z := c.z
		var sphere := Vector3(
			x * sqrt(1.0 - y * y * 0.5 - z * z * 0.5 + y * y * z * z / 3.0),
			y * sqrt(1.0 - z * z * 0.5 - x * x * 0.5 + z * z * x * x / 3.0),
			z * sqrt(1.0 - x * x * 0.5 - y * y * 0.5 + x * x * y * y / 3.0))
		verts[i] = c.lerp(sphere, roundness)
		normals[i] = sphere.normalized()
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am


# ---- fallback code mesh (only if the GLB is unavailable) --------------------
func _build_fallback_mesh() -> void:
	var side := -1.0 if is_left else 1.0
	var palm := _box("Palm", Vector3(0.2, 0.085, 0.18), Vector3.ZERO, _visual)
	palm.name = "Palm"
	_finger_a_pivot = _finger("FingerA", Vector3(side * 0.05, 0.02, 0.09), Vector3(0.07, 0.07, 0.15))
	_finger_b_pivot = _finger("FingerB", Vector3(side * -0.05, 0.02, 0.09), Vector3(0.07, 0.07, 0.15))
	_thumb_pivot = _finger("Thumb", Vector3(side * 0.11, -0.01, 0.02), Vector3(0.075, 0.075, 0.12))


func _box(n: String, size: Vector3, pos: Vector3, parent: Node) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var m := BoxMesh.new(); m.size = size
	mi.mesh = m
	mi.material_override = _mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _finger(n: String, knuckle: Vector3, size: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = n + "Pivot"
	pivot.position = knuckle
	_visual.add_child(pivot)
	var box := _box(n, size, Vector3(0, 0, size.z * 0.5), pivot)
	box.name = n
	return pivot


func _marker(n: String, pos: Vector3) -> Marker3D:
	var mk := Marker3D.new()
	mk.name = n
	mk.position = pos
	add_child(mk)
	return mk


# ---- public API -------------------------------------------------------------
func set_tint(c: Color) -> void:
	tint = c
	if _mat != null:
		_mat.albedo_color = c


func set_curls(thumb: float, a: float, b: float) -> void:
	_target = PackedFloat32Array([clampf(thumb, 0, 1), clampf(a, 0, 1), clampf(b, 0, 1)])


func set_pose_curls(pose: HandPoseResource) -> void:
	if pose == null:
		return
	var c := pose.curls()
	set_curls(c[0], c[1], c[2])


func grab_socket() -> Marker3D: return _grab_socket
func palm_socket() -> Marker3D: return _palm_socket
func hit_socket() -> Marker3D: return _hit_socket


## Put every visual under this hand on a render layer (used to make the owner's OWN hands visible to
## their first-person camera again, after the body was pushed to the self-hide layer).
func set_render_layer(bits: int) -> void:
	_set_layer_rec(self, bits)


func _set_layer_rec(n: Node, bits: int) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = bits
	for c in n.get_children():
		_set_layer_rec(c, bits)


# ---- per-frame --------------------------------------------------------------
func _process(delta: float) -> void:
	var k := clampf(delta * curl_lerp_speed, 0.0, 1.0)
	var changed := false
	for i in 3:
		var n := lerpf(_cur[i], _target[i], k)
		if absf(n - _cur[i]) > 0.0005:
			changed = true
		_cur[i] = n
	if changed:
		_apply_curls(_cur)


func _apply_curls(c: PackedFloat32Array) -> void:
	if _skel != null:
		_bend(_bone["thumb"], c[0], max_thumb_curl_deg)
		_bend(_bone["a"], c[1], max_finger_curl_deg)
		_bend(_bone["b"], c[2], max_finger_curl_deg)
		_bend(_bone["c"], c[2], max_finger_curl_deg)   # 4th finger follows finger B
		return
	# fallback pivots
	var side := -1.0 if is_left else 1.0
	if _finger_a_pivot != null:
		_finger_a_pivot.rotation = Vector3(deg_to_rad(max_finger_curl_deg) * c[1], 0, 0)
	if _finger_b_pivot != null:
		_finger_b_pivot.rotation = Vector3(deg_to_rad(max_finger_curl_deg) * c[2], 0, 0)
	if _thumb_pivot != null:
		_thumb_pivot.rotation = Vector3(0, 0, deg_to_rad(max_thumb_curl_deg) * c[0] * side)


## Curl a single finger bone by `amt` (0..1) up to `max_deg`, applied on top of its rest pose.
func _bend(idx: int, amt: float, max_deg: float) -> void:
	if idx < 0 or _skel == null:
		return
	var rest: Quaternion = _rest.get(idx, Quaternion.IDENTITY)
	var q := Quaternion(curl_axis.normalized(), deg_to_rad(max_deg) * amt * curl_sign)
	_skel.set_bone_pose_rotation(idx, rest * q)


# ---- debug ------------------------------------------------------------------
func _refresh_debug() -> void:
	if not is_inside_tree():
		return
	if _debug_root != null:
		_debug_root.queue_free(); _debug_root = null
	if not debug_draw:
		return
	_debug_root = Node3D.new()
	_debug_root.name = "DebugRoot"
	add_child(_debug_root)
	for s in [_palm_socket, _grab_socket, _hit_socket]:
		if s == null:
			continue
		var mi := MeshInstance3D.new()
		var sp := SphereMesh.new(); sp.radius = 0.02; sp.height = 0.04
		mi.mesh = sp
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1, 0.6, 0.1)
		mi.material_override = m
		mi.position = s.position
		_debug_root.add_child(mi)
