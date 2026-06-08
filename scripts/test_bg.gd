extends Node
var _f := 0
var _cam: Camera3D
var _done := false
func _ready() -> void:
	add_child(load("res://scenes/lobby.tscn").instantiate())
	var dl := DirectionalLight3D.new(); dl.rotation_degrees = Vector3(-35, -120, 0)
	dl.light_energy = 2.0; get_tree().root.add_child(dl)
func _aabb(n: Node, acc: AABB, first) -> Array:
	var f = first
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mi := n as MeshInstance3D
		var a := mi.global_transform * mi.mesh.get_aabb()
		if f: acc = a; f = false
		else: acc = acc.merge(a)
	for c in n.get_children():
		var r = _aabb(c, acc, f); acc = r[0]; f = r[1]
	return [acc, f]
func _process(_dt: float) -> void:
	if _done: return
	_f += 1
	if _f < 30: return
	var p: WPlayer = null
	for n in get_tree().get_nodes_in_group("players"): p = n
	if p == null:
		if _f > 90: get_tree().quit()
		return
	var ch = p._character
	ch.set_reach(1.0); p.rotation.y = 0.0
	var r = _aabb(ch, AABB(), true)
	var bb: AABB = r[0]
	var center = bb.position + bb.size * 0.5
	if _cam == null:
		_cam = Camera3D.new()
		_cam.look_at_from_position(center + Vector3(0.1, bb.size.y*0.2, -2.4), center, Vector3.UP)
		get_tree().root.add_child(_cam)
	_cam.make_current()
	if _f == 75:
		print("char aabb center=", center.snapped(Vector3.ONE*0.01), " size=", bb.size.snapped(Vector3.ONE*0.01))
		get_tree().root.get_texture().get_image().save_png("res://_bg.png")
		print("BG SHOT saved"); _done = true; get_tree().quit()
