extends Node3D
## WATCHERS — gameplay scene (res://scenes/game.tscn).
## A big dark house. 1–2 figures creep toward you whenever you aren't looking at
## them. Complete every TASK to win — but tasks are spread across rooms, so one
## player can't watch the figure AND work at the same time. Yell for help.
##
## Core verb: COVER YOUR ANGLE. The horror is the handoff. Tasks are self-driving
## (see Task.gd) — this scene just builds the house, spawns figures, and tallies.
##
## Level feel is @export-ed below so it's all editable in the Inspector.

# ---- Instanced scenes -------------------------------------------------------
const PLAYER_SCENE := preload("res://scenes/entities/player.tscn")
const WATCHER_SCENE := preload("res://scenes/entities/watcher.tscn")
const PAUSE_MENU_SCENE := preload("res://scenes/ui/pause_menu.tscn")
const RELAY_TASK := preload("res://scenes/tasks/task_relay.tscn")
const CARRY_TASK := preload("res://scenes/tasks/task_carry.tscn")
const SWITCH_TASK := preload("res://scenes/tasks/task_switches.tscn")
const HOUSE_SCENE := preload("res://scenes/bunker.tscn")   # the from-scratch modular bunker level
const MAIN_MENU_PATH := "res://scenes/main_menu.tscn"

# Geometry / lighting / room layout live in the AUTHORED bunker.tscn — edit it in the
# editor (drag walls/lights/markers). game.gd reads its Marker3D spawn points by name.
## ALL difficulty/threat tuning lives in this editor-editable Resource (default_game.tres).
## Open it in the Inspector to change watcher count/speed, task length, danger range, etc.
@export var config: GameConfig

@export_group("Lighting / visibility")
@export var fog_density := 0.02
@export var ambient_energy := 0.32     ## eerie but readable: lamp pools pop, corridors stay dim

@export_group("Heartbeat audio")
@export var heart_min_db := -34.0
@export var heart_max_db := -4.0
@export var heart_min_pitch := 0.85
@export var heart_max_pitch := 1.5

var house: Node3D
var watchers: Array[Watcher] = []
var tasks: Array[Task] = []
var _players_node: Node3D
var _spawner: MultiplayerSpawner
var _cached_local: WPlayer
var _state := "play"            # play | won | caught
var _paused := false
var _vmat: ShaderMaterial
var _hud_center: Label
var _danger := 0.0
var _pulse_t := 0.0
var _heart: AudioStreamPlayer
var _ambient: AudioStreamPlayer
var _pause_menu: CanvasLayer


func _ready() -> void:
	if config == null:
		config = load("res://resources/default_game.tres") as GameConfig
	if config == null:
		config = GameConfig.new()
	WPlayer.input_blocked = false     # clear any leftover pause-block from the lobby/menu
	VoiceManager.lobby_mode = false   # gameplay voice = tighter / more tactical
	_build_house()                    # the authored bunker (env + rooms + tasks live inside it)
	_build_environment()              # only if the bunker scene didn't author one
	_build_player()
	_collect_tasks()                  # tasks are authored in bunker.tscn -> just wire them up
	_build_watchers()
	_build_power()                    # power-outage events + the glowing red reset button
	_build_psx_post()                 # full-screen PSX dither/colour-reduction look
	_build_hud()
	_build_audio()
	_build_pause_menu()


var power: PowerSystem

## The power system reads the bunker's room lights + WorldEnvironment and drives the outage event.
func _build_power() -> void:
	power = PowerSystem.new()
	power.name = "PowerSystem"
	add_child(power)
	var env: Environment = null
	var we := house.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null:
		we = get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null:
		env = we.environment
	power.setup(config, house, env, watchers)
	power.outage_started.connect(func(): _announce_outage(true))
	power.power_restored.connect(func(): _announce_outage(false))


var _outage_label: Label
var _outage_tint: ColorRect
var _outage_flash := 0.0
var _pickup_label: Label

## Tell the players, loud and clear, when the lights die (and when they come back).
func _announce_outage(on: bool) -> void:
	if _outage_label == null:
		return
	_outage_label.visible = true
	if on:
		_outage_label.text = "⚠  POWER FAILURE  ⚠\nfind the red button — restore power"
		_outage_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.15))
		_outage_flash = 1.0
		if not AudioGen.is_headless():
			var a := AudioStreamPlayer.new()
			a.stream = load("res://assets/audio/sfx/button_10.ogg")
			a.volume_db = -2.0; a.pitch_scale = 0.6
			add_child(a); a.play(); a.finished.connect(a.queue_free)
	else:
		_outage_label.text = "POWER RESTORED"
		_outage_label.add_theme_color_override("font_color", Color(0.35, 1.0, 0.45))
		_outage_flash = 0.0
		_outage_tint.color.a = 0.0
		get_tree().create_timer(2.0).timeout.connect(func():
			if is_instance_valid(_outage_label): _outage_label.visible = false)


# ---- Build ------------------------------------------------------------------
## The bunker scene authors its own WorldEnvironment (editor-editable). Only build a
## fallback if it's missing, so the level renders even if you stripped it in the editor.
func _build_environment() -> void:
	if house != null and house.get_node_or_null("WorldEnvironment") != null:
		return
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.015)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.16, 0.18, 0.24)
	env.ambient_light_energy = ambient_energy
	env.fog_enabled = true
	env.fog_light_color = Color(0.02, 0.025, 0.035)
	env.fog_density = fog_density
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.15
	we.environment = env
	add_child(we)


func _build_house() -> void:
	# Prefer the AUTHORED bunker instance in game.tscn (so the level is visible/editable in
	# the editor). Only instance one in code if the scene didn't author it.
	house = get_node_or_null("Bunker")
	if house == null:
		house = HOUSE_SCENE.instantiate()
		house.name = "Bunker"
		add_child(house)
	# Bake the navmesh at RUNTIME from the room/tunnel collider GROUP. (PackedScene.pack does
	# not reliably serialise a runtime-baked navmesh, so we rebuild it on load — after physics
	# frames register the colliders, else the bake is empty and the watcher can't path.)
	var nav := house.get_node_or_null("Nav") as NavigationRegion3D
	if nav == null:
		return
	for cont in ["Rooms", "Tunnels"]:
		var n := house.get_node_or_null(cont)
		if n != null:
			n.add_to_group("navsrc")
	_rebake_nav(nav)


func _rebake_nav(nav: NavigationRegion3D) -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	nav.bake_navigation_mesh(false)


## World position of a named Marker3D inside the authored house (or a fallback).
func _marker(nm: String, fallback := Vector3.ZERO) -> Vector3:
	var m := house.get_node_or_null(nm) as Node3D
	return m.global_position if m != null else fallback


func _build_player() -> void:
	_players_node = Node3D.new()
	_players_node.name = "Players"
	add_child(_players_node)

	if not Net.is_active():
		# Solo: one local player, no networking.
		var p := PLAYER_SCENE.instantiate() as WPlayer
		p.name = "Player"
		p.position = _marker("PlayerSpawn", Vector3(0, 0.4, 26))
		_apply_player_config(p)
		_players_node.add_child(p)
		p.phone_thrown.connect(_spawn_thrown_phone)
		p.picked_up.connect(_on_picked_up)
		return

	# Multiplayer: a MultiplayerSpawner replicates a player per peer to everyone.
	_spawner = MultiplayerSpawner.new()
	_spawner.spawn_function = _spawn_player
	add_child(_spawner)
	_spawner.spawn_path = _players_node.get_path()   # set after both are in the tree
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(func(id): _spawner.spawn(id))
		_spawner.spawn(1)                       # the host's own player
		for id in multiplayer.get_peers():
			_spawner.spawn(id)


## Runs on every peer (the spawner replays it) — names the player after its peer id
## so authority resolves consistently. See player.gd::_enter_tree.
func _spawn_player(data: Variant) -> Node:
	var p := PLAYER_SCENE.instantiate() as WPlayer
	p.name = str(data)
	p.position = _marker("PlayerSpawn", Vector3(0, 0.4, 26))
	_apply_player_config(p)
	p.phone_thrown.connect(_spawn_thrown_phone)
	p.picked_up.connect(_on_picked_up)
	return p


const PICKUP_HINTS := {
	"flashlight": "FLASHLIGHT\npress G to toggle the torch",
	"phone": "CELLPHONE\npress V to throw it and stun the watcher",
	"keycard": "KEYCARD\nuse it on a locked blast door's keypad",
	"cigs": "CIGARETTES\npress C to light one up",
	"battery": "BATTERY\nflashlight recharged",
}

## Big center message when you pick something up: WHAT it is + HOW to use it. Fades after a beat.
func _on_picked_up(kind: String) -> void:
	if _pickup_label == null:
		return
	_pickup_label.text = "PICKED UP — " + String(PICKUP_HINTS.get(kind, kind.to_upper()))
	_pickup_label.visible = true
	_pickup_label.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(2.2)
	t.tween_property(_pickup_label, "modulate:a", 0.0, 1.0)
	t.tween_callback(func(): if is_instance_valid(_pickup_label): _pickup_label.visible = false)


## Push the editor-tunable GameConfig numbers onto a freshly-spawned player (flashlight battery,
## cigarette feel, capacitor carry weight) so all the new systems are balanced from the Resource.
func _apply_player_config(p: WPlayer) -> void:
	p.flashlight_drain = config.flashlight_drain
	p.flashlight_recharge = config.flashlight_recharge
	p.flashlight_energy = config.flashlight_energy
	p.flashlight_range = config.flashlight_range
	p.flashlight_angle = config.flashlight_angle
	p.cig_calm_time = config.cig_calm_time
	p.cig_stamina_restore = config.cig_stamina_restore
	p.capacitor_carry_slow = config.capacitor_carry_slow


## A player threw their phone — fling a stun projectile from their aim.
func _spawn_thrown_phone(origin: Vector3, dir: Vector3) -> void:
	var tp := ThrownPhone.new()
	add_child(tp)
	tp.launch(origin, dir)


## The player THIS peer controls (or the solo player). Cached once found.
func _local_player() -> WPlayer:
	if _cached_local != null and is_instance_valid(_cached_local):
		return _cached_local
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as WPlayer
		if p != null and (not Net.is_active() or p.is_multiplayer_authority()):
			_cached_local = p
			return p
	return null


## Tasks are AUTHORED as real nodes inside bunker.tscn (Tasks/Task_* — edit/move them in the
## editor). At runtime they add themselves to group "tasks"; we just collect + wire them.
func _collect_tasks() -> void:
	tasks.clear()
	for n in get_tree().get_nodes_in_group("tasks"):
		var t := n as Task
		if t == null:
			continue
		if not t.completed.is_connected(_on_task_completed):
			t.completed.connect(_on_task_completed)
			t.progress_changed.connect(_on_task_progress)
		tasks.append(t)


func _build_watchers() -> void:
	# Built on EVERY peer with identical names/positions so the server's
	# MultiplayerSynchronizer (inside watcher.gd) can drive the clients' copies.
	var spawn := _marker("WatcherSpawn", Vector3(0, 0.2, -26))
	for i in config.watcher_count:
		var w := WATCHER_SCENE.instantiate() as Watcher
		w.name = "Watcher%d" % i
		w.position = spawn + Vector3(float(i) * 2.0, 0, 0)
		w.MOVE_SPEED = config.watcher_speed       # difficulty from the config resource
		w.creep_accel = config.watcher_accel
		w.CATCH_DIST = config.catch_distance
		w.anger_time = config.anger_time          # late-game escalation
		w.anger_speed_mult = config.anger_speed_mult
		w.anger_watched_speed = config.anger_watched_speed
		w.stun_time = config.stun_time
		w.add_to_group("watchers")                # thrown phone finds them here
		add_child(w)
		watchers.append(w)
	for w in watchers:
		w.siblings = watchers


func _build_audio() -> void:
	_heart = AudioStreamPlayer.new()
	_heart.stream = AudioGen.heartbeat()
	_heart.volume_db = heart_min_db
	add_child(_heart)

	# A low, looping dread bed under everything (real recorded ambience, not procedural).
	_ambient = AudioStreamPlayer.new()
	var amb := load("res://assets/audio/ambience/ambience_nightmares_mx_1.ogg")
	if amb is AudioStreamOggVorbis:
		(amb as AudioStreamOggVorbis).loop = true
	_ambient.stream = amb
	_ambient.volume_db = -17.0
	add_child(_ambient)

	if not AudioGen.is_headless():
		_heart.play()
		_ambient.play()


func _exit_tree() -> void:
	if _heart != null and _heart.playing:
		_heart.stop()
	if _ambient != null and _ambient.playing:
		_ambient.stop()


func _build_pause_menu() -> void:
	_pause_menu = PAUSE_MENU_SCENE.instantiate()
	add_child(_pause_menu)
	_pause_menu.visible = false
	_pause_menu.resume_requested.connect(func(): _set_paused(false))


## Full-screen PSX colour-reduction/dither pass (reusable PSXPost node), below the pause menu so the
## game + HUD get the retro look but the pause UI stays crisp.
func _build_psx_post() -> void:
	add_child(PSXPost.new())


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	# Danger vignette (radial red that swells as something closes in unseen).
	var vignette := ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vmat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tint : source_color = vec3(1.0, 0.05, 0.04);
void fragment() {
	vec2 uv = SCREEN_UV - 0.5;
	float d = length(uv) * 1.45;
	float v = smoothstep(0.25, 0.85, d) * strength;
	COLOR = vec4(tint, v);
}
"""
	_vmat.shader = sh
	vignette.material = _vmat
	layer.add_child(vignette)

	# Crosshair
	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.55)
	dot.size = Vector2(4, 4)
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.position = Vector2(-2, -2)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(dot)

	# Clean drawn meters (sprint / blink / voice / danger / objective pips) — no text.
	var hud := GameHUD.new()
	hud.player_fn = _local_player
	hud.danger_fn = func(): return _danger
	hud.tasks_fn = func(): return tasks
	layer.add_child(hud)

	# Outage warning tint (red screen wash that pulses while the power's out).
	_outage_tint = ColorRect.new()
	_outage_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_outage_tint.color = Color(0.6, 0.02, 0.02, 0.0)
	_outage_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_outage_tint)
	# Outage banner.
	_outage_label = _make_label(layer, Vector2(0, 70), HORIZONTAL_ALIGNMENT_CENTER, 34,
		Color(1.0, 0.2, 0.15))
	_outage_label.visible = false

	# Pickup confirmation ("PICKED UP — FLASHLIGHT / press G ...") centered, fades out.
	_pickup_label = Label.new()
	_pickup_label.set_anchors_preset(Control.PRESET_CENTER)
	_pickup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pickup_label.add_theme_font_size_override("font_size", 30)
	_pickup_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.7))
	_pickup_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_pickup_label.add_theme_constant_override("outline_size", 6)
	_pickup_label.position = Vector2(-220, -40)
	_pickup_label.size = Vector2(440, 80)
	_pickup_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pickup_label.visible = false
	layer.add_child(_pickup_label)

	# Only the win/lose result uses text (a real game-state message, not a label).
	_hud_center = _make_label(layer, Vector2(0, -40), HORIZONTAL_ALIGNMENT_CENTER, 40,
		Color(1, 1, 1))
	_hud_center.set_anchors_preset(Control.PRESET_CENTER)
	_hud_center.position = Vector2(0, -20)
	_hud_center.visible = false


func _make_label(parent: Node, off: Vector2, align: int, sz: int, col: Color) -> Label:
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_TOP_WIDE)
	l.position = off
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


# ---- Loop -------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	# Restart only in solo for now (a clean MP restart needs a server-driven reload).
	if event.is_action_pressed("restart") and not Net.is_active():
		get_tree().paused = false
		get_tree().reload_current_scene()
		return
	if event.is_action_pressed("pause") and _state == "play" and not _paused:
		_set_paused(true)


const REVIVE_RANGE := 2.6
const REVIVE_TIME := 3.0
var _revive_progress := {}

func _process(delta: float) -> void:
	if _state == "play":
		_update_danger(delta)
		if Net.is_authority():
			_update_coop(delta)
	_pulse_t += delta
	var pulse: float = 1.0 + sin(_pulse_t * (4.0 + _danger * 10.0)) * 0.18 * _danger
	_vmat.set_shader_parameter("strength", clamp(_danger * pulse, 0.0, 1.0))
	_heart.volume_db = lerpf(heart_min_db, heart_max_db, _danger)
	_heart.pitch_scale = lerpf(heart_min_pitch, heart_max_pitch, _danger)
	# Pulse the red outage wash while the power is out.
	if _outage_tint != null and power != null:
		var target := 0.18 if (not power.powered) else 0.0
		_outage_tint.color.a = lerpf(_outage_tint.color.a,
			target * (0.6 + 0.4 * sin(_pulse_t * 6.0)), delta * 4.0)


func _set_paused(p: bool) -> void:
	if _state != "play":
		return
	_paused = p
	# In multiplayer, pause is LOCAL only — block your input + show the overlay, but the
	# world keeps running for everyone. Solo pauses the whole tree (fine).
	if Net.is_active():
		WPlayer.input_blocked = p
	else:
		get_tree().paused = p
	_pause_menu.visible = p
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if p else Input.MOUSE_MODE_CAPTURED


func _update_danger(delta: float) -> void:
	# Danger/heartbeat are LOCAL feedback — relative to the player on THIS screen.
	var lp := _local_player()
	var nearest := 9999.0
	if lp != null:
		for w in watchers:
			if w.is_moving():
				nearest = min(nearest, w.threat_distance_to(lp))
	var target_danger := 0.0
	if nearest < config.danger_range:
		target_danger = clamp(1.0 - nearest / config.danger_range, 0.0, 1.0)
	_danger = lerp(_danger, target_danger, delta * 6.0)


func _on_task_progress(_task: Task, _ratio: float) -> void:
	pass            # the drawn HUD reads task progress live each frame


func _on_task_completed(_task: Task) -> void:
	var done := 0
	var total := 0
	for t in tasks:
		if t.counts_toward_win:
			total += 1
			if t.done:
				done += 1
	if done >= total:
		_win()


## Server/solo: handle downed teammates — revive when a standing player holds
## interact nearby, and lose only when EVERYONE is down.
func _update_coop(delta: float) -> void:
	var players := get_tree().get_nodes_in_group("players")
	var living := 0
	var downed: Array = []
	for n in players:
		var p := n as WPlayer
		if p == null:
			continue
		if p._downed:
			downed.append(p)
		else:
			living += 1
	if players.size() > 0 and living == 0:
		_finish("caught")
		return
	for dp in downed:
		var being_revived := false
		for n in players:
			var rp := n as WPlayer
			if rp == null or rp == dp or rp._downed or not rp.interact_held:
				continue
			if rp.global_position.distance_to((dp as WPlayer).global_position) <= REVIVE_RANGE:
				being_revived = true
				break
		if being_revived:
			_revive_progress[dp] = float(_revive_progress.get(dp, 0.0)) + delta
			if _revive_progress[dp] >= REVIVE_TIME:
				(dp as WPlayer).revive()
				_revive_progress.erase(dp)
		else:
			_revive_progress.erase(dp)


func _win() -> void:
	_finish("won")


## Server/solo decides the end; broadcast it so every peer shows the same result.
func _finish(kind: String) -> void:
	if _state != "play" or not Net.is_authority():
		return
	if Net.is_active():
		_show_end.rpc(kind)
	else:
		_show_end(kind)


@rpc("authority", "call_local", "reliable")
func _show_end(kind: String) -> void:
	_state = kind
	for w in watchers:
		w.stopped = true
	_hud_center.visible = true
	if kind == "caught":
		_danger = 1.0
		_vmat.set_shader_parameter("strength", 1.0)
		_hud_center.text = "CAUGHT" + ("\n[ R ] to try again" if not Net.is_active() else "")
		_hud_center.add_theme_color_override("font_color", Color(1.0, 0.15, 0.12))
	else:
		_hud_center.text = "HOUSE SECURE — you got out" + ("\n[ R ] to play again" if not Net.is_active() else "")
		_hud_center.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
