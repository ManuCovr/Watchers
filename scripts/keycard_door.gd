@tool
class_name KeycardDoor
extends Node3D
## A locked BLAST DOOR that gates a route through the facility. It blocks a doorway with a solid
## leaf until a player who HAS a keycard looks at the reader (keypad) and presses E — then it
## slides up and the way opens. No keycard = no passage, so you're forced to detour and find the
## card first. Self-driving (authority runs the unlock), editor-placeable, size adjustable.

@export var door_width := 3.4:
	set(v): door_width = v; _rebuild()
@export var door_height := 2.7:
	set(v): door_height = v; _rebuild()
@export var consume_keycard := false       ## true = the card is spent opening this door
@export var stay_open := true              ## once opened, it stays open

var _leaf: Node3D
var _leaf_body: StaticBody3D
var _reader: Interactable
var _reader_lamp: OmniLight3D
var _open := false
var _slide := 0.0                          # 0 closed .. 1 open


func _ready() -> void:
	_rebuild()
	if not Engine.is_editor_hint():
		add_to_group("doors")


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for nm in ["Frame", "Leaf", "Reader"]:
		var old := get_node_or_null(nm)
		if old != null:
			old.free()

	# Decorative frame.
	var fps := load("res://assets/bunkers/blast_door_1_frame.glb") as PackedScene
	if fps != null:
		var f := fps.instantiate() as Node3D
		f.name = "Frame"
		add_child(f)
		if Engine.is_editor_hint() and get_tree().edited_scene_root != null:
			f.owner = get_tree().edited_scene_root

	# The sliding leaf = solid door panel that blocks the doorway.
	_leaf_body = StaticBody3D.new()
	_leaf_body.name = "Leaf"
	_leaf_body.collision_layer = 2          # walls layer — blocks the player + occludes interaction
	_leaf_body.collision_mask = 0
	add_child(_leaf_body)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(door_width, door_height, 0.25)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.17, 0.2)
	m.metallic = 0.6
	m.roughness = 0.45
	mi.material_override = m
	_leaf_body.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = bm.size
	cs.shape = bs
	_leaf_body.add_child(cs)
	_leaf_body.position = Vector3(0, door_height * 0.5, 0)
	_leaf = _leaf_body

	# The reader (keypad) beside the door.
	_reader = Interactable.new()
	_reader.name = "Reader"
	_reader.prompt = "Use keycard"
	_reader.add_box(Vector3(0.4, 0.5, 0.3))
	_reader.position = Vector3(door_width * 0.5 + 0.4, 1.4, 0.0)
	add_child(_reader)
	var kp := load("res://assets/psx/Small Props/keypad_1.glb") as PackedScene
	if kp != null:
		var k := kp.instantiate() as Node3D
		k.scale = Vector3.ONE * 2.0
		_reader.add_child(k)
	_reader_lamp = OmniLight3D.new()
	_reader_lamp.light_color = Color(0.95, 0.2, 0.16)   # red = locked
	_reader_lamp.light_energy = 1.0
	_reader_lamp.omni_range = 1.2
	_reader_lamp.position = Vector3(0, 0.3, 0.15)
	_reader.add_child(_reader_lamp)

	if Engine.is_editor_hint() and get_tree().edited_scene_root != null:
		var r := get_tree().edited_scene_root
		for c in [_leaf_body, mi, cs, _reader]:
			if c != null:
				c.owner = r


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	# Slide animation.
	if _open and _slide < 1.0:
		_slide = minf(1.0, _slide + delta * 1.4)
		_leaf.position.y = door_height * 0.5 + _slide * (door_height + 0.1)
		if _slide >= 1.0:
			_leaf_body.collision_layer = 0          # fully open — stop blocking
	# Authority handles the unlock.
	if not Net.is_authority() or _open:
		return
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as WPlayer
		if p == null or p._downed:
			continue
		if p.aimed == _reader and p.consume_interact():
			if p.has_keycard:
				_unlock(p)
			else:
				play_sfx("res://assets/audio/sfx/button_10.ogg", -4.0, 0.6)   # denied buzz
			return


func _unlock(p: WPlayer) -> void:
	_open = true
	if consume_keycard:
		p.has_keycard = false
	if _reader_lamp != null:
		_reader_lamp.light_color = Color(0.2, 0.95, 0.35)     # green = granted
	play_sfx("res://assets/audio/sfx/crack_1_wood.ogg", -1.0, 0.6)


func play_sfx(path: String, vol_db := -4.0, pitch := 1.0) -> void:
	if AudioGen.is_headless():
		return
	var s := load(path)
	if s == null:
		return
	var a := AudioStreamPlayer3D.new()
	a.stream = s; a.volume_db = vol_db; a.pitch_scale = pitch
	a.max_distance = 26.0
	add_child(a); a.play(); a.finished.connect(a.queue_free)
