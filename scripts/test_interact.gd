extends Node
## Headless proof the LOOK-AT + HOLD-E loop drives a task. Runs as a SCENE (so autoloads load):
##   Godot_console.exe --headless --path . res://scenes/test_interact.tscn --quit-after 400
## Instances the game, faces the player at a breaker lever, holds interact, checks aim + progress.

var _f := 0
var _player: WPlayer
var _task: SwitchSequenceTask
var _aim_seen := false
var _progress_seen := 0.0
var _placed := false
var _done := false
var _target: Interactable


func _ready() -> void:
	add_child(load("res://scenes/game.tscn").instantiate())


func _physics_process(_dt: float) -> void:
	if _done:
		return
	_f += 1
	if _f < 20:
		return
	if _player == null:
		for n in get_tree().get_nodes_in_group("players"):
			_player = n as WPlayer
		for n in get_tree().get_nodes_in_group("tasks"):
			if n is SwitchSequenceTask:
				_task = n
		if (_player == null or _task == null):
			if _f > 90:
				print("TEST FAIL: player=", _player, " task=", _task); _finish()
			return

	# Target the lever that's CORRECT to pull next (drive the sequence properly).
	_target = _correct_next_lever()
	if not _placed:
		_placed = true
		Input.action_press("interact")
	# Stand in front of the current target and aim at it.
	var head := _player.get_node_or_null("Head") as Node3D
	if _target != null and head != null:
		_player.global_position = _target.global_position + Vector3(0, -1.3, 1.6)
		var eye: Vector3 = head.global_position
		var to: Vector3 = _target.global_position - eye
		_player.rotation.y = atan2(to.x, to.z) + PI
		head.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())

	if _player.aimed != null:
		_aim_seen = true
	_progress_seen = maxf(_progress_seen, _task.get_progress())
	if _f % 40 == 0:
		print("frame ", _f, " aimed?", _player.aimed != null, " is_using=",
			(_player.is_using(_target) if _target != null else false),
			" progress=", snappedf(_task.get_progress(), 0.01), " done=", _task.done)
	if _task.done:
		print("TEST RESULT aim_found=", _aim_seen, " task_completed=TRUE")
		print("VERDICT: PASS")
		_finish()
		return
	if _f > 800:
		Input.action_release("interact")
		print("TEST RESULT aim_found=", _aim_seen, " max_progress=", _progress_seen, " done=", _task.done)
		print("VERDICT: ", "PASS" if (_aim_seen and _task.done) else "FAIL")
		_finish()


## The lever Interactable whose required order == the task's current step (the correct one to pull).
func _correct_next_lever() -> Interactable:
	var levers: Array = _task._levers
	var order: Array = _task._order
	var nxt: int = _task._next
	for i in levers.size():
		if order[i] == nxt:
			return levers[i]
	return null


func _scan(n: Node, out: Array) -> void:
	if n is Interactable:
		out.append(n)
	for c in n.get_children():
		_scan(c, out)


func _shape_count(n: Node) -> int:
	var c := 0
	for ch in n.get_children():
		if ch is CollisionShape3D:
			c += 1
	return c


func _finish() -> void:
	_done = true
	get_tree().quit()
