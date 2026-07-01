class_name HorrorTextOverlay
extends CanvasLayer
## A tiny, reusable PANIC-TEXT overlay — short blunt words (RUN / WATCH / DOWN) that snap in,
## hold, then glitch/fade out. Deliberately SEPARATE from the HUD (scripts/ui/hud.gd): this is
## diegetic dread, not interface, so it never touches the gold key-prompt layout. Sits ABOVE the
## PSX post layer (70) so the blackletter face stays crisp and readable.
##
## Use it from anywhere:  overlay.flash("RUN")   /   overlay.flash("DOWN", DANGER, 1.6)
## Spam-guarded: a new flash overrides the current one, and it self-hides when idle.

## Pirata One — gothic display face reserved for this panic layer (kept out of the menus, which
## stay Daydream + Super Pandora per the project's two-font rule).
const FONT_PATH := "res://assets/fonts/Pirata_One/PirataOne-Regular.ttf"

const IVORY := Color(0.92, 0.90, 0.86)
const DANGER := Color(1.0, 0.16, 0.12)
const SICK := Color(0.66, 0.82, 0.42)

@export var font_size := 132
@export var default_duration := 1.5
@export var jitter := 7.0           ## max px of nervous horizontal shake while held
@export var enabled := true         ## master switch (lets options/accessibility silence it)

var _control: Control
var _label: Label
var _t := 0.0
var _dur := 0.0
var _active := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	layer = 75
	_rng.randomize()
	_control = Control.new()
	_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_control)

	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f := load(FONT_PATH) as Font
	if f != null:
		_label.add_theme_font_override("font", f)
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 14)
	# A faint shadow gives the word weight against a dark corridor.
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_label.add_theme_constant_override("shadow_offset_x", 4)
	_label.add_theme_constant_override("shadow_offset_y", 5)
	_control.add_child(_label)
	_control.visible = false


## Flash one blunt word. `word` is upper-cased; keep it SHORT (RUN, HIDE, DON'T LOOK).
func flash(word: String, color := DANGER, duration := -1.0) -> void:
	if not enabled or _label == null:
		return
	_label.text = word.to_upper()
	_label.add_theme_color_override("font_color", color)
	_dur = duration if duration > 0.0 else default_duration
	_t = 0.0
	_active = true
	_control.visible = true


func _process(delta: float) -> void:
	if not _active:
		return
	_t += delta
	var k := _t / _dur
	if k >= 1.0:
		_active = false
		_control.visible = false
		return
	# Envelope: hard punch-in (0..0.10), steady hold, glitch-flicker fade (0.70..1.0).
	var alpha := 1.0
	var scl := 1.0
	if k < 0.10:
		var u := k / 0.10
		alpha = u
		scl = lerpf(1.18, 1.0, u)                 # snaps down to size — a flinch
	elif k > 0.70:
		var u := (k - 0.70) / 0.30
		alpha = (1.0 - u)
		# stutter the alpha so it reads as a failing signal, not a smooth UI fade
		if _rng.randf() < 0.4:
			alpha *= _rng.randf_range(0.2, 0.7)
	# nervous shake, strongest at the start, easing off
	var shake := jitter * (1.0 - k)
	_control.position = Vector2(_rng.randf_range(-shake, shake), _rng.randf_range(-shake * 0.5, shake * 0.5))
	_control.scale = Vector2(scl, scl)
	_control.pivot_offset = _control.size * 0.5
	_label.modulate.a = clampf(alpha, 0.0, 1.0)
