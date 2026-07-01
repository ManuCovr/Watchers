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
@export var stun_color := Color(0.64, 0.8, 0.9)   ## eye tell while stunned (muted)
@export_group("Look")
@export var eye_size := 1.3            ## the floating eyeball's largest dimension, in metres
@export var ANGEL_Y := 1.0            ## float height — low, eye at waist/chest, not overhead
@export var look_at_player := true    ## the pupil tracks the chased player (even when unobserved)
## Correction so the model's PUPIL (not its -Z) ends up facing the player. Tune in the Inspector if
## the eye looks the wrong way (e.g. set Y to 180 to flip front/back).
@export var pupil_offset_deg := Vector3(0, 0, 0)
@export var angel_tint := Color(0.62, 0.6, 0.66)     ## (unused now the body is the eyeball)
@export var angel_glow := 0.22        ## (unused now the body is the eyeball)
@export var frozen_color := Color(0.50, 0.66, 0.80)  ## watched — muted cool, not neon blue
@export var moving_color := Color(0.82, 0.34, 0.28)  ## creeping — muted brick red, not pure red
@export_group("Audio")
@export var SKITTER_DB := -9.0
@export var SKITTER_MAX_DIST := 22.0

const EYE_Y := 1.5             # (legacy) — body now floats at ANGEL_Y
const WALL_MASK := 2            # only walls block line-of-sight
const EYE_MESH := "res://assets/models/eyeball/eye.obj"
const EYE_TEX := "res://assets/models/eyeball/eyeball_texture.png"

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

var _eye: MeshInstance3D         # the eyeball mesh (centred on the pivot)
var _eye_shader_mat: ShaderMaterial   # primary: chromatic-aberration eye shader
var _eye_std_mat: StandardMaterial3D  # fallback if the shader fails to load
var _body: Node3D                # a PIVOT at the eye centre — rotated so the pupil tracks the player
var _tell_energy := 0.9          # smoothed glow strength
@export var ring_speed := 0.9    ## (unused — the eye no longer spins)
var _flicker := 0.0
var _cur_speed := 0.0           # ramps up when creeping = eases into motion, less robotic
var _agent: NavigationAgent3D   # paths through the bunker so it can actually chase
var _repath := 0.0              # throttle target updates
var _audio: AudioStreamPlayer3D


func _ready() -> void:
	# The watcher IS a single floating EYEBALL now. Its PUPIL tracks the player it's chasing, and the
	# whole eye is washed gently by the tell (muted blue watched / muted red creeping) + a chromatic
	# fringe. A PIVOT node sits at the eye's centre so look_at() rotates the ball in place.
	_body = Node3D.new()
	_body.position = Vector3(0, ANGEL_Y, 0)
	add_child(_body)

	var mi := MeshInstance3D.new()
	_eye = mi
	# Material: the chromatic-aberration eye shader (StandardMaterial fallback if it won't load).
	var esh := load("res://shaders/watcher_eye.gdshader") as Shader
	var tex = load(EYE_TEX)
	if esh != null:
		_eye_shader_mat = ShaderMaterial.new()
		_eye_shader_mat.shader = esh
		if tex != null:
			_eye_shader_mat.set_shader_parameter("tex", tex)
		mi.material_override = _eye_shader_mat
	else:
		_eye_std_mat = StandardMaterial3D.new()
		_eye_std_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_eye_std_mat.emission_enabled = true
		if tex != null:
			_eye_std_mat.albedo_texture = tex
		mi.material_override = _eye_std_mat

	var eyemesh = load(EYE_MESH)
	if eyemesh != null:
		mi.mesh = eyemesh
		# Normalise unknown .obj units to eye_size, then CENTRE the mesh on the pivot origin (so the
		# eyeball rotates about its own middle when it looks at you, instead of orbiting a point).
		var aabb := (mi.mesh as Mesh).get_aabb()
		var maxd: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
		var s: float = (eye_size / maxd) if maxd > 0.001 else 1.0
		mi.scale = Vector3.ONE * s
		mi.position = -aabb.get_center() * s
	else:
		var sm := SphereMesh.new()
		sm.radius = eye_size * 0.5
		sm.height = eye_size
		mi.mesh = sm
	_body.add_child(mi)

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
			# Being watched freezes it solid — UNLESS it's angry OR the power is out (outage_mult>1).
			# In a blackout it keeps coming no matter where you look (the gaze can't hold it).
			var ignore_gaze := angry or outage_mult > 1.001
			if observed and not ignore_gaze:
				frozen = true
				_cur_speed = 0.0
				velocity = Vector3.ZERO
			else:
				frozen = observed       # tell still reads, but it MOVES
				_creep(delta, observed)
				move_and_slide()
			net_frozen = frozen
	else:
		frozen = net_frozen               # client: mirror the server's state
		angry = net_angry

	# The eye does NOT spin — its pupil LOCKS onto the player it's chasing (runs on every peer for a
	# consistent stare; purely visual so a nearest-player approximation is fine on clients).
	if _body != null and look_at_player:
		_aim_pupil_at_player()
	_update_audio()
	_update_eye(delta)


## Rotate the eye pivot so the model's pupil faces the nearest player. `pupil_offset_deg` corrects
## for whichever local axis the pupil actually points down (look_at aims -Z by default).
func _aim_pupil_at_player() -> void:
	var p := _nearest_player()
	if p == null:
		return
	# Aim at the player's real eye/camera position (tracks crouch), nudged a hair down to read as
	# meeting the gaze rather than staring over the top of the screen.
	var tgt := p.eye_pos() - Vector3(0, 0.13, 0)
	if _body.global_position.distance_to(tgt) < 0.05:
		return
	_body.look_at(tgt, Vector3.UP)
	_body.rotate_object_local(Vector3.UP, deg_to_rad(pupil_offset_deg.y))
	_body.rotate_object_local(Vector3.RIGHT, deg_to_rad(pupil_offset_deg.x))
	_body.rotate_object_local(Vector3.BACK, deg_to_rad(pupil_offset_deg.z))


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
	# States are deliberately SUBTLE now — a gentle wash + soft glow, not a garish red/blue beacon.
	var col: Color
	var energy: float
	if is_stunned():
		# Stunned by the phone — cold wash with a slow shimmer (clearly "knocked out", still soft).
		_flicker += delta * 18.0
		col = stun_color
		energy = 0.6 + absf(sin(_flicker)) * 0.45
	elif frozen and not angry:
		# Watched: calm, steady, low — "I see you, I can't move."
		col = frozen_color
		_tell_energy = lerp(_tell_energy, 0.85, delta * 8.0)
		energy = _tell_energy
	else:
		# Creeping (or angry-and-watched): a muted red, breathing slightly. Angry = a touch hotter.
		_flicker += delta * (10.0 + (8.0 if angry else 0.0))
		col = moving_color if not angry else Color(0.9, 0.26, 0.20)
		energy = (0.7 if not angry else 0.95) + absf(sin(_flicker)) * (0.4 + (0.3 if angry else 0.0))
	_apply_tell(col, energy)


## Push the current tell colour + glow onto whichever eye material exists (shader or fallback).
func _apply_tell(col: Color, energy: float) -> void:
	if _eye_shader_mat != null:
		_eye_shader_mat.set_shader_parameter("tell_color", col)
		_eye_shader_mat.set_shader_parameter("tell_energy", energy)
	elif _eye_std_mat != null:
		_eye_std_mat.albedo_color = col
		_eye_std_mat.emission = col
		_eye_std_mat.emission_energy_multiplier = energy * 1.8
