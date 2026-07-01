@tool
class_name ItemPickup
extends Interactable
## A world item you collect by LOOKING AT it and pressing E. Self-driving (like a Task): it finds
## players, grants the item on the authority, and removes itself. Used for the flashlight, keycard,
## cigarettes, spare battery and the cellphone, so every functional item is a real placeable node.

@export_enum("flashlight", "phone", "keycard", "cigs", "battery", "crowbar", "fish") var kind := "flashlight":
	set(v): kind = v; _rebuild_preview()
@export var model_path := "res://assets/psx/Items & Weapons/flashlight_1.glb":
	set(v): model_path = v; _rebuild_preview()
@export var model_scale := 2.0
## Most item GLBs are modelled FLAT (lying down) — stand them up so they read. (90,0,0) tips a
## floor-flat item to vertical; the flashlight is already upright so it overrides this to ZERO.
@export var model_euler := Vector3(90, 0, 0)
@export var model_lift := 0.45                 ## float the item off the ground so it's visible
@export var spin_speed := 1.1                  ## slow idle spin (rad/s) — classic "pickup" tell
@export var outline_color := Color(0.92, 0.82, 0.48)  ## dirty gold, matches PhysicsItem's targeting outline

var _pivot: Node3D
var _model: Node3D
var _owned_mats: Array = []          # duplicated materials we own, to add/remove the outline pass
var _outline_mat: ShaderMaterial
var _outlined := false


func _ready() -> void:
	super._ready()
	prompt = "Pick up %s" % kind
	# Collider must cover the LIFTED, spinning model (model_lift ~0.45 + its height), or the
	# aim-ray sails over it and nothing is pickable. Tall + a bit wide so it's easy to look at.
	add_box(Vector3(0.9, 1.3, 0.9), Vector3(0, model_lift + 0.2, 0))
	_rebuild_preview()
	if Engine.is_editor_hint():
		return
	add_to_group("pickups")


func _rebuild_preview() -> void:
	if not is_inside_tree():
		return
	# Free only the model PIVOT (named "ModelPivot"/"Model"). DO NOT touch "@"-named children —
	# add_box() makes the CollisionShape3D + hover light with auto "@..." names, and nuking the
	# collider broke ALL pickups (no collider -> aim-ray passes through -> nothing is pickable).
	for c in get_children():
		if c.name == "ModelPivot" or c.name == "Model":
			remove_child(c)
			c.queue_free()
	_pivot = null
	_model = null
	if model_path == "":
		return
	var ps := load(model_path) as PackedScene
	if ps == null:
		return
	# Pivot floats the item up + spins it; the model is tilted upright under it so flat items read.
	_pivot = Node3D.new()
	_pivot.name = "ModelPivot"
	_pivot.position = Vector3(0, model_lift, 0)
	add_child(_pivot)
	_model = ps.instantiate() as Node3D
	_model.name = "Model"
	_model.scale = Vector3.ONE * model_scale
	_model.rotation_degrees = model_euler
	_pivot.add_child(_model)
	# Do NOT set owner — the preview is ephemeral (rebuilt on load), never saved into the scene.
	if not Engine.is_editor_hint():
		_setup_outline()


## Own the model's materials so we can toggle an inverted-hull OUTLINE pass when the player aims at
## the item — same readable gold silhouette as PhysicsItem. No constant glow light; you find items by
## their shape, and looking at one outlines it (consistent "look = outline" language across all items).
func _setup_outline() -> void:
	_owned_mats.clear()
	_outline_mat = null
	_outlined = false
	if _model == null:
		return
	var center := Vector3.ZERO
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		if inst.mesh == null:
			continue
		center = inst.mesh.get_aabb().get_center()
		for i in inst.mesh.get_surface_count():
			var src := inst.get_active_material(i)
			if src == null:
				continue
			var owned := src.duplicate() as Material
			inst.set_surface_override_material(i, owned)
			_owned_mats.append(owned)
	var sh := load("res://materials/player/player_outline.gdshader") as Shader
	if sh != null:
		_outline_mat = ShaderMaterial.new()
		_outline_mat.shader = sh
		_outline_mat.set_shader_parameter("outline_color", outline_color)
		_outline_mat.set_shader_parameter("thickness", 0.02)
		_outline_mat.set_shader_parameter("model_center", center)


func _set_outline(on: bool) -> void:
	if _outline_mat == null or on == _outlined:
		return
	_outlined = on
	for m in _owned_mats:
		(m as Material).next_pass = _outline_mat if on else null


## Override the base hover (which lit a glow light) — pickups OUTLINE on aim instead of glowing.
func look_hover(on: bool) -> void:
	_set_outline(on)


func _process(delta: float) -> void:
	# Idle spin runs on EVERY copy (visual) — before the authority gate below.
	if _pivot != null:
		_pivot.rotation.y += delta * spin_speed
	if Engine.is_editor_hint() or not Net.is_authority():
		return
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as WPlayer
		if p == null or p._downed:
			continue
		if p.aimed == self and p.consume_interact():
			if p.give_item(kind):
				if not AudioGen.is_headless():
					var s := load("res://assets/audio/sfx/button_15.ogg")
					if s != null:
						var a := AudioStreamPlayer3D.new()
						a.stream = s; a.volume_db = -6.0; a.position = global_position
						get_parent().add_child(a); a.global_position = global_position
						a.play(); a.finished.connect(a.queue_free)
				queue_free()
			return
