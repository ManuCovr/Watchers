@tool
class_name Ladder
extends Node3D
## A climbable ladder. FREE-PHYSICS climb: a ClimbArea (Area3D) in front of the rungs; while a player
## is inside it, their gravity is off and W/S move them up/down (player.gd). A solid StaticBody at the
## rungs makes it a real object you bump into. Both the solid AND the climb volume are sized from the
## MESH's actual bounds (the GLB pivot can sit at the top, so we measure rather than assume y=0..H).

@export var ladder_model := "res://assets/psx2/Modular Props/ladder_hr_1_long.glb"
@export var model_scale := 1.0
@export var front_depth := 0.9       ## how far in front of the rungs the climb volume reaches
@export var min_width := 0.8         ## floor for the solid/climb width if the mesh is very thin

var _area: Area3D
var _ab := AABB(Vector3(-0.4, 0.0, -0.1), Vector3(0.8, 4.0, 0.2))   # fallback bounds


func _ready() -> void:
	_build_visual()
	_build_solid()                   # solid in editor too, so you can see/place it
	if Engine.is_editor_hint():
		return
	_build_area()


func _build_visual() -> void:
	var m: Node3D
	if has_node("LadderMesh"):
		m = get_node("LadderMesh")
	else:
		var ps := load(ladder_model) as PackedScene
		if ps == null:
			return
		m = ps.instantiate() as Node3D
		m.name = "LadderMesh"
		m.scale = Vector3.ONE * model_scale
		add_child(m)
	var ab := _combined_aabb(m)
	if ab.size.y > 0.1:
		_ab = ab


## A thin solid slab at the rungs (world layer 2) so player + items collide — you can't walk through.
func _build_solid() -> void:
	if has_node("Solid"):
		return
	var sb := StaticBody3D.new()
	sb.name = "Solid"
	sb.collision_layer = 2
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(_ab.size.x, min_width), _ab.size.y, maxf(_ab.size.z, 0.18))
	cs.shape = box
	cs.position = _ab.position + _ab.size * 0.5      # centre of the actual mesh
	sb.add_child(cs)
	add_child(sb)


## The climb trigger: a box covering the rungs' full height, reaching out in FRONT (+Z). Monitors the
## player layer (1) only; no collision_layer so it never blocks.
func _build_area() -> void:
	_area = Area3D.new()
	_area.name = "ClimbArea"
	_area.collision_layer = 0
	_area.collision_mask = 1
	_area.monitoring = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(_ab.size.x, min_width) + 0.3, _ab.size.y, front_depth)
	cs.shape = box
	var front_z := _ab.position.z + _ab.size.z          # front face of the mesh (+Z)
	cs.position = Vector3(_ab.position.x + _ab.size.x * 0.5, _ab.position.y + _ab.size.y * 0.5,
		front_z + front_depth * 0.5)
	_area.add_child(cs)
	add_child(_area)
	_area.body_entered.connect(_on_enter)
	_area.body_exited.connect(_on_exit)


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


func _on_enter(body: Node) -> void:
	if body is WPlayer:
		(body as WPlayer).enter_ladder(self)


func _on_exit(body: Node) -> void:
	if body is WPlayer:
		(body as WPlayer).exit_ladder(self)
