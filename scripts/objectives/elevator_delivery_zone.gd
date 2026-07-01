class_name ElevatorDeliveryZone
extends Area3D
## The elevator "loading bay". Watches RecoverableObjects that come to REST inside it and emits
## `object_settled` so the RecoveryManager can restock them. Physical delivery: carry it in, drop it,
## it loads — a thrown object still bouncing won't count until it settles, and the volume sits INSIDE
## the elevator so you can't lob from the doorway and have it count mid-air.
##
## Authority-only logic (the rest-timer + emit). The visual bay reads on every peer.

signal object_settled(obj: RecoverableObject)

@export var box_size := Vector3(3.4, 2.2, 3.4)   ## detection volume (a big, forgiving drop-off area)
@export var settle_time := 0.5                    ## seconds at rest before it counts
@export var settle_speed := 0.45                  ## linear speed below this = "at rest"
@export var pad_radius := 1.1
@export var pad_color := Color(0.85, 0.68, 0.32)  ## champagne gold — reads as "load here"
## Optional restock prop goods rest on. Empty by default (just a subtle floor glow — no ugly blocker).
## Drop in a nicer bin/cart model + tune bin_scale in-editor if you want a physical station.
@export var bin_model := ""
@export var bin_scale := 1.0

var _resting := {}                                # RecoverableObject -> seconds at rest so far


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 << 8                        # PhysicsItem lives on layer 9 (1<<8); monitor it
	monitoring = true
	monitorable = false
	_build_collision()
	_build_visual()


func _build_collision() -> void:
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	col.shape = box
	col.position = Vector3(0, box_size.y * 0.5 - 0.4, 0)   # dip below the bay origin so floor-resting goods count
	add_child(col)


## The drop-off STATION inside the elevator: a restock crate/bin you drop goods onto (a solid surface so
## they rest), ringed by a gold floor glow + a soft overhead light so the bay reads as "load here".
func _build_visual() -> void:
	# restock crate — a real surface so dropped goods settle on it (objects = layer 9, bin = world layer 2)
	var ps := load(bin_model) as PackedScene
	if ps != null:
		var vis := ps.instantiate() as Node3D
		vis.scale = Vector3.ONE * bin_scale
		var ab := _combined_aabb(vis)
		if ab.size.y > 0.05:
			var sb := StaticBody3D.new()
			sb.name = "RestockBin"
			sb.collision_layer = 2
			sb.collision_mask = 0
			vis.position.y = -ab.position.y          # base on the bay floor
			sb.add_child(vis)
			var cs := CollisionShape3D.new()
			var bb := BoxShape3D.new()
			bb.size = Vector3(maxf(ab.size.x, 0.4), maxf(ab.size.y, 0.4), maxf(ab.size.z, 0.4))
			cs.shape = bb
			cs.position = Vector3(ab.position.x + ab.size.x * 0.5, ab.size.y * 0.5, ab.position.z + ab.size.z * 0.5)
			sb.add_child(cs)
			add_child(sb)

	# gold floor ring so the bay reads in the dark — no HUD marker, no sign
	var pad := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = pad_radius
	cyl.bottom_radius = pad_radius
	cyl.height = 0.04
	pad.mesh = cyl
	pad.position = Vector3(0, 0.03, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(pad_color.r, pad_color.g, pad_color.b, 0.18)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = pad_color
	m.emission_energy_multiplier = 0.45
	pad.material_override = m
	add_child(pad)

	# soft overhead restock light (gold, DIM, steep falloff — a hint, not a spotlight)
	var lamp := OmniLight3D.new()
	lamp.light_color = pad_color
	lamp.light_energy = 0.4
	lamp.omni_range = 2.6
	lamp.omni_attenuation = 2.6
	lamp.position = Vector3(0, 2.0, 0)
	add_child(lamp)


func _combined_aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		if inst.mesh == null:
			continue
		var a: AABB = (n as Node3D).transform * (inst.transform * inst.mesh.get_aabb())
		if first:
			out = a; first = false
		else:
			out = out.merge(a)
	return out


## Authority POLLS the bodies currently inside the bay every frame (not enter/exit events) — because a
## delivered object is usually carried IN while HELD (frozen) and then DROPPED, which fires no second
## body_entered. Any RecoverableObject that's inside, not held, and at rest for settle_time counts.
func _physics_process(delta: float) -> void:
	if Net.is_active() and not Net.is_authority():
		return
	var inside := {}
	for b in get_overlapping_bodies():
		var obj := b as RecoverableObject
		if obj == null or obj.delivered or obj.held_by != null:
			continue
		inside[obj] = true
		if obj.linear_velocity.length() <= settle_speed:
			_resting[obj] = float(_resting.get(obj, 0.0)) + delta
			if float(_resting[obj]) >= settle_time:
				_resting.erase(obj)
				object_settled.emit(obj)
		else:
			_resting[obj] = 0.0
	# forget objects that left the bay (or got picked back up)
	for o in _resting.keys():
		if not inside.has(o):
			_resting.erase(o)
