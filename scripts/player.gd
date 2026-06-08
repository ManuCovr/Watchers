class_name WPlayer
extends CharacterBody3D
## First-person courier. Mouse-look + WASD (remappable via the Input Map). Exposes
## its Camera3D so watchers can test whether they're being looked at. No weapons —
## your GAZE is the only tool. You also cannot keep your eyes open forever.
##
## Movement feel lives in an editor-editable MovementTuning Resource (see `tuning`).
## Blink/headlamp/emote knobs are @export-ed so everything is editable in-editor.

## The visible co-op body. EXPORTED so you can swap the whole character scene in player.tscn. Defaults
## (set at runtime, see _ready) to the original customizable "potato guy" (character_rig.gd). Swap to
## gangbeast_character.tscn / badguy_character.tscn in the Inspector for the other rigs.
@export var character_scene: PackedScene

# All movement feel is in this Resource — assign default_movement.tres in the
# Inspector, or drop in another profile. Falls back to defaults if left empty.
@export var tuning: MovementTuning

@export_group("Headlamp")
@export var headlamp_energy := 1.1     ## dim ambient wash — the FLASHLIGHT is the real light now
@export var headlamp_range := 12.0
@export var headlamp_angle := 50.0

@export_group("Interaction")
@export var interact_reach := 3.2      ## how far the look-at aim-ray reaches for buttons/levers/items

@export_group("Melee (friendslop)")
@export var melee_range := 2.4          ## how far a swing reaches
@export var melee_cone := 0.4           ## aim dot threshold (~66° in front)
@export var melee_cooldown := 0.7       ## seconds between swings
const MELEE_MODELS := {
	"crowbar": "res://assets/psx2/Structures/rusty_crowbar_mx_1.glb",
	"fish": "res://assets/psx2/Props/fish_mx_1.glb",
}

@export_group("Flashlight (tool)")
@export var flashlight_energy := 6.0
@export var flashlight_range := 24.0
@export var flashlight_angle := 26.0   ## tight cone — a real torch
@export var flashlight_drain := 0.018  ## battery/sec while ON (game.gd overrides from GameConfig)
@export var flashlight_recharge := 0.0 ## battery/sec while OFF

@export_group("Blink / stamina")
@export var blink_enabled := true      ## off for the lobby (relaxed, full-vision space)
## You can't stare forever: a meter drains toward a forced blink, FASTER while you
## stand still and camp one angle, slower while you reposition/sweep.
@export var blink_interval := 4.0      ## seconds of stare-budget at full (camping) drain
@export var blink_duration := 0.18     ## eyes-shut time (fade to black and back)
@export var blink_recovery := 0.4      ## grace after a blink before draining resumes
@export var stare_drain := 1.0         ## drain multiplier while still + holding an angle
@export var move_drain := 0.4          ## drain multiplier while moving / sweeping

@export_group("Emote / meme")
@export var emote_texture: Texture2D            ## world middle finger OTHERS see (3D billboard)
@export var pov_texture: Texture2D              ## first-person finger YOU see (screen overlay)
@export var emote_size := 0.004                 ## Sprite3D pixel_size (bigger = larger finger)
@export var emote_distance := 1.2               ## how far in front of the player it floats

# Mouse-look sensitivity = the tuning resource's base * this user multiplier. The
# multiplier is a static so the options menu sets it once and it PERSISTS across
# scene changes (never reset on spawn). No global manager/singleton needed.
static var sens_multiplier := 1.0
# When true, the LOCAL player ignores input (used for the multiplayer pause overlay —
# the world keeps running for everyone; only your own controls are blocked).
static var input_blocked := false

var cam: Camera3D
var _head: Node3D
var _pitch := 0.0
var _bob_t := 0.0
var _breath_t := 0.0
var _sprint_budget := 0.0
var _was_sprinting := false

# --- BLINK SYSTEM (state) ---
var _blink_rect: ColorRect
var _stamina := 1.0
var _blink_t := -1.0           # <0 = eyes open; >=0 = mid-blink, counting up
var _recover_t := 0.0
var _look_activity := 0.0      # decays; bumped by mouse motion
var _move_activity := 0.0      # set each physics step from WASD input

# --- EMOTE SYSTEM (state) ---
var _emote_sprite: Sprite3D     # world-space billboard — visible to OTHER viewports
var _emote_pov: TextureRect     # first-person overlay — visible only to YOU
var _emote_audio: AudioStreamPlayer
var _emote_held := false

# --- NET ---
var _local := true              # true if THIS peer controls this player (or solo)
var net_emote := false          # replicated: is this player flipping someone off?
var net_mouth := 0.0            # replicated: voice amplitude 0..1 -> teammates' mouth flap
var interact_held := false      # replicated: holding interact (for reviving teammates)
var net_downed := false         # caught by a watcher; needs a revive
var megaphone := false          # holding the lobby megaphone -> boosted/distorted voice
var _downed := false
var _body: Node3D               # visible body so teammates can see you (the rig)
var _character: PlayerCharacter # the expressive rig (big eyes + voice mouth)

var _downed_label: Label3D      # "REVIVE (hold E)" prompt over a downed player
var _downed_overlay: ColorRect
var attack_held := false        # replicated: attack button down (throw / swing)
var holding := false            # replicated: are we carrying something (visual hint)
var _prev_interact := false
var _prev_attack := false
var _interact_pressed := false  # one-shot press flag (consumed by tasks)
var _attack_pressed := false

# --- LOOK-AT INTERACTION ---
var aimed: Interactable = null  # the interactable this player is currently looking at (or null)

# --- ITEMS / TOOLS ---
# Inventory flags (picked up in the world). A "tool" is held in-hand (flashlight/phone/cig);
# the keycard sits in your pocket; a capacitor is a two-handed carry that slows you.
var has_flashlight := false
var has_phone := false
var has_keycard := false
var cigs := 0
var held_tool := ""             # "", "flashlight", "phone", "cig" — cycles as you pick things up
var carrying: Node3D = null     # a carried capacitor model (set by the capacitor task)
# Melee (friendslop): a crowbar or a fish you can SWING to bonk teammates down.
var held_melee := "":           # "", "crowbar", "fish" — replicated so everyone sees + swings it
	set(v): held_melee = v; _rebuild_melee_vm()
var _melee_vm: Node3D           # the weapon viewmodel (held in front of you / by your hand)
var _swing := 0.0               # 0..1 swing animation phase (driven by the attack edge)
var _prev_attack_swing := false
var _melee_cd := 0.0            # server cooldown so one swing can't chain-down everyone
var flashlight_on := false
var net_flashlight := false     # replicated so teammates see your beam
var flashlight_battery := 1.0   # 0..1
var _flashlight: SpotLight3D
var _cig_timer := 0.0           # seconds the current cigarette stays lit
var _puff_t := 0.0              # smoke-puff cadence
var net_smoking := false        # replicated so teammates see your cig too
var _cig_ember: OmniLight3D
var _cig_tip_mat: StandardMaterial3D   # the burning cherry material (flickers)
var _world_cig: Node3D          # cig in the player's mouth (you, the mirror, and teammates see it)
# Config-driven feel (game.gd copies these from GameConfig at spawn; defaults keep solo sane).
var cig_calm_time := 7.0
var cig_stamina_restore := 1.0
var capacitor_carry_slow := 0.62
signal phone_thrown(origin: Vector3, dir: Vector3)   # game.gd spawns the projectile
signal picked_up(kind: String)                       # game.gd shows a "Picked up X" message
# Remote-player smoothing: owners replicate these; remotes lerp toward them.
var net_pos := Vector3.ZERO
var net_yaw := 0.0
var net_pitch := 0.0


func _enter_tree() -> void:
	# In multiplayer the node is named after its owning peer id (set by the spawner),
	# so authority is consistent on every peer. Solo keeps the default authority.
	if Net.is_active() and str(name).is_valid_int():
		set_multiplayer_authority(str(name).to_int())


func _ready() -> void:
	if tuning == null:
		tuning = MovementTuning.new()
	_local = (not Net.is_active()) or is_multiplayer_authority()
	_sprint_budget = tuning.sprint_max_time
	add_to_group("players")     # tasks find players via this group (server tasks see all)

	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0, tuning.eye_height, 0)
	add_child(_head)

	cam = Camera3D.new()
	cam.fov = tuning.fov
	cam.current = _local         # only YOUR camera is active
	cam.near = 0.05
	_head.add_child(cam)

	# Visible co-op body: a goofy big-eyed little guy whose mouth flaps to your voice.
	# Your OWN rig is hidden in first person — you only ever see TEAMMATES, which is
	# exactly where the eyes/mouth tell earns its keep ("who's talking?" with no UI).
	var hue := fmod(absf(float(str(name).hash())) * 0.0001, 1.0)   # stable per-player colour
	if character_scene == null:
		character_scene = load("res://actors/player/character.tscn")   # the original customizable potato guy
	_character = character_scene.instantiate() as PlayerCharacter
	_character.set_tint(Color.from_hsv(hue, 0.5, 0.85))
	add_child(_character)
	_body = _character
	if _local:
		# Don't draw our own body in our own view — but keep it on a layer that OTHER
		# cameras (the lobby MIRROR) can still see, so you can look at yourself.
		_character.set_first_person_layer()
		cam.cull_mask &= ~PlayerCharacter.SELF_LAYER_BIT

	_rebuild_melee_vm()         # build the weapon viewmodel if held_melee already synced in

	# Floating "revive me" prompt shown to everyone when this player is downed.
	_downed_label = Label3D.new()
	_downed_label.text = "REVIVE\n(hold E)"
	_downed_label.font_size = 96
	_downed_label.pixel_size = 0.008
	_downed_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_downed_label.modulate = Color(1.0, 0.3, 0.3)
	_downed_label.position = Vector3(0, 1.6, 0)
	_downed_label.visible = false
	add_child(_downed_label)

	# Headlamp points exactly where you look (SpotLight3D emits along -Z, like the camera).
	# It's only a DIM wash now — the handheld flashlight is the light you rely on (and lose).
	var lamp := SpotLight3D.new()
	lamp.light_color = Color(0.9, 0.93, 1.0)
	lamp.light_energy = headlamp_energy
	lamp.spot_range = headlamp_range
	lamp.spot_angle = headlamp_angle
	lamp.spot_attenuation = 1.4
	lamp.position = Vector3(0, -0.1, 0)
	cam.add_child(lamp)

	# Handheld flashlight: a tight bright cone, battery-limited, starts OFF. Built on EVERY copy
	# (lights are global) so teammates literally see your beam sweep the dark. Driven by
	# net_flashlight; only the owner tracks the battery.
	_flashlight = SpotLight3D.new()
	_flashlight.name = "Flashlight"
	_flashlight.light_color = Color(1.0, 0.97, 0.86)
	_flashlight.light_energy = 0.0
	_flashlight.spot_range = flashlight_range
	_flashlight.spot_angle = flashlight_angle
	_flashlight.spot_attenuation = 0.9
	_flashlight.spot_angle_attenuation = 0.4
	_flashlight.shadow_enabled = true
	_flashlight.position = Vector3(0.18, -0.18, 0.0)   # offset to the hand, not the eye
	cam.add_child(_flashlight)

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.height = 1.7
	cap.radius = 0.34
	col.shape = cap
	col.position = Vector3(0, 0.85, 0)
	add_child(col)

	collision_layer = 1          # player
	collision_mask = 2           # collide with walls/floors only
	net_pos = position           # seed so remote copies don't lerp in from the origin
	net_yaw = rotation.y
	# Floor/slope handling (editor-tunable) — smooth stair + ramp traversal.
	floor_snap_length = tuning.floor_snap_length
	floor_max_angle = deg_to_rad(tuning.floor_max_angle_deg)
	floor_stop_on_slope = tuning.floor_stop_on_slope

	_build_emote_sprite()       # world finger exists on every peer (others see it)
	_build_net_sync()
	if Net.is_active():
		var v := Voice.new()    # proximity voice: local captures mic, all play spatially
		v.name = "Voice"
		v.setup(_local)
		add_child(v)

	# Voice -> face: drive this body's mouth from the replicated amplitude so you can
	# tell who's talking with no UI. Runs on every copy; remotes read net_mouth.
	var face := VoiceFaceDriver.new()
	face.name = "FaceDriver"
	face.configure(_character,
		func(): return net_mouth,
		func(): return _local and VoiceManager.self_muted,
		func(): return _downed)
	add_child(face)
	if _local:
		# Screen overlays + mouse capture only for the player YOU control.
		_build_blink_overlay()
		_build_emote_pov()
		_build_world_cig()      # POV cigarette — only the local player sees it (mirror-excluded layer)
		_build_downed_overlay()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_downed_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 56
	add_child(layer)
	_downed_overlay = ColorRect.new()
	_downed_overlay.color = Color(0.5, 0.0, 0.0, 0.45)
	_downed_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_downed_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_downed_overlay.visible = false
	layer.add_child(_downed_overlay)
	var lbl := Label.new()
	lbl.text = "DOWNED — wait for a teammate to revive you"
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.85))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", 6)
	_downed_overlay.add_child(lbl)


## Replicate position, facing and emote-state from the owning peer to everyone else.
func _build_net_sync() -> void:
	if not Net.is_active():
		return
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"          # fixed name so the sync path matches on every peer
	var cfg := SceneReplicationConfig.new()
	cfg.add_property(NodePath(".:net_pos"))        # owner replicates; remotes lerp (smooth)
	cfg.add_property(NodePath(".:net_yaw"))
	cfg.add_property(NodePath(".:net_pitch"))      # vertical aim (for the gaze-freeze check)
	cfg.add_property(NodePath(".:net_emote"))
	cfg.add_property(NodePath(".:net_mouth"))      # voice amplitude -> remote mouth flap
	cfg.add_property(NodePath(".:interact_held"))  # server reads for revives + press edges
	cfg.add_property(NodePath(".:attack_held"))
	cfg.add_property(NodePath(".:net_flashlight"))  # teammates see your beam on/off
	cfg.add_property(NodePath(".:net_smoking"))     # teammates see your cigarette
	cfg.add_property(NodePath(".:held_melee"))      # which melee weapon you're holding (crowbar/fish)
	sync.replication_config = cfg
	sync.set_multiplayer_authority(get_multiplayer_authority())
	add_child(sync)


# --- BLINK SYSTEM START ------------------------------------------------------
## A full-screen black ColorRect on its own CanvasLayer. Alpha 0 = eyes open.
## We fade it in/out so the forced blink reads as an eye-shut, not a UI cut.
func _build_blink_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50             # above the danger vignette (1), below pause (100)
	add_child(layer)
	_blink_rect = ColorRect.new()
	_blink_rect.color = Color(0, 0, 0, 0)
	_blink_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blink_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_blink_rect)


func _update_blink(delta: float) -> void:
	if not blink_enabled:
		return
	# Look activity decays so a flick of the mouse only briefly counts as "active".
	_look_activity = maxf(0.0, _look_activity - delta * 1.5)

	if _blink_t >= 0.0:
		_advance_blink(delta)
		return
	if _recover_t > 0.0:
		_recover_t = maxf(0.0, _recover_t - delta)
		return

	# Camping (still + fixed gaze) drains fast; active coverage drains slow.
	var activity := clampf(maxf(_move_activity, _look_activity), 0.0, 1.0)
	var drain_mult := lerpf(stare_drain, move_drain, activity)
	_stamina -= (delta / blink_interval) * drain_mult
	if _stamina <= 0.0:
		_stamina = 0.0
		_blink_t = 0.0          # trigger the blink


func _advance_blink(delta: float) -> void:
	_blink_t += delta
	var half := blink_duration * 0.5
	var a: float
	if _blink_t < half:
		a = _blink_t / half                          # eyes closing
	else:
		a = 1.0 - clampf((_blink_t - half) / half, 0.0, 1.0)  # eyes opening
	_blink_rect.color.a = smoothstep(0.0, 1.0, a)
	if _blink_t >= blink_duration:
		_blink_t = -1.0
		_blink_rect.color.a = 0.0
		_stamina = 1.0
		_recover_t = blink_recovery
# --- BLINK SYSTEM END --------------------------------------------------------


# --- EMOTE / MEME SYSTEM START -----------------------------------------------
## HOLD Emote (F): YOU see a first-person POV finger on your screen; everyone ELSE
## sees a world-space billboard finger in front of you. A vine boom plays. No fade
## — both are visible exactly while the key is held.
func _build_emote_sprite() -> void:
	if emote_texture == null:
		emote_texture = load("res://assets/emotes/middlefinger.png")
	# World finger that OTHER players see (your own copy stays hidden — you get the POV).
	_emote_sprite = Sprite3D.new()
	_emote_sprite.texture = emote_texture
	_emote_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_emote_sprite.shaded = false
	_emote_sprite.double_sided = true
	_emote_sprite.no_depth_test = true
	_emote_sprite.pixel_size = emote_size
	_emote_sprite.position = Vector3(0, 1.7, -emote_distance)
	_emote_sprite.visible = false
	add_child(_emote_sprite)

	_emote_audio = AudioStreamPlayer.new()
	_emote_audio.stream = AudioGen.vine_boom()
	_emote_audio.volume_db = -4.0
	add_child(_emote_audio)


## First-person POV finger overlay — built for the LOCAL player only.
func _build_emote_pov() -> void:
	if pov_texture == null:
		pov_texture = load("res://assets/emotes/povmiddlefinger.png")
	var layer := CanvasLayer.new()
	layer.layer = 55
	add_child(layer)
	_emote_pov = TextureRect.new()
	_emote_pov.texture = pov_texture
	_emote_pov.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_emote_pov.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Smaller + tucked into the lower-right (was filling the whole screen). Anchored to the
	# bottom-right corner; the offsets size the box and push it down/right toward the corner.
	_emote_pov.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_emote_pov.flip_h = true
	_emote_pov.offset_left = -540
	_emote_pov.offset_top = -540
	_emote_pov.offset_right = 40            # nudge a touch past the right edge
	_emote_pov.offset_bottom = 50           # and a touch below the bottom edge
	_emote_pov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_emote_pov.visible = false
	layer.add_child(_emote_pov)


## Local player: read the key, drive both fingers + sound, and replicate net_emote.
## Remote player: just mirror the replicated net_emote on the world finger.
func _update_emote() -> void:
	if not _local:
		_emote_sprite.visible = net_emote
		return
	var held := Input.is_action_pressed("emote") and not input_blocked
	if held == _emote_held:
		return
	_emote_held = held
	net_emote = held                   # replicated to other peers (their copy shows the world finger)
	_emote_sprite.visible = false      # never draw our OWN world finger; we get the POV overlay
	if _emote_pov != null:
		_emote_pov.visible = held      # what you see
	if held and not AudioGen.is_headless():
		_emote_audio.play()
# --- EMOTE / MEME SYSTEM END -------------------------------------------------


func _process(delta: float) -> void:
	_update_input_edges()       # detect interact/attack presses from the synced held flags
	_update_emote()             # local drives it, remote mirrors the replicated flag
	_update_melee(delta)        # weapon swing visual (all copies) + server hit resolution
	if _local:
		_update_blink(delta)
	else:
		# Smoothly interpolate remote players toward their replicated transform (no jank).
		var t := clampf(delta * 16.0, 0.0, 1.0)
		# Waddle the rig by how far it's catching up = reads as walking, cheaply.
		if _character != null:
			_character.set_move(clampf(global_position.distance_to(net_pos) * 4.0, 0.0, 1.0))
		global_position = global_position.lerp(net_pos, t)
		rotation.y = lerp_angle(rotation.y, net_yaw, t)
		if _head != null:
			_head.rotation.x = lerp_angle(_head.rotation.x, net_pitch, t)


func _unhandled_input(event: InputEvent) -> void:
	if not _local or input_blocked:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := tuning.mouse_sensitivity * sens_multiplier
		rotate_y(-event.relative.x * sens)
		_pitch = clamp(_pitch - event.relative.y * sens, tuning.pitch_min, tuning.pitch_max)
		_head.rotation.x = _pitch
		# Sweeping the gaze counts as activity (slows the stamina drain).
		_look_activity = minf(1.0, _look_activity + event.relative.length() * 0.02)


# --- INTERACT / ATTACK (network-robust) -------------------------------------
## interact_held / attack_held are REPLICATED (set by the owner each frame). The
## SERVER detects a press as the rising edge of the synced value — so tasks work
## identically for the host AND every client, with no fragile per-press RPC.
func _update_input_edges() -> void:
	if interact_held and not _prev_interact:
		_interact_pressed = true
	_prev_interact = interact_held
	if attack_held and not _prev_attack:
		_attack_pressed = true
	_prev_attack = attack_held


## True ONCE per press; the first system to call it consumes the press.
func consume_interact() -> bool:
	if _interact_pressed:
		_interact_pressed = false
		return true
	return false


func consume_attack() -> bool:
	if _attack_pressed:
		_attack_pressed = false
		return true
	return false


## Owner publishes its transform for replication (remotes lerp toward these).
func _publish_net_transform() -> void:
	net_pos = global_position
	net_yaw = rotation.y
	net_pitch = _head.rotation.x


## Aim direction (forward), accounting for head pitch — used to throw/swing.
func aim_dir() -> Vector3:
	return -(_head.global_transform.basis.z).normalized()


## Eye/camera world position — origin of the aim & interaction rays.
func eye_pos() -> Vector3:
	return _head.global_position if _head != null else global_position + Vector3(0, 1.55, 0)


# ---- LOOK-AT INTERACTION ----------------------------------------------------
## Cast from the eye along the aim. Mask = walls (occlude) | interactables (closest hit wins, so a
## wall between you and a button blocks it). Runs on every copy: the local owner uses it for hover,
## the authority uses each player's `aimed` to drive task logic (buttons/levers/valves/pickups).
const INTERACT_RAY_MASK := 2 | (1 << 7)

func _update_aim() -> void:
	if _head == null:
		return
	var world := get_world_3d()
	if world == null:
		return
	var space := world.direct_space_state
	if space == null:
		return
	var from := eye_pos()
	var q := PhysicsRayQueryParameters3D.create(from, from + aim_dir() * interact_reach)
	q.collision_mask = INTERACT_RAY_MASK
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	var found: Interactable = null
	if hit.has("collider") and hit.collider is Interactable and (hit.collider as Interactable).enabled:
		found = hit.collider
	if found == aimed:
		return
	if _local and aimed != null and is_instance_valid(aimed):
		aimed.look_hover(false)
	aimed = found
	if _local and aimed != null:
		aimed.look_hover(true)


## True if THIS player is holding interact while looking at `piece` — the HOLD contract that
## levers / valves / cranks poll each frame.
func is_using(piece: Node) -> bool:
	return interact_held and not _downed and aimed == piece


# ---- ITEMS / TOOLS ----------------------------------------------------------
func _update_items(delta: float) -> void:
	# Flashlight: toggle (battery-gated), then drain while on / optionally trickle while off.
	if Input.is_action_just_pressed("flashlight") and has_flashlight and not input_blocked:
		if flashlight_battery > 0.02 or flashlight_on:
			flashlight_on = not flashlight_on
			if not AudioGen.is_headless():
				var s := load("res://assets/audio/sfx/button_flashlight_1.ogg")
				if s != null:
					var a := AudioStreamPlayer.new(); a.stream = s; a.volume_db = -6.0
					add_child(a); a.play(); a.finished.connect(a.queue_free)
	if flashlight_on:
		flashlight_battery = maxf(0.0, flashlight_battery - flashlight_drain * delta)
		if flashlight_battery <= 0.0:
			flashlight_on = false
	elif flashlight_recharge > 0.0:
		flashlight_battery = minf(1.0, flashlight_battery + flashlight_recharge * delta)
	net_flashlight = flashlight_on

	# Cellphone: one-time throw at the watcher (game.gd spawns + flies the projectile).
	if Input.is_action_just_pressed("throw_phone") and has_phone and not input_blocked:
		has_phone = false
		if held_tool == "phone":
			held_tool = ""
		phone_thrown.emit(eye_pos() + aim_dir() * 0.5, aim_dir())

	# Cigarette: PURELY COMEDIC. Always available (no pack needed), light up any time. You get a
	# cig in the corner of your view + drifting smoke. No gameplay effect — just vibes.
	if Input.is_action_just_pressed("smoke") and _cig_timer <= 0.0 and not input_blocked:
		_cig_timer = cig_calm_time                 # how long the cig lasts (reused as duration)
		net_smoking = true
		if not AudioGen.is_headless():
			var s := load("res://assets/audio/sfx/button_flashlight_2.ogg")
			if s != null:
				var a := AudioStreamPlayer.new(); a.stream = s; a.volume_db = -9.0; a.pitch_scale = 0.8
				add_child(a); a.play(); a.finished.connect(a.queue_free)
	if _cig_timer > 0.0:
		_cig_timer -= delta
		_puff_t -= delta
		if _puff_t <= 0.0:
			_puff_t = 0.7
			_emit_smoke_puff()
		# flicker the cherry (light + emission) so it smoulders instead of sitting flat
		var fl := 0.75 + 0.35 * sin(Time.get_ticks_msec() * 0.018) + randf() * 0.15
		if _cig_ember != null:
			_cig_ember.light_energy = 0.85 * fl
		if _cig_tip_mat != null:
			_cig_tip_mat.emission_energy_multiplier = 6.0 * fl
		if _cig_timer <= 0.0:
			net_smoking = false
	if _world_cig != null:
		_world_cig.visible = _cig_timer > 0.0    # POV cig (you)
	_set_char_smoking(_cig_timer > 0.0)          # body cig on the rig (mirror + teammates)


## Drive the beam on EVERY copy from net_flashlight (so teammates see your light), but never let
## a dead battery glow on the owner.
func _update_flashlight_visual() -> void:
	if _flashlight != null:
		var on := flashlight_on if _local else net_flashlight
		_flashlight.light_energy = flashlight_energy if on else 0.0
	# Remote smokers: show their BODY cig (on the rig) + drift the odd puff.
	if not _local:
		_set_char_smoking(net_smoking)
		if net_smoking:
			_puff_t -= get_physics_process_delta_time()
			if _puff_t <= 0.0:
				_puff_t = 0.9
				_emit_smoke_puff()


## Toggle the character rig's body cigarette (mirror + teammates). Safe if the rig has no such method.
func _set_char_smoking(on: bool) -> void:
	if _character != null and _character.has_method("set_smoking"):
		_character.set_smoking(on)


## Reach the rig's arms out (gang-beasts) while interacting. interact_held is replicated, so this
## works for remote copies too. Safe if the rig doesn't support it (e.g. the potato).
func _set_char_reach(v: float) -> void:
	if _character != null and _character.has_method("set_reach"):
		_character.set_reach(v)


# ---- CARRY (capacitor) ------------------------------------------------------
## The capacitor task hands us a model to lug; we float it in front of the chest and the carrier
## moves slowly with no sprint (see _physics_process). The task reads `carrying` to know who has it.
func grab_carry(node: Node3D) -> void:
	carrying = node

func drop_carry() -> Node3D:
	var n := carrying
	carrying = null
	return n

func _update_carry() -> void:
	if carrying == null or not is_instance_valid(carrying):
		return
	var fwd := -_head.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() > 0.01:
		fwd = fwd.normalized()
	var target := global_position + fwd * 0.7 + Vector3(0, 1.0, 0)
	carrying.global_position = carrying.global_position.lerp(target, 0.4)
	carrying.rotation.z = sin(Time.get_ticks_msec() * 0.004) * 0.12


# ---- blood pool (downed) ----------------------------------------------------
## A dark pool that spreads under a downed player and shrinks back on revive. (The full BloodPool
## drop-shader needs blood/height textures we don't ship; this captures the read cheaply.)
func _update_blood(downed: bool) -> void:
	if downed:
		if _blood == null:
			_blood = MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 1.0; cyl.bottom_radius = 1.0; cyl.height = 0.02
			_blood.mesh = cyl
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.18, 0.01, 0.01)
			m.roughness = 0.15
			m.metallic = 0.2
			_blood.material_override = m
			_blood.position = Vector3(0, 0.02, 0)
			_blood.scale = Vector3(0.05, 1, 0.05)
			add_child(_blood)
		var t := create_tween()
		t.tween_property(_blood, "scale", Vector3(1.0, 1.0, 1.4), 3.0)
	elif _blood != null:
		var b := _blood
		_blood = null
		var t := create_tween()
		t.tween_property(b, "scale", Vector3(0.05, 1, 0.05), 0.6)
		t.tween_callback(b.queue_free)


# ---- cigarette (comedic) ----------------------------------------------------
## The real cig mesh sticking out of the player's mouth — visible to YOU (in your lower view), in
## the MIRROR, and to teammates. Comedic. Lives at mouth height so it reads as "fag in mouth".
func _build_world_cig() -> void:
	_world_cig = Node3D.new()
	_world_cig.name = "WorldCig"
	var ps := load("res://assets/psx/Small Props/cig_1.glb") as PackedScene
	if ps != null:
		var n := ps.instantiate() as Node3D
		n.scale = Vector3.ONE * 1.3
		n.rotation_degrees = Vector3(0, -90, 0)        # FILTER end into the mouth, LIT end faces out
		_world_cig.add_child(n)
	# Parented to the HEAD so it tracks your view (looking up/down keeps it in the same mouth spot,
	# instead of seeing the whole thing when you look down / losing it when you look up).
	_world_cig.position = Vector3(0.05, -0.16, -0.22)  # head-local: just below + in front of the eyes
	_world_cig.rotation_degrees = Vector3(-9, 0, 0)    # droop the lit end DOWN (natural hang)
	_world_cig.visible = false
	_head.add_child(_world_cig)
	# POV-ONLY: put the mesh on the layer the MIRROR excludes (1<<18), so your own camera shows this
	# POV cig but the mirror shows the BODY cig (cig_12 on the rig) instead — no double.
	for mi in _world_cig.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers = 1 << 18
	# The lit end is just a soft flickering light now (no mesh cherry/cylinder).
	_cig_ember = OmniLight3D.new()
	_cig_ember.light_color = Color(1.0, 0.45, 0.13)
	_cig_ember.light_energy = 0.8
	_cig_ember.omni_range = 0.4
	_cig_ember.omni_attenuation = 2.0
	_cig_ember.position = Vector3(0, 0, -0.14)
	_world_cig.add_child(_cig_ember)


## A drifting smoke puff at the cig — rises and fades. Comedic, cheap, no particle system.
func _emit_smoke_puff() -> void:
	if AudioGen.is_headless() or cam == null:
		return
	var puff := Sprite3D.new()
	puff.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	puff.modulate = Color(0.8, 0.8, 0.82, 0.35)
	puff.pixel_size = 0.004
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	puff.texture = ImageTexture.create_from_image(img)
	puff.global_position = (_world_cig.global_position if _world_cig != null else global_position + Vector3(0, 1.3, 0))
	get_tree().current_scene.add_child(puff)
	var t := create_tween().set_parallel(true)
	t.tween_property(puff, "global_position", puff.global_position + Vector3(randf_range(-0.1, 0.1), 0.6, 0), 1.6)
	t.tween_property(puff, "scale", Vector3.ONE * 5.0, 1.6)
	t.tween_property(puff, "modulate:a", 0.0, 1.6)
	t.chain().tween_callback(puff.queue_free)


# ---- inventory grants (called by world pickups) -----------------------------
func give_item(kind: String) -> bool:
	var prev_melee := held_melee               # what weapon (if any) we held BEFORE this grab
	match kind:
		"flashlight":
			if has_flashlight: return false
			has_flashlight = true; held_tool = "flashlight"; flashlight_battery = 1.0
		"phone":
			if has_phone: return false
			has_phone = true
		"keycard":
			has_keycard = true
		"cigs":
			cigs += 3                          # a fresh pack
		"battery":
			flashlight_battery = 1.0
		"crowbar", "fish":
			held_melee = kind                  # equip a swingable weapon (replicated)
		_:
			return false
	# Your hands are full: grabbing anything ELSE DROPS the weapon you were holding (so you can
	# swap crowbar<->fish, or set a weapon down to take a tool) — it lands as a fresh world pickup.
	if prev_melee != "" and prev_melee != kind:
		if kind != "crowbar" and kind != "fish":
			held_melee = ""                    # took a tool -> weapon hand is now empty
		_drop_weapon(prev_melee, global_position + aim_dir() * 0.9 + Vector3(0, 0.4, 0))
	picked_up.emit(kind)
	return true


## Drop a weapon back into the world as a grabbable pickup (replicated to everyone).
func _drop_weapon(weapon: String, pos: Vector3) -> void:
	if weapon == "":
		return
	if Net.is_active():
		_spawn_drop.rpc(weapon, pos)
	else:
		_do_spawn_drop(weapon, pos)


@rpc("any_peer", "call_local", "reliable")
func _spawn_drop(weapon: String, pos: Vector3) -> void:
	_do_spawn_drop(weapon, pos)


func _do_spawn_drop(weapon: String, pos: Vector3) -> void:
	var model: String = MELEE_MODELS.get(weapon, "")
	if model == "":
		return
	var pk: Node = load("res://scenes/item_pickup.tscn").instantiate()
	pk.set("kind", weapon)
	pk.set("model_path", model)
	pk.set("model_scale", 2.2 if weapon == "fish" else 1.6)
	pk.set("model_euler", Vector3(0, 0, 90))   # stand it up (long axis is +X)
	pk.position = pos
	var host := get_tree().current_scene
	if host != null:
		host.add_child(pk)


# ---- MELEE: swing a crowbar / fish to bonk teammates down (friendslop) -------
## Build the weapon viewmodel in your hand (a child of the head so it tracks aim).
## On the DEFAULT render layer, so YOU see it and so do teammates / the mirror.
func _rebuild_melee_vm() -> void:
	if _melee_vm != null:
		_melee_vm.queue_free()
		_melee_vm = null
	if held_melee == "" or _head == null:
		return
	var path: String = MELEE_MODELS.get(held_melee, "")
	if path == "":
		return
	var ps := load(path) as PackedScene
	if ps == null:
		return
	var holder := Node3D.new()
	holder.name = "MeleeVM"
	holder.position = Vector3(0.28, -0.36, -0.4)    # held bottom-right, CLOSE to the camera
	holder.rotation = Vector3(0.0, -0.3, 0.0)       # swing animates rotation.x; this is the resting yaw
	_head.add_child(holder)
	var m := ps.instantiate() as Node3D
	# The crowbar/fish meshes are long on +X (lying down) -> rotate +90 about Z so the long axis
	# points STRAIGHT UP in your fist (like a club), with a slight forward lean.
	m.scale = Vector3.ONE * (0.9 if held_melee == "fish" else 0.55)
	m.rotation_degrees = Vector3(10, 0, 90)
	m.position = Vector3(0, 0.22, 0)                 # raise it up out of the hand
	holder.add_child(m)
	_melee_vm = holder


## Runs on every copy: animate the swing from the synced attack edge; on the SERVER,
## resolve a hit (down the player you swung at).
func _update_melee(delta: float) -> void:
	if _melee_cd > 0.0:
		_melee_cd -= delta
	# Visual swing — trigger on the rising edge of attack_held (synced => all copies swing).
	if held_melee != "" and attack_held and not _prev_attack_swing:
		_swing = 1.0
	_prev_attack_swing = attack_held
	if _melee_vm != null:
		_swing = maxf(0.0, _swing - delta * 4.0)
		var arc := sin(_swing * PI)                 # 0 -> up&over -> 0
		_melee_vm.rotation.x = -arc * 1.8           # whack down
		_melee_vm.position.z = -0.4 - arc * 0.22    # rest close; pull back a touch mid-swing

	# Server resolves the hit using the synced attack press + aim.
	if held_melee != "" and Net.is_authority() and _melee_cd <= 0.0 and consume_attack():
		_melee_cd = melee_cooldown
		var victim := _melee_target()
		if victim != null:
			victim.down()
		_melee_fx.rpc(global_position + aim_dir() * 1.2, victim != null)


## Nearest LIVING other player in front of us within range — the one we bonk.
func _melee_target() -> WPlayer:
	var best: WPlayer = null
	var bd := melee_range
	var fwd := aim_dir()
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as WPlayer
		if p == null or p == self or p._downed:
			continue
		var to: Vector3 = p.global_position - global_position
		var d := to.length()
		if d > bd or d < 0.05:
			continue
		if fwd.dot(to / d) < melee_cone:
			continue
		bd = d
		best = p
	return best


@rpc("any_peer", "call_local", "unreliable")
func _melee_fx(pos: Vector3, hit: bool) -> void:
	if AudioGen.is_headless():
		return
	var path := "res://assets/audio/sfx/button_15.ogg"      # a dull thwack; fish = sloppier later
	var s := load(path)
	if s == null:
		return
	var a := AudioStreamPlayer3D.new()
	a.stream = s
	a.volume_db = 2.0 if hit else -6.0
	a.pitch_scale = 0.7 if held_melee == "crowbar" else 1.3
	get_tree().current_scene.add_child(a)
	a.global_position = pos
	a.play()
	a.finished.connect(a.queue_free)


# ---- HUD meter readouts (0..1) ---------------------------------------------
func sprint_ratio() -> float:
	return clampf(_sprint_budget / maxf(tuning.sprint_max_time, 0.01), 0.0, 1.0)

func stamina_ratio() -> float:
	return clampf(_stamina, 0.0, 1.0)

func is_downed() -> bool:
	return _downed


## Server/solo calls down()/revive(); rpc broadcasts the state to every peer.
func down() -> void:
	if Net.is_active():
		_rpc_downed.rpc(true)
	else:
		_set_downed(true)


func revive() -> void:
	if Net.is_active():
		_rpc_downed.rpc(false)
	else:
		_set_downed(false)


@rpc("any_peer", "call_local", "reliable")
func _rpc_downed(v: bool) -> void:
	_set_downed(v)


## Server (lobby) calls this when you grab/drop the megaphone; replicated to all so
## everyone hears your boosted voice.
func set_megaphone(v: bool) -> void:
	if Net.is_active():
		_rpc_megaphone.rpc(v)
	else:
		megaphone = v


@rpc("any_peer", "call_local", "reliable")
func _rpc_megaphone(v: bool) -> void:
	megaphone = v


var _blood: MeshInstance3D

func _set_downed(v: bool) -> void:
	_downed = v
	net_downed = v
	_update_blood(v)
	if _body != null:
		_body.rotation.z = PI * 0.5 if v else 0.0     # tip over when downed
		_body.position.y = 0.25 if v else 0.0
	if _character != null:
		_character.set_blank(v)                       # dead-eyes when downed
	if _downed_label != null:
		_downed_label.visible = v
	if _local:
		_head.position.y = (tuning.eye_height * 0.35) if v else tuning.eye_height
		if _downed_overlay != null:
			_downed_overlay.visible = v


func _physics_process(delta: float) -> void:
	_update_aim()               # which interactable am I looking at? (authority needs this per-player)
	_update_flashlight_visual() # drive the beam on every copy from net_flashlight
	_set_char_reach(1.0 if interact_held else 0.0)   # gang-beasts arms reach out while interacting
	if not _local:
		return                  # remote players are positioned by the synchronizer
	interact_held = Input.is_action_pressed("interact") and not input_blocked
	attack_held = Input.is_action_pressed("attack") and not input_blocked
	# Publish our voice amplitude (0 while self-muted) so teammates' copies flap our mouth.
	net_mouth = 0.0 if VoiceManager.self_muted else VoiceManager.mic_level
	_publish_net_transform()
	_update_items(delta)        # flashlight battery, phone throw, cigarette
	_update_carry()             # a carried capacitor floats in front of you

	# Downed OR paused (local overlay): you can't move; just settle under gravity.
	if _downed or input_blocked:
		interact_held = false
		attack_held = false
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y -= tuning.gravity * delta if not is_on_floor() else 0.0
		move_and_slide()
		return

	var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	_move_activity = iv.length()
	var has_input := iv.length() > 0.1

	# --- Sprint (panic burst): a stamina-gated speed boost that *widens* your FOV,
	# so you move faster but cover worse — a real tradeoff, not free speed.
	# Lugging a capacitor disables the sprint (your hands are full and it's heavy).
	var sprinting := false
	if Input.is_action_pressed("sprint") and has_input and carrying == null:
		var threshold := 0.0 if _was_sprinting else tuning.sprint_min_to_start
		if _sprint_budget > threshold:
			sprinting = true
			_sprint_budget = maxf(0.0, _sprint_budget - delta)
	if not sprinting:
		_sprint_budget = minf(tuning.sprint_max_time,
			_sprint_budget + tuning.sprint_recharge * delta)
	_was_sprinting = sprinting

	var speed := tuning.walk_speed * (tuning.sprint_multiplier if sprinting else 1.0)
	if carrying != null:
		speed *= capacitor_carry_slow      # heavy maintenance haul — you're slow and exposed
	var dir := (transform.basis * Vector3(iv.x, 0.0, iv.y)).normalized()
	var target := dir * speed
	# Asymmetric accel/decel gives a touch of weight: snappy to start, softer to stop.
	var rate := tuning.acceleration if has_input else tuning.deceleration
	velocity.x = move_toward(velocity.x, target.x, rate * delta)
	velocity.z = move_toward(velocity.z, target.z, rate * delta)
	# Gravity so stairs / the second floor / ledges work. (Stairs are a smooth ramp
	# collider, so plain move_and_slide climbs them — no step-assist hacks needed.)
	if is_on_floor():
		velocity.y = -2.0          # small downward bias keeps us snapped to slopes
	else:
		velocity.y -= tuning.gravity * delta
	move_and_slide()

	# Sprint widens the FOV slightly (you cover a worse cone while bursting).
	var want_fov := tuning.fov + (tuning.sprint_fov_add if sprinting else 0.0)
	cam.fov = lerpf(cam.fov, want_fov, delta * 8.0)

	_update_camera_motion(delta, iv, speed, sprinting)


func _update_camera_motion(delta: float, iv: Vector2, speed: float, sprinting: bool) -> void:
	_breath_t += delta
	# Low blink-stamina makes the view breathe harder — movement feeds the dread.
	var strain := 1.0 + (1.0 - _stamina) * 0.4
	if iv.length() > 0.1:
		var freq := tuning.bob_frequency * (speed / maxf(tuning.walk_speed, 0.1))
		_bob_t += delta * freq * TAU
		var amp := tuning.bob_amplitude * strain * (1.3 if sprinting else 1.0)
		_head.position.y = tuning.eye_height + sin(_bob_t) * amp
	else:
		var idle := tuning.eye_height + sin(_breath_t * 1.6) * tuning.breath_amplitude * strain
		_head.position.y = lerp(_head.position.y, idle, delta * 6.0)
