class_name MenuUI
extends Object
## Shared UI builders + the WATCHERS font system. The pairing is deliberate:
##   TITLE  = Blood Crow Expanded  — wide gothic-horror display (memorable, dramatic)
##   UI     = Super Pandora        — bold rounded display (the "friendslop" energy, readable)
##   BODY   = Crimson Text         — elegant serif for settings labels / hints
##   ACCENT = Blood Crow Italic    — creepy slanted tagline
## Horror title + punchy buttons = the co-op-horror duality. Buttons carry hover/click SFX so
## the whole UI feels tactile. Fonts are load()ed (ResourceLoader caches) — no statics to leak.

const ACCENT := Color(0.82, 0.16, 0.12)        # WATCHERS blood-red
const ACCENT_HOT := Color(1.0, 0.30, 0.18)
const TEXT := Color(0.90, 0.91, 0.95)
const TEXT_DIM := Color(0.66, 0.62, 0.66)
const INK := Color(0.04, 0.04, 0.055)

const TITLE_FONT := "res://assets/fonts/BloodCrow-Expanded.ttf"
const UI_FONT := "res://assets/fonts/SuperPandora.ttf"
const BODY_FONT := "res://assets/fonts/CrimsonText-SemiBold.ttf"
const ACCENT_FONT := "res://assets/fonts/BloodCrow-Italic.ttf"
const SFX_HOVER := "res://assets/audio/ui/gui_click_3.ogg"
const SFX_CLICK := "res://assets/audio/ui/gui_click_1.ogg"


static func font(path: String) -> FontFile:
	return load(path) as FontFile


# ---- atmosphere -------------------------------------------------------------
## Full-screen darkener with a faint red breath at the bottom — dread without obscuring.
static func dim_bg(a := 0.7) -> Control:
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.color = Color(INK.r, INK.g, INK.b, a)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(bg)
	var glow := ColorRect.new()
	glow.color = Color(0.16, 0.02, 0.02, a * 0.5)
	glow.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	glow.custom_minimum_size = Vector2(0, 240)
	glow.offset_top = -240
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(glow)
	return holder


## A radial vignette overlay (darkens the screen edges). Shader-based, cheap.
static func vignette(strength := 0.65) -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float strength = 0.65;
void fragment() {
	vec2 uv = SCREEN_UV - 0.5;
	float d = length(uv) * 1.35;
	float v = smoothstep(0.35, 0.95, d) * strength;
	COLOR = vec4(0.0, 0.0, 0.0, v);
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("strength", strength)
	r.material = m
	return r


# ---- type -------------------------------------------------------------------
static func title(text: String, size := 96) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(TITLE_FONT))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", TEXT)
	l.add_theme_constant_override("outline_size", 12)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_color_override("font_shadow_color", Color(0.5, 0.03, 0.02, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 6)
	l.add_theme_constant_override("shadow_outline_size", 10)
	return l


static func tagline(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(ACCENT_FONT))
	l.add_theme_font_size_override("font_size", 24)
	l.add_theme_color_override("font_color", Color(0.78, 0.32, 0.28))
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	return l


## A section header for the options screen: bold caps + an accent underline.
static func section(text: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", font(UI_FONT))
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color(0.92, 0.66, 0.5))
	v.add_child(l)
	var rule := ColorRect.new()
	rule.color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.55)
	rule.custom_minimum_size = Vector2(0, 2)
	v.add_child(rule)
	return v


static func label(text: String, col := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(BODY_FONT))
	l.add_theme_font_size_override("font_size", 19)
	l.add_theme_color_override("font_color", col)
	return l


static func hint(text: String) -> Label:
	var l := label(text, TEXT_DIM)
	l.add_theme_font_size_override("font_size", 15)
	return l


# ---- buttons ----------------------------------------------------------------
## The signature button: bold Super Pandora, a left accent spine that ignites on hover,
## tactile SFX. Left-aligned so it reads as a clean nav list (not a centred box stack).
static func button(text: String, big := false) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(330, 50 if big else 44)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", font(UI_FONT))
	b.add_theme_font_size_override("font_size", 26 if big else 22)
	b.add_theme_color_override("font_color", Color(0.80, 0.81, 0.86))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_focus_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(1, 0.92, 0.9))
	b.add_theme_stylebox_override("normal", _btn(Color(0.07, 0.07, 0.09, 0.5), 0, Color.TRANSPARENT))
	b.add_theme_stylebox_override("hover", _btn(Color(0.16, 0.06, 0.06, 0.92), 5, ACCENT_HOT))
	b.add_theme_stylebox_override("pressed", _btn(Color(0.10, 0.05, 0.05, 0.95), 5, ACCENT))
	b.add_theme_stylebox_override("focus", _btn(Color(0.12, 0.07, 0.08, 0.85), 5, ACCENT))
	_wire(b)
	return b


static func _btn(bg: Color, spine: int, spine_col: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(4)
	s.border_width_left = spine                 # the igniting accent spine
	s.border_color = spine_col
	s.content_margin_left = 18.0 + spine        # text slides right as the spine grows
	s.content_margin_right = 18
	s.content_margin_top = 9
	s.content_margin_bottom = 9
	return s


static func _wire(b: Button) -> void:
	if AudioGen.is_headless():
		return
	var click := AudioStreamPlayer.new()
	click.stream = load(SFX_CLICK); click.volume_db = -7.0
	b.add_child(click)
	var hover := AudioStreamPlayer.new()
	hover.stream = load(SFX_HOVER); hover.volume_db = -18.0
	b.add_child(hover)
	b.mouse_entered.connect(func(): if not b.disabled: hover.play())
	b.focus_entered.connect(func(): if not b.disabled: hover.play())
	b.pressed.connect(func(): click.play())


# ---- framed panel (pause / options) -----------------------------------------
## A dark panel with an accent top edge. Returns the inner VBox; the panel is on .get_meta("panel").
static func card(min_w := 420) -> VBoxContainer:
	var panel := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.045, 0.045, 0.06, 0.95)
	s.set_corner_radius_all(8)
	s.set_border_width_all(1)
	s.border_color = Color(0.18, 0.14, 0.16, 0.9)
	s.border_width_top = 3
	s.border_color = ACCENT
	s.content_margin_left = 44
	s.content_margin_right = 44
	s.content_margin_top = 34
	s.content_margin_bottom = 34
	s.shadow_color = Color(0, 0, 0, 0.7)
	s.shadow_size = 26
	panel.add_theme_stylebox_override("panel", s)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.custom_minimum_size = Vector2(min_w, 0)
	panel.add_child(v)
	v.set_meta("panel", panel)
	return v


# ---- controls (options) -----------------------------------------------------
## A labelled slider with a live numeric readout on the right.
static func slider_row(text: String, mn: float, mx: float, val: float, cb: Callable,
		fmt := "%d%%", scale := 100.0) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var head := HBoxContainer.new()
	var l := label(text)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(l)
	var val_l := label(fmt % (val * scale), Color(0.9, 0.7, 0.55))
	head.add_child(val_l)
	row.add_child(head)
	var s := HSlider.new()
	s.min_value = mn; s.max_value = mx; s.step = 0.01; s.value = val
	s.custom_minimum_size = Vector2(0, 18)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_slider(s)
	s.value_changed.connect(func(v):
		val_l.text = fmt % (v * scale)
		cb.call(v))
	row.add_child(s)
	return row


static func toggle_row(text: String, on: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = on
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", font(BODY_FONT))
	b.add_theme_font_size_override("font_size", 19)
	b.add_theme_color_override("font_color", Color(0.78, 0.79, 0.84))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_stylebox_override("normal", _btn(Color(0.07, 0.07, 0.09, 0.4), 0, Color.TRANSPARENT))
	b.add_theme_stylebox_override("hover", _btn(Color(0.13, 0.07, 0.07, 0.7), 4, ACCENT_HOT))
	b.add_theme_stylebox_override("pressed", _btn(Color(0.1, 0.06, 0.06, 0.8), 4, ACCENT))
	var refresh := func():
		b.text = "%s        %s" % [text, "ON" if b.button_pressed else "OFF"]
	refresh.call()
	b.toggled.connect(func(v):
		refresh.call()
		cb.call(v))
	_wire(b)
	return b


static func _style_slider(s: HSlider) -> void:
	var grab := StyleBoxFlat.new()
	grab.bg_color = ACCENT_HOT
	grab.set_corner_radius_all(8)
	grab.content_margin_left = 7; grab.content_margin_right = 7
	grab.content_margin_top = 7; grab.content_margin_bottom = 7
	s.add_theme_stylebox_override("grabber_area", grab)
	s.add_theme_stylebox_override("grabber_area_highlight", grab)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.55, 0.14, 0.12)
	fill.set_corner_radius_all(3)
	s.add_theme_stylebox_override("slider", _track())
	s.add_theme_stylebox_override("grabber_area", fill)


static func _track() -> StyleBoxFlat:
	var t := StyleBoxFlat.new()
	t.bg_color = Color(0.16, 0.16, 0.2)
	t.set_corner_radius_all(3)
	t.content_margin_top = 3; t.content_margin_bottom = 3
	return t
