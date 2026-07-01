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
const HORROR_TEXT_SCENE := preload("res://scenes/ui/horror_text_overlay.tscn")
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

## ---- Task pool / round selection --------------------------------------------
## The bunker AUTHORS a large pool of tasks; each round only a varied SUBSET is activated, so no two
## runs feel the same and players don't memorise one route. Selection is authority-computed, then
## broadcast to clients for display (the win tally is already authority-driven via Task signals, so
## selection can never cause a wrong win). All knobs exposed for tuning.
@export_group("Task pool / round selection")
@export var enable_task_selection := true
@export_range(1, 20) var required_solo := 6          ## tasks to win, solo
@export_range(0, 6) var required_per_extra_player := 2  ## +N per extra player
@export_range(1, 30) var required_max := 14
@export_range(1, 6) var max_same_type_per_round := 3 ## don't flood a round with one task type
@export var min_distance_between_selected := 7.0     ## spread picks across the map (relaxed if needed)
@export var allow_hard_in_solo := true
@export var allow_coop_tasks := true
@export_range(0, 3) var max_coop_tasks_per_round := 1
@export_range(0.0, 1.0, 0.05) var meme_task_rarity := 0.5  ## chance a round includes ONE meme task
@export var weight_easy := 0.35
@export var weight_medium := 0.35
@export var weight_hard := 0.20

## ---- Recovery / restock (Phase 1) -------------------------------------------
## The new core loop: instead of selecting minigame tasks, the round requires the team to RECOVER
## physical objects from the bunker and RESTOCK them into the elevator. When on, all authored tasks
## are left inactive (set-dressing) and RecoveryManager drives the win. See recovery_manager.gd.
@export_group("Recovery / restock (Phase 1)")
@export var enable_recovery_mode := true
@export_range(0, 12) var recovery_food := 3
@export_range(0, 12) var recovery_drinks := 2
@export_range(0, 12) var recovery_electronics := 1
@export_range(0, 4) var recovery_per_extra_player := 0   ## +N to each quota per extra player

## ---- Player-vs-player sprint bumps (co-op chaos; inert in solo) --------------
@export_group("Player bumps")
@export var bump_radius := 1.3                ## how close two players must be to bump
@export var bump_min_rel_speed := 5.0         ## relative speed needed (≈ one sprinting into another)
@export var bump_force := 4.0                 ## knockback shove magnitude (clamped, never lethal)
@export var bump_stagger := 0.9               ## ~1s slowdown after a bump (reuses player _stagger)
@export var bump_cooldown := 1.2              ## a given pair can't re-bump for this long

var _bump_last_pos := {}                      # WPlayer -> last position (for velocity estimate)
var _bump_cd := {}                            # pair key -> cooldown remaining

var house: Node3D
var watchers: Array[Watcher] = []
var tasks: Array[Task] = []
var _players_node: Node3D
var _spawner: MultiplayerSpawner
var _cached_local: WPlayer
var _state := "play"            # play | won | caught
var _paused := false
var _vmat: ShaderMaterial
var _hud: GameHUD
var _hud_center: Label
var _recovery: RecoveryManager
var _danger := 0.0
var _pulse_t := 0.0
var _heart: AudioStreamPlayer
var _ambient: AudioStreamPlayer
var _pause_menu: CanvasLayer
var _horror: HorrorTextOverlay
var _was_downed := false        # local player downed-edge, for the DOWN panic flash


func _ready() -> void:
	if config == null:
		config = load("res://resources/default_game.tres") as GameConfig
	if config == null:
		config = GameConfig.new()
	WPlayer.input_blocked = false     # clear any leftover pause-block from the lobby/menu
	VoiceManager.lobby_mode = false   # gameplay voice = tighter / more tactical
	PhysicsItem.lobby_mode = false    # gameplay items still knock back (prank tools), see physics_item
	_build_house()                    # the authored bunker (env + rooms + tasks live inside it)
	_build_environment()              # only if the bunker scene didn't author one
	_build_player()
	_collect_tasks()                  # tasks are authored in bunker.tscn -> just wire them up
	_build_recovery()                 # Phase 1: recovery/restock objective (deactivates tasks when on)
	_build_room_atmosphere()          # per-room colour + hum identity (derived from task zones)
	_build_watchers()
	_build_power()                    # power-outage events + the glowing red reset button
	_build_psx_post()                 # full-screen PSX dither/colour-reduction look
	_build_hud()
	_build_horror_text()              # short PANIC text (RUN / WATCH / DOWN) — separate from HUD
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

## Tell the players, loud and clear, when the lights die (and when they come back).
func _announce_outage(on: bool) -> void:
	if _outage_label == null:
		return
	_outage_label.visible = true
	if on:
		# Drama goes to the wordless PANIC flash; the banner stays a terse gameplay hint (where to go).
		if _horror != null:
			_horror.flash("RUN", HorrorTextOverlay.DANGER, 1.4)
		_outage_label.text = "power down — slam the red button"
		_outage_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.15))
		_outage_flash = 1.0
		if not AudioGen.is_headless():
			var a := AudioStreamPlayer.new()
			a.stream = load("res://assets/audio/sfx/button_10.ogg")
			a.volume_db = -2.0; a.pitch_scale = 0.6
			add_child(a); a.play(); a.finished.connect(a.queue_free)
	else:
		if _horror != null:
			_horror.flash("MOVE", HorrorTextOverlay.SICK, 1.1)
		_outage_label.text = "power restored"
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
	p.picked_up.connect(_on_picked_up)
	return p


const PICKUP_HINTS := {
	"flashlight": "Picked up FLASHLIGHT  ·  press G to toggle",
	"phone": "Picked up CELLPHONE  ·  press V to flash-stun the Watcher",
	"keycard": "Picked up KEYCARD  ·  opens locked blast doors",
	"cigs": "Picked up CIGARETTES  ·  press C to light one",
	"battery": "Picked up BATTERY  ·  torch + phone flashes recharged",
}

## A small bottom-left toast when you pick something up: WHAT it is + HOW to use it. Routed through
## the HUD so it shares the gold palette + font with the rest of the interface (no big centred banner).
func _on_picked_up(kind: String) -> void:
	if _hud == null or not is_instance_valid(_hud):
		return
	_hud.toast(String(PICKUP_HINTS.get(kind, "Picked up " + kind.to_upper())))


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
	# Recovery mode: the round win is RESTOCK, not minigame tasks. Deactivate AND HIDE every authored
	# task so the old minigame props don't clutter the bunker (the user decorates it themselves). Nothing
	# is deleted — the nodes still exist for later phases; they're just invisible + inert this round.
	if enable_recovery_mode:
		for t in tasks:
			t.set_active(false)
			t.visible = false
		return
	_select_round_tasks()
	# A client may have received the selection broadcast before its tasks existed — apply now.
	if not Net.is_authority() and _pending_selection.size() > 0:
		_apply_selection(_pending_selection)


# ---- Recovery / restock (Phase 1) -------------------------------------------
## Stand up the RecoveryManager: it spawns the round's recoverable objects (anchored to task
## positions), builds the elevator loading bay, and tallies per-category restock quotas. Runs on every
## peer (objects must exist identically); only the authority validates deliveries + fires the win.
func _build_recovery() -> void:
	if not enable_recovery_mode:
		return
	_recovery = RecoveryManager.new()
	_recovery.name = "RecoveryManager"
	_recovery.required_food = recovery_food
	_recovery.required_drinks = recovery_drinks
	_recovery.required_electronics = recovery_electronics
	_recovery.per_extra_player = recovery_per_extra_player
	add_child(_recovery)
	var pc := maxi(1, get_tree().get_nodes_in_group("players").size())
	_recovery.setup(house, pc)
	_recovery.objective_complete.connect(_on_objective_complete)   # callout, then the win
	_recovery.delivered_item.connect(_on_recovery_delivered)


## Local restock confirmation — a small bottom-left toast PLUS the punchy CRT "+ FOOD" value pop.
func _on_recovery_delivered(_category: String, display_name: String) -> void:
	if _hud != null and is_instance_valid(_hud):
		_hud.toast("RESTOCKED — " + display_name)
		_hud.delivery_pop(_category)


## All quotas met — big "ELEVATOR LOADED" callout, then resolve the win.
func _on_objective_complete() -> void:
	if _hud != null and is_instance_valid(_hud):
		_hud.callout("ELEVATOR LOADED")
	_win()


# ---- Round selection --------------------------------------------------------
## Pick a varied subset of the authored pool for THIS round. Authority only; clients receive the
## result via _net_apply_selection. Mixes difficulty (easy/medium/hard weights), caps how many of
## one type appear, spreads picks across the map, gates co-op tasks to enough players, and includes
## at most one (rare) meme task.
var _pending_selection := PackedStringArray()

func _select_round_tasks() -> void:
	if not enable_task_selection or tasks.is_empty():
		return
	if not Net.is_authority():
		return                              # clients wait for the broadcast
	var players := maxi(1, get_tree().get_nodes_in_group("players").size())

	var memes: Array[Task] = []
	var coops: Array[Task] = []
	var normals: Array[Task] = []
	for t in tasks:
		if t.min_players_required > players:
			continue
		if t.requires_two_players and (not allow_coop_tasks or players < 2):
			continue
		if t.difficulty == 3 and not allow_hard_in_solo and players == 1:
			continue
		if t.meme_task:
			memes.append(t)
		elif t.requires_two_players:
			coops.append(t)
		else:
			normals.append(t)
	memes.shuffle()
	coops.shuffle()

	var eligible_n := memes.size() + coops.size() + normals.size()
	var target := clampi(required_solo + (players - 1) * required_per_extra_player, 1, required_max)
	target = mini(target, eligible_n)

	var selected: Array[Task] = []
	var type_counts := {}

	# One rare meme task (keeps it funny, not spammy).
	if not memes.is_empty() and randf() < meme_task_rarity:
		_try_select(memes[0], selected, type_counts)
	# Co-op up to the cap (already gated to player count above).
	var coop_added := 0
	for t in coops:
		if coop_added >= max_coop_tasks_per_round or selected.size() >= target:
			break
		if _try_select(t, selected, type_counts):
			coop_added += 1
	# Fill the rest from normals, biased by the difficulty weights.
	for t in _weight_order(normals, players):
		if selected.size() >= target:
			break
		_try_select(t, selected, type_counts)
	# If type-cap / spacing left us short, relax both and top up so a round is never too thin.
	if selected.size() < target:
		for t in normals + coops + memes:
			if selected.size() >= target:
				break
			if not selected.has(t):
				selected.append(t)

	var names := PackedStringArray()
	for t in selected:
		names.append(String(t.name))
	if Net.is_active():
		_net_apply_selection.rpc(names)     # call_local also applies on the host
	else:
		_apply_selection(names)


## Add `t` to the round unless it'd exceed the per-type cap or sit too close to an existing pick.
func _try_select(t: Task, selected: Array[Task], type_counts: Dictionary) -> bool:
	var key: Script = t.get_script()
	if int(type_counts.get(key, 0)) >= max_same_type_per_round:
		return false
	for s in selected:
		if s.global_position.distance_to(t.global_position) < min_distance_between_selected:
			return false
	selected.append(t)
	type_counts[key] = int(type_counts.get(key, 0)) + 1
	return true


## Weighted shuffle: each task's sort key is biased by its difficulty weight, so easy/medium/hard
## appear roughly in the configured proportions while still randomising round-to-round.
func _weight_order(arr: Array[Task], _players: int) -> Array[Task]:
	var scored: Array = []
	for t in arr:
		var w := weight_medium
		if t.difficulty == 1:
			w = weight_easy
		elif t.difficulty == 3:
			w = weight_hard
		scored.append({"t": t, "k": pow(randf(), 1.0 / maxf(0.01, w))})
	scored.sort_custom(func(a, b): return a["k"] > b["k"])
	var out: Array[Task] = []
	for e in scored:
		out.append(e["t"])
	return out


func _apply_selection(names: PackedStringArray) -> void:
	var want := {}
	for n in names:
		want[n] = true
	for t in tasks:
		t.set_active(want.has(String(t.name)))


@rpc("authority", "call_local", "reliable")
func _net_apply_selection(names: PackedStringArray) -> void:
	_pending_selection = names
	if not tasks.is_empty():
		_apply_selection(names)


## Give each functional room a signature colour + hum so players read the facility by feel (no signs).
## Derives room centres from the tasks already placed there — see room_atmosphere.gd.
func _build_room_atmosphere() -> void:
	var ra := RoomAtmosphere.new()
	ra.name = "RoomAtmosphere"
	add_child(ra)
	ra.build(tasks, house)


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


## The panic-text overlay (its own CanvasLayer above the PSX post). First bunker entry gets a single
## wordless tell — WATCH — so players immediately understand the verb without a tutorial line.
func _build_horror_text() -> void:
	_horror = HORROR_TEXT_SCENE.instantiate()
	add_child(_horror)
	get_tree().create_timer(1.8).timeout.connect(func():
		if is_instance_valid(_horror):
			_horror.flash("WATCH", HorrorTextOverlay.IVORY, 1.8))


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

	# ---- HUD rendered into a SubViewport, shown through the CRT curve shader (world stays crisp) ----
	# Rendered at HUD_RENDER_SCALE of the window so the TextureRect upscales it → bigger, chunkier UI
	# (and coarser, more CRT-like scanlines). 0.5 = 2x-size UI.
	const HUD_RENDER_SCALE := 0.5
	var svp := SubViewport.new()
	svp.name = "HudViewport"
	svp.transparent_bg = true
	svp.disable_3d = true
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svp.size = Vector2i(get_viewport().get_visible_rect().size * HUD_RENDER_SCALE)
	layer.add_child(svp)

	_hud = GameHUD.new()
	_hud.player_fn = _local_player
	_hud.danger_fn = func(): return _danger
	_hud.tasks_fn = func(): return tasks
	_hud.recovery_fn = func(): return _recovery     # Phase 1: RESTOCK panel reads the manager
	svp.add_child(_hud)

	var crt := TextureRect.new()
	crt.name = "CRT"
	crt.set_anchors_preset(Control.PRESET_FULL_RECT)
	crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crt.texture = svp.get_texture()
	crt.material = _hud.build_crt_material()
	layer.add_child(crt)

	# keep the HUD viewport matched to the window (at the render scale)
	get_viewport().size_changed.connect(func():
		if is_instance_valid(svp):
			svp.size = Vector2i(get_viewport().get_visible_rect().size * HUD_RENDER_SCALE))

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

	# Pickup confirmations now route through the HUD as a small bottom-left toast (_on_picked_up).

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
		Transition.reload(true)
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
			_check_player_bumps(delta)
	# DOWN panic flash on the rising edge of the local player being caught (local feedback only).
	if _horror != null:
		var lp := _local_player()
		var down: bool = lp != null and lp._downed
		if down and not _was_downed:
			_horror.flash("DOWN", HorrorTextOverlay.DANGER, 1.6)
		_was_downed = down
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
		if t.counts_for_win():       # active AND counts_toward_win — inactive pool tasks don't count
			total += 1
			if t.done:
				done += 1
	if total > 0 and done >= total:  # guard: never insta-win on an empty active set
		_win()


## Server/solo: handle downed teammates — revive when a standing player holds
## interact nearby, and lose only when EVERYONE is down.
## Authority-only: two players sprinting into each other BUMP — both get shoved apart + a ~1s slowdown,
## and the existing impact-drop roll (inside apply_knockback) may shake their cargo loose. Velocity is
## estimated from per-frame position deltas (works for host + synced clients); a pair cooldown stops
## chain-bumps. Inert with <2 players, so solo never triggers it.
func _check_player_bumps(delta: float) -> void:
	var players := get_tree().get_nodes_in_group("players")
	if players.size() < 2:
		return
	var vel := {}
	for n in players:
		var p := n as WPlayer
		if p == null:
			continue
		var last: Vector3 = _bump_last_pos.get(p, p.global_position)
		vel[p] = (p.global_position - last) / maxf(delta, 0.001)
		_bump_last_pos[p] = p.global_position
	for k in _bump_cd.keys():
		_bump_cd[k] = float(_bump_cd[k]) - delta
		if float(_bump_cd[k]) <= 0.0:
			_bump_cd.erase(k)
	for i in players.size():
		for j in range(i + 1, players.size()):
			var a := players[i] as WPlayer
			var b := players[j] as WPlayer
			if a == null or b == null or a._downed or b._downed:
				continue
			if a.global_position.distance_to(b.global_position) > bump_radius:
				continue
			if (vel.get(a, Vector3.ZERO) - vel.get(b, Vector3.ZERO)).length() < bump_min_rel_speed:
				continue
			var key := "%d_%d" % [mini(a.get_instance_id(), b.get_instance_id()), maxi(a.get_instance_id(), b.get_instance_id())]
			if _bump_cd.has(key):
				continue
			_bump_cd[key] = bump_cooldown
			var dir := a.global_position - b.global_position
			dir.y = 0.0
			dir = dir.normalized() if dir.length() > 0.01 else Vector3(1, 0, 0)
			a.apply_knockback(dir * bump_force + Vector3.UP, bump_stagger)
			b.apply_knockback(-dir * bump_force + Vector3.UP, bump_stagger)


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
		var won_text := "ELEVATOR LOADED — sending it up" if enable_recovery_mode else "HOUSE SECURE — you got out"
		_hud_center.text = won_text + ("\n[ R ] to play again" if not Net.is_active() else "")
		_hud_center.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
