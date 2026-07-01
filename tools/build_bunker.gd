extends SceneTree
## "THE BUNKER" generator -> res://scenes/bunker.tscn. Run ONCE, then HAND-EDIT in the editor
## (everything is real nodes). Re-run to start over.
##   Godot_console.exe --headless --path <proj> --script res://tools/build_bunker.gd
##
## GOTCHA: the room/tunnel doorway openings are dressed with real `tunnel_hole_2.glb` arched frames
## that live in a SEPARATE scene, res://scenes/tunnel_fixes.tscn (built by tools/build_tunnel_fixes.gd),
## which is instanced into bunker.tscn as the "TunnelConnectionFixes" node. RE-RUNNING THIS GENERATOR
## OVERWRITES bunker.tscn and DROPS that instance — re-run build_tunnel_fixes.gd and re-add the
## instance afterwards (or fold the frame placement in here) so the connections don't revert to bare
## box holes with void corners.
##
## This pass: a VARIED irregular facility — long & short halls, a 4-way intersection, dead ends,
## big & small rooms, TWO-STOREY rooms (mezzanine + ramp) and a BASEMENT (ramp down). Tasks are
## MOUNTED against walls (floor-standing, never midair); item pickups sit ON crates; the arrival
## uses the real elevator_1 mesh with its sliding doors.

const PSX := "res://assets/psx/"
const PSX2 := "res://assets/psx2/"
const TECH := "res://assets/tech/"
const B := "res://assets/bunkers/"
const TEX_WALL := "res://assets/psx/Modular Structures/beam_1_concrete_1.jpg"
const TEX_FLOOR := "res://assets/textures/Tiles-Large.png"

const RELAY := "res://scenes/tasks/task_relay.tscn"
const CARRY := "res://scenes/tasks/task_carry.tscn"
const SWITCH := "res://scenes/tasks/task_switches.tscn"
const BUTTONS := "res://scenes/tasks/task_buttons.tscn"
const VALVE := "res://scenes/tasks/task_valve.tscn"
const CAPS := "res://scenes/tasks/task_capacitors.tscn"

const CEIL := 3.3              # normal room height
const CEIL_TALL := 6.6         # two-storey room height
const BASE_DROP := 3.3         # how far a basement sits below the ground floor
const WALL_T := 0.3
const DOOR_W := 3.6   # wider than the 3.5 tunnel mouth so the room wall sits BEHIND the tunnel
                      # wall (no protruding lip into the opening), while the tunnel wall still seals it
const DOOR_H := 2.7
const TUN_HALF := 1.75
const TUN_H := 2.72

var _root: Node3D
var _nav: NavigationRegion3D
var _rooms_node: Node3D
var _tunnels_node: Node3D
var _tasks_node: Node3D

# id -> { pos, size, type, special("" | "2story" | "basement") }. Explicit positions (axis-aligned
# per connection) give varied hall lengths, intersections, dead ends and varied room sizes.
var _rooms := {
	# --- ENTRY + UPPER FACILITY ---
	"arrival":     {"pos": Vector3(0, 0, 0),     "size": 14.0, "type": "arrival",     "special": ""},
	"control":     {"pos": Vector3(0, 0, -30),   "size": 16.0, "type": "control",     "special": ""},
	"security":    {"pos": Vector3(26, 0, -30),  "size": 10.0, "type": "security",    "special": ""},
	"maintenance": {"pos": Vector3(42, 0, -30),  "size": 8.0,  "type": "maintenance", "special": ""},
	"power":       {"pos": Vector3(-28, 0, -30), "size": 18.0, "type": "power",       "special": "2story"},
	"storage":     {"pos": Vector3(-28, 0, -56), "size": 12.0, "type": "storage",     "special": "basement"},
	"comms":       {"pos": Vector3(0, 0, -56),   "size": 11.0, "type": "comms",       "special": ""},
	"generator":   {"pos": Vector3(28, 0, -56),  "size": 20.0, "type": "generator",   "special": "2story"},
	"monitoring":  {"pos": Vector3(28, 0, -80),  "size": 9.0,  "type": "monitoring",  "special": ""},
	"equipment":   {"pos": Vector3(0, 0, -84),   "size": 13.0, "type": "equipment",   "special": ""},
	"barracks":    {"pos": Vector3(-26, 0, -84), "size": 12.0, "type": "barracks",    "special": ""},
	"armory":      {"pos": Vector3(24, 0, -84),  "size": 10.0, "type": "armory",      "special": ""},
	# --- MAINTENANCE TUNNEL LOOP (top-right dead-end network) ---
	"mnt_a":       {"pos": Vector3(58, 0, -30),  "size": 10.0, "type": "maintenance", "special": ""},
	"mnt_b":       {"pos": Vector3(58, 0, -8),   "size": 10.0, "type": "maintenance", "special": ""},
	"mnt_c":       {"pos": Vector3(42, 0, -8),   "size": 10.0, "type": "storage",     "special": ""},
	# --- MIDDLE CORRIDOR (storage/debris + tech sector) at Z=-110 ---
	"junction":    {"pos": Vector3(0, 0, -110),  "size": 14.0, "type": "hub",         "special": ""},
	"store_a":     {"pos": Vector3(-26, 0, -110), "size": 12.0, "type": "storage",    "special": ""},
	"store_b":     {"pos": Vector3(-52, 0, -110), "size": 12.0, "type": "storage",    "special": ""},
	"tech_a":      {"pos": Vector3(28, 0, -110),  "size": 12.0, "type": "monitoring", "special": ""},
	"tech_b":      {"pos": Vector3(54, 0, -110),  "size": 12.0, "type": "control",    "special": ""},
	# --- RESIDENTIAL / HUMAN AFTERMATH ---
	"dorm_a":      {"pos": Vector3(-26, 0, -134), "size": 12.0, "type": "barracks",   "special": ""},
	"dorm_b":      {"pos": Vector3(-52, 0, -134), "size": 11.0, "type": "barracks",   "special": ""},
	# --- SURVEILLANCE RING (wraps the central chamber) ---
	"obs_n":       {"pos": Vector3(0, 0, -134),   "size": 13.0, "type": "observation", "special": ""},
	"obs_s":       {"pos": Vector3(0, 0, -218),   "size": 13.0, "type": "observation", "special": ""},
	"obs_e":       {"pos": Vector3(44, 0, -176),  "size": 13.0, "type": "observation", "special": ""},
	"obs_w":       {"pos": Vector3(-44, 0, -176), "size": 13.0, "type": "observation", "special": ""},
	"ctrl_ne":     {"pos": Vector3(44, 0, -134),  "size": 10.0, "type": "control",    "special": ""},
	"ctrl_nw":     {"pos": Vector3(-44, 0, -134), "size": 10.0, "type": "control",    "special": ""},
	"ctrl_se":     {"pos": Vector3(44, 0, -218),  "size": 10.0, "type": "control",    "special": ""},
	"ctrl_sw":     {"pos": Vector3(-44, 0, -218), "size": 10.0, "type": "control",    "special": ""},
	# --- CENTRAL EVENT ROOM: where the watcher was contained (now breached) ---
	"central_chamber": {"pos": Vector3(0, 0, -176), "size": 44.0, "type": "chamber",  "special": "", "ceil": 13.0},
}
# Tunnels (room-id pairs). control is a 4-WAY intersection; comms + equipment are 3-ways; maintenance/
# storage/monitoring/barracks/armory are dead ends. Hall lengths vary with the gap between rooms.
var _edges := [
	# entry + upper facility
	["arrival", "control"],
	["control", "security"], ["control", "power"], ["control", "comms"],
	["security", "maintenance"],
	["power", "storage"],
	["comms", "generator"], ["comms", "equipment"],
	["generator", "monitoring"],
	["equipment", "barracks"], ["equipment", "armory"],
	# maintenance tunnel LOOP (mnt_c reconnects to maintenance)
	["maintenance", "mnt_a"], ["mnt_a", "mnt_b"], ["mnt_b", "mnt_c"], ["mnt_c", "maintenance"],
	# middle corridor (storage/debris west, tech east) + LOOP-BACKS to the upper facility
	["equipment", "junction"],
	["junction", "store_a"], ["store_a", "store_b"],
	["junction", "tech_a"], ["tech_a", "tech_b"],
	["barracks", "store_a"],        # loop: barracks<->store_a (X=-26)
	["monitoring", "tech_a"],       # loop: monitoring<->tech_a (X=28)
	# residential branch
	["store_a", "dorm_a"], ["dorm_a", "dorm_b"],
	# down into the surveillance ring
	["junction", "obs_n"],
	# surveillance RING loop (wraps the chamber)
	["obs_n", "ctrl_ne"], ["ctrl_ne", "obs_e"], ["obs_e", "ctrl_se"], ["ctrl_se", "obs_s"],
	["obs_s", "ctrl_sw"], ["ctrl_sw", "obs_w"], ["obs_w", "ctrl_nw"], ["ctrl_nw", "obs_n"],
	# four entrances into the CENTRAL CHAMBER (you can see across it from every obs room)
	["obs_n", "central_chamber"], ["obs_s", "central_chamber"],
	["obs_e", "central_chamber"], ["obs_w", "central_chamber"],
]
# Tasks per room (room -> [scene, props]).
var _tasks := {
	"control":   [BUTTONS, {"sequence_length": 4, "task_title": "Bring the control panel online"}],
	"security":  [SWITCH, {"switch_count": 4, "task_title": "Reset the security breakers"}],
	"power":     [RELAY, {"task_title": "Charge the power relay"}],
	"generator": [CAPS, {"count": 2, "socket_offset": Vector3(0, 0, 5.0), "task_title": "Re-seat the generator capacitors"}],
	"monitoring":[VALVE, {"turns_required": 3.0, "task_title": "Crank the coolant valve"}],
	"comms":     [RELAY, {"task_title": "Charge the comms relay"}],
	"equipment": [SWITCH, {"switch_count": 4, "task_title": "Equipment lockdown breakers"}],
	"armory":    [SWITCH, {"switch_count": 5, "task_title": "Final armory lockdown"}],
	# new zones
	"tech_b":    [CAPS, {"count": 2, "socket_offset": Vector3(0, 0, 4.0), "task_title": "Re-seat the surveillance capacitors"}],
	"store_b":   [BUTTONS, {"sequence_length": 3, "task_title": "Route power to the deep sector"}],
	"obs_s":     [SWITCH, {"switch_count": 4, "task_title": "Reboot the observation feeds"}],
	"central_chamber": [RELAY, {"task_title": "Re-energize the containment field"}],
}
# Item pickups (room -> [kind, model, scale]).
var _items := {
	"arrival":     ["flashlight", "res://assets/psx/Items & Weapons/flashlight_1.glb", 2.2],
	"storage":     ["keycard", "res://assets/psx/Items & Weapons/keycard_1.glb", 3.0],
	"comms":       ["phone", "res://assets/psx/Electronics & Misc/cell_phone_3.glb", 3.0],
	"maintenance": ["battery", "res://assets/psx/Electronics & Misc/cell_phone_battery_1.glb", 3.0],
	"dorm_a":      ["battery", "res://assets/psx/Electronics & Misc/cell_phone_battery_1.glb", 3.0],
	# friendslop weapons stashed deep in the facility
	"obs_e":       ["crowbar", "res://assets/psx2/Structures/rusty_crowbar_mx_1.glb", 1.6],
	"store_b":     ["fish", "res://assets/psx2/Props/fish_mx_1.glb", 2.2],
}

var _doors := {}               # id -> Array of "N"/"S"/"E"/"W"


func _initialize() -> void:
	_root = Node3D.new(); _root.name = "Bunker"
	_nav = NavigationRegion3D.new(); _nav.name = "Nav"
	var nm := NavigationMesh.new()
	nm.cell_size = 0.25; nm.cell_height = 0.25
	nm.agent_radius = 0.45; nm.agent_height = 1.8
	nm.agent_max_climb = 0.4; nm.agent_max_slope = 45.0
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = &"navsrc"
	_nav.navigation_mesh = nm
	_attach(_root, _nav)
	_rooms_node = Node3D.new(); _rooms_node.name = "Rooms"; _attach(_root, _rooms_node)
	_rooms_node.add_to_group("navsrc")
	_tunnels_node = Node3D.new(); _tunnels_node.name = "Tunnels"; _attach(_root, _tunnels_node)
	_tunnels_node.add_to_group("navsrc")
	_tasks_node = Node3D.new(); _tasks_node.name = "Tasks"; _attach(_root, _tasks_node)

	_build_environment()
	_compute_doors()
	for id in _rooms:
		_build_room(id)
	for e in _edges:
		_build_tunnel(e[0], e[1])
	_build_markers()

	get_root().add_child(_root)
	await process_frame
	await physics_frame
	await physics_frame
	_nav.bake_navigation_mesh(false)
	await physics_frame
	print("build_bunker: rooms=", _rooms.size(), " navmesh polygons=",
		_nav.navigation_mesh.get_polygon_count())

	_build_tasks()
	_build_systems()

	var packed := PackedScene.new()
	if packed.pack(_root) == OK:
		print("build_bunker: saved err=", ResourceSaver.save(packed, "res://scenes/bunker.tscn"),
			" nodes=", _count(_root))
	else:
		print("build_bunker: PACK FAILED")
	quit()


# ---- helpers ----------------------------------------------------------------
func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children(): c += _count(ch)
	return c

func _attach(parent: Node, child: Node) -> void:
	parent.add_child(child); child.owner = _root

func _rpos(id: String) -> Vector3:
	return _rooms[id]["pos"]

func _rsize(id: String) -> float:
	return _rooms[id]["size"]

func _mat(tex: String, tile: float, tint: Color, size: Vector3) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.roughness = 0.95
	var t = load(tex) if tex != "" else null
	if t != null:
		m.albedo_texture = t; m.albedo_color = tint
		var d := [size.x, size.y, size.z]; d.sort()
		m.uv1_scale = Vector3(maxf(d[2], 0.1) / tile, maxf(d[1], 0.1) / tile, 1.0)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	else:
		m.albedo_color = tint
	return m

func _solid(parent: Node, center: Vector3, size: Vector3, mat: StandardMaterial3D, nm: String) -> void:
	var body := StaticBody3D.new()
	body.name = nm; body.position = center
	body.collision_layer = 2; body.collision_mask = 0
	_attach(parent, body)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = size; mi.mesh = bm; mi.material_override = mat
	_attach(body, mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new(); bs.size = size; cs.shape = bs
	_attach(body, cs)

func _coll(parent: Node, center: Vector3, size: Vector3, nm: String) -> void:
	var body := StaticBody3D.new()
	body.name = nm; body.position = center
	body.collision_layer = 2; body.collision_mask = 0
	_attach(parent, body)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new(); bs.size = size; cs.shape = bs
	_attach(body, cs)

func _place(parent: Node, path: String, pos: Vector3, rot := 0.0, nm := "P", scale := 1.0) -> Node3D:
	var ps := load(path) as PackedScene
	if ps == null:
		print("MISS ", path); return null
	var n := ps.instantiate() as Node3D
	n.name = nm; n.position = pos; n.rotation.y = deg_to_rad(rot); n.scale = Vector3.ONE * scale
	_attach(parent, n)
	return n

## A walkable RAMP (visual + collision) from one height to another over a horizontal run along an axis.
func _ramp(parent: Node, foot: Vector3, run: float, rise: float, width: float, axis: String, nm: String) -> void:
	var length := sqrt(run * run + rise * rise)
	var ang := atan2(rise, run)
	var body := StaticBody3D.new()
	body.name = nm
	body.collision_layer = 2; body.collision_mask = 0
	# midpoint of the ramp
	var mid := foot + Vector3(0, rise * 0.5, 0)
	if axis == "Z":
		mid += Vector3(0, 0, -run * 0.5)
		body.rotation.x = ang
	else:
		mid += Vector3(run * 0.5, 0, 0)
		body.rotation.z = -ang
	body.position = mid
	_attach(parent, body)
	var size := Vector3(width, 0.3, length) if axis == "Z" else Vector3(length, 0.3, width)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = size; mi.mesh = bm
	mi.material_override = _mat(TEX_FLOOR, 3.0, Color(0.3, 0.31, 0.34), size)
	_attach(body, mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new(); bs.size = size; cs.shape = bs
	_attach(body, cs)

func _light(parent: Node, pos: Vector3, col: Color, energy: float, rng: float, nm: String) -> void:
	var l := OmniLight3D.new()
	l.name = nm; l.position = pos; l.light_color = col; l.light_energy = energy
	l.omni_range = rng; l.omni_attenuation = 1.5
	_attach(parent, l)


# ---- environment ------------------------------------------------------------
func _build_environment() -> void:
	var we := WorldEnvironment.new(); we.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.015)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.15, 0.17, 0.23)
	env.ambient_light_energy = 0.28
	env.fog_enabled = true
	env.fog_light_color = Color(0.02, 0.025, 0.035)
	env.fog_density = 0.018
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true; env.glow_intensity = 0.45; env.glow_bloom = 0.12
	we.environment = env
	_attach(_root, we)


# ---- doors (which wall sides each room opens on) ----------------------------
func _compute_doors() -> void:
	for id in _rooms:
		_doors[id] = []
	for e in _edges:
		var a: String = e[0]; var b: String = e[1]
		var d: Vector3 = _rpos(b) - _rpos(a)
		# Connected rooms MUST share an exact X or Z, or the straight axis-aligned tunnel won't line
		# up with the (centred) doorways -> blocked tube + off-bounds slit. Catch it at build time.
		if absf(d.x) > 0.1 and absf(d.z) > 0.1:
			push_warning("MISALIGNED EDGE %s<->%s dx=%.1f dz=%.1f (won't seal)" % [a, b, d.x, d.z])
			print("BUNKER WARN: misaligned edge %s<->%s dx=%.1f dz=%.1f" % [a, b, d.x, d.z])
		if absf(d.x) > absf(d.z):
			if d.x > 0: _doors[a].append("E"); _doors[b].append("W")
			else: _doors[a].append("W"); _doors[b].append("E")
		else:
			if d.z > 0: _doors[a].append("S"); _doors[b].append("N")     # +Z = "south"
			else: _doors[a].append("N"); _doors[b].append("S")


# ---- rooms ------------------------------------------------------------------
func _build_room(id: String) -> void:
	var info: Dictionary = _rooms[id]
	var type: String = info["type"]
	var special: String = info["special"]
	var size: float = info["size"]
	var h := size * 0.5
	var ceil_h: float = CEIL_TALL if special == "2story" else CEIL
	if info.has("ceil"):
		ceil_h = info["ceil"]               # explicit override (e.g. the tall central chamber)
	var g := Node3D.new()
	g.name = "Room_%s" % id
	g.position = _rpos(id)
	_attach(_rooms_node, g)

	# floor (a basement room gets a framed floor with an OPEN pit; others a full slab) + ceiling
	if special == "basement":
		_basement_floor(g, size)
	else:
		_solid(g, Vector3(0, -0.15, 0), Vector3(size + 0.4, 0.3, size + 0.4),
			_mat(TEX_FLOOR, 3.0, Color(0.33, 0.34, 0.37), Vector3(size, 1, size)), "Floor")
	_solid(g, Vector3(0, ceil_h + 0.15, 0), Vector3(size + 0.4, 0.3, size + 0.4),
		_mat(TEX_WALL, 2.5, Color(0.17, 0.17, 0.2), Vector3(size, 1, size)), "Ceil")
	# walls (with doorway gaps)
	_wall(g, "N", h, size, ceil_h)
	_wall(g, "S", h, size, ceil_h)
	_wall(g, "E", h, size, ceil_h)
	_wall(g, "W", h, size, ceil_h)

	# lights (more for big/tall rooms)
	var lcol := Color(0.6, 0.72, 0.92) if type != "arrival" else Color(0.95, 0.78, 0.5)
	_place(g, PSX + "Lighting/ceiling_lamp_1_on.glb", Vector3(0, ceil_h - 0.12, 0), 0.0, "LampModel")
	_light(g, Vector3(0, ceil_h - 0.5, 0), lcol, 2.4, size * 0.9, "Light")
	if size >= 16.0:
		_light(g, Vector3(h * 0.5, ceil_h - 0.5, h * 0.5), lcol, 1.4, size * 0.6, "Light2")
		_light(g, Vector3(-h * 0.5, ceil_h - 0.5, -h * 0.5), lcol, 1.4, size * 0.6, "Light3")

	# task anchor (kept for compatibility; tasks are positioned by _build_tasks)
	var a := Marker3D.new(); a.name = "TaskAnchor"; _attach(g, a)

	if special == "2story":
		_build_mezzanine(g, size, ceil_h)
	elif special == "basement":
		_build_basement(g, size)

	if type == "arrival":
		_build_elevator(g, size)
	else:
		_dress(g, type, size, id)


func _wall(g: Node3D, side: String, h: float, size: float, ceil_h: float) -> void:
	var has_door: bool = side in _doors[_room_of(g)]
	# wall line + axis
	var along_x := side == "N" or side == "S"
	var line_z := h if side == "S" else -h
	var line_x := h if side == "E" else -h
	if not has_door:
		if along_x:
			_solid(g, Vector3(0, ceil_h * 0.5, line_z), Vector3(size + WALL_T, ceil_h, WALL_T),
				_mat(TEX_WALL, 2.5, Color(0.4, 0.41, 0.45), Vector3(size, ceil_h, WALL_T)), "Wall" + side)
		else:
			_solid(g, Vector3(line_x, ceil_h * 0.5, 0), Vector3(WALL_T, ceil_h, size + WALL_T),
				_mat(TEX_WALL, 2.5, Color(0.4, 0.41, 0.45), Vector3(WALL_T, ceil_h, size)), "Wall" + side)
		return
	# centred doorway: two side panels + a lintel above
	var side_len := (size - DOOR_W) * 0.5
	var tint := Color(0.4, 0.41, 0.45)
	if along_x:
		for sgn in [-1.0, 1.0]:
			var cx: float = sgn * (DOOR_W * 0.5 + side_len * 0.5)
			_solid(g, Vector3(cx, ceil_h * 0.5, line_z), Vector3(side_len, ceil_h, WALL_T),
				_mat(TEX_WALL, 2.5, tint, Vector3(side_len, ceil_h, WALL_T)), "Wall%s_%d" % [side, int(sgn)])
		_solid(g, Vector3(0, (DOOR_H + ceil_h) * 0.5, line_z), Vector3(DOOR_W, ceil_h - DOOR_H, WALL_T),
			_mat(TEX_WALL, 2.5, tint, Vector3(DOOR_W, ceil_h - DOOR_H, WALL_T)), "Wall%s_lin" % side)
	else:
		for sgn in [-1.0, 1.0]:
			var cz: float = sgn * (DOOR_W * 0.5 + side_len * 0.5)
			_solid(g, Vector3(line_x, ceil_h * 0.5, cz), Vector3(WALL_T, ceil_h, side_len),
				_mat(TEX_WALL, 2.5, tint, Vector3(WALL_T, ceil_h, side_len)), "Wall%s_%d" % [side, int(sgn)])
		_solid(g, Vector3(line_x, (DOOR_H + ceil_h) * 0.5, 0), Vector3(WALL_T, ceil_h - DOOR_H, DOOR_W),
			_mat(TEX_WALL, 2.5, tint, Vector3(WALL_T, ceil_h - DOOR_H, DOOR_W)), "Wall%s_lin" % side)


func _room_of(g: Node3D) -> String:
	return String(g.name).trim_prefix("Room_")


# ---- two-storey: a mezzanine platform + a ramp up ---------------------------
func _build_mezzanine(g: Node3D, size: float, ceil_h: float) -> void:
	var h := size * 0.5
	var lvl := ceil_h * 0.5 + 0.3            # upper floor height
	var depth := size * 0.45                  # platform covers the back ~45%
	# platform slab against the back (north, -Z) wall, leaving the front open
	_solid(g, Vector3(0, lvl - 0.15, -h + depth * 0.5), Vector3(size - 0.6, 0.3, depth),
		_mat(TEX_FLOOR, 3.0, Color(0.3, 0.31, 0.34), Vector3(size, 1, depth)), "Mezz")
	# low railing along the open edge (leave a gap on the east where the ramp lands)
	_solid(g, Vector3(-1.2, lvl + 0.5, -h + depth), Vector3(size - 4.0, 1.0, 0.12),
		_mat("", 1, Color(0.12, 0.12, 0.14), Vector3.ONE), "MezzRail")
	# a long gentle ramp up the EAST wall, landing at the platform's front edge
	var run: float = size - 1.0 - depth
	_ramp(g, Vector3(h - 1.4, 0.0, h - 1.0), run, lvl, 2.0, "Z", "MezzRamp")
	_light(g, Vector3(0, lvl + 1.4, -h + depth * 0.5), Color(0.6, 0.7, 0.9), 1.4, size * 0.6, "MezzLight")
	_place(g, TECH + "computer_terminal_etx_1.glb", Vector3(-h * 0.5, lvl, -h + 1.0), 0, "MezzTerminal")


## Ground floor for a basement room: a solid frame around an OPEN pit (so you can descend into it).
## Pit footprint = the sub-room, centred at z=-2.0.
func _basement_floor(g: Node3D, size: float) -> void:
	var h := size * 0.5
	var sub := size * 0.7
	var sh := sub * 0.5
	var cz := -2.0
	var fmat := _mat(TEX_FLOOR, 3.0, Color(0.33, 0.34, 0.37), Vector3(size, 1, size))
	# four border strips around the pit [x:-sh..sh, z:cz-sh..cz+sh]
	var south_d := h - (cz + sh)            # strip in front of the pit (+Z)
	var north_d := (cz - sh) - (-h)         # strip behind the pit (-Z)
	if south_d > 0.05:
		_solid(g, Vector3(0, -0.15, (cz + sh + h) * 0.5), Vector3(size + 0.4, 0.3, south_d), fmat, "FloorS")
	if north_d > 0.05:
		_solid(g, Vector3(0, -0.15, (-h + cz - sh) * 0.5), Vector3(size + 0.4, 0.3, north_d), fmat, "FloorN")
	_solid(g, Vector3((sh + h) * 0.5, -0.15, cz), Vector3(h - sh, 0.3, sub), fmat, "FloorE")
	_solid(g, Vector3((-sh - h) * 0.5, -0.15, cz), Vector3(h - sh, 0.3, sub), fmat, "FloorW")


# ---- basement: a sunken sub-room reached by a ramp down through the pit ------
func _build_basement(g: Node3D, size: float) -> void:
	var sub := size * 0.7
	var sh := sub * 0.5
	var cz := -2.0
	var fy := -BASE_DROP
	# lower floor
	_solid(g, Vector3(0, fy - 0.15, cz), Vector3(sub, 0.3, sub),
		_mat(TEX_FLOOR, 3.0, Color(0.28, 0.29, 0.32), Vector3(sub, 1, sub)), "BaseFloor")
	# lower perimeter walls (3 sides; the ramp comes down the +Z/front side)
	for d in [[Vector3(0, fy + CEIL * 0.5, cz - sh), Vector3(sub, CEIL, WALL_T)],
			[Vector3(-sh, fy + CEIL * 0.5, cz), Vector3(WALL_T, CEIL, sub)],
			[Vector3(sh, fy + CEIL * 0.5, cz), Vector3(WALL_T, CEIL, sub)]]:
		_solid(g, d[0], d[1], _mat(TEX_WALL, 2.5, Color(0.34, 0.35, 0.39), d[1]), "BaseWall")
	# ramp DOWN along the WEST side of the pit, from the ground-floor edge to the lower floor
	_ramp(g, Vector3(-sh + 1.3, 0.0, cz + sh - 0.4), sub - 1.4, BASE_DROP, 2.2, "Z", "BaseRamp")
	_light(g, Vector3(0, fy + CEIL - 0.5, cz), Color(0.5, 0.6, 0.85), 1.8, sub, "BaseLight")
	_place(g, PSX + "Large Props/metal_barrel_mp_1.glb", Vector3(sh - 1.2, fy, cz - sh + 1.0), 0, "BaseDrum")
	_place(g, TECH + "fuse_box_etx_1.glb", Vector3(sh - 0.5, fy + 1.5, cz), -90, "BaseFuse")


# ---- tunnels ----------------------------------------------------------------
func _build_tunnel(a: String, b: String) -> void:
	var pa := _rpos(a); var pb := _rpos(b)
	var dir := (pb - pa).normalized()
	var along_z := absf(dir.z) > absf(dir.x)
	var from := pa + dir * (_rsize(a) * 0.5)
	var to := pb - dir * (_rsize(b) * 0.5)
	var mid := (from + to) * 0.5
	var length := (to - from).length()
	var g := Node3D.new()
	g.name = "Tun_%s_%s" % [a, b]
	g.position = mid
	_attach(_tunnels_node, g)
	# tunnel_straight.glb is exactly 6.0 long. Tile n pieces and STRETCH each along its length so
	# they butt flush across the whole run (no gaps between segments, whatever the tunnel length).
	var n := maxi(int(round(length / 6.0)), 1)
	var spacing := length / float(n)
	for i in n:
		var t := (float(i) + 0.5) / float(n)
		var p := from.lerp(to, t) - mid
		var tube := _place(g, B + "tunnel_straight.glb", p, (0.0 if along_z else 90.0), "Tube%d" % i)
		if tube != null:
			tube.scale = Vector3(1.0, 1.0, spacing / 6.0)   # local +Z is the length axis (pre-rotation)
	if along_z:
		_coll(g, Vector3(0, -0.15, 0), Vector3(TUN_HALF * 2 + 0.4, 0.3, length + 0.6), "F")
		_coll(g, Vector3(TUN_HALF, CEIL * 0.5, 0), Vector3(0.2, CEIL, length + 0.6), "Wa")
		_coll(g, Vector3(-TUN_HALF, CEIL * 0.5, 0), Vector3(0.2, CEIL, length + 0.6), "Wb")
		_coll(g, Vector3(0, TUN_H + 0.1, 0), Vector3(TUN_HALF * 2, 0.3, length + 0.6), "C")
	else:
		_coll(g, Vector3(0, -0.15, 0), Vector3(length + 0.6, 0.3, TUN_HALF * 2 + 0.4), "F")
		_coll(g, Vector3(0, CEIL * 0.5, TUN_HALF), Vector3(length + 0.6, CEIL, 0.2), "Wa")
		_coll(g, Vector3(0, CEIL * 0.5, -TUN_HALF), Vector3(length + 0.6, CEIL, 0.2), "Wb")
		_coll(g, Vector3(0, TUN_H + 0.1, 0), Vector3(length + 0.6, 0.3, TUN_HALF * 2), "C")


# ---- dressing (DOOR-AWARE: furniture only on walls WITHOUT a doorway, so it never blocks a
#      tube opening; floor props sit at y=0; pipes/signs/vents on walls + ceiling) -------------
func _free_sides(id: String) -> Array:
	var used: Array = _doors[id]
	var f: Array = []
	for s in ["N", "S", "E", "W"]:
		if not (s in used):
			f.append(s)
	return f

## [pos, yaw_deg] against a wall side. lateral = sideways along the wall, inset = into the room.
func _at(side: String, h: float, lateral: float, inset: float) -> Array:
	match side:
		"N": return [Vector3(lateral, 0, -h + inset), 0.0]
		"S": return [Vector3(lateral, 0, h - inset), 180.0]
		"E": return [Vector3(h - inset, 0, lateral), -90.0]
		"W": return [Vector3(-h + inset, 0, lateral), 90.0]
	return [Vector3.ZERO, 0.0]

## Place against a wall side (facing into the room) at height y.
func _pw(g: Node3D, path: String, side: String, h: float, lateral: float, inset: float, nm: String,
		y := 0.0, scale := 1.0) -> Node3D:
	var a := _at(side, h, lateral, inset)
	var pos: Vector3 = a[0]; pos.y = y
	return _place(g, path, pos, a[1], nm, scale)

## A row of props along a free wall.
func _row(g: Node3D, side: String, h: float, paths: Array, count: int, inset: float,
		spacing: float, nm: String) -> void:
	for i in count:
		var lat := (float(i) - (count - 1) * 0.5) * spacing
		_pw(g, paths[i % paths.size()], side, h, lat, inset, "%s%d" % [nm, i])

## Industrial detail in EVERY room: ceiling vents + hanging lamp, corner clutter, a wall sign + pipe.
func _universal_detail(g: Node3D, h: float, ch: float, free: Array, id: String) -> void:
	var seed_h := absi(id.hash())
	_place(g, B + "vent_4.glb", Vector3(h * 0.45, ch - 0.05, -h * 0.45), 0, "Vent1")
	_place(g, B + "vent_4.glb", Vector3(-h * 0.45, ch - 0.05, h * 0.45), 0, "Vent2")
	_place(g, B + "lamp_0.glb", Vector3(0, ch - 0.05, 0), 0, "HangLamp")
	# corner clutter (corners are always solid — doors are centred), grounded on the floor
	var c := h - 1.5
	_place(g, B + "wood_pallet_1.glb", Vector3(-c, 0, -c), 15, "Pallet")
	_place(g, B + "trash_%d.glb" % (1 + seed_h % 6), Vector3(c, 0, -c + 0.6), seed_h % 180, "Trash")
	# wall accents on the free walls: a sign + a vertical pipe run
	if free.size() > 0:
		_pw(g, B + "sign_%d.glb" % (1 + seed_h % 4), free[0], h, h * 0.4, 0.22, "Sign", 2.3)
		_pw(g, B + "pipe_1.glb", free[0], h, -h * 0.55, 0.3, "WallPipe", 0.0)
	if free.size() > 1:
		_pw(g, B + "wall_box_%d.glb" % (1 + seed_h % 3), free[1], h, 0.0, 0.2, "Panel", 1.6)


## Floor-standing identity props for a room type (used in the solid corners of 4-way rooms).
func _type_props(type: String) -> Array:
	match type:
		"control", "monitoring", "comms", "observation":
			return [B + "computer_1.glb", B + "military_radio_1.glb"]
		"storage", "armory", "equipment":
			return [B + "metal_crate_3.glb", B + "supply_box_1.glb"]
		"power", "generator":
			return [B + "machinery_1.glb", PSX + "Large Props/metal_barrel_mp_1.glb"]
		"maintenance":
			return [B + "water_barrel_1.glb", B + "trash_3.glb"]
		"security":
			return [B + "computer_1.glb", B + "metal_crate_3.glb"]
		"barracks":
			return [B + "metal_shelf_1.glb", B + "chair_wooden_1.glb"]
		_:
			return [B + "wooden_crate_9.glb", PSX2 + "Props/concrete_block_mx_1.glb"]


func _corner_identity(g: Node3D, h: float, type: String) -> void:
	var c := h - 1.7
	var spots := [[Vector3(c, 0, c), -135.0], [Vector3(-c, 0, c), 135.0]]   # corners free of clutter
	var props := _type_props(type)
	for i in mini(spots.size(), props.size()):
		_place(g, props[i], spots[i][0], spots[i][1], "CornerProp%d" % i)


func _dress(g: Node3D, type: String, size: float, id: String) -> void:
	var h := size * 0.5
	var info: Dictionary = _rooms[id]
	var ch: float = info["ceil"] if info.has("ceil") else (CEIL_TALL if info["special"] == "2story" else CEIL)
	if type == "chamber":
		_dress_chamber(g, h, ch)
		return
	var free: Array = _free_sides(id)
	_universal_detail(g, h, ch, free, id)
	if free.is_empty():
		# 4-way room (doors on every wall): NEVER put furniture on a wall — use the solid corners.
		_corner_identity(g, h, type)
		return
	var pri: String = free[0]                               # main feature wall (door-free)
	var alt: String = free[1] if free.size() > 1 else pri
	match type:
		"control", "monitoring", "comms", "observation":
			# a console bank against a free wall (never blocking the view-tube to the chamber)
			_row(g, pri, h, [B + "computer_1.glb", TECH + "computer_terminal_etx_1.glb",
				B + "military_radio_1.glb", B + "cpu_1.glb"], 4, 0.7, 2.0, "Console")
			_pw(g, TECH + "screen_etx_1_stand.glb", pri, h, 2.6, 1.4, "Screen")
			_pw(g, PSX + "Furniture/chair_mp_1.glb", pri, h, 0.5, 2.2, "Chair")
			_pw(g, B + "scanner_1.glb", alt, h, -1.0, 0.9, "Scanner")
			if type == "observation":
				_pw(g, PSX2 + "Decals/poster_cx_11.glb", alt, h, 1.5, 0.2, "Warn", 2.0, 2.0)
			else:
				_pw(g, B + ["pcb_1.glb", "pcb_2.glb", "pcb_4.glb", "pcb_5.glb"][absi(id.hash()) % 4],
					alt, h, 1.6, 0.2, "PCB", 1.6)
		"storage", "armory", "equipment":
			# metal shelving along a FREE wall, stocked with supply boxes / crates / cans
			_row(g, pri, h, [B + "metal_shelf_1.glb", B + "metal_shelf_2.glb"], 3, 0.6, 2.2, "Shelf")
			_pw(g, B + "supply_box_1.glb", pri, h, -2.0, 1.4, "Supply")
			_pw(g, B + "metal_crate_3.glb", alt, h, 0.0, 1.4, "Crate")
			_pw(g, B + "wooden_crate_8.glb", alt, h, 1.8, 1.4, "Crate2")
			_place(g, B + "canned_food_3.glb", Vector3(h - 2.0, 0, h - 2.0), 18, "Cans")
		"power", "generator":
			_pw(g, B + "generator_1.glb", pri, h, 0.0, 2.0, "Generator")
			_pw(g, B + "machinery_%d.glb" % (1 + absi(id.hash()) % 3), alt, h, 0.0, 1.8, "Machine")
			_pw(g, B + "power_supply_1.glb", alt, h, 2.2, 1.0, "PSU")
			_place(g, PSX + "Large Props/metal_barrel_mp_1.glb", Vector3(-h + 1.4, 0, h - 1.4), 0, "Drum1")
			_place(g, PSX + "Large Props/metal_barrel_mp_2.glb", Vector3(-h + 2.5, 0, h - 1.3), 0, "Drum2")
		"maintenance":
			_pw(g, B + "pipe_2.glb", pri, h, 0.0, 0.4, "Pipe2", 1.4)
			_pw(g, B + "pipe_1_ancle.glb", pri, h, 2.0, 0.4, "PipeAnkle", 1.4)
			_place(g, B + "water_barrel_1.glb", Vector3(h - 1.4, 0, h - 1.4), 0, "Water")
			_place(g, B + "drain_cover_2.glb", Vector3(0, 0.02, 0), 0, "Drain")
			_place(g, B + "trash_3.glb", Vector3(-h + 1.4, 0, -h + 1.4), 40, "Junk")
		"security":
			_pw(g, B + "table_large_3.glb", pri, h, 0.0, 1.6, "Desk")
			_pw(g, B + "computer_1.glb", pri, h, 0.0, 1.6, "Cctv", 0.95)
			_pw(g, B + "military_radio_2.glb", alt, h, 0.0, 1.0, "Radio")
		"barracks":
			_pw(g, PSX + "Furniture/bed_1.glb", pri, h, -1.8, 1.4, "Bed1")
			_pw(g, PSX + "Furniture/bed_1.glb", pri, h, 1.8, 1.4, "Bed2")
			_pw(g, B + "metal_shelf_1.glb", alt, h, 0.0, 0.7, "Locker")
			_place(g, B + "mre_1.glb", Vector3(h - 1.6, 0, h - 1.6), 0, "Rations")
			_place(g, B + "chair_wooden_1.glb", Vector3(-h + 2.0, 0, 1.2), 30, "Chair")
		"hub", "storage_x":
			_place(g, B + "wooden_crate_9.glb", Vector3(h - 2.0, 0, h - 2.0), 20, "Crate")
			_place(g, PSX2 + "Props/concrete_block_mx_1.glb", Vector3(-h + 2.0, 0, h - 2.0), 0, "Block")
			_pw(g, PSX2 + "Decals/graffiti_mx_2.glb", pri, h, 0.0, 0.22, "Graf", 1.8, 2.5)


# ---- CENTRAL CHAMBER dressing: the breached containment + debris + storytelling ----
func _dress_chamber(g: Node3D, h: float, ch: float) -> void:
	seed(7)                                       # deterministic debris scatter
	# Use the TALL volume: corner support pillars + a high lighting gantry, so the height reads.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_solid(g, Vector3(sx * (h - 2.0), ch * 0.5, sz * (h - 2.0)), Vector3(1.2, ch, 1.2),
				_mat(TEX_WALL, 2.0, Color(0.16, 0.16, 0.19), Vector3(1, ch, 1)), "Pillar")
			_place(g, B + "machinery_%d.glb" % (1 + (int(sx + sz) + 2) % 3),
				Vector3(sx * (h - 4.0), 0, sz * (h - 4.0)), 45, "Machine")
	# overhead gantry beams + bright industrial lamps high up (contrast with the dim tunnels)
	for zx in [-8.0, 8.0]:
		_solid(g, Vector3(0, ch - 0.6, zx), Vector3(h * 2 - 2, 0.4, 0.6),
			_mat(TEX_WALL, 2.0, Color(0.1, 0.1, 0.12), Vector3(h, 1, 1)), "Gantry")
		_place(g, B + "lamp_0.glb", Vector3(0, ch - 0.7, zx), 0, "GantryLampA", 1.5)
		_light(g, Vector3(0, ch - 1.5, zx), Color(0.8, 0.85, 1.0), 2.0, h * 0.9, "GantryLight")
	# The relic that was contained here, on a low plinth (the watcher's origin point).
	_solid(g, Vector3(0, 0.3, 0), Vector3(3, 0.6, 3),
		_mat(TEX_WALL, 2.0, Color(0.2, 0.2, 0.23), Vector3(3, 1, 3)), "Plinth")
	_place(g, PSX2 + "Props/ancient_artifact_mx_1.glb", Vector3(0, 0.6, 0), 0, "Artifact", 2.2)
	# Broken containment ring: barrels around the breach, half of them knocked over.
	for i in 8:
		var a := TAU * i / 8.0
		var b := _place(g, PSX + ("Large Props/metal_barrel_mp_1.glb" if i % 2 == 0
			else "Large Props/metal_barrel_mp_2.glb"),
			Vector3(cos(a) * 6.0, 0, sin(a) * 6.0), rad_to_deg(a), "Cont%d" % i)
		if b != null and i % 2 == 0:
			b.rotation.x = PI * 0.5               # toppled
	# A torn structural frame marking where it broke OUT (the breach, north wall).
	_place(g, PSX2 + "Structures/warehouse_hl_1_frame_piece.glb", Vector3(0, 0, -h + 4), 0, "Breach", 2.0)
	# Heavy debris field scattered across the floor.
	var debris := ["Props/concrete_block_mx_1.glb", "Debris & Misc/brick_mx_1.glb",
		"Props/cardboard_box_1.glb", "Props/cardboard_box_2.glb", "Props/jerrycan_mx_1.glb"]
	for i in 16:
		var p := Vector3(randf_range(-h + 3, h - 3), 0, randf_range(-h + 3, h - 3))
		if p.length() < 4.0:
			continue                              # keep the plinth clear
		_place(g, PSX2 + debris[i % debris.size()], p, randf() * 360.0, "Debris%d" % i,
			randf_range(0.8, 1.3))
	# Toppled crate stack against a wall.
	for i in 3:
		_place(g, PSX + "Large Props/wooden_crate_5.glb", Vector3(h - 3, i * 0.9, -6 + i * 2), 15, "Crate%d" % i)
	# Collapsed lighting: dead lamps + a single red emergency wash.
	_place(g, PSX2 + "Light Sources/lamp_mx_2_off.glb", Vector3(-h + 1, 4.5, -h + 6), 0, "DeadLampA", 1.5)
	_place(g, PSX2 + "Light Sources/lamp_mx_2_off.glb", Vector3(h - 1, 4.5, 6), 0, "DeadLampB", 1.5)
	_light(g, Vector3(0, 5.5, 4), Color(1.0, 0.35, 0.25), 3.0, h, "EmergencyGlow")
	# Warnings / failed-containment notes on the walls (no readable text — graffiti + posters).
	_place(g, PSX2 + "Decals/graffiti_mx_1.glb", Vector3(-h + 0.3, 2.4, -4), 90, "Graf1", 4.0)
	_place(g, PSX2 + "Decals/graffiti_mx_4.glb", Vector3(h - 0.3, 2.4, 8), -90, "Graf2", 4.0)
	_place(g, PSX2 + "Decals/poster_cx_4.glb", Vector3(6, 2.4, -h + 0.3), 0, "Poster1", 3.0)
	_place(g, PSX2 + "Decals/poster_cx_12.glb", Vector3(-6, 2.4, h - 0.3), 180, "Poster2", 3.0)


# ---- elevator (the real elevator_1 mesh + its doors, with box collision) -----
## On the SOUTH wall, opening NORTH into the room (the only doorway is on the north wall, to control).
func _build_elevator(g: Node3D, size: float) -> void:
	var h := size * 0.5
	var bz := h - 0.3                  # back wall, at the south wall
	var depth := 2.2
	var oz := bz - depth               # opening edge (faces the room, -Z)
	var cx := 1.35
	# the real elevator mesh (back wall + sliding door panels), rotated 180 so its doors face -Z
	_place(g, PSX + "Modular Structures/elevator_1.glb", Vector3(0, 0, oz + 0.1), 180, "ElevCar", 1.0)
	var steel := Color(0.13, 0.14, 0.17)
	_solid(g, Vector3(0, 1.5, bz), Vector3(cx * 2 + 0.3, 3.0, 0.2), _mat("", 1, steel, Vector3.ONE), "ElevBack")
	_solid(g, Vector3(-cx, 1.5, (bz + oz) * 0.5), Vector3(0.2, 3.0, depth), _mat("", 1, steel, Vector3.ONE), "ElevLeft")
	_solid(g, Vector3(cx, 1.5, (bz + oz) * 0.5), Vector3(0.2, 3.0, depth), _mat("", 1, steel, Vector3.ONE), "ElevRight")
	_solid(g, Vector3(0, 3.0, (bz + oz) * 0.5), Vector3(cx * 2 + 0.3, 0.2, depth + 0.2), _mat("", 1, Color(0.1, 0.1, 0.12), Vector3.ONE), "ElevRoof")
	_place(g, PSX + "Electronics & Misc/elevator_buttons_1.glb", Vector3(cx - 0.2, 1.2, oz + 0.4), 180, "ElevButtons")
	_place(g, PSX + "Electronics & Misc/elevator_sign_1.glb", Vector3(0, 2.6, bz - 0.2), 180, "ElevSign")
	_light(g, Vector3(0, 2.7, (bz + oz) * 0.5), Color(1.0, 0.82, 0.5), 2.0, 4.0, "ElevGlow")


# ---- task instances (mounted against a free wall, floor-standing) -----------
func _build_tasks() -> void:
	for id in _tasks:
		var entry: Array = _tasks[id]
		var ps := load(entry[0]) as PackedScene
		if ps == null:
			continue
		var t := ps.instantiate()
		var props: Dictionary = entry[1]
		for k in props:
			t.set(k, props[k])
		var mount := _free_wall(id)
		t.position = _rpos(id) + (mount[0] as Vector3)
		t.rotation.y = deg_to_rad(mount[1])
		t.name = "Task_%s" % id
		_attach(_tasks_node, t)


## A wall WITHOUT a doorway to mount a task on: returns [offset_from_room_centre, yaw_deg] facing in.
## Sits near the wall (0.35 m) so the task's backplate is FLUSH against it, never floating.
func _free_wall(id: String) -> Array:
	var h := _rsize(id) * 0.5 - 0.35
	var used: Array = _doors[id]
	# prefer N, then S, E, W — pick the first wall with no door. yaw makes the task's +Z face INTO
	# the room: N wall -> +Z (0deg), S wall -> -Z (180), E wall -> -X (-90), W wall -> +X (90).
	var order := [["N", Vector3(0, 0, -h), 0.0], ["S", Vector3(0, 0, h), 180.0],
		["E", Vector3(h, 0, 0), -90.0], ["W", Vector3(-h, 0, 0), 90.0]]
	for w in order:
		if not (w[0] in used):
			return [w[1], w[2]]
	# All walls have doors (a 4-way intersection): tuck the task into a CORNER (solid, between the
	# centred doorways), facing the room centre. Still on the floor against the corner.
	var c := _rsize(id) * 0.5 - 1.6
	return [Vector3(c, 0, -c), -45.0]   # NE corner, facing SW into the room


# ---- items + power button + keycard door ------------------------------------
func _build_systems() -> void:
	var sys := Node3D.new(); sys.name = "Systems"; _attach(_root, sys)
	var pickup_ps := load("res://scenes/item_pickup.tscn") as PackedScene
	var rb_ps := load("res://scenes/power_reset_button.tscn") as PackedScene
	var door_ps := load("res://scenes/keycard_door.tscn") as PackedScene

	# Item pickups sit ON a crate against a wall (never midair).
	for id in _items:
		var spec: Array = _items[id]
		var h := _rsize(id) * 0.5 - 1.4
		var spot := _rpos(id) + Vector3(-h, 0, h)        # a back corner
		_place(sys, PSX + "Large Props/wooden_crate_5.glb", spot, 0, "Crate_%s" % spec[0])
		var pk := pickup_ps.instantiate()
		pk.name = "Pickup_%s_%s" % [spec[0], id]
		pk.set("kind", spec[0]); pk.set("model_path", spec[1]); pk.set("model_scale", spec[2])
		# Stand flat items upright: flashlight is already upright; crowbar/fish are long on X
		# (rotate about Z); cards/phones/batteries are flat in Y (rotate about X).
		var euler := Vector3(90, 0, 0)
		if spec[0] == "flashlight":
			euler = Vector3.ZERO
		elif spec[0] == "crowbar" or spec[0] == "fish":
			euler = Vector3(0, 0, 90)
		pk.set("model_euler", euler)
		pk.position = spot + Vector3(0, 0.95, 0)          # resting on top of the crate
		_attach(sys, pk)

	# Emergency power button on the POWER room's WEST wall (the wall is solid there).
	var rb := rb_ps.instantiate()
	rb.name = "PowerResetButton"
	var ph := _rsize("power") * 0.5
	rb.position = _rpos("power") + Vector3(-ph + 0.35, 1.4, -2.0)
	rb.rotation.y = deg_to_rad(90)
	_attach(sys, rb)

	# Keycard blast door gating the ARMORY (its WEST doorway, facing equipment).
	var door := door_ps.instantiate()
	door.name = "ArmoryDoor"
	door.position = _rpos("armory") + Vector3(-_rsize("armory") * 0.5, 0, 0)
	door.rotation.y = deg_to_rad(90)
	_attach(sys, door)


# ---- markers ----------------------------------------------------------------
func _build_markers() -> void:
	var s := Marker3D.new(); s.name = "PlayerSpawn"
	# inside the elevator car (south wall), facing north into the room
	s.position = _rpos("arrival") + Vector3(0, 0.4, _rsize("arrival") * 0.5 - 1.6)
	_attach(_root, s)
	var w := Marker3D.new(); w.name = "WatcherSpawn"
	w.position = _rpos("central_chamber")        # it starts where it broke out, then hunts north
	_attach(_root, w)
