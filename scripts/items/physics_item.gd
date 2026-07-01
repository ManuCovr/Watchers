class_name PhysicsItem
extends RigidBody3D
## A grabbable, throwable, swingable physics toy (crowbar / fish / ...). Friendslop chaos, NOT
## combat: grab with E, it settles into a defined HELD POSE (no random floor rotation), hold Q to
## charge a throw, tap LMB to swing (a windup -> arc -> recovery), and hits KNOCK people back gently
## (never lethal). All feel is exported per item.
##
## Held = FROZEN KINEMATIC, lerped toward the pose in front of the camera. The item layer never
## collides with players, AND a thrown item ignores its OWN thrower briefly (so you don't launch
## yourself on release). Authority (server / local in single-player) simulates and reads the holder's
## already-replicated input (interact_held / attack_held / throw_held).
##
## Controls (held):  E = drop · Q = hold to charge / release to throw · LMB = swing (swingable items)

static var lobby_mode := false      ## lobby = toys only (set by lobby.gd / game.gd). Hits are knockback-only anyway.

@export_group("Model")
@export var item_name := "item"
@export var model_path := ""
@export var model_scale := 1.6
@export var model_euler := Vector3.ZERO
@export var collider_pad := 1.0

@export_group("Weight")
@export var item_mass := 1.4

@export_group("Hold pose")
## Camera-space offset when held (+X right, +Y up, -Z forward). Per item — crowbar != fish.
@export var hold_position_offset := Vector3(0.3, -0.28, 0.0)
@export var hold_rotation_degrees := Vector3(0, 0, 0)
@export var hold_distance := 0.75
@export var hold_lerp_speed := 16.0
@export var hold_rotation_lerp_speed := 16.0
@export var two_handed := false
## Optional per-item override for the detached HAND grip (finger curls + fine hand offset). If unset,
## DetachedHandsController falls back to a preset chosen by item_name. Keeps poses OUT of player.gd.
@export var hand_pose: HandPoseResource

@export_group("Throw")
@export var throw_min_force := 4.0
@export var throw_max_force := 13.0
@export var throw_charge_time := 0.8
@export var throw_spin := 7.0
## After a throw the item ignores its thrower this long, so you never bonk/launch yourself on release.
@export var throw_owner_ignore_time := 0.35

@export_group("Swing (state machine: windup -> active -> recovery)")
@export var can_swing := false
@export var swing_axis := Vector3(0.55, 1, 0.15)   ## camera space: a big diagonal cross-body sweep
@export var swing_angle_degrees := 195.0           ## HUGE arc — a real friendslop haymaker
@export var swing_windup_back := 0.6               ## winds back hard first (clear anticipation)
@export var swing_pivot_offset := Vector3(0, -0.5, 0.15)   ## low pivot = a big arc that sweeps across the view
@export var windup_time := 0.14                    ## quick, readable pull-back
@export var active_time := 0.12                    ## FAST committed strike (the whip)
@export var recovery_time := 0.34                  ## longer settle so the follow-through reads
@export var swing_cooldown := 0.55
@export var swing_lerp_speed := 80.0               ## near-SNAP during the swing so the FULL arc plays (no lag/tap)
@export var swing_range := 2.2
@export var swing_knockback := 4.5                 ## REDUCED — a shove, not a launch
@export var swing_up := 0.5

@export_group("Throw impact (knockback, never lethal)")
@export var impact_speed := 3.5
@export var impact_knockback := 2.5                ## REDUCED
@export var impact_up := 0.4
@export var max_knockback := 6.5                   ## hard clamp so nobody flies across the room
@export var hit_cooldown := 0.4

@export_group("Sounds")
## Dry, short samples (footsteps/wood) — the impact_* set was reverby/loud. Volumes kept low below.
@export var pickup_sound := "res://assets/audio/sfx/footstep_wood_a_2.ogg"
@export var throw_sound := "res://assets/audio/sfx/footstep_wood_a_5.ogg"
@export var swing_sound := "res://assets/audio/sfx/footstep_metal_a_2.ogg"
@export var impact_sound := "res://assets/audio/sfx/footstep_metal_a_1.ogg"
@export var sound_volume_db := -16.0       ## master trim for ALL of this item's sounds
@export var impact_sound_offset := 0.0     ## start the impact sound this many sec in (skip leading silence)

@export_group("Debug")
@export var debug_draw := false

# --- state -------------------------------------------------------------------
var held_by: WPlayer = null
var grab_range := 2.0          # max grab distance; the tight aim cone in _update_aimed_item gates the rest
var _charge := 0.0
var _charging := false
var _prev_throw := false
var _prev_attack := false
var _swing_t := -1.0            # <0 idle; else counts up through windup+active+recovery
var _swing_cd := 0.0
var _swing_hit_done := false
var _impact_cd := 0.0
var _last_owner: WPlayer = null
var _owner_ignore_t := 0.0
var _model: Node3D
var _audio: AudioStreamPlayer3D
var _dbg: MeshInstance3D
var _owned_mats: Array = []          # duplicated surface materials we own (for the targeting outline)
var _outline_mat: ShaderMaterial     # warm gold inverted-hull outline, shown only while targeted
var _outlined := false


func _ready() -> void:
	add_to_group("phys_items")
	mass = item_mass
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	linear_damp = 0.4
	angular_damp = 1.0
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	collision_layer = 1 << 8
	collision_mask = 2 | (1 << 8)          # world + other items; NEVER players (no self-shove)
	body_entered.connect(_on_body_entered)
	_build_visual()
	_audio = AudioStreamPlayer3D.new()
	add_child(_audio)
	if Net.is_active():
		set_multiplayer_authority(1)
		if not Net.is_authority():
			freeze = true
		_build_sync()


func _build_sync() -> void:
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var cfg := SceneReplicationConfig.new()
	cfg.add_property(NodePath(".:position"))
	cfg.add_property(NodePath(".:rotation"))
	sync.replication_config = cfg
	sync.set_multiplayer_authority(1)
	add_child(sync)


func _build_visual() -> void:
	var aabb := AABB()
	if model_path != "":
		var ps := load(model_path) as PackedScene
		if ps != null:
			_model = ps.instantiate() as Node3D
			_model.name = "MeshRoot"
			_model.scale = Vector3.ONE * model_scale
			_model.rotation_degrees = model_euler
			add_child(_model)
			aabb = _combined_aabb(_model)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = (aabb.size if aabb.size.length() > 0.05 else Vector3(0.3, 0.3, 0.3)) * collider_pad
	col.shape = box
	col.position = aabb.position + aabb.size * 0.5
	add_child(col)
	_setup_outline()


## Own the mesh's materials so we can add/remove a targeting outline pass without touching the GLB.
func _setup_outline() -> void:
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
		_outline_mat.set_shader_parameter("outline_color", Color(0.92, 0.82, 0.48))  # dirty gold, reads in the dark
		_outline_mat.set_shader_parameter("thickness", 0.014)
		_outline_mat.set_shader_parameter("model_center", center)


func _set_outline(on: bool) -> void:
	if _outline_mat == null:
		return
	for m in _owned_mats:
		(m as Material).next_pass = _outline_mat if on else null


## VISUAL (runs on every copy): highlight me while the local player is aiming at me to grab.
func _process(_delta: float) -> void:
	var want := false
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as WPlayer
		if p != null and p.aimed_item == self:
			want = true
			break
	if want != _outlined:
		_outlined = want
		_set_outline(want)


func _combined_aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		if inst.mesh == null:
			continue
		var a: AABB = _model.transform * (inst.transform * inst.mesh.get_aabb())
		if first:
			out = a; first = false
		else:
			out = out.merge(a)
	return out


# ---- grab / drop / throw ----------------------------------------------------
func grab(p: WPlayer) -> void:
	if held_by != null or p == null:
		return
	held_by = p
	p.held_item = self
	p._grab_time_ms = Time.get_ticks_msec()    # post-grab grace before an impact can shake it loose
	angular_velocity = Vector3.ZERO
	linear_velocity = Vector3.ZERO
	freeze = true
	_charge = 0.0
	_charging = false
	_prev_throw = p.throw_held
	_prev_attack = p.attack_held
	_swing_t = -1.0
	_play(pickup_sound, 0.0, 1.1)


func _release() -> void:
	if held_by != null and held_by.held_item == self:
		held_by.held_item = null
	held_by = null
	freeze = false
	_charging = false
	_charge = 0.0
	_swing_t = -1.0


func drop() -> void:
	_release()


func throw(charge01: float) -> void:
	var p := held_by
	if p == null:
		return
	var dir := p.aim_dir()
	# Remember the thrower + start the ignore window BEFORE detaching, so the release frame
	# (item still right in front of you) can't knock you back.
	_last_owner = p
	_owner_ignore_t = throw_owner_ignore_time
	_release()                         # fully detach (held_by -> null, dynamic body) before impulse
	var force := lerpf(throw_min_force, throw_max_force, clampf(charge01, 0.0, 1.0))
	linear_velocity = dir * force + Vector3.UP * (force * 0.1)
	angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * throw_spin
	_play(throw_sound, 0.0, 1.0)


func charge_ratio() -> float:
	return clampf(_charge / maxf(throw_charge_time, 0.01), 0.0, 1.0) if _charging else 0.0


## True while a swing's windup→active→recovery is playing — the detached hand reads this to ride the arc.
func is_swinging() -> bool:
	return _swing_t >= 0.0


# ---- per-frame (authority only) --------------------------------------------
func _physics_process(delta: float) -> void:
	if _swing_cd > 0.0: _swing_cd -= delta
	if _impact_cd > 0.0: _impact_cd -= delta
	if _owner_ignore_t > 0.0: _owner_ignore_t -= delta
	if Net.is_active() and not Net.is_authority():
		return

	if held_by == null:
		_thrown_impact()
		_try_grab()
		return
	if not is_instance_valid(held_by) or held_by._downed:
		drop(); return

	_advance_swing(delta)
	_hold(delta)
	_handle_input(delta)


func _try_grab() -> void:
	# Grab ONLY if this is the item the player is most directly looking at. The player picks that
	# single target (most crosshair-aligned) in _update_aimed_item(), so two items side by side can't
	# fight over the grab — the centred one always wins, and it matches the HUD highlight exactly.
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as WPlayer
		if p == null or p._downed or p.held_item != null:
			continue
		if p.aimed_item == self and p.consume_interact():
			grab(p)
			return


## Drive the kinematic body toward the held pose (camera-relative) + the live swing arc.
func _hold(delta: float) -> void:
	if held_by.cam == null:
		return
	var cam := held_by.cam.global_transform
	var hold_basis := Basis.from_euler(Vector3(
		deg_to_rad(hold_rotation_degrees.x), deg_to_rad(hold_rotation_degrees.y), deg_to_rad(hold_rotation_degrees.z)))
	var hold_pos := hold_position_offset + Vector3(0, 0, -hold_distance)
	var ang := _swing_angle()
	if absf(ang) > 0.01:
		var rot := Basis(swing_axis.normalized(), deg_to_rad(ang))
		var pivot := hold_pos + hold_basis * swing_pivot_offset
		hold_pos = pivot + rot * (hold_pos - pivot)
		hold_basis = rot * hold_basis
	var target := cam * Transform3D(hold_basis, hold_pos)
	# While SWINGING, follow the arc almost instantly (both position AND rotation) so the whole sweep
	# plays out big and readable instead of lerp-lagging into a little tap. Idle hold stays soft/laggy.
	var swinging := _swing_t >= 0.0
	var pspeed := swing_lerp_speed if swinging else hold_lerp_speed
	var rspeed := swing_lerp_speed if swinging else hold_rotation_lerp_speed
	var np := global_position.lerp(target.origin, clampf(delta * pspeed, 0.0, 1.0))
	var cq := global_transform.basis.get_rotation_quaternion()
	var tq := target.basis.get_rotation_quaternion()
	var nq := cq.slerp(tq, clampf(delta * rspeed, 0.0, 1.0))
	global_transform = Transform3D(Basis(nq), np)
	_update_debug(target.origin)


func _handle_input(delta: float) -> void:
	# THROW (Q): charge while held, release to hurl. Separate from swing.
	var thr: bool = held_by.throw_held
	if thr and not _prev_throw:
		_charging = true; _charge = 0.0
	if thr and _charging:
		_charge = minf(throw_charge_time, _charge + delta)
	if (not thr) and _prev_throw:
		throw(charge_ratio())
		_charging = false; _charge = 0.0
		_prev_throw = thr
		return                              # thrown -> held_by gone
	_prev_throw = thr

	# SWING (LMB): start the windup->active->recovery state machine on the press edge.
	var atk: bool = held_by.attack_held
	if atk and not _prev_attack and can_swing and _swing_cd <= 0.0 and _swing_t < 0.0:
		_swing_t = 0.0
		_swing_hit_done = false
		_swing_cd = swing_cooldown
		_play(swing_sound, -2.0, 1.15)
	_prev_attack = atk

	# DROP (E): consumes the press so it won't also poke the elevator / a task.
	if held_by != null and held_by.consume_interact():
		drop()


# ---- swing state machine ----------------------------------------------------
func _advance_swing(delta: float) -> void:
	if _swing_t < 0.0:
		return
	_swing_t += delta
	var total := windup_time + active_time + recovery_time
	# Hitbox is live only during the ACTIVE phase.
	var in_active := _swing_t >= windup_time and _swing_t <= windup_time + active_time
	if in_active and not _swing_hit_done:
		_swing_hit()
	if _swing_t >= total:
		_swing_t = -1.0


## Angle of the arc over the swing — tuned for friendslop "weight": a snappy ANTICIPATION pull-back,
## an ACCELERATING committed strike (the whip), then a springy OVERSHOOT past rest before settling.
func _swing_angle() -> float:
	if _swing_t < 0.0:
		return 0.0
	var back := -swing_angle_degrees * swing_windup_back
	# 1) ANTICIPATION — quick ease-out pull-back, then hold wound-up for a beat.
	if _swing_t < windup_time:
		var w := _swing_t / windup_time
		return lerpf(0.0, back, 1.0 - pow(1.0 - w, 2.0))
	var t := _swing_t - windup_time
	# 2) STRIKE — accelerate out of the wound-up pose through the full arc (fastest at impact).
	if t < active_time:
		var a := t / active_time
		return lerpf(back, swing_angle_degrees, a * a)
	t -= active_time
	# 3) FOLLOW-THROUGH — overshoot a little past the rest pose, then settle back (spring).
	if t < recovery_time:
		var r := t / recovery_time
		var overshoot := -swing_angle_degrees * 0.12
		if r < 0.45:
			return lerpf(swing_angle_degrees, overshoot, smoothstep(0.0, 1.0, r / 0.45))
		return lerpf(overshoot, 0.0, smoothstep(0.0, 1.0, (r - 0.45) / 0.55))
	return 0.0


func _swing_hit() -> void:
	var p := held_by
	if p == null:
		return
	var fwd := p.aim_dir()
	for n in get_tree().get_nodes_in_group("players"):
		var o := n as WPlayer
		if o == null or o == p or o._downed:
			continue
		var to: Vector3 = o.global_position - global_position
		var d := to.length()
		if d <= swing_range and fwd.dot(to.normalized()) > 0.1:
			_swing_hit_done = true
			var kb := (fwd * swing_knockback + Vector3.UP * swing_up).limit_length(max_knockback)
			o.apply_knockback(kb, 0.22)
			_play(impact_sound, 2.0, 0.85 if can_swing else 1.25, impact_sound_offset)
			return


# ---- thrown-item impact (knockback, never lethal, never the thrower) --------
func _thrown_impact() -> void:
	if _impact_cd > 0.0:
		return
	var spd := linear_velocity.length()
	if spd < impact_speed:
		return
	for n in get_tree().get_nodes_in_group("players"):
		var o := n as WPlayer
		if o == null or o._downed:
			continue
		if o == _last_owner and _owner_ignore_t > 0.0:
			continue                       # never bonk the thrower right after release
		if global_position.distance_to(o.global_position + Vector3(0, 1.0, 0)) < 1.2:
			_impact_cd = hit_cooldown
			var dir := linear_velocity.normalized()
			var force := clampf(impact_knockback * mass * (spd / 7.0), 0.0, max_knockback)
			o.apply_knockback(dir * force + Vector3.UP * impact_up, 0.18)
			_play(impact_sound, clampf(spd * 0.4 - 5.0, -5.0, 3.0), 1.2, impact_sound_offset)
			return


func _on_body_entered(_body: Node) -> void:
	if (Net.is_active() and not Net.is_authority()) or held_by != null:
		return
	if linear_velocity.length() >= impact_speed:
		_play(impact_sound, clampf(linear_velocity.length() * 0.4 - 6.0, -8.0, 0.0), 1.2 if not can_swing else 0.85, impact_sound_offset)


# ---- debug + audio ----------------------------------------------------------
func _update_debug(anchor: Vector3) -> void:
	if not debug_draw:
		if _dbg != null:
			_dbg.visible = false
		return
	if _dbg == null:
		_dbg = MeshInstance3D.new()
		var s := SphereMesh.new(); s.radius = 0.05; s.height = 0.1
		_dbg.mesh = s
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.albedo_color = Color(1, 0.8, 0.2)
		_dbg.material_override = m
		_dbg.top_level = true
		add_child(_dbg)
	_dbg.visible = true
	_dbg.global_position = anchor


func _play(path: String, db: float, pitch: float, from := 0.0) -> void:
	if AudioGen.is_headless() or _audio == null or path == "":
		return
	var s := load(path)
	if s == null:
		return
	_audio.stream = s
	_audio.volume_db = db + sound_volume_db        # master trim keeps everything quiet
	_audio.max_db = 0.0
	_audio.unit_size = 4.0                          # falls off quickly -> less room-filling
	_audio.pitch_scale = pitch
	_audio.play(from)                              # `from` skips leading silence on some sfx
