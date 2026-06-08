class_name ThrownPhone
extends Node3D
## The one-shot cellphone the player hurls at the watcher (`cell_phone_3`). It arcs through the
## air; if it strikes a watcher it STUNS it solid for a few seconds (the late-game desperation
## tool once the watcher is angry and won't freeze to your gaze). Self-contained: spawned by
## game.gd from WPlayer.phone_thrown.

const HIT_RADIUS := 1.4

var _vel := Vector3.ZERO
var _life := 4.0
var _spin := Vector3(8.0, 11.0, 5.0)
var _dead := false


func launch(origin: Vector3, dir: Vector3, speed := 16.0) -> void:
	global_position = origin
	_vel = dir.normalized() * speed
	var ps := load("res://assets/psx/Electronics & Misc/cell_phone_3.glb") as PackedScene
	if ps != null:
		var n := ps.instantiate() as Node3D
		n.scale = Vector3.ONE * 3.0
		add_child(n)
	else:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = Vector3(0.1, 0.04, 0.2); mi.mesh = bm
		add_child(mi)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	_vel.y -= 9.0 * delta * 0.35                       # light arc
	rotation += _spin * delta
	var from := global_position
	var to := from + _vel * delta

	# Strike a watcher?
	for w in get_tree().get_nodes_in_group("watchers"):
		var wat := w as Watcher
		if wat == null:
			continue
		if to.distance_to(wat.global_position + Vector3(0, 1.4, 0)) <= HIT_RADIUS:
			wat.stun()
			_impact(true)
			return

	# Hit a wall? (mask 2)
	var space := get_world_3d().direct_space_state
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collision_mask = 2
		if not space.intersect_ray(q).is_empty():
			_impact(false)
			return
	global_position = to


func _impact(hit_watcher: bool) -> void:
	_dead = true
	if not AudioGen.is_headless():
		var s := load("res://assets/audio/sfx/crack_1_wood.ogg")
		if s != null:
			var a := AudioStreamPlayer3D.new()
			a.stream = s
			a.volume_db = 0.0 if hit_watcher else -8.0
			a.pitch_scale = 1.4 if hit_watcher else 1.0
			a.global_position = global_position
			get_tree().current_scene.add_child(a)
			a.global_position = global_position
			a.play(); a.finished.connect(a.queue_free)
	queue_free()
