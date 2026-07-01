extends SceneTree
## Functional test for the DELIVERY COUNTING logic, without relying on RigidBody teleport (flaky in a
## detached test). Let a food object settle where it naturally rests (a spawn marker = proven solid
## floor), MOVE the bay onto it, then check the tally goes 0 -> 1.


func _initialize() -> void:
	var g := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(g)
	_run(g)


func _run(g: Node) -> void:
	for i in 80:                      # let objects spawn + settle on the floor
		await physics_frame
	var mgr = g.get_node_or_null("RecoveryManager")
	var zone = mgr.get_node_or_null("ElevatorDeliveryZone") if mgr else null
	if zone == null:
		print("TEST: FAIL no zone"); quit(); return

	var food = null
	for o in get_nodes_in_group("recoverables"):
		if String(o.category) == "food" and o.linear_velocity.length() < 0.3:
			food = o; break
	if food == null:
		print("TEST: FAIL no rested food"); quit(); return

	print("TEST: food rests at ", food.global_position, " vel=", food.linear_velocity.length())
	print("TEST: before delivered=", mgr.delivered)
	# Put the bay right under the resting food (box bottom on its floor).
	zone.global_position = food.global_position - Vector3(0, 0.2, 0)

	for i in 120:
		await physics_frame
	print("TEST: after delivered=", mgr.delivered)
	print("TEST: %s" % ("PASS" if int(mgr.delivered.get("food", 0)) >= 1 else "FAIL"))
	quit()
