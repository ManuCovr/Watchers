extends SceneTree
## Debug screenshot harness. Instances a scene, waits for it to render, saves a PNG
## so we can SEE what the game looks like. Run NON-headless:
##   Godot.exe --path <proj> --script res://tools/shot.gd -- scene=res://scenes/game.tscn out=res://_shot.png

var _out := "res://_shot.png"
var _cam: Camera3D


func _initialize() -> void:
	var scene_path := "res://scenes/game.tscn"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("scene="):
			scene_path = a.substr(6)
		elif a.begins_with("out="):
			_out = a.substr(4)
	var ps := load(scene_path)
	if ps == null:
		print("SHOT: could not load ", scene_path)
		quit()
		return
	get_root().add_child(ps.instantiate())
	# Optional free inspection camera: cam=x,y,z look=x,y,z
	var has_cam := false
	var cam_pos := Vector3.ZERO
	var look := Vector3.ZERO
	for a in OS.get_cmdline_user_args():
		if a.begins_with("cam="):
			var p: PackedStringArray = a.substr(4).split(",")
			cam_pos = Vector3(float(p[0]), float(p[1]), float(p[2]))
			has_cam = true
		elif a.begins_with("look="):
			var p2: PackedStringArray = a.substr(5).split(",")
			look = Vector3(float(p2[0]), float(p2[1]), float(p2[2]))
	if has_cam:
		_cam = Camera3D.new()
		get_root().add_child(_cam)
		_cam.look_at_from_position(cam_pos, look, Vector3.UP)
		_cam.current = true
	var t := create_timer(1.5)
	t.timeout.connect(_grab)


func _grab() -> void:
	if _cam != null:
		_cam.make_current()          # re-assert over the scene's own (player) camera
		await process_frame
	var img := get_root().get_texture().get_image()
	img.save_png(_out)
	print("SHOT saved ", _out, " size ", img.get_size())
	quit()
