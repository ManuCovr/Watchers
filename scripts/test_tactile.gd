extends Node3D
## DEV TEST HARNESS for the tactile interaction pass (run this scene directly, F6).
## Walk up to each station with your detached hands and try it:
##   LEVERS  — look at a breaker, HOLD E, drag the mouse DOWN (heavy)
##   VALVE   — look at the wheel, HOLD E, circle the mouse (real rotation; shaking won't work)
##   BUTTONS — look at a button, press E (the hand points + pokes it)
## WASD + mouse to move/look. Not part of the game flow.

const PLAYER := preload("res://scenes/entities/player.tscn")
const T_VALVE := preload("res://scenes/tasks/task_valve.tscn")
const T_SWITCHES := preload("res://scenes/tasks/task_switches.tscn")
const T_BUTTONS := preload("res://scenes/tasks/task_buttons.tscn")
const T_RELAY := preload("res://scenes/tasks/task_relay.tscn")


func _ready() -> void:
	_build_env()
	_build_floor()
	_place(T_SWITCHES, Vector3(-5, 0, -4), "LEVERS\nhold E + drag mouse DOWN")
	_place(T_VALVE, Vector3(-1, 0, -4), "VALVE\nhold E + circle the mouse")
	_place(T_BUTTONS, Vector3(3, 0, -4), "BUTTONS\nlook + press E (poke)")
	_place(T_RELAY, Vector3(7, 0, -4), "RELAY\nhold E")

	var player: WPlayer = PLAYER.instantiate()
	player.blink_enabled = false                  # no forced blinks while testing
	player.position = Vector3(-1, 1.0, 2.5)
	player.add_to_group("players")
	add_child(player)

	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := GameHUD.new()
	hud.player_fn = func(): return player
	layer.add_child(hud)


func _place(scene: PackedScene, pos: Vector3, label: String) -> void:
	var t: Node3D = scene.instantiate()
	t.position = pos
	add_child(t)
	var l := Label3D.new()
	l.text = label
	l.font_size = 40
	l.pixel_size = 0.004
	l.modulate = Color(0.96, 0.85, 0.5)
	l.outline_size = 10
	l.outline_modulate = Color(0, 0, 0)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = pos + Vector3(0, 2.7, 0)
	add_child(l)


func _build_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.07, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.8)
	env.ambient_light_energy = 0.55
	we.environment = env
	add_child(we)
	var dl := DirectionalLight3D.new()
	dl.rotation_degrees = Vector3(-52, -40, 0)
	dl.light_energy = 1.1
	add_child(dl)


func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 2        # player walks on layer-2 floors/walls
	body.collision_mask = 0
	add_child(body)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(40, 1, 40)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.28, 0.28, 0.32)
	mi.material_override = m
	add_child(mi)
