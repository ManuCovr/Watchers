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

const ROOM := 10.5      ## a touch bigger than the original 9 (room to mess around, not cavernous)
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
	_trim()
	_lounge()
	_plants()
	_paintings()
	_elevator()
	_music()
	_toys()
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
	env.background_color = Color(0.03, 0.028, 0.03)
	env.ambient_light_color = Color(0.42, 0.37, 0.32)     # LUXURY: warm, clean, well-lit (not abandoned)
	env.ambient_light_energy = 1.15
	env.fog_enabled = true; env.fog_density = 0.005; env.fog_light_color = Color(0.2, 0.16, 0.14)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true; env.glow_intensity = 0.4
	we.environment = env
	_attach(_root, we)


func _lights() -> void:
	# Warm pockets over each zone (reception / lounge / centre) + two hanging fixtures. Moody, not bright.
	_light(Vector3(0, CEIL - 0.6, 1.0), Color(1.0, 0.82, 0.56), 4.5, 13.0, "CentreChandelier", true)
	_light(Vector3(0, CEIL - 0.7, 5.5), Color(1.0, 0.78, 0.52), 4.5, 13.0, "LoungeGlow")
	_light(Vector3(7.5, CEIL - 0.9, -2.0), Color(1.0, 0.76, 0.48), 3.8, 10.0, "ReceptionGlow")
	_light(Vector3(0, CEIL - 0.6, -ROOM + 3.0), Color(0.66, 0.74, 1.0), 1.8, 8.0, "ElevatorCold")  # slightly cold/wrong by the lift
	_prop(PSX + "Lighting/ceiling_lamp_4_on.glb", Vector3(0, CEIL - 0.1, 1.0), 0.0, "Chandelier1")
	_prop(PSX + "Lighting/ceiling_lamp_4_on.glb", Vector3(0, CEIL - 0.1, 5.5), 0.0, "Chandelier2")


func _room() -> void:
	# Warm "old-money" palette: cream marble floor, muted gold/brown walls, dark ceiling.
	var wall := TEX_WALL
	var wt := Color(0.42, 0.36, 0.3)        # muted gold-brown wall
	_solid(Vector3(0, -0.5, 0), Vector3(ROOM * 2, 1, ROOM * 2), _mat(TEX_FLOOR, 3.0, Color(0.58, 0.53, 0.45), Vector3(ROOM * 2, 1, ROOM * 2)), "Floor")
	_solid(Vector3(0, CEIL + 0.5, 0), Vector3(ROOM * 2, 1, ROOM * 2), _mat(wall, 2.5, Color(0.14, 0.12, 0.12), Vector3(ROOM * 2, 1, ROOM * 2)), "Ceiling")
	# North wall has a GAP for the elevator opening (the lift is recessed BEHIND this wall, outside the room).
	var ow := 1.5            # opening half-width
	var oh := 2.7            # opening height
	_solid(Vector3(-(ROOM + ow) * 0.5, CEIL * 0.5, -ROOM), Vector3(ROOM - ow, CEIL, 0.6), _mat(wall, 2.5, wt, Vector3(ROOM - ow, CEIL, 0.6)), "WallN_L")
	_solid(Vector3((ROOM + ow) * 0.5, CEIL * 0.5, -ROOM), Vector3(ROOM - ow, CEIL, 0.6), _mat(wall, 2.5, wt, Vector3(ROOM - ow, CEIL, 0.6)), "WallN_R")
	_solid(Vector3(0, (oh + CEIL) * 0.5, -ROOM), Vector3(ow * 2, CEIL - oh, 0.6), _mat(wall, 2.5, wt, Vector3(ow * 2, CEIL - oh, 0.6)), "WallN_Top")
	_solid(Vector3(0, CEIL * 0.5, ROOM), Vector3(ROOM * 2, CEIL, 0.6), _mat(wall, 2.5, wt, Vector3(ROOM * 2, CEIL, 0.6)), "WallS")
	# LEFT wall holds the mirror -> BACK_WALL_BIT so the reflection cam doesn't draw it.
	_solid(Vector3(-ROOM, CEIL * 0.5, 0), Vector3(0.6, CEIL, ROOM * 2), _mat(wall, 2.5, wt, Vector3(0.6, CEIL, ROOM * 2)), "WallW_Mirror", BACK_WALL_BIT)
	_solid(Vector3(ROOM, CEIL * 0.5, 0), Vector3(0.6, CEIL, ROOM * 2), _mat(wall, 2.5, wt, Vector3(0.6, CEIL, ROOM * 2)), "WallE")
	# A long runner carpet down the middle (real asset, scaled) + grand pillars in the corners.
	_prop(PSX + "Large Props/carpet_mp_1.glb", Vector3(0, 0.02, 1.0), 0.0, "RunnerCarpet", 4.0)
	var pcol := Color(0.34, 0.3, 0.26)
	_solid(Vector3(-7, CEIL * 0.5, -7), Vector3(0.6, CEIL, 0.6), _mat(wall, 1.5, pcol, Vector3(0.6, CEIL, 0.6)), "Pillar1")
	_solid(Vector3(7, CEIL * 0.5, -7), Vector3(0.6, CEIL, 0.6), _mat(wall, 1.5, pcol, Vector3(0.6, CEIL, 0.6)), "Pillar2")
	_solid(Vector3(-7, CEIL * 0.5, 8), Vector3(0.6, CEIL, 0.6), _mat(wall, 1.5, pcol, Vector3(0.6, CEIL, 0.6)), "Pillar3")
	_solid(Vector3(7, CEIL * 0.5, 8), Vector3(0.6, CEIL, 0.6), _mat(wall, 1.5, pcol, Vector3(0.6, CEIL, 0.6)), "Pillar4")


## Drop a list of [path, pos, rot_deg, name, (scale)] real-asset props under a named group.
func _group(group_name: String, items: Array) -> void:
	var g := Node3D.new(); g.name = group_name; _attach(_root, g)
	for it in items:
		var ps := load(it[0]) as PackedScene
		if ps == null:
			print("MISS ", it[0]); continue
		var n := ps.instantiate() as Node3D
		n.name = it[3]; n.position = it[1]; n.rotation.y = deg_to_rad(it[2])
		n.scale = Vector3.ONE * (it[4] if it.size() > 4 else 1.0)
		g.add_child(n); n.owner = _root


func _smat(col: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = col; m.roughness = rough; m.metallic = metal
	return m


## A PROPER built front desk against the east wall: a dark-wood counter with a polished marble top,
## a brass kick-rail, and concierge clutter on top. Reads as a real hotel reception, not a table pile.
func _reception() -> void:
	var dx := ROOM - 1.6          # counter face a bit off the east wall
	var top := 1.08
	_solid(Vector3(dx, top * 0.5, -2), Vector3(1.0, top, 4.6), _smat(Color(0.26, 0.16, 0.09), 0.6, 0.0), "ReceptionBase")
	_solid(Vector3(dx, top + 0.07, -2), Vector3(1.3, 0.14, 5.0), _smat(Color(0.6, 0.56, 0.5), 0.3, 0.15), "ReceptionTop")
	_solid(Vector3(dx - 0.46, 0.12, -2), Vector3(0.06, 0.24, 4.6), _smat(Color(0.45, 0.36, 0.18), 0.4, 0.6), "ReceptionRail")
	# concierge clutter ON the marble top
	_group("ReceptionProps", [
		[PSX + "Lighting/lamp_1_on.glb", Vector3(dx, top + 0.15, -0.2), 200.0, "DeskLamp"],
		[PSX + "Items & Weapons/notebook_1.glb", Vector3(dx, top + 0.15, -1.6), 20.0, "Ledger"],
		[PSX + "Small Props/open_book_mp_1.glb", Vector3(dx - 0.1, top + 0.15, -2.6), -10.0, "GuestBook"],
		[PSX + "Items & Weapons/key_mp_1.glb", Vector3(dx + 0.15, top + 0.15, -1.0), 40.0, "Key1"],
		[PSX + "Items & Weapons/keycard_1.glb", Vector3(dx + 0.1, top + 0.15, -3.3), 0.0, "Keycard"],
		[PSX + "Small Props/ashtray_1.glb", Vector3(dx - 0.2, top + 0.15, -2.1), 0.0, "DeskAshtray"],
	])
	_light(Vector3(dx, top + 0.8, -0.2), Color(1.0, 0.74, 0.42), 1.8, 4.0, "DeskLampGlow")


## Waiting lounge in the middle-south: a rug, sofas + chairs around a coffee table with clutter,
## floor lamps. The open social space where friends mess with the physics toys.
func _lounge() -> void:
	_group("Lounge", [
		[PSX + "Large Props/carpet_mp_1.glb", Vector3(0, 0.03, 5.5), 90.0, "LoungeRug", 3.2],
		[PSX + "Furniture/sofa_1.glb", Vector3(0, 0, 7.3), 180.0, "Sofa1"],
		[PSX + "Furniture/sofa_2.glb", Vector3(-3.2, 0, 5.4), 90.0, "Sofa2"],
		[PSX + "Furniture/sofa_3.glb", Vector3(3.2, 0, 5.4), -90.0, "Sofa3"],
		[PSX + "Furniture/coffee_table_1.glb", Vector3(0, 0, 5.4), 0.0, "CoffeeTable"],
		[PSX + "Furniture/chair_mp_1.glb", Vector3(-2.0, 0, 8.0), 150.0, "LoungeChair1"],
		[PSX + "Furniture/chair_mp_1.glb", Vector3(2.0, 0, 8.0), 210.0, "LoungeChair2"],
		[PSX + "Lighting/lamp_3_1_on.glb", Vector3(-3.6, 0, 7.6), 0.0, "FloorLamp1"],
		[PSX + "Lighting/lamp_3_1_on.glb", Vector3(3.6, 0, 7.6), 0.0, "FloorLamp2"],
		# coffee-table clutter (decor — the throwables are spawned by lobby.gd)
		[PSX + "Small Props/ashtray_1.glb", Vector3(0.3, 0.42, 5.4), 0.0, "LoungeAshtray"],
		[PSX + "Items & Weapons/glass_bottle_1.glb", Vector3(-0.3, 0.42, 5.2), 0.0, "Bottle1"],
		[PSX + "Items & Weapons/glass_bottle_1.glb", Vector3(-0.45, 0.42, 5.6), 30.0, "Bottle2"],
		[PSX + "Small Props/book_mp_1.glb", Vector3(0.4, 0.42, 5.7), 60.0, "LoungeBook"],
	])
	_light(Vector3(-3.6, 1.2, 7.6), Color(1.0, 0.7, 0.4), 1.3, 3.5, "FloorLamp1Glow")
	_light(Vector3(3.6, 1.2, 7.6), Color(1.0, 0.7, 0.4), 1.3, 3.5, "FloorLamp2Glow")


## A little greenery in the corners — ferns as potted hotel plants.
func _plants() -> void:
	_group("Plants", [
		["res://assets/nature/fern_1.glb", Vector3(-9.2, 0, -9.0), 0.0, "Fern1", 1.4],
		["res://assets/nature/fern_2.glb", Vector3(9.2, 0, -9.0), 30.0, "Fern2", 1.4],
		["res://assets/nature/fern_1.glb", Vector3(-9.2, 0, 9.2), 60.0, "Fern3", 1.5],
		["res://assets/nature/fern_3.glb", Vector3(9.2, 0, 9.2), 90.0, "Fern4", 1.5],
		["res://assets/nature/fern_2.glb", Vector3(-5.5, 0, 0.0), 0.0, "Fern5", 1.2],
	])


## Diegetic-ish jazz: an FM radio prop on the desk + a NON-positional AudioStreamPlayer so the music
## is the same volume everywhere in the lobby (not affected by where you stand). The .mp3 loops.
func _music() -> void:
	_prop("res://assets/psx2/Props/handheld_fm_radio_etx_1.glb", Vector3(0.4, 0.45, 5.1), 200.0, "JazzRadio")
	var a := AudioStreamPlayer.new()
	a.name = "LobbyJazz"
	a.stream = load("res://assets/audio/music/lobby_jazz.mp3")
	a.volume_db = -15.0            # subtle background, even across the whole room
	a.autoplay = true
	_attach(_root, a)


## Visual-only box (no collision) — for moulding/beams/doors that shouldn't block movement.
func _vmesh(parent: Node, center: Vector3, size: Vector3, mat: StandardMaterial3D, nm: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); mi.name = nm
	var bm := BoxMesh.new(); bm.size = size; mi.mesh = bm; mi.material_override = mat; mi.position = center
	parent.add_child(mi); mi.owner = _root
	return mi


## Wall + ceiling richness: wainscoting + chair rail + crown on the N/S/E walls (NOT the W mirror
## wall — its trim showed as a bar in the reflection), brass PILASTERS between bays, a coffered
## CEILING of wood beams, and warm wall sconces. Makes it feel furnished, not a bare box.
func _trim() -> void:
	var wains := _smat(Color(0.22, 0.14, 0.08), 0.6, 0.0)     # dark wood dado
	var brass := _smat(Color(0.44, 0.35, 0.18), 0.4, 0.6)     # brass moulding / pilasters
	var beam := _smat(Color(0.2, 0.13, 0.08), 0.7, 0.0)       # ceiling beam wood
	var R := ROOM
	# wainscoting (low) + chair rail (mid) + crown (top) — N, S, E walls only.
	var walls := [[Vector3(0, 0, -R), Vector3(R * 2, 0, 0.14)], [Vector3(0, 0, R), Vector3(R * 2, 0, 0.14)],
		[Vector3(R, 0, 0), Vector3(0.14, 0, R * 2)]]
	for w in walls:
		_vmesh(_root, Vector3(w[0].x, 0.55, w[0].z), Vector3(maxf(w[1].x, 0.14), 1.1, maxf(w[1].z, 0.14)), wains, "Wainscot")
		_vmesh(_root, Vector3(w[0].x, 1.18, w[0].z), Vector3(maxf(w[1].x, 0.18), 0.12, maxf(w[1].z, 0.18)), brass, "ChairRail")
		_vmesh(_root, Vector3(w[0].x, CEIL - 0.22, w[0].z), Vector3(maxf(w[1].x, 0.2), 0.26, maxf(w[1].z, 0.2)), brass, "Crown")
	# pilasters (vertical brass columns) between the bays — skip the elevator opening at x~0 on the N wall.
	for x in [-7.0, -3.5, 3.5, 7.0]:
		_vmesh(_root, Vector3(x, CEIL * 0.5, -R + 0.12), Vector3(0.34, CEIL, 0.18), brass, "PilasterN")
	for x in [-7.0, -3.5, 0.0, 3.5, 7.0]:
		_vmesh(_root, Vector3(x, CEIL * 0.5, R - 0.12), Vector3(0.34, CEIL, 0.18), brass, "PilasterS")
	for z in [-7.0, -3.5, 0.0, 3.5, 7.0]:
		_vmesh(_root, Vector3(R - 0.12, CEIL * 0.5, z), Vector3(0.18, CEIL, 0.34), brass, "PilasterE")
	# coffered ceiling: a grid of beams just under the ceiling.
	for x in [-7.0, -3.5, 0.0, 3.5, 7.0]:
		_vmesh(_root, Vector3(x, CEIL - 0.18, 0), Vector3(0.3, 0.3, R * 2), beam, "BeamZ")
	for z in [-7.0, -3.5, 3.5, 7.0]:
		_vmesh(_root, Vector3(0, CEIL - 0.18, z), Vector3(R * 2, 0.3, 0.3), beam, "BeamX")
	# warm wall sconces (small lamp props + a soft light each)
	var sconces := [[Vector3(R - 0.3, 2.4, 4.0), -90.0], [Vector3(R - 0.3, 2.4, -7.0), -90.0],
		[Vector3(-R + 0.3, 2.4, 5.0), 90.0], [Vector3(-R + 0.3, 2.4, -5.0), 90.0],
		[Vector3(-5.0, 2.4, R - 0.3), 180.0], [Vector3(5.0, 2.4, R - 0.3), 180.0]]
	for sc in sconces:
		_prop(PSX + "Lighting/lamp_2_on.glb", sc[0], sc[1], "Sconce")
		_light(sc[0] + Vector3(0, 0.1, 0), Color(1.0, 0.76, 0.46), 1.2, 3.4, "SconceGlow")


## Framed paintings on the walls showing the downloaded art (built frame + canvas so the texture
## override saves cleanly into the scene). Forward (canvas +Z) is oriented by `rot`.
const ART := ["res://assets/textures/paintings/art_a.jpg", "res://assets/textures/paintings/art_b.jpg",
	"res://assets/textures/paintings/art_c.jpg", "res://assets/textures/paintings/art_d.png",
	"res://assets/textures/paintings/art_e.jpg"]

func _painting(pos: Vector3, rot: float, tex: String, nm: String, w := 1.5, h := 1.05) -> void:
	var g := Node3D.new(); g.name = nm; g.position = pos; g.rotation.y = deg_to_rad(rot); _attach(_root, g)
	var frame := MeshInstance3D.new(); frame.name = "Frame"
	var fb := BoxMesh.new(); fb.size = Vector3(w + 0.14, h + 0.14, 0.07); frame.mesh = fb
	frame.material_override = _smat(Color(0.4, 0.32, 0.16), 0.4, 0.6); _attach(g, frame)
	var canvas := MeshInstance3D.new(); canvas.name = "Canvas"
	var qb := QuadMesh.new(); qb.size = Vector2(w, h)   # QuadMesh = clean 0-1 UV -> image fills/stretches to the frame
	canvas.mesh = qb
	canvas.position = Vector3(0, 0, 0.05)
	var cm := StandardMaterial3D.new(); cm.albedo_texture = load(tex); cm.roughness = 0.55; cm.albedo_color = Color(0.95, 0.93, 0.9)
	canvas.material_override = cm; _attach(g, canvas)

## Physics toys as REAL editor nodes (a crowbar + two bats) on the open lounge floor — they fall and
## settle at runtime. Editor-visible so you can move/add them in the scene.
func _toys() -> void:
	var g := Node3D.new(); g.name = "Toys"; _attach(_root, g)
	for it in [["res://items/item_crowbar.tscn", Vector3(-2.0, 0.5, 3.4)],
			["res://items/item_baseball_bat.tscn", Vector3(2.0, 0.6, 3.4)],
			["res://items/item_baseball_bat.tscn", Vector3(0.7, 0.6, 2.6)]]:
		var ps := load(it[0]) as PackedScene
		if ps == null:
			continue
		var n := ps.instantiate()
		n.position = it[1]
		g.add_child(n); n.owner = _root


func _paintings() -> void:
	# east wall (faces -X -> rot -90), west wall (faces +X -> rot 90, avoid the mirror near z=2), south (faces -Z -> 180)
	_painting(Vector3(ROOM - 0.34, 2.35, 1.5), -90.0, ART[0], "ArtE1")
	_painting(Vector3(ROOM - 0.34, 2.35, -6.5), -90.0, ART[1], "ArtE2")
	_painting(Vector3(-ROOM + 0.34, 2.35, -5.0), 90.0, ART[2], "ArtW1")
	_painting(Vector3(-ROOM + 0.34, 2.35, 7.5), 90.0, ART[3], "ArtW2")
	_painting(Vector3(-5.0, 2.35, ROOM - 0.34), 180.0, ART[4], "ArtS1", 1.8, 1.2)
	_painting(Vector3(5.0, 2.35, ROOM - 0.34), 180.0, ART[0], "ArtS2", 1.8, 1.2)


## A real brass HOTEL LIFT recessed BEHIND the north wall (outside the room), entered through the
## wall opening. Built from clean editor-visible pieces (no model), with open doors, a control panel,
## a warm interior light, exterior shaft rails, a sign and a low hum.
func _elevator() -> void:
	var g := Node3D.new(); g.name = "Elevator"; _attach(_root, g)
	var zf := float(-ROOM)         # opening plane (the north wall)
	var depth := 2.6
	var zc := zf - depth * 0.5     # car centre, OUTSIDE the room
	var hw := 1.5                  # matches the wall opening half-width
	var ht := 2.7
	var brass := Color(0.5, 0.42, 0.26)
	var dark := Color(0.16, 0.14, 0.11)
	# Car shell (recessed beyond the wall).
	_elev_solid(g, Vector3(0, ht * 0.5, zf - depth), Vector3(hw * 2, ht, 0.15), brass, "Back")
	_elev_solid(g, Vector3(-hw, ht * 0.5, zc), Vector3(0.15, ht, depth), brass, "Left")
	_elev_solid(g, Vector3(hw, ht * 0.5, zc), Vector3(0.15, ht, depth), brass, "Right")
	_elev_solid(g, Vector3(0, ht, zc), Vector3(hw * 2, 0.15, depth), brass, "Ceil")
	_elev_solid(g, Vector3(0, -0.04, zc), Vector3(hw * 2, 0.08, depth), Color(0.22, 0.19, 0.16), "CarFloor")
	# Brass door frame around the opening + two OPEN doors slid to the sides.
	_elev_solid(g, Vector3(0, ht + 0.12, zf), Vector3(hw * 2 + 0.5, 0.32, 0.28), brass, "Lintel")
	_elev_solid(g, Vector3(-hw - 0.18, ht * 0.5, zf), Vector3(0.28, ht, 0.28), brass, "JambL")
	_elev_solid(g, Vector3(hw + 0.18, ht * 0.5, zf), Vector3(0.28, ht, 0.28), brass, "JambR")
	# Doors are VISUAL ONLY (no collision) so they never block the entrance; they slide shut on descend.
	var dmat := _smat(Color(0.55, 0.47, 0.3), 0.35, 0.5)
	_vmesh(g, Vector3(-hw + 0.38, ht * 0.5, zf - 0.16), Vector3(0.72, ht - 0.1, 0.08), dmat, "DoorL")
	_vmesh(g, Vector3(hw - 0.38, ht * 0.5, zf - 0.16), Vector3(0.72, ht - 0.1, 0.08), dmat, "DoorR")
	# Exterior shaft rails (so it reads as an external lift attached to the building).
	_elev_solid(g, Vector3(-hw - 0.35, CEIL * 0.6, zf - 0.2), Vector3(0.16, CEIL * 1.2, 0.16), dark, "RailL")
	_elev_solid(g, Vector3(hw + 0.35, CEIL * 0.6, zf - 0.2), Vector3(0.16, CEIL * 1.2, 0.16), dark, "RailR")
	# Control panel inside (right wall) + a diegetic call button.
	_elev_solid(g, Vector3(hw - 0.12, 1.2, zc + 0.35), Vector3(0.06, 0.55, 0.32), dark, "PanelPlate")
	var cb := load(PSX + "Electronics & Misc/elevator_call_button_1.glb") as PackedScene
	if cb != null:
		var b := cb.instantiate() as Node3D
		b.name = "CallButton"; b.position = Vector3(hw - 0.17, 1.2, zc + 0.35); b.rotation.y = deg_to_rad(-90)
		g.add_child(b); b.owner = _root
	# Warm interior light + exterior sign.
	var l := OmniLight3D.new()
	l.name = "ElevLight"; l.position = Vector3(0, ht - 0.25, zc)
	l.light_color = Color(1.0, 0.82, 0.5); l.light_energy = 2.8; l.omni_range = 4.0; l.shadow_enabled = true
	g.add_child(l); l.owner = _root
	var sign := load(PSX + "Electronics & Misc/elevator_sign_1.glb") as PackedScene
	if sign != null:
		var s := sign.instantiate() as Node3D
		s.name = "ElevSign"; s.position = Vector3(0, ht + 0.45, zf + 0.12)
		g.add_child(s); s.owner = _root
	# Low mechanical hum from the shaft (subtle).
	var hum := AudioStreamPlayer3D.new()
	hum.name = "ElevHum"; hum.position = Vector3(0, 1.0, zc)
	hum.stream = load("res://assets/audio/sfx/machine_mx_1_loop.ogg")
	hum.volume_db = -26.0; hum.unit_size = 4.0; hum.autoplay = true
	g.add_child(hum); hum.owner = _root
	# Start zone (lobby.gd reads this to know where "in the lift" is) — just inside the doors.
	var m := Marker3D.new(); m.name = "StartZone"; m.position = Vector3(0, 0, zf - 0.6)
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
	var s := Marker3D.new(); s.name = "PlayerSpawn"; s.position = Vector3(0, 0.4, 1.5); _attach(_root, s)
