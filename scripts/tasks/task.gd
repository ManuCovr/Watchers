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

var done := false
var _beacon: Node3D


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


## NO floating text. Just a soft local glow so the task OBJECT itself is readable in the
## dark (the work is found by light + the prop's look, not a label). Hidden on done.
func _build_beacon() -> void:
	_beacon = Node3D.new()
	_beacon.name = "Glow"
	add_child(_beacon)
	var lamp := OmniLight3D.new()
	lamp.light_color = beacon_color
	lamp.light_energy = 2.4
	lamp.omni_range = 5.0
	lamp.omni_attenuation = 1.4
	lamp.position = Vector3(0, 1.4, 0)
	_beacon.add_child(lamp)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return                     # editor: don't run gameplay simulation
	# Tasks are simulated by the server (or solo). Clients show them statically for
	# now; networked task interaction is the next netcode step.
	if done or not Net.is_authority():
		return
	_task_process(delta)


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
