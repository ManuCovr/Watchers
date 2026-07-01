extends SceneTree
## ADDITIVE connection-fix pass for THE BUNKER. Generates res://scenes/tunnel_fixes.tscn:
## a "TunnelConnectionFixes" Node3D holding a real `tunnel_hole_2.glb` wall-with-arched-hole frame
## at EVERY room/tunnel doorway, so the rectangular box wall-hole (which left void corners around the
## round tunnel) is replaced by a clean arched opening with trim. Frames are VISUAL-ONLY (no collision),
## so navmesh + player/watcher traversal are unchanged. This scene is instanced into bunker.tscn under
## the Bunker root, preserving the entire authored facility.
##   Godot_console.exe --headless --path <proj> --script res://tools/build_tunnel_fixes.gd
##
## Room/edge data is copied verbatim from build_bunker.gd so the openings line up exactly.

const HOLE := "res://assets/bunkers/tunnel_hole_2.glb"   # 4.06w x 3.02h x 0.30 deep, arch matches tunnel
const EPS := 0.03                                         # nudge toward the room (avoid z-fighting the wall)

var _rooms := {
	"arrival": Vector3(0, 0, 0), "control": Vector3(0, 0, -30), "security": Vector3(26, 0, -30),
	"maintenance": Vector3(42, 0, -30), "power": Vector3(-28, 0, -30), "storage": Vector3(-28, 0, -56),
	"comms": Vector3(0, 0, -56), "generator": Vector3(28, 0, -56), "monitoring": Vector3(28, 0, -80),
	"equipment": Vector3(0, 0, -84), "barracks": Vector3(-26, 0, -84), "armory": Vector3(24, 0, -84),
	"mnt_a": Vector3(58, 0, -30), "mnt_b": Vector3(58, 0, -8), "mnt_c": Vector3(42, 0, -8),
	"junction": Vector3(0, 0, -110), "store_a": Vector3(-26, 0, -110), "store_b": Vector3(-52, 0, -110),
	"tech_a": Vector3(28, 0, -110), "tech_b": Vector3(54, 0, -110),
	"dorm_a": Vector3(-26, 0, -134), "dorm_b": Vector3(-52, 0, -134),
	"obs_n": Vector3(0, 0, -134), "obs_s": Vector3(0, 0, -218), "obs_e": Vector3(44, 0, -176),
	"obs_w": Vector3(-44, 0, -176), "ctrl_ne": Vector3(44, 0, -134), "ctrl_nw": Vector3(-44, 0, -134),
	"ctrl_se": Vector3(44, 0, -218), "ctrl_sw": Vector3(-44, 0, -218),
	"central_chamber": Vector3(0, 0, -176),
}
var _sizes := {
	"arrival": 14.0, "control": 16.0, "security": 10.0, "maintenance": 8.0, "power": 18.0,
	"storage": 12.0, "comms": 11.0, "generator": 20.0, "monitoring": 9.0, "equipment": 13.0,
	"barracks": 12.0, "armory": 10.0, "mnt_a": 10.0, "mnt_b": 10.0, "mnt_c": 10.0,
	"junction": 14.0, "store_a": 12.0, "store_b": 12.0, "tech_a": 12.0, "tech_b": 12.0,
	"dorm_a": 12.0, "dorm_b": 11.0, "obs_n": 13.0, "obs_s": 13.0, "obs_e": 13.0, "obs_w": 13.0,
	"ctrl_ne": 10.0, "ctrl_nw": 10.0, "ctrl_se": 10.0, "ctrl_sw": 10.0, "central_chamber": 44.0,
}
var _edges := [
	["arrival", "control"], ["control", "security"], ["control", "power"], ["control", "comms"],
	["security", "maintenance"], ["power", "storage"], ["comms", "generator"], ["comms", "equipment"],
	["generator", "monitoring"], ["equipment", "barracks"], ["equipment", "armory"],
	["maintenance", "mnt_a"], ["mnt_a", "mnt_b"], ["mnt_b", "mnt_c"], ["mnt_c", "maintenance"],
	["equipment", "junction"], ["junction", "store_a"], ["store_a", "store_b"],
	["junction", "tech_a"], ["tech_a", "tech_b"], ["barracks", "store_a"], ["monitoring", "tech_a"],
	["store_a", "dorm_a"], ["dorm_a", "dorm_b"], ["junction", "obs_n"],
	["obs_n", "ctrl_ne"], ["ctrl_ne", "obs_e"], ["obs_e", "ctrl_se"], ["ctrl_se", "obs_s"],
	["obs_s", "ctrl_sw"], ["ctrl_sw", "obs_w"], ["obs_w", "ctrl_nw"], ["ctrl_nw", "obs_n"],
	["obs_n", "central_chamber"], ["obs_s", "central_chamber"],
	["obs_e", "central_chamber"], ["obs_w", "central_chamber"],
]

var _doors := {}
var _root: Node3D


func _initialize() -> void:
	for id in _rooms:
		_doors[id] = []
	# same side-resolution as build_bunker._compute_doors
	for e in _edges:
		var a: String = e[0]; var b: String = e[1]
		var d: Vector3 = _rooms[b] - _rooms[a]
		if absf(d.x) > absf(d.z):
			if d.x > 0: _doors[a].append("E"); _doors[b].append("W")
			else: _doors[a].append("W"); _doors[b].append("E")
		else:
			if d.z > 0: _doors[a].append("S"); _doors[b].append("N")
			else: _doors[a].append("N"); _doors[b].append("S")

	var ps := load(HOLE) as PackedScene
	if ps == null:
		print("FATAL missing ", HOLE); quit(1); return

	_root = Node3D.new(); _root.name = "TunnelConnectionFixes"
	var count := 0
	for id in _rooms:
		var h: float = _sizes[id] * 0.5
		for side in _doors[id]:
			var f := ps.instantiate() as Node3D
			f.name = "Open_%s_%s" % [id, side]
			f.position = _rooms[id] + _offset(side, h)
			f.rotation.y = deg_to_rad(0.0 if (side == "N" or side == "S") else 90.0)
			_root.add_child(f)
			f.owner = _root
			count += 1

	get_root().add_child(_root)
	var packed := PackedScene.new()
	if packed.pack(_root) == OK:
		var err := ResourceSaver.save(packed, "res://scenes/tunnel_fixes.tscn")
		print("build_tunnel_fixes: frames=", count, " save_err=", err)
	else:
		print("build_tunnel_fixes: PACK FAILED")
	quit()


func _offset(side: String, h: float) -> Vector3:
	match side:
		"N": return Vector3(0, 0, -h + EPS)
		"S": return Vector3(0, 0, h - EPS)
		"E": return Vector3(h - EPS, 0, 0)
		"W": return Vector3(-h + EPS, 0, 0)
	return Vector3.ZERO
