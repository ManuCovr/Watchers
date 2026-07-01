extends SceneTree
## BIGGER + PRETTIER bunker elevator. Replaces the cramped, floorless elevator recess in Room_arrival
## with a ~3x interior: dark smoked panels + champagne-gold trim + a warm ceiling light, AND a real
## FLOOR (the old one was an open shaft — goods free-fell). A floor means the drop-off station can live
## INSIDE the car (an "elevator_bay" marker marks the spot). Load → mutate → save; reversible via git.
##
##   Godot_console.exe --headless --path <proj> --script res://tools/upgrade_elevator.gd

const SRC := "res://scenes/bunker.tscn"

# Car interior (world coords; Room_arrival is at origin). Doorway is the WallS gap at z≈7; the car sits
# behind it, now much larger.
const FRONT_Z := 7.0
const BACK_Z := 11.4
const HALF_W := 2.3          # x half-width
const CEIL_Y := 3.8
const CENTER := Vector3(0.0, 0.0, 9.2)   # car centre (z = midpoint)

const DARK := Color(0.075, 0.075, 0.092)      # smoked panel
const GOLD := Color(0.85, 0.68, 0.32)         # champagne trim
var _root: Node3D
var _room: Node3D


func _initialize() -> void:
	var ps := load(SRC) as PackedScene
	if ps == null:
		print("upgrade_elevator: FAILED to load ", SRC); quit(); return
	_root = ps.instantiate() as Node3D
	_room = _root.get_node_or_null("Rooms/Room_arrival") as Node3D
	if _room == null:
		print("upgrade_elevator: no Rooms/Room_arrival"); quit(); return

	# remove the old cramped elevator collision shells (keep ElevCar GLB doors + the sign)
	for nm in ["ElevBack", "ElevLeft", "ElevRight", "ElevRoof", "ElevatorBig"]:
		var old := _room.get_node_or_null(nm)
		if old != null:
			old.free()

	var depth := BACK_Z - FRONT_Z
	var midz := (FRONT_Z + BACK_Z) * 0.5
	var big := Node3D.new()
	big.name = "ElevatorBig"
	_room.add_child(big)
	big.owner = _root

	var wall_mat := _mat(DARK)
	var floor_mat := _mat(DARK.lerp(Color(0,0,0), 0.3))
	# shell: floor / ceiling / back / left / right (front = open doorway)
	_wall(big, "Floor", Vector3(0, -0.1, midz), Vector3(HALF_W * 2.0, 0.2, depth), floor_mat)
	_wall(big, "Ceil", Vector3(0, CEIL_Y, midz), Vector3(HALF_W * 2.0, 0.2, depth), wall_mat)
	_wall(big, "Back", Vector3(0, CEIL_Y * 0.5, BACK_Z), Vector3(HALF_W * 2.0, CEIL_Y, 0.2), wall_mat)
	_wall(big, "Left", Vector3(-HALF_W, CEIL_Y * 0.5, midz), Vector3(0.2, CEIL_Y, depth), wall_mat)
	_wall(big, "Right", Vector3(HALF_W, CEIL_Y * 0.5, midz), Vector3(0.2, CEIL_Y, depth), wall_mat)

	# champagne-gold trim: vertical corner strips + a horizontal band near the ceiling + a back-wall inlay
	var trim_mat := _mat(GOLD, true, 1.6)
	for sx in [-1.0, 1.0]:
		_trim(big, Vector3(sx * (HALF_W - 0.06), CEIL_Y * 0.5, FRONT_Z + 0.1), Vector3(0.06, CEIL_Y, 0.06), trim_mat)
		_trim(big, Vector3(sx * (HALF_W - 0.06), CEIL_Y * 0.5, BACK_Z - 0.1), Vector3(0.06, CEIL_Y, 0.06), trim_mat)
	_trim(big, Vector3(0, CEIL_Y - 0.25, BACK_Z - 0.12), Vector3(HALF_W * 2.0 - 0.3, 0.08, 0.04), trim_mat)
	_trim(big, Vector3(0, 1.4, BACK_Z - 0.12), Vector3(HALF_W * 1.2, 0.9, 0.04), _mat(GOLD.darkened(0.4), true, 0.5))
	# floor inlay strip so the bay reads as "the loading deck"
	_trim(big, Vector3(0, 0.02, midz), Vector3(HALF_W * 1.4, 0.02, depth - 0.6), _mat(GOLD.darkened(0.55), true, 0.35))

	# warm overhead light
	var lamp := OmniLight3D.new()
	lamp.name = "ElevLight"
	lamp.light_color = Color(1.0, 0.82, 0.55)
	lamp.light_energy = 2.4
	lamp.omni_range = 8.0
	lamp.omni_attenuation = 1.4
	big.add_child(lamp); lamp.owner = _root
	lamp.position = Vector3(0, CEIL_Y - 0.3, midz)

	# the drop-off marker (group "elevator_bay") — RecoveryManager places the delivery zone here
	var bay := Marker3D.new()
	bay.name = "ElevatorBay"
	big.add_child(bay); bay.owner = _root
	bay.position = Vector3(0, 0.1, midz)
	bay.add_to_group("elevator_bay", true)

	var out := PackedScene.new()
	if out.pack(_root) != OK:
		print("upgrade_elevator: PACK FAILED"); quit(); return
	var serr := ResourceSaver.save(out, SRC)
	print("=== upgrade_elevator: saved err=%d  car=%.1fx%.1fx%.1f  bay@%v ===" % [
		serr, HALF_W * 2.0, depth, CEIL_Y, bay.position])
	quit()


func _mat(col: Color, emissive := false, energy := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.65
	m.metallic = 0.2
	if emissive:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = energy
	return m


func _wall(parent: Node3D, nm: String, pos: Vector3, size: Vector3, mat: Material) -> void:
	var sb := StaticBody3D.new()
	sb.name = nm
	sb.collision_layer = 2
	sb.collision_mask = 0
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	sb.add_child(mi)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	sb.add_child(cs)
	parent.add_child(sb)
	sb.position = pos
	sb.owner = _root
	mi.owner = _root
	cs.owner = _root


func _trim(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	parent.add_child(mi)
	mi.position = pos
	mi.owner = _root
