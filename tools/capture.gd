extends Node
## Boots the lobby, waits for it to render, and saves the FIRST-PERSON view (what the player camera
## sees, incl. the detached hands) to a PNG so the in-engine result can actually be eyeballed.
## Run NON-headless (it needs a real renderer):
##   godot --path . res://tools/capture.tscn

const OUT := "C:/Users/Manu/Desktop/w/tools/_fp_capture.png"


func _ready() -> void:
	var lobby: Node = load("res://scenes/lobby.tscn").instantiate()
	get_tree().root.add_child.call_deferred(lobby)
	_grab()


func _grab() -> void:
	await get_tree().create_timer(3.0).timeout      # let the player spawn + scene settle
	var players := get_tree().get_nodes_in_group("players")
	print("PLAYERS=", players.size())
	for n in players:
		var cam = n.get("cam")
		if cam is Camera3D:
			(cam as Camera3D).current = true
			print("CAM SET current; fov=", (cam as Camera3D).fov)
	for i in 5:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(OUT)
		print("CAPTURED ", OUT)
	else:
		print("CAPTURE_FAILED null image")
	get_tree().quit()
