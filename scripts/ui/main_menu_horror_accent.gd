class_name MainMenuHorrorAccent
extends Node
## A SMALL taste of dread for the luxury-hotel main menu — the hint that something under the hotel
## is wrong. Three independent, tunable accents, each disable-able. Deliberately rare and gentle:
## a rare flicker beats constant horror. Add as a child of the menu and call setup(menu_root, tagline).
##
##   MainMenu
##    └─ HorrorAccent   (this node: light-dip flicker + distant drone + rare subtitle glitch)

@export_group("Light flicker (power dip under the hotel)")
@export var flicker_enabled := true
@export var first_flicker_delay := 2.5      ## first dip soon after load so the menu reads as "alive"
@export var flicker_min_delay := 7.0
@export var flicker_max_delay := 18.0
@export var flicker_intensity := 0.55      ## max darken alpha of a dip (0..1) — keep subtle

@export_group("Subtitle glitch")
@export var title_glitch_enabled := true
@export var first_glitch_delay := 6.0       ## first glitch a few seconds in
@export var title_glitch_min_delay := 12.0
@export var title_glitch_max_delay := 30.0

@export_group("Distant audio undercurrent")
@export var audio_accent_enabled := true
@export var audio_accent_volume_db := -30.0   ## very low — sits UNDER the lobby jazz
## A safe local drone from the project's mx_ pack (NOT the licence-flagged jazz).
@export var audio_accent_stream := "res://assets/audio/sfx/sfx_drone_mx_1.ogg"

const GLITCH_FONT := "res://assets/fonts/Pirata_One/PirataOne-Regular.ttf"
const GLITCH_WORDS := ["RUN", "DON'T BLINK", "LOOK", "WAIT", "DOWN"]
const GLITCH_COLOR := Color(0.78, 0.18, 0.14)

var _overlay: ColorRect
var _audio: AudioStreamPlayer
var _tagline: Label
var _tag_text := "Don't Blink."
var _tag_font: Font
var _tag_color := Color(0.86, 0.73, 0.46)
var _flicker_t := 0.0
var _glitch_t := 0.0
var _glitching := false


func setup(menu_root: Control, tagline: Label) -> void:
	# Flicker overlay — a brief near-black dip over the whole menu reads as the hotel lights
	# stuttering on unstable power. Mouse-transparent so it never blocks the buttons.
	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_root.add_child(_overlay)

	if tagline != null:
		_tagline = tagline
		_tag_text = tagline.text
		_tag_font = tagline.get_theme_font("font")
		_tag_color = tagline.get_theme_color("font_color")

	if audio_accent_enabled and not AudioGen.is_headless():
		var stream := load(audio_accent_stream)
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		if stream != null:
			_audio = AudioStreamPlayer.new()
			_audio.stream = stream
			_audio.volume_db = audio_accent_volume_db
			add_child(_audio)
			_audio.play()

	_flicker_t = first_flicker_delay      # first occurrences happen soon, then settle into rare cadence
	_glitch_t = first_glitch_delay


func _reset_flicker() -> void:
	_flicker_t = randf_range(flicker_min_delay, flicker_max_delay)

func _reset_glitch() -> void:
	_glitch_t = randf_range(title_glitch_min_delay, title_glitch_max_delay)


func _process(delta: float) -> void:
	if flicker_enabled and _overlay != null:
		_flicker_t -= delta
		if _flicker_t <= 0.0:
			_do_flicker()
			_reset_flicker()
	if title_glitch_enabled and _tagline != null and not _glitching:
		_glitch_t -= delta
		if _glitch_t <= 0.0:
			_do_glitch()
			_reset_glitch()


## A quick stutter: one or two short dips, like a fluorescent tube fighting to stay on.
func _do_flicker() -> void:
	var i := flicker_intensity
	var tw := create_tween()
	tw.tween_property(_overlay, "color:a", i, 0.04)
	tw.tween_property(_overlay, "color:a", 0.0, 0.07)
	if randf() < 0.6:                     # sometimes a second, weaker blip
		tw.tween_property(_overlay, "color:a", i * 0.6, 0.03)
		tw.tween_property(_overlay, "color:a", 0.0, 0.10)


## The subtitle briefly corrupts to a blunt panic word (gothic Pirata One), then restores. Layout-safe
## (scale punch from centre, no position change), readable, and over in a fraction of a second.
func _do_glitch() -> void:
	if not is_instance_valid(_tagline):
		return
	_glitching = true
	var word: String = GLITCH_WORDS[randi() % GLITCH_WORDS.size()]
	var gfont := load(GLITCH_FONT) as Font
	_tagline.text = word
	if gfont != null:
		_tagline.add_theme_font_override("font", gfont)
	_tagline.add_theme_color_override("font_color", GLITCH_COLOR)
	_tagline.pivot_offset = _tagline.size * 0.5
	# stutter the alpha a couple of frames, a tiny scale flinch, then snap back to the elegant tagline
	var tw := create_tween()
	tw.tween_property(_tagline, "modulate:a", 0.3, 0.03)
	tw.tween_property(_tagline, "modulate:a", 1.0, 0.03)
	tw.parallel().tween_property(_tagline, "scale", Vector2(1.06, 1.06), 0.06)
	tw.tween_interval(0.12)
	tw.tween_property(_tagline, "scale", Vector2.ONE, 0.05)
	tw.finished.connect(_restore_tagline)


func _restore_tagline() -> void:
	if not is_instance_valid(_tagline):
		_glitching = false
		return
	_tagline.text = _tag_text
	if _tag_font != null:
		_tagline.add_theme_font_override("font", _tag_font)
	_tagline.add_theme_color_override("font_color", _tag_color)
	_tagline.modulate.a = 1.0
	_tagline.scale = Vector2.ONE
	_glitching = false
