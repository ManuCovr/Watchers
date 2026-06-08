class_name PSXPost
extends CanvasLayer
## Drop-in full-screen PSX post: ordered-dither colour reduction over the whole frame. Add it once
## per gameplay scene (game + lobby) — NOT to menus. Sits below the pause UI so menus stay crisp.
## Editor-tunable colours/dither via the exports.

@export var colors := 14
@export var dither_size := 2
@export var dithering := true


func _ready() -> void:
	layer = 70
	var sh := load("res://shaders/psx_post.gdshader") as Shader
	if sh == null:
		return
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("colors", colors)
	mat.set_shader_parameter("dither_size", dither_size)
	mat.set_shader_parameter("dithering", dithering)
	rect.material = mat
	add_child(rect)
