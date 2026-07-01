extends SceneTree
func _initialize():
	var g = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(g)
	_run(g)
func _run(g):
	for i in 60: await physics_frame
	var bottle = null
	for o in get_nodes_in_group("recoverables"):
		if o.fragile and not o.broken:
			bottle = o; break
	if bottle == null:
		print("TEST: FAIL no fragile object"); quit(); return
	print("TEST: fragile=", bottle.fragile, " broken_before=", bottle.broken, " threshold=", bottle.break_threshold, " wc=", bottle.weight_class)
	bottle.freeze = false
	bottle.linear_velocity = Vector3(0, 0, 10)   # hard impact, above break_threshold
	bottle._on_body_entered(bottle)              # invoke the impact handler
	await physics_frame
	print("TEST: broken_after=", bottle.broken, " value=", bottle.value)
	print("TEST: ", ("PASS" if (bottle.broken and bottle.value == 0) else "FAIL"))
	quit()
