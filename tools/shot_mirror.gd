extends SceneTree
## Dumps the lobby mirror SubViewport's OWN texture, to prove whether it renders.

func _initialize() -> void:
	var ps := load("res://scenes/lobby.tscn")
	get_root().add_child((ps as PackedScene).instantiate())
	var t := create_timer(2.0)
	t.timeout.connect(_grab)


func _grab() -> void:
	var sv := get_root().find_child("MirrorView", true, false)
	if sv == null:
		print("MIRROR: no MirrorView found")
	else:
		var img: Image = (sv as SubViewport).get_texture().get_image()
		img.save_png("res://_shot_mirrortex.png")
		print("MIRROR tex saved; size=", img.get_size())
	quit()
