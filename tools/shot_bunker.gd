extends Node
## Boots the bunker and screenshots several room/tunnel connections so the seams can be eyeballed.
## Run NON-headless (needs a real renderer):
##   godot --path . res://tools/shot_bunker.tscn
## A camera-mounted light is added so geometry is readable regardless of the dim bunker mood.

const OUT := "C:/Users/Manu/Desktop/w/tools/_bunker_"

# [name, camera_pos, look_at] — chosen at known connections from build_bunker.gd's layout.
var _shots := [
	# arrival(0,0,0 size14) -> control(0,0,-30): N doorway of arrival at z=-7; tunnel z=-7..-22
	["arrival_to_tunnel", Vector3(0, 1.6, -3.0), Vector3(0, 1.4, -12.0)],
	["tunnel_to_control", Vector3(0, 1.6, -19.0), Vector3(0, 1.4, -26.0)],
	# control(0,0,-30 size16) -> power(-28,0,-30): W doorway of control at x=-8
	["control_to_power", Vector3(-5.0, 1.6, -30.0), Vector3(-16.0, 1.4, -30.0)],
	# junction(0,0,-110 size14) -> obs_n(0,0,-134): S doorway of junction at z=-117
	["junction_to_obs", Vector3(0, 1.6, -113.0), Vector3(0, 1.4, -124.0)],
	# obs_n(0,0,-134) -> central_chamber(0,0,-176 size44): S doorway of obs_n
	["obs_to_chamber", Vector3(0, 1.6, -140.0), Vector3(0, 2.0, -156.0)],
]
var _i := 0
var _cam: Camera3D


func _ready() -> void:
	var bunker: Node = load("res://scenes/bunker.tscn").instantiate()
	get_tree().root.add_child.call_deferred(bunker)
	_cam = Camera3D.new()
	_cam.fov = 75.0
	_cam.current = true
	get_tree().root.add_child.call_deferred(_cam)
	var lamp := OmniLight3D.new()
	lamp.light_energy = 6.0
	lamp.omni_range = 22.0
	_cam.add_child.call_deferred(lamp)
	_run()


func _run() -> void:
	await get_tree().create_timer(2.0).timeout      # let scene settle + nav bake
	for shot in _shots:
		_cam.global_position = shot[1]
		_cam.look_at(shot[2], Vector3.UP)
		for i in 4:
			await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img != null:
			img.save_png(OUT + str(shot[0]) + ".png")
			print("SHOT ", shot[0])
		else:
			print("SHOT_FAIL ", shot[0])
	print("SHOTS_DONE")
	get_tree().quit()
