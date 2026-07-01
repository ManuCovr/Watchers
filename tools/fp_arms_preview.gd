extends Node3D
## Quick viewer for assets/models/fp_arms/fp_arms_low_poly.glb — open this scene and press F6
## (Run Current Scene). SPACE cycles Idle / Run / Walk. H toggles "hands only" (hides the arm/
## forearm/shoulder bones' geometry attempt) so you can judge whether a hands-only crop is viable.

const GLB := "res://assets/models/fp_arms/fp_arms_low_poly.glb"

var _anim: AnimationPlayer
var _names: PackedStringArray = []
var _idx := 0
var _label: Label
var _model: Node3D
var _hands_only := false


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.08, 0.08, 0.1)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.65)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 40, 0)
	add_child(key)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.1, 1.2)
	cam.look_at(Vector3(0, 0, 0), Vector3.UP)
	add_child(cam)

	var ps := load(GLB) as PackedScene
	if ps != null:
		_model = ps.instantiate() as Node3D
		add_child(_model)
		_anim = _find_anim(_model)
		if _anim != null:
			_names = _anim.get_animation_list()
			for n in _names:
				var a := _anim.get_animation(n)
				if a != null:
					a.loop_mode = Animation.LOOP_LINEAR
			_play(0)

	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(20, 20)
	_label.add_theme_font_size_override("font_size", 22)
	layer.add_child(_label)
	_refresh_label()


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var r := _find_anim(c)
		if r != null:
			return r
	return null


func _play(i: int) -> void:
	if _anim == null or _names.is_empty():
		return
	_idx = wrapi(i, 0, _names.size())
	_anim.play(_names[_idx])
	_refresh_label()


func _refresh_label() -> void:
	if _label == null:
		return
	var cur := _names[_idx] if not _names.is_empty() else "<none>"
	_label.text = "fp_arms_low_poly.glb\nanim: %s   (SPACE = next)\nhands-only: %s   (H = toggle)" % [
		cur, "ON" if _hands_only else "off"]


## A cheap "hands only" experiment: hide the mesh and re-show by hiding the arm bones is not possible
## on a single skinned surface, so instead we just shrink the upper-arm/forearm/shoulder bones toward
## the hand. It's a rough preview of the idea, NOT a shipping crop (that needs a Blender mesh split).
func _toggle_hands_only() -> void:
	_hands_only = not _hands_only
	var skel := _find_skel(_model)
	if skel == null:
		_refresh_label(); return
	for i in skel.get_bone_count():
		var bn := skel.get_bone_name(i)
		if bn.begins_with("shoulder") or bn.begins_with("arm_stretch") or bn.begins_with("forearm"):
			if _hands_only:
				skel.set_bone_pose_scale(i, Vector3.ONE * 0.001)
			else:
				skel.set_bone_pose_scale(i, Vector3.ONE)
	_refresh_label()


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_play(_idx + 1)
		elif event.keycode == KEY_H:
			_toggle_hands_only()
