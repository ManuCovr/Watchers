extends Node
## Headless proof the POWER OUTAGE works: forces an outage, checks the facility lights die + the red
## reset button arms, then restores and checks the lights come back. Run as a scene:
##   Godot_console.exe --headless --path . res://scenes/test_power.tscn --quit-after 200


func _ready() -> void:
	add_child(load("res://scenes/game.tscn").instantiate())
	await _run()
	get_tree().quit()


func _run() -> void:
	for i in 30:
		await get_tree().physics_frame
	var game := get_node_or_null("Game")
	var power: PowerSystem = game.power if game != null else null
	var btn: PowerResetButton = null
	for n in get_tree().get_nodes_in_group("power_reset"):
		btn = n
	if power == null or power._lights.is_empty():
		print("TEST FAIL: power=", power, " btn=", btn)
		return

	var lit_before := _lit(power)
	power._trigger(true)            # force a blackout
	await get_tree().physics_frame
	var lit_during := _lit(power)
	var armed := btn != null and btn.enabled
	power._trigger(false)           # restore
	await get_tree().physics_frame
	var lit_after := _lit(power)

	print("POWER lights lit: before=", lit_before, " during_outage=", lit_during, " after=", lit_after,
		" | red_button_armed_during=", armed, " powered_after=", power.powered)
	var ok := lit_before > 0 and lit_during == 0 and lit_after == lit_before and armed and power.powered
	print("VERDICT: ", "PASS" if ok else "FAIL")


func _lit(power: PowerSystem) -> int:
	var n := 0
	for d in power._lights:
		if (d["l"] as Light3D).light_energy > 0.01:
			n += 1
	return n
