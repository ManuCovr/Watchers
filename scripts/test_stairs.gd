extends Node3D
## Headless stair climb test: drive the player into the stairs and log Y over time.

var _p: WPlayer
var _t := 0.0


func _ready() -> void:
	var house: Node = load("res://scenes/bunker.tscn").instantiate()
	add_child(house)
	_p = load("res://scenes/entities/player.tscn").instantiate()
	_p.name = "P"
	_p.position = Vector3(0, 0.6, -3)
	add_child(_p)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_press("move_forward")


func _physics_process(delta: float) -> void:
	if _p == null:
		return
	_t += delta
	if fmod(_t, 0.3) < delta:
		print("T=%.2f z=%.2f y=%.2f on_floor=%s on_wall=%s" % [
			_t, _p.global_position.z, _p.global_position.y,
			str(_p.is_on_floor()), str(_p.is_on_wall())])
	if _t > 6.0:
		print("RESULT final_y=%.2f climbed=%s" % [_p.global_position.y, str(_p.global_position.y > 2.5)])
		get_tree().quit()
