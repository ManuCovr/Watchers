extends SceneTree
## Author res://actors/player/gangbeast_character.tscn — the Gang Beast GLB as the player BODY.
## Node3D root running gangbeast_character.gd; every node editable; faces -Z. Built detached so no
## _ready runs during packing.
##   Godot_console.exe --headless --path . --script res://tools/build_gangbeast_character.gd

const OUT := "res://actors/player/gangbeast_character.tscn"

func _initialize() -> void:
	var ps := load("res://assets/models/gangbeast/gang_beast_rigged.glb") as PackedScene
	if ps == null:
		print("FAIL: gang_beast_rigged.glb missing"); quit(); return
	var src := ps.instantiate()

	var root := Node3D.new()
	root.name = "GangBeastCharacter"
	root.set_script(load("res://scripts/gangbeast_character.gd"))

	for c in src.get_children():
		src.remove_child(c)
		root.add_child(c)
	src.free()

	var model := root.get_node_or_null("Sketchfab_model") as Node3D
	if model != null:
		# (this rig already faces -Z / Godot forward — no flip needed)
		# Mixamo origin is at the HIPS, so the feet hang ~1m below the player origin. Lift the model
		# so the bottom of its mesh sits at y=0 (feet on the floor).
		var bb := _calc_aabb(root, Transform3D(), true)[0] as AABB
		model.position.y -= bb.position.y

	_own(root, root)

	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		print("FAIL pack"); quit(); return
	DirAccess.make_dir_recursive_absolute("res://actors/player")
	print("build_gangbeast_character: saved err=", ResourceSaver.save(packed, OUT), " nodes=", _count(root))
	quit()

## Combined mesh AABB in `root` space (the model is detached, so walk transforms manually).
func _calc_aabb(n: Node, xform: Transform3D, first: bool) -> Array:
	var acc := AABB()
	var f := first
	var x := xform
	if n is Node3D:
		x = xform * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var a := x * (n as MeshInstance3D).mesh.get_aabb()
		acc = a; f = false
	for c in n.get_children():
		var r := _calc_aabb(c, x, f)
		var ca := r[0] as AABB
		if not r[1]:
			if f: acc = ca; f = false
			else: acc = acc.merge(ca)
	return [acc, f]


func _own(n: Node, r: Node) -> void:
	for c in n.get_children():
		c.owner = r
		_own(c, r)

func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children(): c += _count(ch)
	return c
