@tool
class_name Mirror
extends Node3D
## A real planar mirror you can DROP ANYWHERE in a level (scenes/mirror.tscn).
##
## How it works (true planar reflection, not a fake):
##   - A SubViewport renders the SAME world from a MirrorCamera that is the player camera
##     REFLECTED across this mirror's plane.
##   - The mirror surface is an unshaded quad whose shader samples that reflection by SCREEN_UV.
##     Because a planar reflection shares its image plane with the real camera at the glass, the
##     reflected pixel for any mirror fragment lives at the SAME screen coordinate — so SCREEN_UV
##     sampling gives a perspective-correct, parallax-correct reflection with no UV alignment math.
##
## THE PURPLE FIX: a ViewportTexture baked into a .tscn does NOT survive packing (it reloads as the
## magenta "missing texture"). This scene is HYBRID (root + script; children built in code) and the
## material+texture are (re)bound every _ready in BOTH the editor and at runtime, so it is never
## purple. The SubViewport is also given the live World3D explicitly (an empty sub-world = blank).
##
## Editor-friendly: size/resolution/clip/distance/layers are all @export. In the editor it previews
## a static reflection from in front of the glass so you can place it; at runtime it tracks the
## live player camera. Recursion-safe: the surface sits on its own visual layer that EVERY mirror
## camera excludes, so mirrors never render themselves or each other.

const SURFACE_LAYER_BIT := 1 << 18    ## visual layer 19 — excluded from all mirror cameras
const BACKING_LAYER_BIT := 1 << 17    ## visual layer 18 — the wall the mirror hangs on (hidden from the reflection)
const BODY_LAYER_BIT := 1 << 19       ## PlayerCharacter.SELF_LAYER_BIT — kept so you see yourself
const BACKING_PROBE_MASK := 2         ## walls live on physics layer 2

@export_group("Dimensions")
@export var mirror_size := Vector2(2.4, 3.0):     ## width x height of the glass, in metres
	set(v): mirror_size = v; _rebuild()
@export var show_frame := true:
	set(v): show_frame = v; _rebuild()
@export var frame_depth := 0.08
@export var tint := Color(0.86, 0.9, 0.96)        ## subtle glass tint (mirrors aren't perfectly white)

@export_group("Reflection quality / performance")
@export_range(0.25, 1.0, 0.05) var resolution_scale := 0.75   ## SubViewport render scale vs the window
@export var far_clip := 28.0          ## limit how deep the reflection renders (perf)
@export var near_clip := 0.05
@export var max_render_distance := 20.0  ## stop re-rendering when the player is beyond this
@export var move_epsilon := 0.015     ## min camera move (m) before we re-render
@export var rot_epsilon_deg := 0.35   ## min camera turn (deg) before we re-render
## Keep re-rendering this long (s) AFTER the camera stops, so body animation (lean settle, bob)
## finishes on screen instead of freezing mid-pose when you stand still.
@export var settle_time := 0.7

var _surface: MeshInstance3D
var _frame: MeshInstance3D
var _sv: SubViewport
var _cam: Camera3D
var _mat: ShaderMaterial
var _last_cam_pos := Vector3(1e9, 1e9, 1e9)
var _last_cam_basis := Basis()
var _settle := 0.0
var _built := false
var _backing_done := false


func _ready() -> void:
	_rebuild()
	set_process(true)


## Hide the wall the mirror is mounted on FROM THE REFLECTION ONLY. Probe straight back along
## -normal; the StaticBody we hit is the backing wall. We move its meshes to BACKING_LAYER_BIT,
## which the mirror camera excludes but every normal camera still renders. Correct because a
## mirror's own backing wall can never legitimately appear in its reflection. Runtime only (we
## don't want to dirty the saved scene from the editor). General: works wherever you hang it.
func _hide_backing_wall() -> void:
	if _backing_done or Engine.is_editor_hint() or not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	if space == null:
		return                       # physics not ready yet — retry next frame
	var n := global_transform.basis.z.normalized()
	var from := global_position + n * 0.02
	var q := PhysicsRayQueryParameters3D.create(from, global_position - n * 0.8)
	q.collision_mask = BACKING_PROBE_MASK
	var hit := space.intersect_ray(q)
	if hit.has("collider") and hit.collider is Node:
		for mi in _meshes_under(hit.collider):
			mi.layers = BACKING_LAYER_BIT
		_backing_done = true         # only stop once we've actually hidden a wall


func _meshes_under(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes_under(c))
	return out


# ---- build (editor + runtime) ----------------------------------------------
func _rebuild() -> void:
	if not is_inside_tree():
		return
	# Tear down any previous children so re-edits in the editor stay clean.
	for nm in ["Surface", "Frame", "MirrorView"]:
		var old := get_node_or_null(nm)
		if old != null:
			old.free()

	# SubViewport that renders the reflection.
	_sv = SubViewport.new()
	_sv.name = "MirrorView"
	_sv.world_3d = get_world_3d()                  # render the SAME room, not an empty sub-world
	_sv.transparent_bg = false
	_sv.handle_input_locally = false
	_sv.positional_shadow_atlas_size = 0
	_sv.msaa_3d = Viewport.MSAA_DISABLED
	_sv.render_target_update_mode = SubViewport.UPDATE_DISABLED   # we trigger renders on demand
	add_child(_sv)

	_cam = Camera3D.new()
	_cam.name = "MirrorCamera"
	_cam.near = near_clip
	_cam.far = far_clip
	# Render everything EXCEPT the mirror surfaces (no self/peer-mirror recursion) and the BACKING
	# wall (the wall the mirror hangs on, which would otherwise sit right in front of this camera
	# and black out the whole reflection). The player BODY layer is kept, so you see yourself.
	_cam.cull_mask = (0xFFFFF & ~SURFACE_LAYER_BIT & ~BACKING_LAYER_BIT)
	_cam.current = true
	_sv.add_child(_cam)

	# The glass surface. PlaneMesh facing +Z (its world normal = this node's basis.z). Rotate the
	# Mirror node so +Z points into the room.
	_surface = MeshInstance3D.new()
	_surface.name = "Surface"
	var pm := PlaneMesh.new()
	pm.size = mirror_size
	pm.orientation = PlaneMesh.FACE_Z
	_surface.mesh = pm
	_surface.layers = SURFACE_LAYER_BIT            # excluded from every mirror camera
	_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = _make_material()
	_surface.material_override = _mat
	add_child(_surface)

	if show_frame:
		_frame = MeshInstance3D.new()
		_frame.name = "Frame"
		var bm := BoxMesh.new()
		bm.size = Vector3(mirror_size.x + 0.18, mirror_size.y + 0.18, frame_depth)
		_frame.mesh = bm
		_frame.position = Vector3(0, 0, -frame_depth * 0.5 - 0.005)
		_frame.layers = SURFACE_LAYER_BIT      # excluded from mirror cams (a mirror never reflects its own frame)
		var fmat := StandardMaterial3D.new()
		fmat.albedo_color = Color(0.05, 0.05, 0.06)
		fmat.metallic = 0.6
		fmat.roughness = 0.5
		_frame.material_override = fmat
		add_child(_frame)

	# Set ownership so the children show up when this scene is instanced into a level (editor).
	if Engine.is_editor_hint():
		var ed_root := get_tree().edited_scene_root
		if ed_root != null:
			for c in [_sv, _surface, _frame]:
				if c != null:
					c.owner = ed_root
			if _cam != null:
				_cam.owner = ed_root

	_built = true
	_resize_viewport()
	_last_cam_pos = Vector3(1e9, 1e9, 1e9)          # force a first render
	_render_once()


func _make_material() -> ShaderMaterial:
	var sh := Shader.new()
	# Unshaded (a mirror must not be re-lit) + cull_disabled so it's visible from either face.
	# Sample the reflection by SCREEN_UV = perspective/parallax-correct planar reflection.
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, specular_disabled;
uniform sampler2D reflection_tex : source_color, filter_linear, hint_default_black;
uniform vec3 tint : source_color = vec3(0.86, 0.9, 0.96);
void fragment() {
	vec2 uv = SCREEN_UV;
	ALBEDO = texture(reflection_tex, uv).rgb * tint;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("reflection_tex", _sv.get_texture())   # LIVE texture, bound now (no purple)
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	return m


func _resize_viewport() -> void:
	if _sv == null:
		return
	var base := Vector2(1152, 648)
	if not Engine.is_editor_hint():
		var w := get_window()
		if w != null:
			base = Vector2(w.size)
	var s := clampf(resolution_scale, 0.25, 1.0)
	_sv.size = Vector2i(maxi(16, int(base.x * s)), maxi(16, int(base.y * s)))


# ---- per-frame: reflect the player camera, re-render on demand --------------
func _process(delta: float) -> void:
	if not _built or _sv == null or _cam == null:
		return
	if not _backing_done:
		_hide_backing_wall()
	var pcam := _player_camera()
	if pcam == null:
		_editor_preview()
		return
	# Distance gate: skip work (and rendering) when the player is far from the glass.
	if global_position.distance_to(pcam.global_position) > max_render_distance:
		return
	# Movement gate: re-render while the camera moves AND for a short settle window after it stops,
	# so the body's lean/bob finishes animating in the reflection instead of freezing mid-pose.
	var moved := _last_cam_pos.distance_to(pcam.global_position) > move_epsilon
	var turned := _basis_angle(_last_cam_basis, pcam.global_basis) > deg_to_rad(rot_epsilon_deg)
	if moved or turned:
		_settle = settle_time
	elif _settle > 0.0:
		_settle = maxf(0.0, _settle - delta)
	else:
		return
	_last_cam_pos = pcam.global_position
	_last_cam_basis = pcam.global_basis
	_cam.fov = pcam.fov
	_cam.global_transform = _reflect_xform(pcam.global_transform)
	_render_once()


## The active main-viewport camera (the player's, in this project). Decoupled — works for any cam.
func _player_camera() -> Camera3D:
	var vp := get_viewport()
	if vp == null:
		return null
	return vp.get_camera_3d()


## Reflect a transform across this mirror's plane (point = origin, normal = basis.z).
func _reflect_xform(x: Transform3D) -> Transform3D:
	var n := global_transform.basis.z.normalized()
	var p := global_position
	var o := x.origin
	var ro := o - 2.0 * (o - p).dot(n) * n
	return Transform3D(
		Basis(_reflect_vec(x.basis.x, n), _reflect_vec(x.basis.y, n), _reflect_vec(x.basis.z, n)),
		ro)


func _reflect_vec(v: Vector3, n: Vector3) -> Vector3:
	return v - 2.0 * v.dot(n) * n


func _basis_angle(a: Basis, b: Basis) -> float:
	# Angle between the two cameras' forward vectors — cheap "did we turn?" test.
	var fa := -a.z
	var fb := -b.z
	return fa.angle_to(fb)


func _render_once() -> void:
	if _sv != null:
		_sv.render_target_update_mode = SubViewport.UPDATE_ONCE


## In-editor with no running player: place the mirror cam as the reflection of a viewpoint a couple
## of metres out in front of the glass, so you see a believable static reflection while placing it.
func _editor_preview() -> void:
	var front := global_transform.basis.z.normalized()
	var eye := global_position + front * 2.5 + Vector3(0, 0.2, 0)
	var look := Transform3D(Basis(), eye).looking_at(global_position, Vector3.UP)
	_cam.global_transform = _reflect_xform(look)
	_render_once()
