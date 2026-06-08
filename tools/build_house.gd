extends SceneTree
## ONE-TIME GENERATOR for an authored, TEXTURED, multi-room house -> res://scenes/house.tscn.
## Run: Godot_console.exe --headless --path <proj> --script res://tools/build_house.gd
## Re-running OVERWRITES house.tscn. Real nodes (drag them in the editor).
##
## Layout (compact, corridor-spine):
##   front entry/foyer -> central corridor -> stairwell at the back (ramp up to 2F)
##   Left wing:  LIVING (front, the "watch zone") + KITCHEN (back)
##   Right wing: OFFICE (front) + BATHROOM (back)
##   Upstairs:   landing + 2 bedrooms over the wings.
## Stairs are a smooth RAMP collider under stepped visuals (verified climbable).

const HALF_X := 15.0
const HALF_Z := 16.0
const FLOOR_H := 3.5        # storey height; with a THIN slab the ceiling sits ~3.2m = comfy headroom
const SLAB_T := 0.3         # floor-slab thickness (thin = no head-scraping ceiling)
const WALL_T := 0.3
const DOOR_W := 3.2         # slightly wider doorways feel less cramped
const CORR := 3.2           # corridor half-width
# Stairwell + 2F opening (back of the corridor, no side doors there).
const SW_Z0 := -13.0        # ramp top (lands on solid 2F at z < SW_Z0)
const SW_Z1 := -6.0         # ramp base (corridor side)

var _root: Node3D
var _nav: NavigationRegion3D
var _t_wall: Texture2D
var _t_floor: Texture2D
var _t_tile: Texture2D
var _t_slab: Texture2D
var _t_roof: Texture2D


func _initialize() -> void:
	_root = Node3D.new()
	_root.name = "House"
	_t_wall = load("res://assets/textures/Brick-Stone.png")
	_t_floor = load("res://assets/textures/Wood-Dark.png")
	_t_tile = load("res://assets/textures/Floor-Tiles.png")
	_t_slab = load("res://assets/textures/Wood-Mid.png")
	_t_roof = load("res://assets/textures/Roof-Tiles.png")

	_nav = NavigationRegion3D.new()
	_nav.name = "Nav"
	var nm := NavigationMesh.new()
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	_nav.navigation_mesh = nm
	_attach(_root, _nav)

	_build_slabs()
	_build_perimeter()
	_build_rooms()
	_build_stairs()
	_build_upstairs()
	_build_lights()
	_build_ceiling_fixtures()      # PSX lamp models hung under each light
	_build_clutter()               # PSX furniture (real models, draggable nodes)
	_build_cobwebs()               # corner decals = lived-in/abandoned
	_build_easter_eggs()
	_build_markers()

	var packed := PackedScene.new()
	if packed.pack(_root) == OK:
		print("build_house: saved err=", ResourceSaver.save(packed, "res://scenes/house.tscn"),
			" nodes=", _count(_root))
	_root.free()
	quit()


func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c


func _attach(parent: Node, child: Node) -> void:
	parent.add_child(child)
	if child != _root:
		child.owner = _root


# ---- textured box -----------------------------------------------------------
func _mat(tex: Texture2D, _size: Vector3, tile := 3.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.roughness = 0.95
	if tex != null:
		m.albedo_texture = tex
		# WORLD triplanar = texture tiles by world position on every face, so big slabs
		# never stretch (this was the "stretched textures" bug). Same scale everywhere.
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE / tile
	else:
		m.albedo_color = Color(0.13, 0.13, 0.16)
	return m


func _uv_scale(size: Vector3, tile: float) -> Vector3:
	# Tile roughly every `tile` metres on the box's two largest faces.
	var flat := size.y <= size.x and size.y <= size.z       # floor/ceiling slab
	if flat:
		return Vector3(maxf(size.x, 0.5) / tile, maxf(size.z, 0.5) / tile, 1)
	return Vector3(maxf(maxf(size.x, size.z), 0.5) / tile, maxf(size.y, 0.5) / tile, 1)


func _box(pos: Vector3, size: Vector3, tex: Texture2D, nm := "Box", tile := 3.5) -> void:
	var body := StaticBody3D.new()
	body.name = nm
	body.position = pos
	body.collision_layer = 2
	body.collision_mask = 0
	_attach(_nav, body)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(tex, size, tile)
	_attach(body, mi)
	var col := CollisionShape3D.new()
	col.name = "Col"
	var bs := BoxShape3D.new()
	bs.size = size
	col.shape = bs
	_attach(body, col)


## A wall SEGMENT: an invisible box collider skinned with tiled PSX wall panels (real
## 4×3m modular pieces) so the walls are actual kit geometry, not stretched texture boxes.
const PSX_WALL := "res://assets/psx/Modular Structures/wall_1_plain.glb"
const WALL_PANEL_W := 4.06
const WALL_PANEL_H := 3.0

func _wall_seg(pos: Vector3, size: Vector3, nm := "Wall") -> void:
	var body := StaticBody3D.new()
	body.name = nm
	body.position = pos
	body.collision_layer = 2
	body.collision_mask = 0
	_attach(_nav, body)
	var col := CollisionShape3D.new()
	col.name = "Col"
	var bs := BoxShape3D.new()
	bs.size = size
	col.shape = bs
	_attach(body, col)

	var ps := load(PSX_WALL) as PackedScene
	if ps == null:
		return
	var along_x := size.x >= size.z
	var run: float = size.x if along_x else size.z
	var cols: int = maxi(1, int(round(run / WALL_PANEL_W)))
	var rows: int = maxi(1, int(round(size.y / WALL_PANEL_H)))
	var pw := run / float(cols)
	var ph := size.y / float(rows)
	var skin := _mat(_t_wall, size, 3.0)
	for r in rows:
		for c in cols:
			var panel := ps.instantiate() as Node3D
			panel.name = "Panel"
			panel.scale = Vector3(pw / WALL_PANEL_W, ph / WALL_PANEL_H, 1.0)
			var off := -run * 0.5 + pw * (float(c) + 0.5)
			var y := -size.y * 0.5 + ph * float(r)
			if along_x:
				panel.position = Vector3(off, y, 0)
			else:
				panel.position = Vector3(0, y, off)
				panel.rotation.y = PI * 0.5
			_skin(panel, skin)              # readable stone over the PSX panel geometry
			_attach(body, panel)


## Recursively set a material_override so a dark imported model reads under our lights.
func _skin(n: Node, mat: Material) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_override = mat
	for c in n.get_children():
		_skin(c, mat)


# Wall along X with up to several doorways (gap centres in `doors`).
func _wall_x(cx: float, cz: float, length: float, yb: float, h: float, doors: Array = []) -> void:
	var ds := doors.duplicate()
	ds.sort()
	var cursor := cx - length * 0.5
	for dx in ds:
		var seg_end: float = dx - DOOR_W * 0.5
		if seg_end - cursor > 0.1:
			_wall_seg(Vector3((cursor + seg_end) * 0.5, yb + h * 0.5, cz),
				Vector3(seg_end - cursor, h, WALL_T), "WallX")
		cursor = dx + DOOR_W * 0.5
	var far := cx + length * 0.5
	if far - cursor > 0.1:
		_wall_seg(Vector3((cursor + far) * 0.5, yb + h * 0.5, cz),
			Vector3(far - cursor, h, WALL_T), "WallX")


# Wall along Z with up to several doorways.
func _wall_z(cx: float, cz: float, length: float, yb: float, h: float, doors: Array = []) -> void:
	var ds := doors.duplicate()
	ds.sort()
	var cursor := cz - length * 0.5
	for dz in ds:
		var seg_end: float = dz - DOOR_W * 0.5
		if seg_end - cursor > 0.1:
			_wall_seg(Vector3(cx, yb + h * 0.5, (cursor + seg_end) * 0.5),
				Vector3(WALL_T, h, seg_end - cursor), "WallZ")
		cursor = dz + DOOR_W * 0.5
	var far := cz + length * 0.5
	if far - cursor > 0.1:
		_wall_seg(Vector3(cx, yb + h * 0.5, (cursor + far) * 0.5),
			Vector3(WALL_T, h, far - cursor), "WallZ")


# ---- slabs ------------------------------------------------------------------
func _build_slabs() -> void:
	# Ground floor (solid). Wood in living areas, tiles handled by separate kitchen/bath floors.
	_box(Vector3(0, -0.5, 0), Vector3(HALF_X * 2, 1, HALF_Z * 2), _t_floor, "GroundFloor", 4.0)
	# Tiled floors for kitchen (back-left) + bathroom (back-right) on TOP of the wood.
	_box(Vector3(-9, 0.01, -1), Vector3(11.5, 0.04, 10.5), _t_tile, "KitchenFloor", 2.0)
	_box(Vector3(9, 0.01, -1), Vector3(11.5, 0.04, 10.5), _t_tile, "BathFloor", 2.0)
	# Second floor (solid except the stairwell opening).
	_slab_with_opening(FLOOR_H, _t_slab, "SecondFloor")
	# Flat roof.
	_box(Vector3(0, FLOOR_H * 2 + 0.25, 0), Vector3(HALF_X * 2, 0.5, HALF_Z * 2), _t_roof, "Roof", 4.0)


func _slab_with_opening(top_y: float, tex: Texture2D, nm: String) -> void:
	var t := SLAB_T              # thin slab -> the ceiling underside is right below top_y
	var yc := top_y - t * 0.5
	# south of opening (z > SW_Z1)
	_box(Vector3(0, yc, (HALF_Z + SW_Z1) * 0.5), Vector3(HALF_X * 2, t, HALF_Z - SW_Z1), tex, nm, 4.0)
	# north of opening (z < SW_Z0)
	_box(Vector3(0, yc, (-HALF_Z + SW_Z0) * 0.5), Vector3(HALF_X * 2, t, SW_Z0 + HALF_Z), tex, nm, 4.0)
	# west of opening
	_box(Vector3((-HALF_X - CORR) * 0.5, yc, (SW_Z0 + SW_Z1) * 0.5),
		Vector3(HALF_X - CORR, t, SW_Z1 - SW_Z0), tex, nm, 4.0)
	# east of opening
	_box(Vector3((HALF_X + CORR) * 0.5, yc, (SW_Z0 + SW_Z1) * 0.5),
		Vector3(HALF_X - CORR, t, SW_Z1 - SW_Z0), tex, nm, 4.0)


func _build_perimeter() -> void:
	var fh := FLOOR_H * 2
	_wall_seg(Vector3(0, fh * 0.5, -HALF_Z), Vector3(HALF_X * 2, fh, WALL_T), "PerimN")
	_wall_seg(Vector3(0, fh * 0.5, HALF_Z), Vector3(HALF_X * 2, fh, WALL_T), "PerimS")
	_wall_seg(Vector3(-HALF_X, fh * 0.5, 0), Vector3(WALL_T, fh, HALF_Z * 2), "PerimW")
	_wall_seg(Vector3(HALF_X, fh * 0.5, 0), Vector3(WALL_T, fh, HALF_Z * 2), "PerimE")


func _build_rooms() -> void:
	# Corridor walls (x = +/-CORR). z[SW_Z1, HALF_Z] has room doors; z[-HALF_Z, SW_Z1] = solid stairwell sides.
	# Left corridor wall: doors at z=10 (living) and z=0 (kitchen).
	_wall_z(-CORR, (SW_Z1 + HALF_Z) * 0.5, HALF_Z - SW_Z1, 0, FLOOR_H, [10.0, 0.0])
	_wall_z(-CORR, (-HALF_Z + SW_Z1) * 0.5, SW_Z1 + HALF_Z, 0, FLOOR_H)          # stairwell side (solid)
	# Right corridor wall: doors at z=10 (office), z=0 (bathroom).
	_wall_z(CORR, (SW_Z1 + HALF_Z) * 0.5, HALF_Z - SW_Z1, 0, FLOOR_H, [10.0, 0.0])
	_wall_z(CORR, (-HALF_Z + SW_Z1) * 0.5, SW_Z1 + HALF_Z, 0, FLOOR_H)
	# Wing dividers at z=5 (no doors — each room opens to the corridor).
	_wall_x(-((HALF_X + CORR) * 0.5), 5.0, HALF_X - CORR, 0, FLOOR_H)
	_wall_x(((HALF_X + CORR) * 0.5), 5.0, HALF_X - CORR, 0, FLOOR_H)


func _build_stairs() -> void:
	# Smooth ramp collider from (z=SW_Z1, y=0) up to (z=SW_Z0, y=FLOOR_H), 5 wide.
	var run := SW_Z1 - SW_Z0                 # 7
	var length := sqrt(run * run + FLOOR_H * FLOOR_H) + 0.5
	var angle := atan2(FLOOR_H, run)
	var ramp := StaticBody3D.new()
	ramp.name = "StairRampCollider"
	ramp.collision_layer = 2
	ramp.collision_mask = 0
	ramp.position = Vector3(0, FLOOR_H * 0.5 - 0.18, (SW_Z0 + SW_Z1) * 0.5)
	ramp.rotation.x = angle                  # +z end (base SW_Z1) DOWN ; -z end (top SW_Z0) UP
	_attach(_nav, ramp)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var bm := BoxMesh.new()
	bm.size = Vector3(5.0, 0.3, length)
	mi.mesh = bm
	mi.material_override = _mat(_t_slab, Vector3(5, 0.3, length), 2.0)
	_attach(ramp, mi)
	var col := CollisionShape3D.new()
	col.name = "Col"
	var bs := BoxShape3D.new()
	bs.size = Vector3(5.0, 0.3, length)
	col.shape = bs
	_attach(ramp, col)
	# Visible step fronts (no collision) for looks.
	var nsteps := 8
	for i in nsteps:
		var h := FLOOR_H * float(i + 1) / float(nsteps)
		var zc := SW_Z1 - (run) * float(i) / float(nsteps) - 0.4
		_visual(Vector3(0, h * 0.5, zc), Vector3(5, h, 0.5), _t_slab, "StepVis%d" % i)
	# Landing rails around the 2F opening.
	_box(Vector3(-CORR - 0.1, FLOOR_H + 0.55, (SW_Z0 + SW_Z1) * 0.5),
		Vector3(0.25, 1.1, run), _t_wall, "RailW")
	_box(Vector3(CORR + 0.1, FLOOR_H + 0.55, (SW_Z0 + SW_Z1) * 0.5),
		Vector3(0.25, 1.1, run), _t_wall, "RailE")


func _visual(pos: Vector3, size: Vector3, tex: Texture2D, nm: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.position = pos
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(tex, size, 2.0)
	_attach(_nav, mi)


func _build_upstairs() -> void:
	# Two bedrooms over the wings, off a landing. Doors face the stair landing.
	_wall_z(-CORR, 5.0, HALF_Z - 5.0, FLOOR_H, FLOOR_H, [11.0])
	_wall_z(CORR, 5.0, HALF_Z - 5.0, FLOOR_H, FLOOR_H, [11.0])
	_wall_x(-((HALF_X + CORR) * 0.5), 2.0, HALF_X - CORR, FLOOR_H, FLOOR_H)
	_wall_x(((HALF_X + CORR) * 0.5), 2.0, HALF_X - CORR, FLOOR_H, FLOOR_H)


# ---- lighting (warm, per room) ----------------------------------------------
const LIGHT_BOOST := 1.9    # brighter pools so the PSX walls/props actually read

func _lamp(pos: Vector3, energy: float, rng: float, nm: String, col := Color(1.0, 0.92, 0.78)) -> void:
	var l := OmniLight3D.new()
	l.name = nm
	l.position = pos
	l.light_color = col
	l.light_energy = energy * LIGHT_BOOST
	l.omni_range = rng * 1.25
	l.omni_attenuation = 1.4
	_attach(_nav, l)


func _build_lights() -> void:
	# Moody, warm, pools of light with dark gaps between rooms (atmosphere > flat-lit).
	var yc := FLOOR_H - 0.35
	var warm := Color(1.0, 0.86, 0.62)
	var cold := Color(0.7, 0.82, 1.0)
	_lamp(Vector3(-9, yc, 9), 2.6, 12, "LivingLamp", warm)        # living (watch zone) — brightest
	_lamp(Vector3(-9, yc, -4), 1.4, 10, "KitchenLamp", cold)      # kitchen — cold/clinical
	_lamp(Vector3(9, yc, 11), 1.6, 10, "OfficeLamp", warm)
	_lamp(Vector3(11, yc, -8), 1.0, 8, "BathLamp", cold)          # bath — dim
	_lamp(Vector3(0, yc, 12), 1.1, 9, "FoyerLamp", warm)          # foyer pool
	_lamp(Vector3(0, yc, 2), 1.0, 9, "CorridorLamp", warm)        # corridor spine — readable walls
	_lamp(Vector3(0, FLOOR_H - 0.5, -9), 0.8, 8, "StairLamp", Color(1.0, 0.75, 0.5))  # gloomy stairs
	# Upstairs — dimmer/colder (you're more exposed up here).
	_lamp(Vector3(-9, FLOOR_H * 2 - 0.35, 10), 1.5, 11, "BedLampL", warm)
	_lamp(Vector3(9, FLOOR_H * 2 - 0.35, 10), 1.3, 11, "BedLampR", cold)
	_lamp(Vector3(0, FLOOR_H * 2 - 0.35, -10), 0.9, 9, "Landing2", Color(1.0, 0.8, 0.55))


# ---- greybox clutter (cover/occlusion; PSX furniture added by game.gd) -------
func _prop(pos: Vector3, size: Vector3, col: Color, nm: String) -> void:
	var body := StaticBody3D.new()
	body.name = nm
	body.position = pos
	body.collision_layer = 2
	body.collision_mask = 0
	_attach(_nav, body)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.8
	mi.material_override = m
	_attach(body, mi)
	var col2 := CollisionShape3D.new()
	col2.name = "Col"
	var bs := BoxShape3D.new()
	bs.size = size
	col2.shape = bs
	_attach(body, col2)


## Instance a PSX/FBX model as a VISUAL child of a box StaticBody (so you collide
## with it AND it looks like a real prop). Editable: the instance is a draggable node.
const PSX := "res://assets/psx/"
const FBX := "res://assets/models/furniture/"

func _furn(model_path: String, pos: Vector3, rot_deg: float, colsize: Vector3, nm: String, scale := 1.0) -> void:
	var body := StaticBody3D.new()
	body.name = nm
	body.position = pos
	body.rotation.y = deg_to_rad(rot_deg)
	body.collision_layer = 2
	body.collision_mask = 0
	_attach(_nav, body)
	var ps := load(model_path) as PackedScene
	if ps != null:
		var vis := ps.instantiate()
		vis.name = "Model"
		(vis as Node3D).scale = Vector3.ONE * scale
		_attach(body, vis)
	var col := CollisionShape3D.new()
	col.name = "Col"
	var bs := BoxShape3D.new()
	bs.size = colsize
	col.shape = bs
	col.position = Vector3(0, colsize.y * 0.5, 0)
	_attach(body, col)


## Decorative model (no collision): lamps, clutter, fan blades, etc.
func _deco(model_path: String, pos: Vector3, rot_deg: float, nm: String, scale := 1.0) -> void:
	var ps := load(model_path) as PackedScene
	if ps == null:
		return
	var n := ps.instantiate() as Node3D
	n.name = nm
	n.position = pos
	n.rotation.y = deg_to_rad(rot_deg)
	n.scale = Vector3.ONE * scale
	_attach(_nav, n)


func _build_clutter() -> void:
	# Real PSX furniture, grouped by room function and pushed to the walls so the
	# centres stay walkable (and the task markers stay reachable). All draggable nodes.

	# LIVING (x[-15,-3] z[5,16]) — the "watch zone": a seating cluster facing a TV.
	_furn(PSX + "Furniture/sofa_1.glb", Vector3(-12.5, 0, 9), 90, Vector3(2.4, 0.9, 1.0), "Sofa")
	_furn(PSX + "Furniture/coffee_table_1.glb", Vector3(-9.5, 0, 9), 0, Vector3(1.6, 0.5, 0.9), "CoffeeTable")
	_furn(PSX + "Furniture/tv_table_1.glb", Vector3(-6, 0, 9), -90, Vector3(1.4, 1.2, 0.7), "TVStand")
	_furn(PSX + "Furniture/chair_mp_1.glb", Vector3(-9, 0, 13.5), 180, Vector3(0.7, 1.0, 0.7), "LivingChair")
	_furn(PSX + "Furniture/shelf_mp_5.glb", Vector3(-13.5, 0, 14), 45, Vector3(1.2, 2.0, 0.5), "LivingShelf")
	_furn(PSX + "Furniture/display_cabinet_mp_1.glb", Vector3(-5, 0, 15.4), 180, Vector3(1.6, 2.0, 0.6), "Cabinet")

	# KITCHEN (x[-15,-3] z[-16,5]) — appliances on the back wall (PSX lacks these, FBX fills in).
	_furn(FBX + "Fridge/Fridge.fbx", Vector3(-13.5, 0, -14.5), 0, Vector3(1.2, 2.0, 1.2), "Fridge")
	_furn(FBX + "Stove/Stove.fbx", Vector3(-10.5, 0, -15.0), 0, Vector3(1.2, 1.1, 1.0), "Stove")
	_furn(PSX + "Furniture/table_large_2.glb", Vector3(-8, 0, -6), 0, Vector3(2.0, 1.0, 1.2), "KitchenTable")
	_furn(PSX + "Furniture/chair_mp_1.glb", Vector3(-6.5, 0, -6), -90, Vector3(0.7, 1.0, 0.7), "KitchenChair")

	# OFFICE (x[3,15] z[5,16]) — desk + shelving along the walls.
	_furn(PSX + "Furniture/table_large_3.glb", Vector3(13.5, 0, 12), 90, Vector3(1.2, 1.0, 2.4), "Desk")
	_furn(PSX + "Furniture/chair_mp_1.glb", Vector3(11.5, 0, 12), 90, Vector3(0.7, 1.0, 0.7), "OfficeChair")
	_furn(PSX + "Furniture/shelf_mp_5.glb", Vector3(7, 0, 15.4), 180, Vector3(1.2, 2.0, 0.5), "OfficeShelf")
	_furn(PSX + "Furniture/display_cabinet_mp_1.glb", Vector3(13.5, 0, 7, ), 90, Vector3(1.6, 2.0, 0.6), "OfficeCab")

	# BATH (x[3,15] z[-16,5]) — tub + toilet (FBX) on the tiled floor.
	_furn(FBX + "Bathtub/Bathtub.fbx", Vector3(12.5, 0, -14.5), 0, Vector3(1.8, 0.7, 0.9), "Bathtub")
	_furn(FBX + "Toilet/Toilet.fbx", Vector3(6, 0, -14, ), 0, Vector3(0.8, 1.0, 0.8), "Toilet")

	# FOYER / corridor — supply crates as cover + a sightline break (choke point).
	_furn(PSX + "Large Props/wooden_crate_5.glb", Vector3(-2.4, 0, 6), 12, Vector3(1.0, 1.0, 1.0), "FoyerCrate1")
	_furn(PSX + "Large Props/supply_crate_1_empty.glb", Vector3(2.4, 0, 2), -8, Vector3(1.0, 1.0, 1.0), "FoyerCrate2")
	_furn(PSX + "Large Props/wooden_crate_6.glb", Vector3(2.2, 0, 9), 0, Vector3(1.0, 1.0, 1.0), "FoyerCrate3")

	# UPSTAIRS bedrooms (y=FLOOR_H) — beds + storage against the walls.
	_furn(PSX + "Furniture/bed_1.glb", Vector3(-12, FLOOR_H, 13), 90, Vector3(2.0, 0.7, 1.2), "BedL")
	_furn(PSX + "Furniture/bedside_table_1.glb", Vector3(-13.5, FLOOR_H, 10.5), 0, Vector3(0.6, 0.6, 0.6), "NightL")
	_furn(PSX + "Furniture/wardrobe_mp_1.glb", Vector3(-6, FLOOR_H, 15.2), 180, Vector3(1.4, 2.2, 0.6), "WardrobeL")
	_furn(PSX + "Furniture/bed_1.glb", Vector3(12, FLOOR_H, 13), -90, Vector3(2.0, 0.7, 1.2), "BedR")
	_furn(PSX + "Furniture/bedside_table_1.glb", Vector3(13.5, FLOOR_H, 10.5), 0, Vector3(0.6, 0.6, 0.6), "NightR")
	_furn(PSX + "Furniture/wardrobe_mp_1.glb", Vector3(6, FLOOR_H, 15.2), 180, Vector3(1.4, 2.2, 0.6), "WardrobeR")


## Hang a PSX ceiling-lamp model under each room light so the glow has a real source.
func _build_ceiling_fixtures() -> void:
	var lamp := PSX + "Lighting/ceiling_lamp_1_on.glb"
	var spots := [
		Vector3(-9, FLOOR_H - 0.05, 9), Vector3(-9, FLOOR_H - 0.05, -4),
		Vector3(9, FLOOR_H - 0.05, 11), Vector3(9, FLOOR_H - 0.05, -8),
		Vector3(0, FLOOR_H - 0.05, 12),
		Vector3(-9, FLOOR_H * 2 - 0.05, 10), Vector3(9, FLOOR_H * 2 - 0.05, 10),
		Vector3(0, FLOOR_H * 2 - 0.05, -10),
	]
	for i in spots.size():
		_deco(lamp, spots[i], 0, "Fixture%d" % i)


## Cobwebs tucked into ceiling corners — cheap, huge "this place is abandoned" payoff.
func _build_cobwebs() -> void:
	var web := PSX + "Decals/cobweb_5.glb"
	var corners := [
		Vector3(-14, FLOOR_H - 0.3, 15), Vector3(14, FLOOR_H - 0.3, 15),
		Vector3(-14, FLOOR_H - 0.3, -15), Vector3(14, FLOOR_H - 0.3, -15),
		Vector3(-14, FLOOR_H * 2 - 0.3, 14), Vector3(14, FLOOR_H * 2 - 0.3, 14),
	]
	for i in corners.size():
		_deco(web, corners[i], i * 57.0, "Cobweb%d" % i, 1.2)


func _build_easter_eggs() -> void:
	# Visual-only (no floating text). A glowing finger shrine + a rubber duck.
	var finger = load("res://assets/emotes/middlefinger.png")
	if finger != null:
		var s := Sprite3D.new()
		s.name = "ShrineFinger"
		s.texture = finger
		s.shaded = false
		s.pixel_size = 0.005
		s.position = Vector3(-13.5, 1.3, -14)
		_attach(_nav, s)
	var duck := MeshInstance3D.new()
	duck.name = "Duck"
	var dm := SphereMesh.new()
	dm.radius = 0.28
	dm.height = 0.56
	duck.mesh = dm
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.albedo_color = Color(1.0, 0.9, 0.1)
	duck.material_override = dmat
	duck.position = Vector3(13, FLOOR_H + 1.0, 13)
	_attach(_nav, duck)


func _marker(nm: String, pos: Vector3) -> void:
	var m := Marker3D.new()
	m.name = nm
	m.position = pos
	_attach(_root, m)


func _build_markers() -> void:
	_marker("PlayerSpawn", Vector3(0, 0.4, 14))        # foyer
	_marker("WatcherSpawn", Vector3(0, 0.2, -11))      # back, near stairs
	# 6 task slots across separated rooms + upstairs.
	_marker("TaskSlot0", Vector3(-10, 0, 11))          # living (watch zone)
	_marker("TaskSlot1", Vector3(10, 0, 11))           # office
	_marker("TaskSlot2", Vector3(-10, 0, -2))          # kitchen
	_marker("TaskSlot3", Vector3(10, 0, -2))           # bathroom
	_marker("TaskSlot4", Vector3(-10, FLOOR_H, 10))    # bedroom L (stair trip)
	_marker("TaskSlot5", Vector3(10, FLOOR_H, 10))     # bedroom R
