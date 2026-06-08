extends SceneTree
## Headless nav check: load the bunker, bake the navmesh, confirm it's non-empty, and
## prove a path exists from the player spawn to the FAR room (watcher chase connectivity).
##   Godot_console.exe --headless --path <proj> --script res://tools/test_nav.gd

func _initialize() -> void:
	var ps := load("res://scenes/bunker.tscn") as PackedScene
	var bunker := ps.instantiate()
	get_root().add_child(bunker)
	var nav := bunker.get_node("Nav") as NavigationRegion3D
	# Replicate game.gd's runtime bake: add room/tunnel containers to the source group, then
	# bake after physics frames register the colliders.
	for cont in ["Rooms", "Tunnels"]:
		var n = bunker.get_node_or_null(cont)
		if n != null:
			n.add_to_group("navsrc")
	await process_frame
	await physics_frame
	await physics_frame
	nav.bake_navigation_mesh(false)
	await physics_frame
	await physics_frame

	var mesh := nav.navigation_mesh
	var vtx := mesh.get_vertices().size()
	var polys := mesh.get_polygon_count()
	print("NAV vertices=", vtx, " polygons=", polys)

	var map := nav.get_navigation_map()
	# Wait for the map to sync so path queries work.
	for i in 8:
		await physics_frame
	var from := Vector3(-9, 0.3, -4.0)       # arrival room (player spawn)
	var to := Vector3(27, 0.3, 54.0)         # far corner room (watcher spawn)
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	print("PATH points=", path.size(), " reaches=",
		("YES" if path.size() > 0 and path[path.size() - 1].distance_to(to) < 3.0 else "NO"))
	if path.size() > 0:
		print("  end=", path[path.size() - 1], " target=", to)
	quit()
