extends SceneTree
## Preview the player character rig: instance it, light it, tint it, open the mouth a
## bit, and save a PNG so we can SEE the body. Run NON-headless:
##   Godot.exe --path <proj> --script res://tools/shot_char.gd -- scene=res://actors/player/character.tscn out=res://_char.png

func _initialize() -> void:
	var scene_path := "res://actors/player/character.tscn"
	var out := "res://_char.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("scene="):
			scene_path = a.substr(6)
		elif a.begins_with("out="):
			out = a.substr(4)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.1, 0.11, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.4, 0.4, 0.45)
	e.ambient_light_energy = 0.6
	env.environment = e
	get_root().add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	sun.light_energy = 1.6
	get_root().add_child(sun)

	var rig = load(scene_path).instantiate()
	get_root().add_child(rig)
	if rig.has_method("set_tint"):
		rig.set_tint(Color.from_hsv(0.08, 0.5, 0.85))
	if rig.has_method("set_mouth_open"):
		rig.set_mouth_open(0.6)

	var cam := Camera3D.new()
	get_root().add_child(cam)
	# View from -Z (the character's front, since forward = -Z).
	cam.look_at_from_position(Vector3(0.6, 1.4, -2.6), Vector3(0, 1.05, 0), Vector3.UP)
	cam.current = true

	var t := create_timer(1.2)
	t.timeout.connect(func():
		var img := get_root().get_texture().get_image()
		img.save_png(out)
		print("SHOT_CHAR saved ", out)
		quit())
