class_name Watcher
extends CharacterBody3D
## A creeping figure. It advances toward the player ONLY while no one is looking
## at it. The instant it enters the player's view (with clear line-of-sight), it
## freezes solid. Eye glows calm BLUE when frozen, hot RED while it moves.

@export_group("Threat tuning")
@export var MOVE_SPEED := 2.3         ## creep speed (m/s) when unobserved (facility is large)
@export var CATCH_DIST := 1.15        ## reaches the player -> downs them
@export var SEP_DIST := 1.2           ## avoid stacking on other watchers
@export var SEP_FORCE := 1.3
@export var creep_accel := 6.0        ## how fast it ramps to full speed when you look away
@export_group("Escalation (anger / stun / outage)")
@export var anger_time := 600.0       ## seconds before it gets ANGRY (gaze stops fully freezing it)
@export var anger_speed_mult := 1.6   ## speed multiplier once angry
@export var anger_watched_speed := 0.9 ## m/s it STILL creeps at while watched, when angry
@export var stun_time := 6.0          ## seconds a thrown phone freezes it solid (the hard counter)
@export var stun_color := Color(0.7, 0.95, 1.0)   ## eye tell while stunned
@export_group("Look")
@export var ANGEL_SCALE := 1.25       ## the PS1 angel model is ~2m; tweak to taste
@export var ANGEL_Y := 1.45           ## lift so its feet/rings sit near the floor
@export var angel_tint := Color(0.62, 0.6, 0.66)     ## darkens the ring texture (moody)
@export var angel_glow := 0.22        ## faint self-emission so it reads in the dark
@export var frozen_color := Color(0.35, 0.65, 1.0)   ## eye when you're watching it
@export var moving_color := Color(1.0, 0.06, 0.03)   ## eye when it's creeping
@export_group("Audio")
@export var SKITTER_DB := -9.0
@export var SKITTER_MAX_DIST := 22.0

const EYE_Y := 1.5             # central ball height — sits in the middle of the rings
const WALL_MASK := 2            # only walls block line-of-sight
const ANGEL_MESH := "res://assets/models/angel/Biblically_Accurate_Angel.obj"
const ANGEL_TEX := "res://assets/models/angel/Ring_Texture.png"

signal caught

var siblings: Array = []
var frozen := true
var stopped := false            # global stop (win/lose)
var net_frozen := true          # replicated server -> clients
var _down_cd := 0.0             # cooldown so it can't chain-down players instantly
var _retreat := 0.0             # seconds remaining to back away after a takedown
# Escalation state
var _age := 0.0                 # seconds alive (drives anger)
var angry := false              # late-game: gaze no longer fully freezes it
var net_angry := false          # replicated for the client eye-tell
var _stun_t := 0.0              # >0 = frozen solid by a thrown phone
var net_stun := 0.0             # replicated so clients show the stun tell
var outage_mult := 1.0          # >1 while the power's out (bolder in the dark)

var _eye: MeshInstance3D
var _eye_mat: StandardMaterial3D
var _body_mat: StandardMaterial3D
var _flicker := 0.0
var _cur_speed := 0.0           # ramps up when creeping = eases into motion, less robotic
var _agent: NavigationAgent3D   # paths through the bunker so it can actually chase
var _repath := 0.0              # throttle target updates
var _audio: AudioStreamPlayer3D


func _ready() -> void:
	var body := MeshInstance3D.new()
	var angel = load(ANGEL_MESH)
	_body_mat = StandardMaterial3D.new()
	_body_mat.roughness = 1.0
	if angel != null:
		# Biblically-accurate angel: the spinning RINGS are plain dark metal/gold (no eye on
		# them) — the single EYE lives in the central ball (built below). The rings read in
		# the dark from a faint cold rim-emission, keeping the silhouette eerie.
		body.mesh = angel
		body.scale = Vector3.ONE * ANGEL_SCALE
		body.position = Vector3(0, ANGEL_Y, 0)
		_body_mat.albedo_color = angel_tint * Color(0.5, 0.5, 0.55)
		_body_mat.metallic = 0.7
		_body_mat.roughness = 0.55
		_body_mat.emission_enabled = true
		_body_mat.emission = Color(0.4, 0.46, 0.7)
		_body_mat.emission_energy_multiplier = angel_glow
	else:
		var cap := CapsuleMesh.new()
		cap.height = 2.0
		cap.radius = 0.30
		body.mesh = cap
		body.position = Vector3(0, 1.0, 0)
		_body_mat.albedo_color = Color(0.015, 0.015, 0.022)
	body.material_override = _body_mat
	# The body becomes a shimmering hole in reality (screen refraction + drifting starfield). The
	# EYE is a separate mesh built below, so the blue/red gameplay tell is unaffected.
	var bsh := load("res://shaders/watcher.gdshader") as Shader
	if bsh != null:
		var bsm := ShaderMaterial.new()
		bsm.shader = bsh
		body.material_override = bsm
	add_child(body)

	# The EYE = the central ball inside the rings. The ring/eye texture sits on it (a
	# glowing iris) and its emission COLOUR is the gameplay tell (blue frozen / red moving).
	_eye = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.32
	sm.height = 0.64
	_eye.mesh = sm
	_eye.position = Vector3(0, EYE_Y, 0.0)
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_mat.emission_enabled = true
	var iris = load(ANGEL_TEX)
	if iris != null:
		_eye_mat.albedo_texture = iris         # the eye texture lives HERE, on the central ball
	# albedo_color + emission are driven by the gameplay tell (blue frozen / red moving) so
	# the ball glows the tell colour over the eye texture — readable across a dark room.
	_eye.material_override = _eye_mat
	add_child(_eye)

	var col := CollisionShape3D.new()
	var cap2 := CapsuleShape3D.new()
	cap2.height = 2.0
	cap2.radius = 0.30
	col.shape = cap2
	col.position = Vector3(0, 1.0, 0)
	add_child(col)

	collision_layer = 4          # watcher (player gaze ray uses mask 2, so it won't hit us)
	collision_mask = 2           # collide with walls/floor so we can't phase through them

	# Navigation: path through the bunker (around walls) instead of shuffling into them.
	_agent = NavigationAgent3D.new()
	_agent.path_desired_distance = 0.7
	_agent.target_desired_distance = 1.0
	_agent.radius = 0.4
	_agent.height = 1.8
	_agent.path_max_distance = 6.0
	add_child(_agent)

	# Each watcher owns its tiny skitter stream (no static cache — that leaks at exit).
	_audio = AudioStreamPlayer3D.new()
	_audio.stream = AudioGen.skitter()
	_audio.volume_db = SKITTER_DB
	_audio.unit_size = 4.0
	_audio.max_distance = SKITTER_MAX_DIST
	_audio.position = Vector3(0, 1.0, 0)
	add_child(_audio)

	# In multiplayer the SERVER simulates the watcher; clients receive position + frozen.
	if Net.is_active():
		var sync := MultiplayerSynchronizer.new()
		sync.name = "Sync"      # fixed name so the sync path matches on every peer
		var cfg := SceneReplicationConfig.new()
		cfg.add_property(NodePath(".:position"))
		cfg.add_property(NodePath(".:net_frozen"))
		cfg.add_property(NodePath(".:net_angry"))
		cfg.add_property(NodePath(".:net_stun"))
		sync.replication_config = cfg
		sync.set_multiplayer_authority(1)     # server authority
		add_child(sync)


func _physics_process(delta: float) -> void:
	if stopped:
		if _audio.playing:
			_audio.stop()
		return

	if Net.is_authority():
		_age += delta
		angry = _age >= anger_time
		net_angry = angry
		# STUN (thrown phone) overrides everything — frozen solid, can't advance.
		if _stun_t > 0.0:
			_stun_t -= delta
			net_stun = _stun_t
			frozen = true
			net_frozen = true
			_cur_speed = 0.0
			velocity = Vector3.ZERO
		else:
			net_stun = 0.0
			var observed := _observed_by_any()
			# EARLY game: being watched freezes it solid. LATE game (angry): it ignores the gaze
			# and keeps creeping (just slower) — the phone becomes the only hard stop.
			if observed and not angry:
				frozen = true
				_cur_speed = 0.0
				velocity = Vector3.ZERO
			else:
				frozen = observed       # angry+watched: tell still reads, but it MOVES
				_creep(delta, observed)
				move_and_slide()
			net_frozen = frozen
	else:
		frozen = net_frozen               # client: mirror the server's state
		angry = net_angry

	_update_audio()
	_update_eye(delta)


## Frozen solid for `dur` seconds by a thrown cellphone (the desperation counter once it's angry).
func stun(dur := -1.0) -> void:
	if not Net.is_authority():
		return
	_stun_t = maxf(_stun_t, stun_time if dur < 0.0 else dur)


## PowerSystem sets the multiplier (config.outage_watcher_speed_mult on a blackout, 1.0 otherwise).
func set_outage(mult: float) -> void:
	outage_mult = maxf(0.1, mult)


func is_stunned() -> bool:
	return (_stun_t if Net.is_authority() else net_stun) > 0.0


## Effective creep speed: base, boosted by anger and by a power outage. When angry AND being
## watched it only manages a slow, defiant crawl (anger_watched_speed).
func _effective_speed(observed: bool) -> float:
	if angry and observed:
		return anger_watched_speed * outage_mult
	var s := MOVE_SPEED * outage_mult
	if angry:
		s *= anger_speed_mult
	return s


func _creep(delta: float, observed := false) -> void:
	if _down_cd > 0.0:
		_down_cd -= delta
	var p := _nearest_player()
	if p == null:
		return                     # everyone's downed — game.gd handles the loss
	var spd := _effective_speed(observed)

	# After a takedown the watcher RETREATS for a few seconds, clearing the body so
	# teammates can actually revive (no camping the corpse / death-trapping the reviver).
	if _retreat > 0.0:
		_retreat -= delta
		var away := global_position - p.global_position
		away.y = 0.0
		velocity = away.normalized() * spd if away.length() > 0.1 else Vector3.ZERO
		return

	var to := p.global_position - global_position
	var dy := absf(to.y)
	var d := Vector2(to.x, to.z).length()
	# Reach a player on our level -> DOWN them (a teammate can revive). Not game over.
	if d <= CATCH_DIST and dy < 1.5:
		velocity = Vector3.ZERO
		if _down_cd <= 0.0:
			p.down()
			_down_cd = 3.0
			_retreat = 4.5         # back off so the body can be revived
		return

	# Follow the NAVMESH toward the player (paths around walls = a real chase).
	_repath -= delta
	if _repath <= 0.0:
		_agent.target_position = p.global_position
		_repath = 0.25
	_cur_speed = move_toward(_cur_speed, spd, creep_accel * delta)
	var next := _agent.get_next_path_position()
	var step := next - global_position
	step.y = 0.0
	if step.length() > 0.05 and not _agent.is_navigation_finished():
		velocity = step.normalized() * _cur_speed
	else:
		# Fallback (e.g. before the navmesh has synced): head straight at them.
		var flat := Vector3(to.x, 0, to.z)
		velocity = flat.normalized() * _cur_speed if flat.length() > 0.05 else Vector3.ZERO
	velocity.y = 0.0


## Nearest LIVING player (downed players are ignored — go for whoever's still up).
func _nearest_player() -> WPlayer:
	var best: WPlayer = null
	var bd := INF
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as WPlayer
		if p == null or p._downed:
			continue
		var d := global_position.distance_to(p.global_position)
		if d < bd:
			bd = d
			best = p
	return best


func _exit_tree() -> void:
	# Release the active playback on teardown so it doesn't leak at exit.
	if _audio != null and _audio.playing:
		_audio.stop()


## Distance to a given player on the floor plane (for that player's danger meter).
## Returns a huge value if the player is on a different level — no scare from below.
func threat_distance_to(p: WPlayer) -> float:
	if p == null:
		return 9999.0
	var to := p.global_position - global_position
	if absf(to.y) > 2.5:
		return 9999.0
	to.y = 0.0
	return to.length()


func is_moving() -> bool:
	return not frozen and not stopped


## Skitter plays only while creeping — the sound IS the "something moved" tell.
func _update_audio() -> void:
	if AudioGen.is_headless():
		return
	var moving := is_moving()
	if moving and not _audio.playing:
		_audio.play()
	elif not moving and _audio.playing:
		_audio.stop()


## Frozen if ANY player is looking at the eye with clear line-of-sight — the co-op
## rule (one teammate holding the gaze freezes it for everyone). Uses a cone on the
## SYNCED aim, so it's identical for the host and every client (no proxy-camera issues).
func _observed_by_any() -> bool:
	var eye_pos := global_position + Vector3(0, EYE_Y, 0)
	var space := get_world_3d().direct_space_state
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as WPlayer
		if p == null or p._downed:
			continue
		var view := p.global_position + Vector3(0, 1.55, 0)
		var to := eye_pos - view
		var d := to.length()
		if d < 0.05 or p.aim_dir().dot(to / d) < 0.68:    # ~47° cone
			continue
		var q := PhysicsRayQueryParameters3D.create(view, eye_pos)
		q.collision_mask = WALL_MASK
		if space.intersect_ray(q).is_empty():
			return true
	return false


func _update_eye(delta: float) -> void:
	if is_stunned():
		# Stunned by the phone — eye flares cold white-blue and pulses hard (clearly "knocked out").
		_flicker += delta * 40.0
		_eye_mat.albedo_color = stun_color
		_eye_mat.emission = stun_color
		_eye_mat.emission_energy_multiplier = 4.0 + absf(sin(_flicker)) * 5.0
	elif frozen and not angry:
		# Calm, steady blue — "I see you, I can't move."
		_eye_mat.albedo_color = frozen_color
		_eye_mat.emission = frozen_color
		_eye_mat.emission_energy_multiplier = lerp(
			_eye_mat.emission_energy_multiplier, 4.0, delta * 10.0)
	else:
		# Moving (or angry-and-watched): hot red. Angry = deeper, faster, brighter — it's pissed.
		_flicker += delta * (30.0 + (24.0 if angry else 0.0))
		var base := 2.5 + (2.0 if angry else 0.0)
		var pulse: float = base + absf(sin(_flicker)) * (3.5 + (2.5 if angry else 0.0))
		var col := moving_color if not angry else Color(1.0, 0.0, 0.0)
		_eye_mat.albedo_color = col
		_eye_mat.emission = col
		_eye_mat.emission_energy_multiplier = pulse
