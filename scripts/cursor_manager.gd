extends Node
## Global hardware-cursor controller (autoload `Cursors`). Swaps Godot's built-in cursor SHAPES to
## the Kenney hand set so the whole mouse-driven UI feels handmade:
##   ARROW          (resting)      -> hand, pointing
##   POINTING_HAND  (hover)        -> hand, open          (buttons / clickables opt in via
##                                    `mouse_default_cursor_shape = CURSOR_POINTING_HAND`)
##   CROSS          (paint canvas) -> drawing brush / eraser (the customization face plate)
## While the left mouse is HELD over a POINTING_HAND control the open hand becomes a CLOSED fist, so
## clicking a button reads as a grab.
##
## In-world reticles (the gameplay crosshair) are NOT handled here — the mouse is captured during play
## so the OS cursor is hidden; the HUD draws the dot/hand reticle itself (see hud.gd::_draw_crosshair).
##
## Kenney cursor pack is CC0 — safe for commercial release (unlike the lobby music, see CLAUDE.md §10).

const DIR := "res://assets/ui/cursors/"

# Hotspots are in image pixels (32x32, original scale). Hands point near the fingertip; the dot/brush
# at the obvious working tip so the click lands where the art implies.
const HS_POINT := Vector2(10, 2)
const HS_OPEN := Vector2(15, 2)
const HS_CLOSED := Vector2(15, 10)
const HS_BRUSH := Vector2(4, 4)
const HS_ERASER := Vector2(5, 27)

var _point: Texture2D
var _open: Texture2D
var _closed: Texture2D
var _brush: Texture2D
var _eraser: Texture2D


func _ready() -> void:
	# Stay live even while the tree is paused so the pause menu's buttons still get the hand cursors.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_point = load(DIR + "hand_point.png")
	_open = load(DIR + "hand_open.png")
	_closed = load(DIR + "hand_closed.png")
	_brush = load(DIR + "drawing_brush.png")
	_eraser = load(DIR + "drawing_eraser.png")
	apply_default()


## (Re)install the resting + hover + brush shapes. Call after anything that may have changed a shape.
func apply_default() -> void:
	if _point == null:
		return   # headless / missing import — leave the system cursor alone
	Input.set_custom_mouse_cursor(_point, Input.CURSOR_ARROW, HS_POINT)
	Input.set_custom_mouse_cursor(_open, Input.CURSOR_POINTING_HAND, HS_OPEN)
	Input.set_custom_mouse_cursor(_brush, Input.CURSOR_CROSS, HS_BRUSH)


## Point the CROSS shape (used by the customization face canvas) at the brush or the eraser.
func set_drawing(erase: bool) -> void:
	if _brush == null:
		return
	Input.set_custom_mouse_cursor(_eraser if erase else _brush, Input.CURSOR_CROSS,
		HS_ERASER if erase else HS_BRUSH)


func _input(event: InputEvent) -> void:
	if _open == null:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		# The hover hand clenches into a fist while the button is held -> a tactile "grab" on click.
		var pressed := (event as InputEventMouseButton).pressed
		Input.set_custom_mouse_cursor(_closed if pressed else _open, Input.CURSOR_POINTING_HAND,
			HS_CLOSED if pressed else HS_OPEN)
