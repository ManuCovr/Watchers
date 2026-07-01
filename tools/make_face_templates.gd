extends SceneTree
## Generates blank 512x512 FACE TEMPLATES on the Desktop for you to draw on, plus a faint GUIDE
## showing where the eyes/mouth land on the blob's plate. Draw a face on a template, rename it
## (e.g. "goofy.png"), and drop it into res://assets/player_faces/ — it auto-appears as a preset
## in the lobby customizer (filename = label).
##
##   Godot_console.exe --headless --path <proj> --script res://tools/make_face_templates.gd

const SIZE := 512
const BG := Color(0.91, 0.89, 0.85)        # the clean off-white plate (matches face_default.tres)
const GUIDE := Color(0.80, 0.78, 0.74)     # faint guide marks
const DESKTOP := "C:/Users/Manu/Desktop/watchers_face_templates"
const PROJECT_DIR := "res://assets/player_faces"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(DESKTOP)
	for i in 6:
		var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		img.fill(BG)
		img.save_png("%s/template_%d.png" % [DESKTOP, i + 1])
	_save_guide()

	# Project preset folder + a readme so the (otherwise empty) dir survives in git.
	var proj := ProjectSettings.globalize_path(PROJECT_DIR)
	DirAccess.make_dir_recursive_absolute(proj)
	var f := FileAccess.open(PROJECT_DIR + "/README.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("Drop 512x512 PNG faces here. Filename = preset label in the lobby customizer.\n"
			+ "Draw on the templates in Desktop/watchers_face_templates, then rename + copy them here.\n")
		f.close()
	print("make_face_templates: wrote templates to ", DESKTOP, " and preset dir ", proj)
	quit()


func _save_guide() -> void:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(BG)
	_ring(img, Vector2(180, 205), 42)          # left eye zone
	_ring(img, Vector2(332, 205), 42)          # right eye zone
	# mouth zone arc (faint smile guide)
	var prev := Vector2.ZERO
	for i in 25:
		var t := float(i) / 24.0
		var p := Vector2(lerpf(168.0, 344.0, t), 330.0 - 60.0 * sin(PI * t))
		if i > 0:
			_line(img, prev, p)
		prev = p
	# plate border
	_rect(img, 24, 24, SIZE - 24, SIZE - 24)
	img.save_png(DESKTOP + "/GUIDE_reference.png")


func _px(img: Image, x: int, y: int) -> void:
	if x >= 0 and x < SIZE and y >= 0 and y < SIZE:
		img.set_pixel(x, y, GUIDE)

func _ring(img: Image, c: Vector2, rad: float) -> void:
	for i in 90:
		var a := TAU * float(i) / 90.0
		_px(img, int(c.x + cos(a) * rad), int(c.y + sin(a) * rad))

func _line(img: Image, a: Vector2, b: Vector2) -> void:
	var steps := maxi(1, int(a.distance_to(b)))
	for i in steps + 1:
		var p := a.lerp(b, float(i) / float(steps))
		_px(img, int(p.x), int(p.y))

func _rect(img: Image, x0: int, y0: int, x1: int, y1: int) -> void:
	for x in range(x0, x1):
		_px(img, x, y0); _px(img, x, y1)
	for y in range(y0, y1):
		_px(img, x0, y); _px(img, x1, y)
