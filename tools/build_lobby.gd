extends SceneTree
## Generates res://scenes/lobby.tscn as REAL authored nodes (like the bunker) so you can
## open it in the editor and move/tune everything: room, props, lights, elevator, mirror.
## lobby.gd is then just a runtime controller that drives the authored nodes (mirror camera,
## player spawn, descent). Run ONCE, then hand-edit in the editor.
##
## Run: Godot_console.exe --headless --path <proj> --script res://tools/build_lobby.gd

const PSX := "res://assets/psx/"
const TECH := "res://assets/tech/"
const TEX_WALL := "res://assets/psx/Modular Structures/beam_1_concrete_1.jpg"
const TEX_FLOOR := "res://assets/textures/Tiles-Large.png"

const ROOM := 9.0
const CEIL := 4.0
const MIRROR_LAYER_BIT := 1 << 18
const BACK_WALL_BIT := 1 << 16

var _root: Node3D


func _initialize() -> void:
	_root = Node3D.new()
	_root.name = "Lobby"
	_root.set_script(load("res://scripts/lobby.gd"))

	_environment()
	_lights()
	_room()
	_props()
	_elevator()
	_mirror()
	_markers()

	var packed := PackedScene.new()
	if packed.pack(_root) == OK:
		print("build_lobby: saved err=", ResourceSaver.save(packed, "res://scenes/lobby.tscn"),
			" nodes=", _count(_root))
	else:
		print("build_lobby: PACK FAILED")
	quit()


func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children(): c += _count(ch)
	return c

func _attach(parent: Node, child: Node) -> void:
	parent.add_child(child); child.owner = _root

func _mat(tex: String, tile: float, tint: Color, size: Vector3) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.roughness = 0.95
	var t = load(tex) if tex != "" else null
	if t != null:
		m.albedo_texture = t; m.albedo_color = tint
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		var flat: bool = size.y <= size.x and size.y <= size.z
		m.uv1_scale = Vector3(size.x / tile, size.z / tile, 1) if flat \
			else Vector3(maxf(size.x, size.z) / tile, size.y / tile, 1)
	else:
		m.albedo_color = tint
	return m

func _solid(center: Vector3, size: Vector3, mat: StandardMaterial3D, nm: String, vis_layer := 0) -> void:
	var body := StaticBody3D.new()
	body.name = nm; body.position = center
	body.collision_layer = 2; body.collision_mask = 0
	_attach(_root, body)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = size; mi.mesh = bm; mi.material_override = mat
	if vis_layer != 0: mi.layers = vis_layer
	_attach(body, mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new(); bs.size = size; cs.shape = bs
	_attach(body, cs)

func _prop(path: String, pos: Vector3, rot: float, nm: String, scale := 1.0) -> void:
	var ps := load(path) as PackedScene
	if ps == null:
		print("MISS ", path); return
	var n := ps.instantiate() as Node3D
	n.name = nm; n.position = pos; n.rotation.y = deg_to_rad(rot); n.scale = Vector3.ONE * scale
	_attach(_root, n)

func _light(pos: Vector3, col: Color, energy: float, rng: float, nm: String, shadow := false) -> void:
	var l := OmniLight3D.new()
	l.name = nm; l.position = pos; l.light_color = col; l.light_energy = energy
	l.omni_range = rng; l.omni_attenuation = 1.7; l.shadow_enabled = shadow
	_attach(_root, l)


func _environment() -> void:
	var we := WorldEnvironment.new(); we.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.015, 0.022)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.14, 0.15, 0.2)
	env.ambient_light_energy = 0.22
	env.fog_enabled = true; env.fog_density = 0.03; env.fog_light_color = Color(0.04, 0.045, 0.06)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true; env.glow_intensity = 0.4
	we.environment = env
	_attach(_root, we)


func _lights() -> void:
	_light(Vector3(0, CEIL - 0.5, 2.5), Color(1.0, 0.76, 0.48), 2.2, 9.0, "WarmBulb", true)
	_light(Vector3(0, CEIL - 0.6, -ROOM + 2.5), Color(0.5, 0.68, 1.0), 1.3, 7.0, "ColdFill")
	_prop(PSX + "Lighting/ceiling_lamp_1_on.glb", Vector3(0, CEIL - 0.15, 2.5), 0.0, "TableLamp")


func _room() -> void:
	var wall := TEX_WALL
	var wt := Color(0.4, 0.41, 0.45)
	_solid(Vector3(0, -0.5, 0), Vector3(ROOM * 2, 1, ROOM * 2), _mat(TEX_FLOOR, 3.0, Color(0.33, 0.34, 0.37), Vector3(ROOM * 2, 1, ROOM * 2)), "Floor")
	_solid(Vector3(0, CEIL + 0.5, 0), Vector3(ROOM * 2, 1, ROOM * 2), _mat(wall, 2.5, Color(0.18, 0.18, 0.2), Vector3(ROOM * 2, 1, ROOM * 2)), "Ceiling")
	_solid(Vector3(0, CEIL * 0.5, -ROOM), Vector3(ROOM * 2, CEIL, 0.6), _mat(wall, 2.5, wt, Vector3(ROOM * 2, CEIL, 0.6)), "WallN")
	_solid(Vector3(0, CEIL * 0.5, ROOM), Vector3(ROOM * 2, CEIL, 0.6), _mat(wall, 2.5, wt, Vector3(ROOM * 2, CEIL, 0.6)), "WallS")
	# LEFT wall holds the mirror -> BACK_WALL_BIT so the reflection cam doesn't draw it.
	_solid(Vector3(-ROOM, CEIL * 0.5, 0), Vector3(0.6, CEIL, ROOM * 2), _mat(wall, 2.5, wt, Vector3(0.6, CEIL, ROOM * 2)), "WallW_Mirror", BACK_WALL_BIT)
	_solid(Vector3(ROOM, CEIL * 0.5, 0), Vector3(0.6, CEIL, ROOM * 2), _mat(wall, 2.5, wt, Vector3(0.6, CEIL, ROOM * 2)), "WallE")
	_solid(Vector3(-5, CEIL * 0.5, -5), Vector3(0.55, CEIL, 0.55), _mat(wall, 1.5, Color(0.3, 0.31, 0.34), Vector3(0.55, CEIL, 0.55)), "Pillar1")
	_solid(Vector3(5, CEIL * 0.5, 5), Vector3(0.55, CEIL, 0.55), _mat(wall, 1.5, Color(0.3, 0.31, 0.34), Vector3(0.55, CEIL, 0.55)), "Pillar2")


func _props() -> void:
	var p := Node3D.new(); p.name = "Props"; _attach(_root, p)
	var items := [
		[PSX + "Furniture/table_large_2.glb", Vector3(0, 0, 2.5), 0.0, "BriefingTable"],
		[PSX + "Furniture/chair_mp_1.glb", Vector3(1.5, 0, 3.6), 200.0, "Chair1"],
		[PSX + "Furniture/chair_mp_1.glb", Vector3(-1.5, 0, 3.6), 160.0, "Chair2"],
		[PSX + "Furniture/chair_mp_1.glb", Vector3(0, 0, 4.2), 180.0, "Chair3"],
		[PSX + "Furniture/shelf_mp_3.glb", Vector3(ROOM - 0.7, 0, 3.5), -90.0, "Shelf1"],
		[PSX + "Furniture/shelf_mp_3.glb", Vector3(ROOM - 0.7, 0, 5.5), -90.0, "Shelf2"],
		[PSX + "Furniture/display_cabinet_mp_1.glb", Vector3(ROOM - 0.7, 0, -2.0), -90.0, "Locker1"],
		[PSX + "Furniture/display_cabinet_mp_1.glb", Vector3(ROOM - 0.7, 0, -4.0), -90.0, "Locker2"],
		[PSX + "Large Props/wooden_crate_5.glb", Vector3(-ROOM + 1.5, 0, -3.5), 18.0, "Crate"],
		[PSX + "Large Props/cardboard_box_1.glb", Vector3(-ROOM + 2.4, 0, -2.6), -22.0, "Box"],
		[PSX + "Large Props/metal_barrel_mp_1.glb", Vector3(-ROOM + 1.4, 0, 5.5), 0.0, "Barrel"],
		[TECH + "screen_etx_1_stand.glb", Vector3(ROOM - 0.8, 1.6, 0.5), -90.0, "WallScreen"],
		[TECH + "control_panel_etx_1.glb", Vector3(-ROOM + 0.8, 0, 1.5), 90.0, "WallPanel"],
	]
	for it in items:
		var ps := load(it[0]) as PackedScene
		if ps == null:
			continue
		var n := ps.instantiate() as Node3D
		n.name = it[3]; n.position = it[1]; n.rotation.y = deg_to_rad(it[2])
		p.add_child(n); n.owner = _root


func _elevator() -> void:
	var g := Node3D.new(); g.name = "Elevator"; _attach(_root, g)
	var car_z := -ROOM + 1.4
	var half := 1.6
	var steel := Color(0.15, 0.16, 0.19)
	for d in [
		[Vector3(0, CEIL * 0.5, car_z - half), Vector3(half * 2 + 0.3, CEIL, 0.2), "Back"],
		[Vector3(-half, CEIL * 0.5, car_z), Vector3(0.2, CEIL, half * 2), "Left"],
		[Vector3(half, CEIL * 0.5, car_z), Vector3(0.2, CEIL, half * 2), "Right"],
		[Vector3(0, CEIL - 0.1, car_z), Vector3(half * 2, 0.2, half * 2), "Roof"],
		[Vector3(0, CEIL - 0.45, car_z + half), Vector3(half * 2 + 0.3, 0.9, 0.18), "Lintel"],
	]:
		_elev_solid(g, d[0], d[1], steel, d[2])
	var ps := load(PSX + "Modular Structures/elevator_1.glb") as PackedScene
	if ps != null:
		var n := ps.instantiate() as Node3D
		n.name = "ElevCar"; n.position = Vector3(0, 0, car_z - half + 0.2)
		g.add_child(n); n.owner = _root
	var cb := load(PSX + "Electronics & Misc/elevator_call_button_1.glb") as PackedScene
	if cb != null:
		var b := cb.instantiate() as Node3D
		b.name = "CallButton"; b.position = Vector3(half - 0.15, 1.2, car_z + half - 0.2)
		g.add_child(b); b.owner = _root
	var glow := OmniLight3D.new()
	glow.name = "ElevGlow"; glow.position = Vector3(0, CEIL - 0.6, car_z)
	glow.light_color = Color(1.0, 0.78, 0.45); glow.light_energy = 1.9; glow.omni_range = 4.5
	g.add_child(glow); glow.owner = _root
	# Start zone marker (lobby.gd reads its position to know where "in the elevator" is).
	var m := Marker3D.new(); m.name = "StartZone"; m.position = Vector3(0, 0, car_z)
	g.add_child(m); m.owner = _root


func _elev_solid(parent: Node, center: Vector3, size: Vector3, col: Color, nm: String) -> void:
	var body := StaticBody3D.new()
	body.name = nm; body.position = center; body.collision_layer = 2; body.collision_mask = 0
	parent.add_child(body); body.owner = _root
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = size; mi.mesh = bm
	var m := StandardMaterial3D.new(); m.albedo_color = col; m.metallic = 0.4; m.roughness = 0.5
	mi.material_override = m
	body.add_child(mi); mi.owner = _root
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new(); bs.size = size; cs.shape = bs
	body.add_child(cs); cs.owner = _root


## Instance the reusable, self-driving Mirror scene (scenes/mirror.tscn) on the west wall, facing
## the room. The Mirror tracks the live player camera and binds its reflection texture at runtime
## (no baked ViewportTexture = never purple). Move/resize it in the editor via its @exports.
func _mirror() -> void:
	var center := Vector3(-ROOM + 0.42, 1.75, 2.0)
	var ps := load("res://scenes/mirror.tscn") as PackedScene
	if ps == null:
		print("MISS mirror.tscn"); return
	var m := ps.instantiate() as Node3D
	m.name = "Mirror"
	m.position = center
	m.rotation.y = deg_to_rad(90.0)        # local +Z (the glass normal) points +X = into the room
	m.set("mirror_size", Vector2(4.0, 2.8))
	_attach(_root, m)
	# A soft fill so what the mirror reflects isn't pitch black.
	_light(center + Vector3(1.6, 0.4, 0), Color(0.7, 0.78, 0.95), 1.4, 5.0, "MirrorLight")


func _markers() -> void:
	var s := Marker3D.new(); s.name = "PlayerSpawn"; s.position = Vector3(0, 0.4, 4.5); _attach(_root, s)
