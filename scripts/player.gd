class_name WPlayer
extends CharacterBody3D
## First-person courier. Mouse-look + WASD (remappable via the Input Map). Exposes
## its Camera3D so watchers can test whether they're being looked at. No weapons —
## your GAZE is the only tool. You also cannot keep your eyes open forever.
##
## Movement feel lives in an editor-editable MovementTuning Resource (see `tuning`).
## Blink/headlamp/emote knobs are @export-ed so everything is editable in-editor.

## The visible co-op body. EXPORTED so you can swap the whole character scene in player.tscn. Defaults
## (set at runtime, see _ready) to the low-poly BLOB (actors/player_models/player_blob_black.tscn, a
## PlayerModelView). Swap to another player_blob_<colour>.tscn variant in the Inspector per player.
@export var character_scene: PackedScene

# All movement feel is in this Resource — assign default_movement.tres in the
# Inspector, or drop in another profile. Falls back to defaults if left empty.
@export var tuning: MovementTuning

@export_group("Headlamp")
@export var headlamp_energy := 0.0     ## OFF by default — it lit up the mirror/teammates and looked weird. The handheld FLASHLIGHT is the only player light now. Set >0 to bring back a faint wash.
@export var headlamp_range := 12.0
@export var headlamp_angle := 50.0

@export_group("Jump / crouch")
@export var jump_force := 4.6           ## upward velocity on jump (Space)
@export var crouch_eye_factor := 0.55   ## camera drops to this fraction of eye height when crouched
@export var crouch_speed_factor := 0.55 ## move this much slower while crouched
@export var crouch_lerp := 16.0         ## how fast you duck / stand (snappy, not laggy)

@export_group("Interaction")
@export var interact_reach := 3.2      ## how far the look-at aim-ray reaches for buttons/levers/items

@export_group("Flashlight (tool)")
@export var flashlight_energy := 6.0
@export var flashlight_range := 24.0
@export var flashlight_angle := 26.0   ## tight cone — a real torch
@export var flashlight_drain := 0.018  ## battery/sec while ON (game.gd overrides from GameConfig)
@export var flashlight_recharge := 0.0 ## battery/sec while OFF

@export_group("Phone flash (Watcher stun tool — NOT throwable)")
@export var phone_max_charges := 3        ## flashes before you need a battery
@export var phone_flash_range := 16.0     ## metres the flash reaches
@export var phone_flash_angle := 28.0     ## half-cone degrees you must be aiming within
@export var phone_flash_cooldown := 4.0   ## seconds between flashes
@export var phone_stun_duration := 3.0    ## seconds it freezes the Watcher
@export var phone_stun_late_mult := 0.6   ## stun shortened this much while the power's out (bolder Watcher)

@export_group("Blink / stamina")
@export var blink_enabled := true      ## off for the lobby (relaxed, full-vision space)
## You can't stare forever: a meter drains toward a forced blink, FASTER while you
## stand still and camp one angle, slower while you reposition/sweep.
@export var blink_interval := 4.0      ## seconds of stare-budget at full (camping) drain
@export var blink_duration := 0.18     ## eyes-shut time (fade to black and back)
@export var blink_recovery := 0.4      ## grace after a blink before draining resumes
@export var stare_drain := 1.0         ## drain multiplier while still + holding an angle
@export var move_drain := 0.4          ## drain multiplier while moving / sweeping

@export_group("Ladder climb")
@export var ladder_climb_speed := 3.2      ## up/down speed while inside a ladder's ClimbArea
@export var ladder_stand_dist := 0.55      ## how far in front of the rungs you're held while climbing

@export_group("Carry chaos (impact drop)")
## A hard impact while carrying can knock the cargo out of your hands — chance, not constant. Sprinting
## + heavy/fragile cargo raise it; a short grace after grabbing keeps tiny bumps from instantly dropping.
@export var min_impact_speed_for_drop := 4.0
@export var base_drop_chance := 0.06
@export var sprint_drop_bonus := 0.14
@export var fragile_drop_bonus := 0.10
@export var max_drop_chance := 0.7
@export var pickup_drop_grace_ms := 600

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
var _crouch_t := 0.0            # 0 standing .. 1 crouched (smoothed)
var net_crouch := 0.0          # replicated so teammates/mirror see you crouch
var _col: CollisionShape3D     # body capsule (shrunk while crouching)
var _capsule: CapsuleShape3D
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

# --- STAIRS / FALL SAFETY ---
@export_group("Stairs / safety")
@export var step_height := 0.45     ## auto-climb steps/curbs up to this tall (CharacterBody3D won't on its own)
@export var fall_limit := -14.0     ## fall below this Y -> respawn at the last safe spot (anti-softlock)
var _last_safe := Vector3.ZERO
var _safe_t := 0.0

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
var _ladder: Node = null        # the Ladder whose ClimbArea we're inside (free-physics climb)
var _grab_time_ms := 0          # when the current held_item was grabbed (impact-drop grace)
var _body: Node3D               # visible body so teammates can see you (the rig)
var _character: PlayerCharacter # the expressive rig (big eyes + voice mouth)

var _downed_label: Label3D      # "REVIVE (hold E)" prompt over a downed player
var _downed_overlay: ColorRect
var attack_held := false        # replicated: attack button down (swing)
var throw_held := false          # replicated: throw button (Q) down -> charge + throw a held item
var _knockback := Vector3.ZERO   # decaying shove from a bonk/thrown item (funny, non-lethal)
var _stagger := 0.0              # brief loss-of-control after a hit
var holding := false            # replicated: are we carrying something (visual hint)
var _prev_interact := false
var _prev_attack := false
## Press EDGES as short-lived timestamps (ms), NOT sticky booleans. A press is consumable for a
## brief window then EXPIRES on its own — so an un-consumed tap can't latch and later auto-trigger a
## pickup/task the instant you look at it (that was the "grabbed it without pressing E" bug). -1 = none.
var _interact_press_t := -1.0
var _attack_press_t := -1.0
const PRESS_WINDOW_MS := 120.0

# --- LOOK-AT INTERACTION ---
var aimed: Interactable = null  # the interactable this player is currently looking at (or null)

# --- TACTILE GESTURE (levers/valves) ---
# While holding E aimed at a PULL/ROTATE interactable, the local owner diverts mouse motion into this
# monotonic accumulator (look is suppressed) and replicates it; the authority task reads the delta.
var tactile_input := 0.0
var _prev_tactile := Vector2.ZERO
var _rot_cursor := Vector2.ZERO     # virtual cursor for ROTATE — real circling accumulates, shaking cancels
var _rot_angle := 0.0
var _rot_started := false
# Button POKE: the local hand jabs out to a pressed button for a moment (point pose).
var _poke_start := -1.0
var _poke_dur := 0.2
var _poke_point := Vector3.ZERO
var _poke_left := false   # which hand reaches — randomised per press

# --- ITEMS / TOOLS ---
# Inventory flags (picked up in the world). A "tool" is held in-hand (flashlight/phone/cig);
# the keycard sits in your pocket; a capacitor is a two-handed carry that slows you.
var has_flashlight := false
var has_phone := false
var phone_charges := 0          # flash charges remaining (refilled by a battery)
var _phone_cd := 0.0            # flash cooldown timer
var has_keycard := false
var cigs := 0
var held_tool := ""             # "", "flashlight", "phone", "cig" — cycles as you pick things up
var carrying: Node3D = null     # a carried capacitor model (set by the capacitor task)
var held_item: PhysicsItem = null   # a grabbed physics toy (fish/crowbar); the item drives itself
var aimed_item: PhysicsItem = null  # the grabbable item you're looking at (for the HUD pickup prompt)
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
		character_scene = load("res://actors/player_models/player_blob_black.tscn")  # low-poly blob (default body)
	_character = character_scene.instantiate() as PlayerCharacter
	_character.set_tint(Color.from_hsv(hue, 0.5, 0.85))
	add_child(_character)
	_body = _character
	if _local:
		# Don't draw our own body in our own view — but keep it on a layer that OTHER
		# cameras (the lobby MIRROR) can still see, so you can look at yourself.
		_character.set_first_person_layer()
		cam.cull_mask &= ~PlayerCharacter.SELF_LAYER_BIT
		# BUT we DO want to see our own hands (Gambling-With-Friends style) — pull them back onto a
		# visible layer + switch them to a camera-relative viewmodel pose. Done AFTER the self-layer
		# pass above so it isn't clobbered.
		if _character.has_method("enable_first_person_hands"):
			_character.enable_first_person_hands(cam)
		_apply_local_customization()    # carry the lobby-mirror look (body/hands/outline/face) onto me

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

	# Headlamp: OFF by default (it washed the mirror / teammates and read as the player "glowing").
	# Only built if you dial headlamp_energy back up. The handheld flashlight is the real light now.
	if headlamp_energy > 0.0:
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
	# Softer cone edge (gentle vignette at the rim) so the beam doesn't read as a hard disc.
	_flashlight.spot_angle_attenuation = 1.0
	# NO shadows: the FP hands sit right at the light origin and throw huge ugly shadows across the
	# beam. A handheld torch viewmodel is the classic case where shadow-casting hurts more than helps.
	_flashlight.shadow_enabled = false
	_flashlight.position = Vector3(0.18, -0.18, 0.0)   # offset to the hand, not the eye
	cam.add_child(_flashlight)

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.height = 1.7
	cap.radius = 0.34
	col.shape = cap
	col.position = Vector3(0, 0.85, 0)
	add_child(col)
	_col = col
	_capsule = cap

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


# ---- customization (lobby mirror) -------------------------------------------
## Replicated so teammates see your blob colours. Face paint is sent separately (compressed PNG via
## RPC on apply / spawn) — never per stroke. See _apply_local_customization / receive_face_png.
var net_body_color := Color(0.12, 0.12, 0.14)
var net_outline_color := Color(0.04, 0.04, 0.05)
var _remote_look_applied := Color(0, 0, 0, 0)   # sentinel so remotes only re-apply on change


## LOCAL owner: push the PlayerCustomization look onto my model + keep it live while I edit at the
## lobby mirror, and replicate the colours. Face paint is broadcast as a PNG (deferred) so late peers
## / the bunker scene get it without per-stroke spam.
func _apply_local_customization() -> void:
	if not _local or _character == null:
		return
	PlayerCustomization.apply_to(_character)
	net_body_color = PlayerCustomization.body_color
	net_outline_color = PlayerCustomization.outline_color
	if not PlayerCustomization.changed.is_connected(_on_custom_changed):
		PlayerCustomization.changed.connect(_on_custom_changed)
	if Net.is_active():
		broadcast_face.call_deferred()


func _on_custom_changed() -> void:
	if not _local or _character == null:
		return
	PlayerCustomization.apply_to(_character)
	net_body_color = PlayerCustomization.body_color
	net_outline_color = PlayerCustomization.outline_color


## Call when the player finishes painting (UI "Apply") — send the face image once to everyone.
func broadcast_face() -> void:
	if not _local or not Net.is_active():
		return
	receive_face_png.rpc(PlayerCustomization.face_png())


@rpc("any_peer", "call_remote", "reliable")
func receive_face_png(bytes: PackedByteArray) -> void:
	if _character == null or not _character.has_method("set_face_texture"):
		return
	var img := Image.new()
	if bytes.is_empty() or img.load_png_from_buffer(bytes) != OK:
		return
	_character.set_face_texture(ImageTexture.create_from_image(img))


## REMOTE copy: re-apply replicated colours only when they actually change (cheap idle).
func _apply_remote_look() -> void:
	if net_body_color == _remote_look_applied:
		return
	_remote_look_applied = net_body_color
	if _character.has_method("set_player_color"):
		_character.set_player_color(net_body_color)
	if "outline_color" in _character:
		_character.outline_color = net_outline_color


func _exit_tree() -> void:
	if PlayerCustomization.changed.is_connected(_on_custom_changed):
		PlayerCustomization.changed.disconnect(_on_custom_changed)


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
	cfg.add_property(NodePath(".:tactile_input"))  # server reads the gesture delta for tactile tasks
	cfg.add_property(NodePath(".:attack_held"))
	cfg.add_property(NodePath(".:throw_held"))      # server reads for the held-item throw charge
	cfg.add_property(NodePath(".:net_crouch"))      # teammates/mirror see you crouch
	cfg.add_property(NodePath(".:net_flashlight"))  # teammates see your beam on/off
	cfg.add_property(NodePath(".:net_smoking"))     # teammates see your cigarette
	cfg.add_property(NodePath(".:net_body_color"))  # customization: blob + hand colour
	cfg.add_property(NodePath(".:net_outline_color"))
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
	if _local:
		_update_blink(delta)
	else:
		# Smoothly interpolate remote players toward their replicated transform (no jank).
		var t := clampf(delta * 16.0, 0.0, 1.0)
		# Waddle the rig by how far it's catching up = reads as walking, cheaply.
		if _character != null:
			_apply_remote_look()                   # pick up replicated body/outline colour changes
			_character.set_move(clampf(global_position.distance_to(net_pos) * 4.0, 0.0, 1.0))
			_character.set_look_pitch(net_pitch)   # remotes tilt their head with their aim
			_character.set_crouch(net_crouch)      # remotes show their crouch
			if not net_downed:      # don't fight the tip-over rotation while a remote is downed
				var rl := global_transform.basis.inverse() * (net_pos - global_position)
				rl.y = 0.0
				_character.set_movement_lean(rl * 8.0, delta)   # remotes lean from their catch-up direction
		global_position = global_position.lerp(net_pos, t)
		rotation.y = lerp_angle(rotation.y, net_yaw, t)
		if _head != null:
			_head.rotation.x = lerp_angle(_head.rotation.x, net_pitch, t)


func _unhandled_input(event: InputEvent) -> void:
	if not _local or input_blocked:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel: Vector2 = event.relative
		# Tactile gesture? Divert the mouse into the lever/valve and DON'T move the camera.
		var kind := _tactile_kind()
		if kind == Interactable.Kind.PULL:
			tactile_input += maxf(0.0, rel.y) * 0.01            # mouse is fully committed to heaving the lever
			return
		elif kind == Interactable.Kind.ROTATE:
			# A virtual cursor integrates the mouse; we add the SIGNED change of its angle. Real circling
			# rotates the cursor steadily (accumulates); a back-and-forth shake just oscillates it (≈0).
			_rot_cursor = (_rot_cursor + rel * 0.06).limit_length(48.0)
			if _rot_cursor.length() > 10.0:
				var a := _rot_cursor.angle()
				if _rot_started:
					tactile_input += angle_difference(_rot_angle, a)
				_rot_angle = a
				_rot_started = true
			return
		_prev_tactile = Vector2.ZERO
		_rot_started = false
		_rot_cursor = Vector2.ZERO
		var sens := tuning.mouse_sensitivity * sens_multiplier
		rotate_y(-rel.x * sens)
		_pitch = clamp(_pitch - rel.y * sens, tuning.pitch_min, tuning.pitch_max)
		_head.rotation.x = _pitch
		# Sweeping the gaze counts as activity (slows the stamina drain).
		_look_activity = minf(1.0, _look_activity + rel.length() * 0.02)


# --- INTERACT / ATTACK (network-robust) -------------------------------------
## interact_held / attack_held are REPLICATED (set by the owner each frame). The
## SERVER detects a press as the rising edge of the synced value — so tasks work
## identically for the host AND every client, with no fragile per-press RPC.
func _update_input_edges() -> void:
	var now := float(Time.get_ticks_msec())
	if interact_held and not _prev_interact:
		_interact_press_t = now                       # fresh press: open the consume window
	elif _interact_press_t >= 0.0 and now - _interact_press_t > PRESS_WINDOW_MS:
		_interact_press_t = -1.0                      # expire an un-consumed press (no sticky latch)
	_prev_interact = interact_held
	if attack_held and not _prev_attack:
		_attack_press_t = now
	elif _attack_press_t >= 0.0 and now - _attack_press_t > PRESS_WINDOW_MS:
		_attack_press_t = -1.0
	_prev_attack = attack_held


## True ONCE per press; the first system to call it consumes the press.
func consume_interact() -> bool:
	if _interact_press_t >= 0.0 and float(Time.get_ticks_msec()) - _interact_press_t <= PRESS_WINDOW_MS:
		_interact_press_t = -1.0          # one consumer wins, then the press is spent
		return true
	return false


func consume_attack() -> bool:
	if _attack_press_t >= 0.0 and float(Time.get_ticks_msec()) - _attack_press_t <= PRESS_WINDOW_MS:
		_attack_press_t = -1.0
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


## The gesture style of what we're actively using right now (PRESS if none) — drives mouse capture.
func _tactile_kind() -> int:
	if interact_held and not _downed and aimed != null and is_instance_valid(aimed) and aimed.enabled:
		return aimed.interaction_type
	return Interactable.Kind.PRESS


## The node the hand should reach + grip while gesturing — the moving handle/rim if the piece exposes
## one (so the hand FOLLOWS the lever/valve), else the piece body. Null when not gesturing.
func tactile_target() -> Node3D:
	if _tactile_kind() != Interactable.Kind.PRESS and aimed != null:
		return aimed.grab_point if aimed.grab_point != null and is_instance_valid(aimed.grab_point) else aimed
	return null


## The secondary prompt line ("PULL MOUSE DOWN" / "ROTATE MOUSE") while gesturing, else "".
func tactile_hold_prompt() -> String:
	if _tactile_kind() != Interactable.Kind.PRESS and aimed != null:
		return aimed.hold_prompt
	return ""


## Is the local hand mid-poke (jabbing a pressed button)? + the jab progress (0=rest, .5=touch, 1=back).
func poke_active() -> bool:
	return _poke_start >= 0.0 and (Time.get_ticks_msec() / 1000.0 - _poke_start) < _poke_dur
func poke_phase() -> float:
	return clampf((Time.get_ticks_msec() / 1000.0 - _poke_start) / _poke_dur, 0.0, 1.0)
func poke_point() -> Vector3:
	return _poke_point
func poke_is_left() -> bool:
	return _poke_left


## The grabbable physics item you're MOST DIRECTLY looking at — the single source of truth for both
## the HUD "[E] PICK UP" prompt AND the actual grab (the item only grabs if it == this). We rank by
## crosshair ALIGNMENT (highest dot = most centred), not raw distance, so an item off to the side
## never beats the one under your reticle; distance is only a gentle tiebreak between equally-aimed
## items. Runs on the local owner (HUD) and on the authority (so it drives grabs for every player).
func _update_aimed_item() -> void:
	aimed_item = null
	if held_item != null:
		return
	var dir := aim_dir()
	var eye := eye_pos()
	var best_score := -1.0
	for n in get_tree().get_nodes_in_group("phys_items"):
		var it := n as PhysicsItem
		if it == null or it.held_by != null:
			continue
		var to := it.global_position - eye
		var d := to.length()
		if d > it.grab_range or d < 0.05:
			continue
		var align := dir.dot(to / d)
		if align < 0.92:                   # must be near the crosshair (~23° cone) — no peripheral grabs
			continue
		var score := align - d * 0.04      # alignment dominates; nearer wins only on a near-tie
		if score > best_score:
			best_score = score
			aimed_item = it


# ---- ITEMS / TOOLS ----------------------------------------------------------
func _update_items(delta: float) -> void:
	# Flashlight: toggle (battery-gated), then drain while on / optionally trickle while off.
	# HAND OCCUPANCY: the torch is a one-hand tool — you can't hold it while your hands are full
	# with a physics item or a two-handed carry. Toggling on is blocked, and grabbing something
	# while it's on snaps it off (no impossible "torch + crowbar + valve" overlaps).
	if Input.is_action_just_pressed("flashlight") and has_flashlight and not input_blocked:
		if held_item != null or carrying != null:
			_play_ui_sound("res://assets/audio/sfx/button_10.ogg", -12.0, 0.8)   # hands full
		elif flashlight_battery > 0.02 or flashlight_on:
			flashlight_on = not flashlight_on
			if not AudioGen.is_headless():
				var s := load("res://assets/audio/sfx/button_flashlight_1.ogg")
				if s != null:
					var a := AudioStreamPlayer.new(); a.stream = s; a.volume_db = -6.0
					add_child(a); a.play(); a.finished.connect(a.queue_free)
	if flashlight_on and (held_item != null or carrying != null):
		flashlight_on = false                # hands just got full -> torch off
	if flashlight_on:
		flashlight_battery = maxf(0.0, flashlight_battery - flashlight_drain * delta)
		if flashlight_battery <= 0.0:
			flashlight_on = false
	elif flashlight_recharge > 0.0:
		flashlight_battery = minf(1.0, flashlight_battery + flashlight_recharge * delta)
	net_flashlight = flashlight_on

	# Cellphone FLASH: a limited-use Watcher stun tool (no longer throwable). Aim at the figure and
	# press the phone key — the camera flash blinds it for a few seconds. 3 charges; refill at a battery.
	if _phone_cd > 0.0:
		_phone_cd = maxf(0.0, _phone_cd - delta)
	if Input.is_action_just_pressed("throw_phone") and has_phone and not input_blocked:
		_try_phone_flash()

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


## Hand-occupancy gate for one-shot tools (the phone flash). You can't raise the phone while a held
## physics item or a two-handed carry occupies your hands, while gesturing a tactile task, or downed —
## priority: downed > tactile task > held item/carry > tool. Keeps tool use physically plausible.
func _can_use_tool() -> bool:
	if _downed or carrying != null or held_item != null:
		return false
	if _tactile_kind() != Interactable.Kind.PRESS:
		return false
	return true


## PHONE FLASH (owner-side). Gate on charges + cooldown locally for a responsive HUD, fire the local
## blind-flash FX, then ask the AUTHORITY to validate range/cone/LOS and stun the Watcher.
func _try_phone_flash() -> void:
	if _phone_cd > 0.0:
		return
	if phone_charges <= 0:
		_play_ui_sound("res://assets/audio/sfx/button_10.ogg", -6.0, 0.7)   # empty click — find a battery
		return
	# Item-occupancy: can't flash mid-swing/throw of a held item (see _can_use_tool).
	if not _can_use_tool():
		return
	phone_charges -= 1
	_phone_cd = phone_flash_cooldown
	_phone_flash_fx()
	var origin := eye_pos()
	var dir := aim_dir()
	if Net.is_active():
		_net_flash.rpc_id(1, origin, dir)     # host validates + applies the stun
	else:
		_do_flash_stun(origin, dir)


## A bright, brief self-flash (you raised the phone; the glare washes your own view a little too).
func _phone_flash_fx() -> void:
	if AudioGen.is_headless():
		return
	if _flashlight != null and _flashlight.get_parent() != null:
		var pop := OmniLight3D.new()
		pop.light_color = Color(1, 1, 1)
		pop.light_energy = 8.0
		pop.omni_range = 6.0
		_flashlight.get_parent().add_child(pop)
		pop.position = Vector3(0.1, -0.1, -0.3)
		var tw := create_tween()
		tw.tween_property(pop, "light_energy", 0.0, 0.22)
		tw.tween_callback(pop.queue_free)
	_play_ui_sound("res://assets/audio/sfx/camera_flash.mp3", -1.0, 1.0)   # downloaded iOS camera-flash snap


## Server-side: find the most-aimed Watcher within range + cone + clear line of sight and stun it.
@rpc("any_peer", "call_remote", "reliable")
func _net_flash(origin: Vector3, dir: Vector3) -> void:
	_do_flash_stun(origin, dir)


func _do_flash_stun(origin: Vector3, dir: Vector3) -> void:
	if not Net.is_authority():
		return
	var cone := cos(deg_to_rad(phone_flash_angle))
	var best: Watcher = null
	var best_dot := cone
	for n in get_tree().get_nodes_in_group("watchers"):
		var w := n as Watcher
		if w == null:
			continue
		var to: Vector3 = (w.global_position + Vector3(0, 1.4, 0)) - origin
		var d := to.length()
		if d > phone_flash_range or d < 0.01:
			continue
		var nd := to / d
		var dot := dir.dot(nd)
		if dot < best_dot:
			continue                          # outside the aim cone (or a better one already found)
		if _wall_between(origin, w.global_position + Vector3(0, 1.4, 0)):
			continue                          # flash doesn't punch through walls
		best = w
		best_dot = dot
	if best != null:
		var dur := phone_stun_duration
		if best.outage_mult > 1.001:          # bolder in a blackout -> shorter stun
			dur *= phone_stun_late_mult
		best.stun(dur)


## Clear line of sight between two points (walls = layer 2 occlude the flash).
func _wall_between(a: Vector3, b: Vector3) -> bool:
	var world := get_world_3d()
	if world == null or world.direct_space_state == null:
		return false
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.collision_mask = 2
	return not world.direct_space_state.intersect_ray(q).is_empty()


func _play_ui_sound(path: String, db: float, pitch := 1.0) -> void:
	if AudioGen.is_headless():
		return
	var s := load(path)
	if s == null:
		return
	var a := AudioStreamPlayer.new()
	a.stream = s
	a.volume_db = db
	a.pitch_scale = pitch
	add_child(a)
	a.play()
	a.finished.connect(a.queue_free)


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
	match kind:
		"flashlight":
			if has_flashlight: return false
			has_flashlight = true; held_tool = "flashlight"; flashlight_battery = 1.0
		"phone":
			if has_phone: return false
			has_phone = true
			phone_charges = phone_max_charges  # comes charged
		"keycard":
			has_keycard = true
		"cigs":
			cigs += 3                          # a fresh pack
		"battery":
			flashlight_battery = 1.0
			phone_charges = phone_max_charges  # a battery powers BOTH the torch and the phone flash
		_:
			return false
	picked_up.emit(kind)
	return true


# ---- HUD meter readouts (0..1) ---------------------------------------------
func sprint_ratio() -> float:
	return clampf(_sprint_budget / maxf(tuning.sprint_max_time, 0.01), 0.0, 1.0)

## True while the burst is spent and hasn't recharged past the minimum needed to start a new
## sprint — i.e. you're locked out and must wait. The HUD reads this to show the "recharging" tell.
func sprint_locked() -> bool:
	return not _was_sprinting and _sprint_budget < tuning.sprint_min_to_start

func stamina_ratio() -> float:
	return clampf(_stamina, 0.0, 1.0)

func is_downed() -> bool:
	return _downed


## Called by Ladder's ClimbArea when this player enters/leaves it. Local + owner-driven (climbing is
## movement, like sprint) — no RPC; position is already replicated.
func enter_ladder(l: Node) -> void:
	_ladder = l

func exit_ladder(l: Node) -> void:
	if _ladder == l:
		_ladder = null


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


## A funny, NON-LETHAL shove from a bonk or a thrown item. Movement is owned by the local peer, so
## route it to the player's owner; the owner's _physics_process bleeds it into velocity (with decay).
func apply_knockback(impulse: Vector3, stagger := 0.22) -> void:
	if Net.is_active() and not is_multiplayer_authority():
		_rpc_knockback.rpc_id(get_multiplayer_authority(), impulse, stagger)
		return
	_knockback += Vector3(impulse.x, maxf(0.0, impulse.y), impulse.z)
	_stagger = maxf(_stagger, stagger)
	_maybe_drop_from_impact(impulse.length())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_knockback(impulse: Vector3, stagger: float) -> void:
	_knockback += Vector3(impulse.x, maxf(0.0, impulse.y), impulse.z)
	_stagger = maxf(_stagger, stagger)
	_maybe_drop_from_impact(impulse.length())


## Infinite-sprint flag readers use this (held items wobble, the bump system, the HUD).
func is_sprinting() -> bool:
	return _was_sprinting


## A hard enough hit may knock the cargo out of your hands. Chance-based, weighted by sprint + the
## item's weight class + fragile, gated by an impact-speed floor and a post-grab grace window. Runs on
## the holder (who owns held_item), so the drop lands on the right peer.
func _maybe_drop_from_impact(force: float) -> void:
	if held_item == null or not is_instance_valid(held_item):
		return
	if force < min_impact_speed_for_drop:
		return
	if Time.get_ticks_msec() - _grab_time_ms < pickup_drop_grace_ms:
		return
	var chance := base_drop_chance
	if is_sprinting():
		chance += sprint_drop_bonus
	if held_item is RecoverableObject:
		var ro := held_item as RecoverableObject
		chance += ro.drop_bonus()
		if ro.fragile:
			chance += fragile_drop_bonus
	if randf() < clampf(chance, 0.0, max_drop_chance):
		held_item.drop()


## Shrink the capsule from the top (feet stay on the floor) so you fit under gaps, and squash the
## visible blob. Camera height ducks in _update_camera_motion.
func _apply_crouch() -> void:
	if _capsule != null and _col != null:
		_capsule.height = lerpf(1.7, 0.95, _crouch_t)
		_col.position.y = _capsule.height * 0.5
	if _character != null:
		_character.set_crouch(_crouch_t)


func _physics_process(delta: float) -> void:
	_update_aim()               # which interactable am I looking at? (authority needs this per-player)
	if _local or Net.is_authority():
		_update_aimed_item()    # the grabbable item I'm centred on (HUD prompt + drives the grab)
	_update_flashlight_visual() # drive the beam on every copy from net_flashlight
	_set_char_reach(1.0 if interact_held else 0.0)   # gang-beasts arms reach out while interacting
	if not _local:
		return                  # remote players are positioned by the synchronizer
	var was_interact := interact_held
	interact_held = Input.is_action_pressed("interact") and not input_blocked
	# Button POKE: jab the hand out (point pose) when you press E on a PRESS interactable.
	if interact_held and not was_interact and aimed != null and is_instance_valid(aimed) \
			and aimed.enabled and aimed.interaction_type == Interactable.Kind.PRESS:
		_poke_start = Time.get_ticks_msec() / 1000.0
		_poke_point = aimed.global_position
		_poke_left = randf() < 0.5                    # random hand reaches for it
	attack_held = Input.is_action_pressed("attack") and not input_blocked
	throw_held = Input.is_action_pressed("throw") and not input_blocked
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

	# --- Crouch (hold Ctrl): duck the camera, shrink the capsule, squash the blob in half ---
	var crouch_target := 1.0 if (Input.is_action_pressed("crouch") and not input_blocked) else 0.0
	_crouch_t = move_toward(_crouch_t, crouch_target, delta * crouch_lerp)
	net_crouch = _crouch_t
	_apply_crouch()

	# --- Sprint (panic burst): INFINITE — no stamina gate, sprint whenever you're moving. The FOV still
	# widens (you move faster but cover worse), and the CONSEQUENCE of sprinting is physical chaos
	# (object instability / player bumps), handled elsewhere — not a tiredness meter.
	# Lugging a two-handed capacitor still blocks it (your hands are full).
	var sprinting := Input.is_action_pressed("sprint") and has_input and carrying == null
	_was_sprinting = sprinting
	_sprint_budget = tuning.sprint_max_time      # pinned full so any legacy reader sees "never locked"

	var speed := tuning.walk_speed * (tuning.sprint_multiplier if sprinting else 1.0)
	speed *= lerpf(1.0, crouch_speed_factor, _crouch_t)   # crouch-walk is slower
	if carrying != null:
		speed *= capacitor_carry_slow      # heavy maintenance haul — you're slow and exposed
	var dir := (transform.basis * Vector3(iv.x, 0.0, iv.y)).normalized()
	# While staggered (just got bonked) you barely control your feet — the knockback carries you.
	var target := dir * speed * (0.25 if _stagger > 0.0 else 1.0)
	# Asymmetric accel/decel gives a touch of weight: snappy to start, softer to stop.
	var rate := tuning.acceleration if has_input else tuning.deceleration
	velocity.x = move_toward(velocity.x, target.x, rate * delta)
	velocity.z = move_toward(velocity.z, target.z, rate * delta)
	# Jump (Space): a pop off the floor when standing. Gravity then brings you down.
	var grounded := is_on_floor()
	if _ladder != null and not _downed and not input_blocked and is_instance_valid(_ladder):
		# LADDER CLIMB: gravity off; W/S drive you up/down. You're STUCK to the ladder's front
		# centre-line (so it grips like a real ladder, not floaty), and jump hops you off. Reaching the
		# top: keep holding W and you rise above the climb volume → exit → land on the ledge.
		var lad := _ladder as Node3D
		var face: Vector3 = lad.global_transform.basis.z       # ladder's front (toward the climber)
		var stand := lad.global_position + face * ladder_stand_dist
		var to := stand - global_position
		to.y = 0.0
		velocity.x = to.x * 8.0                                 # spring onto the centre-line
		velocity.z = to.z * 8.0
		velocity.y = Input.get_axis("move_back", "move_forward") * ladder_climb_speed   # W up, S down
		if Input.is_action_just_pressed("jump"):
			velocity = face * 3.5 + Vector3.UP * 2.5            # hop off the ladder
			_ladder = null
	elif grounded and _crouch_t < 0.5 and Input.is_action_just_pressed("jump") and not input_blocked:
		velocity.y = jump_force
		grounded = false               # so the floor-snap below doesn't eat the jump
	# Gravity so stairs / the second floor / ledges work. (Stairs are a smooth ramp
	# collider, so plain move_and_slide climbs them — no step-assist hacks needed.)
	elif grounded:
		velocity.y = -2.0          # small downward bias keeps us snapped to slopes
	else:
		velocity.y -= tuning.gravity * delta
	# KNOCKBACK (bonk / thrown item): a decaying shove added AFTER gravity so an upward pop survives
	# the floor-snap. Funny, never lethal — it just pushes you around.
	velocity.x += _knockback.x
	velocity.z += _knockback.z
	velocity.y += _knockback.y
	_knockback = _knockback.move_toward(Vector3.ZERO, delta * 16.0)
	if _stagger > 0.0:
		_stagger = maxf(0.0, _stagger - delta)
	move_and_slide()

	# Sprint widens the FOV slightly (you cover a worse cone while bursting).
	var want_fov := tuning.fov + (tuning.sprint_fov_add if sprinting else 0.0)
	cam.fov = lerpf(cam.fov, want_fov, delta * 8.0)

	_update_camera_motion(delta, iv, speed, sprinting)

	# Visual-only body lean toward movement. Uses post-slide velocity in LOCAL space; never rotates
	# the CharacterBody3D itself (this tilts the rig child only), so collision/camera are untouched.
	if _character != null:
		var lvel := global_transform.basis.inverse() * velocity
		lvel.y = 0.0
		_character.set_movement_lean(lvel / maxf(tuning.walk_speed, 0.1), delta)
		_character.set_look_pitch(_pitch)      # blob tilts its head with your look (seen in mirror/by teammates)


func _update_camera_motion(delta: float, iv: Vector2, speed: float, sprinting: bool) -> void:
	_breath_t += delta
	# Low blink-stamina makes the view breathe harder — movement feeds the dread.
	var strain := 1.0 + (1.0 - _stamina) * 0.4
	# Crouch ducks the camera toward crouch_eye_factor of standing eye height.
	var eh := tuning.eye_height * lerpf(1.0, crouch_eye_factor, _crouch_t)
	if iv.length() > 0.1:
		var freq := tuning.bob_frequency * (speed / maxf(tuning.walk_speed, 0.1))
		_bob_t += delta * freq * TAU
		var amp := tuning.bob_amplitude * strain * (1.3 if sprinting else 1.0)
		_head.position.y = eh + sin(_bob_t) * amp
	else:
		var idle := eh + sin(_breath_t * 1.6) * tuning.breath_amplitude * strain
		# Track the crouch height quickly (crouch_t already smooths the duck) so the camera isn't laggy.
		_head.position.y = lerp(_head.position.y, idle, clampf(delta * 14.0, 0.0, 1.0))
