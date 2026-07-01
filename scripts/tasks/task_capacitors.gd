@tool
class_name CapacitorTask
extends Task
## A bunker MAINTENANCE haul: carry capacitors (`capacitor_etx_2`) one at a time from the rack to
## a socket bank across the room. Look at a capacitor + E to lift it; you then move SLOWLY with no
## sprint (see player.carrying), so you're exposed while you shuffle it over. Look at a free socket
## + E to seat it. All sockets filled = done. Inconvenient and tense on purpose.

@export var count := 2                          ## capacitors to transport
@export var socket_offset := Vector3(0, 0, 6.0) ## where the socket bank sits, relative to task origin
@export var pickup_spacing := 0.6
@export var socket_spacing := 0.6
@export var model := "res://assets/tech/capacitor_etx_2.glb"
@export var model_scale := 4.0

var _caps: Array[Node3D] = []                   # the capacitor models
var _pickups: Array[Interactable] = []          # rack hit-boxes (one per capacitor)
var _sockets: Array[Interactable] = []          # socket hit-boxes
var _socket_pos: Array[Vector3] = []            # world seat position per socket
var _carried_by: Array = []                     # WPlayer or null, per capacitor
var _placed: Array[bool] = []                   # per capacitor
var _socket_filled: Array[bool] = []            # per socket
var _placed_n := 0


func _build() -> void:
	if is_default_title():
		task_title = "Transport the capacitors"
	task_category = &"carry"
	difficulty = 2
	estimated_duration = 10.0
	# A rack the capacitors start on.
	var rack := make_model("res://assets/psx/Furniture/shelf_mp_3.glb",
		Vector3(1.4, 1.0, 0.5), Color(0.18, 0.18, 0.2), 1.0)
	rack.position = Vector3(0, 0, -0.4)
	add_child(rack)

	var start_x := -float(count - 1) * pickup_spacing * 0.5
	for i in count:
		# Capacitor model + its pickup hit-box.
		var cap := make_model(model, Vector3(0.18, 0.3, 0.18), Color(0.6, 0.55, 0.3), model_scale)
		cap.position = Vector3(start_x + i * pickup_spacing, 0.95, 0.0)
		add_child(cap)
		_caps.append(cap)
		var pk := make_interactable(Vector3(0.34, 0.42, 0.34), "Lift capacitor")
		pk.position = cap.position
		add_child(pk)
		_pickups.append(pk)
		_carried_by.append(null)
		_placed.append(false)

	# The socket bank: a powered device with `count` seats.
	var bank := make_model("res://assets/tech/fuse_box_etx_1.glb",
		Vector3(1.2, 1.2, 0.4), Color(0.14, 0.14, 0.16), 2.0)
	bank.position = socket_offset + Vector3(0, 0, 0)
	add_child(bank)
	var sstart_x := -float(count - 1) * socket_spacing * 0.5
	for i in count:
		var sock := make_interactable(Vector3(0.4, 0.4, 0.4), "Seat capacitor")
		sock.position = socket_offset + Vector3(sstart_x + i * socket_spacing, 1.0, 0.3)
		add_child(sock)
		_sockets.append(sock)
		_socket_pos.append(sock.position)
		_socket_filled.append(false)
		# An empty-socket marker light (red until filled).
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(0.9, 0.2, 0.15)
		lamp.light_energy = 0.8
		lamp.omni_range = 0.8
		sock.add_child(lamp)
		sock.set_meta("lamp", lamp)


func _task_process(_delta: float) -> void:
	for nd in get_tree().get_nodes_in_group("players"):
		var p := nd as WPlayer
		if p == null or p._downed:
			continue
		# Pick up a capacitor (only if your hands are free).
		if p.carrying == null:
			for i in _pickups.size():
				if _placed[i] or _carried_by[i] != null:
					continue
				if p.aimed == _pickups[i] and p.consume_interact():
					_carried_by[i] = p
					_pickups[i].enabled = false
					p.grab_carry(_caps[i])
					play_sfx("res://assets/audio/sfx/button_15.ogg", -7.0)
					break
		else:
			# Carrying — seat it in a free socket you're looking at.
			for s in _sockets.size():
				if _socket_filled[s]:
					continue
				if p.aimed == _sockets[s] and p.consume_interact():
					_seat(p, s)
					break


func _seat(p: WPlayer, s: int) -> void:
	var model_node := p.drop_carry()
	if model_node == null:
		return
	# Find which capacitor this is.
	var ci := _caps.find(model_node)
	if ci >= 0:
		_placed[ci] = true
		_carried_by[ci] = null
	model_node.global_position = to_global(_socket_pos[s])
	model_node.rotation = Vector3.ZERO
	_socket_filled[s] = true
	_placed_n += 1
	var lamp := _sockets[s].get_meta("lamp", null) as OmniLight3D
	if lamp != null:
		lamp.light_color = Color(0.2, 0.95, 0.35)
	play_sfx("res://assets/audio/sfx/button_4.ogg", -4.0)
	report_progress(float(_placed_n) / float(count))
	if _placed_n >= count:
		mark_done()


func get_progress() -> float:
	return float(_placed_n) / float(maxi(count, 1))
