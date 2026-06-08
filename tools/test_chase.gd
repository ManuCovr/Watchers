extends SceneTree
## Headless chase check: load the game, make the player look AWAY (so the watcher
## unfreezes), run ~3s of physics, and confirm the watcher closes distance via the navmesh
## (i.e. it actually paths toward the player instead of standing still / wall-humping).
##   Godot_console.exe --headless --path <proj> --script res://tools/test_chase.gd

func _initialize() -> void:
	var ps := load("res://scenes/game.tscn") as PackedScene
	get_root().add_child(ps.instantiate())
	for i in 12:
		await physics_frame
	var players := get_root().get_tree().get_nodes_in_group("players")
	if players.is_empty():
		print("CHASE: no player"); quit(); return
	var player := players[0] as Node3D
	var watcher := get_root().find_child("Watcher0", true, false) as Node3D
	if watcher == null:
		print("CHASE: no watcher"); quit(); return

	# Watcher is at +Z (north). Face -Z (south) so the player is looking AWAY -> it creeps.
	player.rotation.y = 0.0
	var start_d := watcher.global_position.distance_to(player.global_position)
	var start_pos := watcher.global_position
	for i in 180:                    # ~3s at 60hz
		await physics_frame
	var end_d := watcher.global_position.distance_to(player.global_position)
	var moved := start_pos.distance_to(watcher.global_position)
	print("CHASE start_dist=%.2f end_dist=%.2f moved=%.2f -> %s" % [
		start_d, end_d, moved,
		("CHASING" if moved > 1.0 and end_d < start_d else "STUCK/IDLE")])
	quit()
