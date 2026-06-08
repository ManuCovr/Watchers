@tool
class_name PowerResetButton
extends Interactable
## The emergency power-restore button (`button_etx_red_1`), bolted in the electrical room. Dark and
## inert while power is on; during an OUTAGE it pulses an angry red so you can find it across the
## blacked-out facility. Look at it + E to slam it and bring the lights (and the gaze-rule) back.
## The PowerSystem arms it, reads the press, and lights it.

@export var model := "res://assets/tech/button_etx_red_1.glb"
@export var model_scale := 6.0

var _cap: Node3D                  # the press-cap child of the GLB (depresses when hit)
var _cap_rest := Vector3.ZERO
var _lamp: OmniLight3D
var _glow_mat: StandardMaterial3D
var _armed := false
var _press_t := 0.0
var _pulse := 0.0


func _ready() -> void:
	super._ready()
	prompt = "Restore power"
	add_box(Vector3(0.7, 0.7, 0.5), Vector3(0, 0, 0.1))
	var ps := load(model) as PackedScene
	if ps != null:
		var n := ps.instantiate() as Node3D
		n.name = "Model"
		n.scale = Vector3.ONE * model_scale
		n.rotation_degrees = Vector3(-90, 0, 0)    # face the player
		add_child(n)
		if Engine.is_editor_hint() and get_tree().edited_scene_root != null:
			n.owner = get_tree().edited_scene_root
		var cap := _find(n, "child")
		if cap != null:
			_cap = cap
			_cap_rest = cap.position
		# Give the button cap an emissive override we can pulse.
		var capmesh := _first_mesh(n)
		if capmesh != null:
			_glow_mat = StandardMaterial3D.new()
			_glow_mat.albedo_color = Color(0.5, 0.04, 0.03)
			_glow_mat.emission_enabled = true
			_glow_mat.emission = Color(1.0, 0.1, 0.06)
			_glow_mat.emission_energy_multiplier = 0.0
			capmesh.material_override = _glow_mat
	_lamp = OmniLight3D.new()
	_lamp.light_color = Color(1.0, 0.12, 0.08)
	_lamp.light_energy = 0.0
	_lamp.omni_range = 6.0
	_lamp.position = Vector3(0, 0.1, 0.2)
	add_child(_lamp)
	if not Engine.is_editor_hint():
		add_to_group("power_reset")


func set_armed(on: bool) -> void:
	_armed = on
	enabled = on                  # only interactable while the power's actually out


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	# Pulse the glow while armed so it's findable in the dark.
	_pulse += delta * 4.0
	var e := (0.6 + 0.4 * sin(_pulse)) if _armed else 0.0
	_lamp.light_energy = 4.0 * e
	if _glow_mat != null:
		_glow_mat.emission_energy_multiplier = 6.0 * e
	# Press-cap return.
	if _press_t > 0.0:
		_press_t = maxf(0.0, _press_t - delta * 3.0)
		if _cap != null:
			_cap.position = _cap_rest - Vector3(0, _press_t * 0.02, 0)


func punch() -> void:
	_press_t = 1.0
	if not AudioGen.is_headless():
		var s := load("res://assets/audio/sfx/button_22.ogg")
		if s != null:
			var a := AudioStreamPlayer3D.new()
			a.stream = s; a.volume_db = -2.0; add_child(a)
			a.play(); a.finished.connect(a.queue_free)


func _find(root: Node, frag: String) -> Node3D:
	if root is Node3D and frag in String(root.name).to_lower():
		return root
	for c in root.get_children():
		var r := _find(c, frag)
		if r != null:
			return r
	return null


func _first_mesh(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D:
		return root
	for c in root.get_children():
		var r := _first_mesh(c)
		if r != null:
			return r
	return null
