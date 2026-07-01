extends SceneTree
## Headless GLB inspector: prints the node tree + skeleton bone names of the hand model so we know
## exactly what to drive. Run: godot --headless --script res://tools/dump_glb.gd

func _init() -> void:
	for path in ["res://assets/models/hands/hand_right.glb"]:
		print("==== ", path, " ====")
		var ps := load(path) as PackedScene
		if ps == null:
			print("  FAILED TO LOAD")
			continue
		var root := ps.instantiate()
		_walk(root, 0)
	quit()


func _walk(n: Node, depth: int) -> void:
	var pad := ""
	for i in depth:
		pad += "  "
	print(pad, n.name, "  [", n.get_class(), "]")
	if n is Skeleton3D:
		var sk := n as Skeleton3D
		for b in sk.get_bone_count():
			print(pad, "  bone ", b, ": ", sk.get_bone_name(b))
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		print(pad, "  mesh surfaces: ", mi.mesh.get_surface_count() if mi.mesh else 0, " skin: ", mi.skin != null)
	for c in n.get_children():
		_walk(c, depth + 1)
