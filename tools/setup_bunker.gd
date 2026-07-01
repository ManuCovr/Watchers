extends SceneTree
## RECOVERY-LOOP BUNKER SETUP for res://scenes/bunker.tscn — load → mutate → save (reversible via git).
##
##   Godot_console.exe --headless --path <proj> --script res://tools/setup_bunker.gd
##
## Does three things the user asked for:
##  1. REMOVE every minigame task instance (scene_file_path under /tasks/) — they're gone for real now,
##     not just hidden. The task SCENES still exist on disk, so they can be re-instanced later.
##  2. ADD a `RecoverableSpawns` node of Marker3D spawn points (group "recoverable_spawn" + a "zone"
##     meta). RecoveryManager already PREFERS this group, and RoomAtmosphere reads the zone metas — so
##     these markers drive BOTH where objects spawn AND each room's colour/hum identity.
##  3. ADD a demo Ladder near the elevator so the climb mechanic is immediately testable. (Reposition
##     ladders at real vertical transitions in the editor — placement is best-effort.)
##
## Root is NOT added to the tree, so @tool scripts stay dormant; we re-pack exactly what's authored.

const SRC := "res://scenes/bunker.tscn"
const LADDER := "res://scenes/objectives/ladder.tscn"

## Marker spawn points: [Vector3 floor pos, zone label]. Positions are the verified-good floor spots
## near the elevator (same ones the manager's CURATED_SPAWNS used). Zones spread across the palette.
const SPAWNS := [
	# [pos, zone label, recovery category] — category drives which loot the island stages + its container.
	[Vector3(6.0, 0.4, -38.4), "Deep Storage", "food"],
	[Vector3(2.7, 0.4, -37.4), "Equipment Bay", "food"],
	[Vector3(-27.8, 0.4, -25.5), "Electrical", "electronics"],
	[Vector3(-23.8, 0.4, -21.3), "Coolant", "drink"],
	[Vector3(24.5, 0.4, -46.7), "Security", "electronics"],
	[Vector3(27.9, 0.4, -46.0), "Comms", "electronics"],
	[Vector3(-5.3, 0.4, -56.3), "Maintenance Corner", "drink"],
	[Vector3(7.3, 0.4, -38.9), "Generator", "food"],
	[Vector3(2.5, 0.4, -38.7), "Armory", "drink"],
]

## Where to drop demo ladders (pos, climb_height). Best-effort — move to real vertical shafts in-editor.
const LADDERS := [
	[Vector3(6.5, 0.2, 4.5), 4.0],
]


func _initialize() -> void:
	var ps := load(SRC) as PackedScene
	if ps == null:
		print("setup_bunker: FAILED to load ", SRC); quit(); return
	var root := ps.instantiate() as Node3D

	# 1) remove task instances
	var removed := 0
	var to_free: Array = []
	_collect_tasks(root, to_free)
	for n in to_free:
		if is_instance_valid(n):
			n.free(); removed += 1

	# 2) spawn markers
	if root.has_node("RecoverableSpawns"):
		root.get_node("RecoverableSpawns").free()
	var spawns := Node3D.new()
	spawns.name = "RecoverableSpawns"
	root.add_child(spawns)
	spawns.owner = root
	for entry in SPAWNS:
		var m := Marker3D.new()
		m.name = "Spawn_" + String(entry[1]).replace(" ", "_")
		spawns.add_child(m)
		m.owner = root
		m.position = entry[0]            # spawns is at root origin (identity) → local == world
		m.set_meta("zone", entry[1])
		m.set_meta("category", entry[2])            # loot category for this island
		m.add_to_group("recoverable_spawn", true)   # persistent → serialized into the .tscn

	# 3) demo ladder(s) — clear any from a previous run first (idempotent)
	for c in root.get_children():
		if String(c.name).begins_with("Ladder_"):
			c.free()
	var ladder_ps := load(LADDER) as PackedScene
	var ladders_added := 0
	if ladder_ps != null:
		for entry in LADDERS:
			var l := ladder_ps.instantiate() as Node3D
			l.name = "Ladder_%d" % ladders_added
			root.add_child(l)
			l.owner = root
			l.position = entry[0]            # ladder parented at root origin → local == world
			l.set("climb_height", entry[1])
			ladders_added += 1

	var out := PackedScene.new()
	var err := out.pack(root)
	if err != OK:
		print("setup_bunker: PACK FAILED err=", err); quit(); return
	var serr := ResourceSaver.save(out, SRC)
	print("=== setup_bunker: saved err=%d  removed_tasks=%d  markers=%d  ladders=%d ===" % [
		serr, removed, SPAWNS.size(), ladders_added])
	quit()


func _collect_tasks(n: Node, out: Array) -> void:
	var src: String = n.scene_file_path
	if src != "" and "/tasks/" in src:
		out.append(n)
		return                     # whole task subtree goes
	for c in n.get_children():
		_collect_tasks(c, out)
