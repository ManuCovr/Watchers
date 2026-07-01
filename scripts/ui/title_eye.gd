class_name TitleEye
extends Control
## A pupil that roams the title's amber eye-socket — the "O" in DON'T — toward the cursor. The baked
## pupil + catchlight were painted out of title.png, so this draws a fresh pupil on the clean iris.
## Pure 2D _draw (no viewport, so it ALWAYS renders); it's a child of the title TextureRect and all
## positions are fractions of that rect (the title is sized to the image's exact aspect — no letterbox).

@export var eye_frac := Vector2(0.398, 0.2684)   ## eye centre, fraction of the title rect
@export var pupil_frac := 0.021                  ## pupil radius / rect WIDTH
@export var iris_frac := 0.041                   ## iris radius / rect WIDTH (bounds the travel)
@export var reach_px := 560.0                    ## cursor distance for full deflection (screen px)
@export var smooth := 12.0

var _off := Vector2.ZERO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	# A full-rect child of a non-container Control doesn't reliably get sized — force our rect to match
	# the title TextureRect so _draw has real dimensions.
	var parent := get_parent() as Control
	if parent != null:
		size = parent.size
	var sz := size
	if sz.x <= 0.0:
		return
	var center := Vector2(eye_frac.x * sz.x, eye_frac.y * sz.y)
	var pr := pupil_frac * sz.x
	var ir := iris_frac * sz.x
	var max_off := maxf(0.0, ir - pr - 2.0)
	# Global coords are robust to the title's nested layout.
	var eye_global := get_global_rect().position + center
	var dir := get_global_mouse_position() - eye_global
	var target := Vector2.ZERO
	if dir.length() > 0.5:
		var k := clampf(dir.length() / reach_px, 0.0, 1.0)   # eases out as the cursor nears the eye
		target = dir.normalized() * max_off * k
	_off = _off.lerp(target, clampf(delta * smooth, 0.0, 1.0))
	queue_redraw()


func _draw() -> void:
	var sz := size
	if sz.x <= 0.0:
		return
	var center := Vector2(eye_frac.x * sz.x, eye_frac.y * sz.y)
	var pr := pupil_frac * sz.x
	var pc := center + _off
	draw_circle(pc, pr, Color(0.04, 0.03, 0.02))                                     # pupil
	draw_circle(pc + Vector2(pr * 0.42, -pr * 0.5), pr * 0.34, Color(1, 1, 1, 0.92)) # catchlight
