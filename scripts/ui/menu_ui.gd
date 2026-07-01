class_name MenuUI
extends Object
## Shared UI builders + the WATCHERS font system. The pairing is deliberate:
##   TITLE  = Blood Crow Expanded  — wide gothic-horror display (memorable, dramatic)
##   UI     = Super Pandora        — bold rounded display (the "friendslop" energy, readable)
##   BODY   = Crimson Text         — elegant serif for settings labels / hints
##   ACCENT = Blood Crow Italic    — creepy slanted tagline
## Horror title + punchy buttons = the co-op-horror duality. Buttons carry hover/click SFX so
## the whole UI feels tactile. Fonts are load()ed (ResourceLoader caches) — no statics to leak.

## LUXURY HOTEL palette — champagne gold on warm charcoal (the blood-red is gone; deep red is
## reserved for real danger only). Consistent across main menu / pause / options.
const ACCENT := Color(0.78, 0.62, 0.32)        # champagne / brass
const ACCENT_HOT := Color(0.96, 0.82, 0.46)    # bright gold (hover/focus)
const TEXT := Color(0.93, 0.91, 0.86)          # warm ivory
const TEXT_DIM := Color(0.66, 0.62, 0.55)
const INK := Color(0.05, 0.045, 0.05)

# THREE fonts, clear hierarchy: Daydream = logo, Cinzel = elegant accents/headings, Super Pandora =
# everything readable (buttons + body + HUD). Keep it to these.
# Menu font system (shared by main / pause / options + the menu THEME resources/ui/menu_theme.tres):
#   TITLE = Pirata One        — gothic display, "undertaker elegance" under the luxury hotel
#   UI/BODY = Alegreya Sans SC — readable-but-soulful small caps (buttons, body, hints)
const TITLE_FONT := "res://assets/fonts/Pirata_One/PirataOne-Regular.ttf"
const HEADING_FONT := "res://assets/fonts/Alegreya_Sans_SC/AlegreyaSansSC-Bold.ttf"
const UI_FONT := "res://assets/fonts/Alegreya_Sans_SC/AlegreyaSansSC-Medium.ttf"
const BODY_FONT := "res://assets/fonts/Alegreya_Sans_SC/AlegreyaSansSC-Medium.ttf"
const ACCENT_FONT := "res://assets/fonts/Pirata_One/PirataOne-Regular.ttf"
## Heavy small-caps — the "fuller", premium weight for nav words + the tagline (not skinny/basic).
const BOLD_FONT := "res://assets/fonts/Alegreya_Sans_SC/AlegreyaSansSC-Black.ttf"
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
	# A faint warm breath at the bottom — a SMOOTH gradient (not a flat band, which read as an ugly
	# black bar). Fades in over the lower third of the screen.
	var glow := ColorRect.new()
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gsh := Shader.new()
	gsh.code = """
shader_type canvas_item;
uniform vec4 col : source_color;
void fragment() {
	float g = smoothstep(0.62, 1.0, SCREEN_UV.y);
	COLOR = vec4(col.rgb, col.a * g);
}"""
	var gm := ShaderMaterial.new()
	gm.shader = gsh
	gm.set_shader_parameter("col", Color(0.16, 0.04, 0.03, a * 0.55))
	glow.material = gm
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
	l.add_theme_color_override("font_color", Color(0.96, 0.9, 0.76))   # warm ivory/gold
	l.add_theme_constant_override("outline_size", 10)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_color_override("font_shadow_color", Color(0.55, 0.42, 0.16, 0.55))   # gold glow
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 5)
	l.add_theme_constant_override("shadow_outline_size", 10)
	return l


## A title with a soft champagne SIGNAGE GLOW — layered translucent copies behind the crisp text
## (drawn via show_behind_parent so they don't disturb layout). Returns the crisp Label; the glow
## layers are its children named "Glow*", so callers can pulse them. Approximates bloom without an
## environment, keeps the foreground text crisp + readable.
static func glow_title(text: String, size := 96, glow := Color(0.97, 0.86, 0.58), strength := 0.5) -> Label:
	var l := title(text, size)
	for spec in [[34, 0.32], [18, 0.55]]:        # [outline halo px, alpha factor]
		var g := Label.new()
		g.name = "Glow%d" % int(spec[0])
		g.text = text
		g.show_behind_parent = true
		g.set_anchors_preset(Control.PRESET_FULL_RECT)
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		g.add_theme_font_override("font", font(TITLE_FONT))
		g.add_theme_font_size_override("font_size", size)
		var a: float = strength * float(spec[1])
		g.add_theme_color_override("font_color", Color(glow.r, glow.g, glow.b, a))
		g.add_theme_constant_override("outline_size", int(spec[0]))
		g.add_theme_color_override("font_outline_color", Color(glow.r, glow.g, glow.b, a * 0.7))
		l.add_child(g)
	return l


## Pulse the glow layers of a glow_title() label (call from _process). amount 0..1, t = elapsed time.
static func pulse_glow(title_label: Label, t: float, speed := 1.3, amount := 0.35) -> void:
	if title_label == null:
		return
	var k := 1.0 - amount + amount * (0.5 + 0.5 * sin(t * speed))
	for c in title_label.get_children():
		if c is Label:
			(c as Label).self_modulate.a = k


static func tagline(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(BOLD_FONT))   # heavy small-caps — fuller, not skinny
	l.add_theme_font_size_override("font_size", 40)
	l.add_theme_color_override("font_color", Color(0.93, 0.82, 0.55))
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	# soft champagne glow so it reads as warm signage rather than plain text
	l.add_theme_color_override("font_shadow_color", Color(0.85, 0.66, 0.32, 0.5))
	l.add_theme_constant_override("shadow_outline_size", 10)
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 0)
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
## A STANDALONE WORD — no box, no spine, no gold outline. Heavy small-caps (Alegreya Black) so it
## reads full and premium, not skinny; ivory that turns gold on hover/focus, with a small left-pivot
## lean + tactile SFX. The signature nav button.
static func button(text: String, big := false) -> Button:
	var sz := 56 if big else 46
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 74 if big else 62)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND   # open hand on hover (Cursors autoload)
	b.add_theme_font_override("font", font(BOLD_FONT))
	b.add_theme_font_size_override("font_size", sz)
	b.add_theme_color_override("font_color", TEXT)              # warm ivory
	b.add_theme_color_override("font_hover_color", ACCENT_HOT)  # gold on hover/focus
	b.add_theme_color_override("font_focus_color", ACCENT_HOT)
	b.add_theme_color_override("font_pressed_color", Color(1, 0.97, 0.85))
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))   # BLACK legibility outline
	b.add_theme_constant_override("outline_size", 7)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, _empty_btn())
	_wire(b)
	_animate(b)
	return b


static func _empty_btn() -> StyleBoxEmpty:
	var s := StyleBoxEmpty.new()
	s.content_margin_left = 2
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s


## Hover/focus: the word leans forward slightly from its left edge (layout-safe, scale never reflows).
static func _animate(b: Button) -> void:
	var lean := func(grow: bool):
		if not is_instance_valid(b):
			return
		b.pivot_offset = Vector2(0, b.size.y * 0.5)
		var tw := b.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(b, "scale", Vector2(1.05, 1.05) if grow else Vector2.ONE, 0.18)
	b.mouse_entered.connect(func(): lean.call(true))
	b.mouse_exited.connect(func(): lean.call(false))
	b.focus_entered.connect(func(): lean.call(true))
	b.focus_exited.connect(func(): lean.call(false))


static func _btn(bg: Color, spine: int, spine_col: Color, glow := 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(4)
	s.border_width_left = spine                 # the igniting accent spine (drawn inside the left margin)
	s.border_color = spine_col
	if glow > 0.0:                              # soft champagne bloom around the selected/hover row
		s.shadow_color = Color(ACCENT_HOT.r, ACCENT_HOT.g, ACCENT_HOT.b, glow)
		s.shadow_size = 7
	# CONSTANT margins across every state so the button width never changes on hover -> text never clips.
	s.content_margin_left = 22
	s.content_margin_right = 26
	s.content_margin_top = 8
	s.content_margin_bottom = 8
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
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
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
	fill.bg_color = ACCENT          # gold fill (was red)
	fill.set_corner_radius_all(3)
	fill.shadow_color = Color(ACCENT_HOT.r, ACCENT_HOT.g, ACCENT_HOT.b, 0.35)   # faint gold active glow
	fill.shadow_size = 5
	s.add_theme_stylebox_override("slider", _track())
	s.add_theme_stylebox_override("grabber_area", fill)


static func _track() -> StyleBoxFlat:
	var t := StyleBoxFlat.new()
	t.bg_color = Color(0.16, 0.16, 0.2)
	t.set_corner_radius_all(3)
	t.content_margin_top = 3; t.content_margin_bottom = 3
	return t
