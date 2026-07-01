@tool
class_name Task
extends Node3D
## Base for every objective object. SELF-DRIVING: a task finds players via the
## "players" group, updates itself each frame, and emits `completed` when finished.
## Drop a task scene into a level, connect `completed`, done — that's the contract.
## This decoupling is what makes co-op additive later (tasks don't care who acts).
##
## @tool: the prop VISUALS build in the editor too, so a task you drop into bunker.tscn is
## visible and movable in-editor. Runtime-only logic is guarded by Engine.is_editor_hint().
##
## Subclass and override `_build()` (greybox visuals) and `_task_process(delta)`.

signal completed(task: Task)
signal progress_changed(task: Task, ratio: float)

@export var task_title := "Do the thing"   ## one-line goal shown in the HUD
@export var counts_toward_win := true       ## include in the level's objective count
@export var show_beacon := true             ## floating name + light beam so players find it
@export var beacon_color := Color(1.0, 0.78, 0.3)

## ---- Pool metadata -----------------------------------------------------------
## The round selector (game.gd::_select_round_tasks) reads ONLY this metadata — it never needs to
## know a task's concrete type. Add a new task type, give it sane metadata here (or in its _build),
## and it joins the pool automatically. Subclasses set type-appropriate defaults in _build() while
## still default (so a value authored per-instance in bunker.tscn wins).
@export_group("Pool Metadata")
@export var task_id: StringName = &""             ## stable id (optional; defaults to node name)
@export_range(1, 3) var difficulty := 2           ## 1 easy · 2 medium · 3 hard
@export var task_category: StringName = &"physical"  ## physical · puzzle · coop · meme · carry
@export var zone_id: StringName = &""             ## bunker wing, for zone-spread selection
@export var zone_display_name := ""               ## human room label shown in the HUD ("Pipe Room", "Security")
@export var estimated_duration := 6.0             ## seconds, rough (for pacing/assignment later)
@export var allow_personal_assignment := true     ## reserved for the deferred personal-task pass
@export var requires_two_players := false          ## co-op: needs a second living player to finish
@export_range(1, 4) var min_players_required := 1  ## not eligible below this player count
@export var meme_task := false                     ## rare/funny — selected sparingly
@export var puzzle_task := false                   ## thinking task — selector tracks these

var done := false
var active := true                                 ## selected this round? inactive = set-dressing only
var _beacon: Node3D
var _beacon_lamp: OmniLight3D
var _beacon_phase := 0.0


## True if the title is still the base placeholder — lets a subclass set a default title in _build
## WITHOUT clobbering one authored per-instance in the editor / bunker generator.
func is_default_title() -> bool:
	return task_title == "" or task_title == "Do the thing"


func _ready() -> void:
	_build()                       # build prop visuals in editor AND at runtime
	if show_beacon:
		_build_beacon()
	if Engine.is_editor_hint():
		return                     # editor: visuals only, no gameplay logic
	add_to_group("tasks")


## NO floating text. A diegetic STATUS LAMP on the fixture: a slow "unfinished job" breathe in the
## dark that WAKES UP (brighter + a faster pulse) as a player approaches — so the task that's near
## you visibly calls for attention, without an arcade marker. (When personal assignment lands, swap
## the proximity drive in _update_beacon for an is-assigned-to-me check.) Hidden when inactive/done.
func _build_beacon() -> void:
	_beacon = Node3D.new()
	_beacon.name = "Glow"
	add_child(_beacon)
	_beacon_lamp = OmniLight3D.new()
	_beacon_lamp.light_color = beacon_color
	_beacon_lamp.light_energy = 0.8
	_beacon_lamp.omni_range = 4.5
	_beacon_lamp.omni_attenuation = 1.6
	_beacon_lamp.position = Vector3(0, 1.4, 0)
	_beacon.add_child(_beacon_lamp)


## Visual only — runs on EVERY copy (host + clients), before the authority gate in _process.
func _update_beacon(delta: float) -> void:
	if _beacon_lamp == null or _beacon == null or not _beacon.visible:
		return
	var nearest := 999.0
	var p := nearest_player()
	if p != null:
		nearest = global_position.distance_to(p.global_position)
	var prox := clampf(1.0 - nearest / 14.0, 0.0, 1.0)   # 0 far → 1 right on top of it
	_beacon_phase += delta * lerpf(1.6, 5.5, prox)        # idle breathe → insistent pulse up close
	var breathe := 0.55 + 0.45 * sin(_beacon_phase)
	_beacon_lamp.light_energy = lerpf(0.7, 2.8, prox) * breathe


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return                     # editor: don't run gameplay simulation
	_update_beacon(delta)          # VISUAL status lamp — every copy, even on clients
	# Tasks are simulated by the server (or solo). Clients show them statically for
	# now; networked task interaction is the next netcode step.
	# Inactive (not selected this round) tasks never simulate — they're just props.
	if done or not active or not Net.is_authority():
		return
	_task_process(delta)


# ---- Round selection --------------------------------------------------------
## True only if this task should count toward the level's objective tally THIS round.
func counts_for_win() -> bool:
	return active and counts_toward_win


## game.gd flips this after collecting the pool. Inactive tasks drop their beacon + interact
## targets (so no prompt, no glow, not aimable) and stop simulating — the prop remains as
## set-dressing so the bunker still reads as a facility full of (mostly broken) systems.
func set_active(on: bool) -> void:
	if active == on:
		return
	active = on
	_apply_active()


func _apply_active() -> void:
	if _beacon != null:
		_beacon.visible = active
	_set_interactables_targetable(self, active)
	_on_active_changed(active)


func _set_interactables_targetable(n: Node, on: bool) -> void:
	if n is Interactable:
		var it := n as Interactable
		it.enabled = on
		it.set_targetable(on)
	for c in n.get_children():
		_set_interactables_targetable(c, on)


## Override to dim/brighten type-specific lights when a task is (de)selected. Default: nothing.
func _on_active_changed(_on: bool) -> void:
	pass


# ---- Override points --------------------------------------------------------
func _build() -> void:
	pass

func _task_process(_delta: float) -> void:
	pass

## 0..1 for the HUD. Override for partial-progress tasks.
func get_progress() -> float:
	return 1.0 if done else 0.0

## Override for completion feedback (recolor, sound...).
func _on_done() -> void:
	pass


# ---- Shared helpers ---------------------------------------------------------
func mark_done() -> void:
	if done:
		return
	done = true
	if _beacon != null:
		_beacon.queue_free()      # work's done — drop the beacon
		_beacon = null
	_on_done()
	progress_changed.emit(self, 1.0)
	completed.emit(self)


func report_progress(ratio: float) -> void:
	progress_changed.emit(self, clampf(ratio, 0.0, 1.0))


## A spatial one-shot interaction sound at this task (clicks, cranks, thuds).
func play_sfx(path: String, vol_db := -5.0, pitch := 1.0) -> void:
	if AudioGen.is_headless():
		return
	var s := load(path)
	if s == null:
		return
	var a := AudioStreamPlayer3D.new()
	a.stream = s
	a.volume_db = vol_db
	a.pitch_scale = pitch
	a.unit_size = 3.0
	a.max_distance = 22.0
	add_child(a)
	a.play()
	a.finished.connect(a.queue_free)


## Is this player close enough AND holding interact (the physical "work" input)?
func _holding(p: WPlayer, point: Vector3, rng: float) -> bool:
	return p != null and not p._downed and p.interact_held \
		and p.global_position.distance_to(point) <= rng


## Nearest player to this task, or null if none exist yet.
func nearest_player() -> WPlayer:
	var best: WPlayer = null
	var bd := INF
	for p in get_tree().get_nodes_in_group("players"):
		if p is WPlayer:
			var d := global_position.distance_to((p as Node3D).global_position)
			if d < bd:
				bd = d
				best = p
	return best


## Find a descendant whose name CONTAINS `frag` (case-insensitive) — used to grab a specific
## sub-mesh of a GLB, e.g. a lever's "_child" handle or a valve's "valve_" wheel, so we can move
## ONLY that part (not the whole fixture).
func find_part(root: Node, frag: String) -> Node3D:
	if root is Node3D and frag.to_lower() in String(root.name).to_lower():
		return root
	for c in root.get_children():
		var r := find_part(c, frag)
		if r != null:
			return r
	return null


## A targetable "look at it + press/hold E" piece (Interactable on the interact layer) with a box
## hit-volume. The owning task polls player.aimed / player.is_using() to drive it.
func make_interactable(size: Vector3, prompt := "Use", offset := Vector3.ZERO) -> Interactable:
	var it := Interactable.new()
	it.prompt = prompt
	it.add_box(size, offset)
	return it


## A real model (GLB) if it exists, else a greybox box fallback. Returns a Node3D.
func make_model(path: String, fallback_size: Vector3, fallback_col: Color, scale := 1.0) -> Node3D:
	var ps := load(path) as PackedScene
	if ps != null:
		var n := ps.instantiate() as Node3D
		n.scale = Vector3.ONE * scale
		return n
	return make_box(fallback_size, fallback_col)


## Greybox box mesh; set emissive for "active/glowing" props.
func make_box(size: Vector3, col: Color, emissive := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	if emissive:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 2.0
	m.roughness = 0.85
	mi.material_override = m
	return mi


## A flat floor marker (thin disc) for drop zones / targets.
func make_marker(radius: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.06
	mi.mesh = cyl
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 1.4
	mi.material_override = m
	return mi
