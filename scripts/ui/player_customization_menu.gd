class_name PlayerCustomizationMenu
extends CanvasLayer
## LOBBY-ONLY blob customizer — a luxury-hotel "photo-booth / vanity" character editor. A live 3D
## preview of YOUR blob sits on the left (body + hands + outline + painted face, all updating live,
## drag or use the arrows to spin it); the controls sit on the right: body/hands colour, outline
## colour, and a real MS-Paint face canvas (left-click paint, right-click erase) with brush colours,
## size, eraser, clear, and starter faces. Everything writes to the PlayerCustomization autoload, so
## the live lobby model AND the preview update instantly and the look carries into the bunker.
##
## Opened by the lobby vanity sign; emits `closed` when done (the lobby recaptures the mouse + pushes
## the face in multiplayer). The preview model is visual-only (own SubViewport world, no collision,
## not in the "players" group, isolated duplicated materials) so it never affects gameplay or sync.

signal closed

const MODEL_SCENE := "res://actors/player_models/player_blob_black.tscn"

const BODY_SWATCHES := [
	Color(0.10, 0.10, 0.12), Color(0.55, 0.56, 0.6), Color(0.78, 0.16, 0.16),
	Color(0.16, 0.34, 0.72), Color(0.2, 0.6, 0.27), Color(0.86, 0.74, 0.16),
	Color(0.5, 0.2, 0.62), Color(0.86, 0.45, 0.12), Color(0.9, 0.45, 0.6),
	Color(0.93, 0.9, 0.83),
]
const OUTLINE_SWATCHES := [
	Color(0.93, 0.9, 0.83), Color(0.04, 0.04, 0.05), Color(0.78, 0.62, 0.32),
	Color(0.78, 0.16, 0.16), Color(0.16, 0.34, 0.72), Color(0.2, 0.6, 0.27),
	Color(0.5, 0.2, 0.62), Color(0.2, 0.7, 0.74),
]
const BRUSH_SWATCHES := [
	Color(0, 0, 0), Color(0.98, 0.98, 0.98), Color(0.85, 0.15, 0.15),
	Color(0.15, 0.35, 0.8), Color(0.2, 0.65, 0.25), Color(0.95, 0.8, 0.1),
	Color(0.55, 0.2, 0.65), Color(0.95, 0.5, 0.15),
]

var _canvas: TextureRect
var _brush_color := Color(0, 0, 0)
var _brush_radius := 10
var _erase := false
var _painting := false
var _last_uv := Vector2.ZERO

# live preview
var _preview_model: Node3D
var _preview_yaw := PI               # spun so the face turns toward the preview camera
var _dragging := false
var _spin_vel := 0.0                 # angular velocity (rad/s) — fling momentum after a drag
var _idle_spin := 0.2                # rad/s gentle baseline the fling decays back toward

# swatch selection highlight
var _body_swatches: Array[Button] = []
var _outline_swatches: Array[Button] = []
var _brush_btns: Array[Button] = []


func _ready() -> void:
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	PlayerCustomization.changed.connect(_apply_to_preview)
	_apply_to_preview.call_deferred()   # after the preview model has built its materials


func _exit_tree() -> void:
	if PlayerCustomization.changed.is_connected(_apply_to_preview):
		PlayerCustomization.changed.disconnect(_apply_to_preview)


func _build() -> void:
	add_child(MenuUI.dim_bg(0.86))
	add_child(MenuUI.vignette(0.6))

	var box := MenuUI.card(1300)
	box.add_theme_constant_override("separation", 18)
	var panel: Control = box.get_meta("panel")
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	box.add_child(_build_header())
	box.add_child(_rule())

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 56)
	box.add_child(cols)
	cols.add_child(_build_preview())       # LEFT: live character
	cols.add_child(_build_controls())      # RIGHT: colour + face controls

	box.add_child(_gap(8))
	box.add_child(_rule())
	box.add_child(_build_footer())

	_refresh_swatches()

	# Panel entrance
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.985, 0.985)
	panel.pivot_offset = Vector2(590, 360)
	var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.parallel().tween_property(panel, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_property(panel, "scale", Vector2.ONE, 0.3)


# ---- header -----------------------------------------------------------------
func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := MenuUI.title("CUSTOMIZE", 58)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	titles.add_child(head)
	titles.add_child(MenuUI.tagline("make your little guy"))
	row.add_child(titles)
	var pill := _pill("LOBBY ONLY")
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pill)
	return row


# ---- live 3D preview --------------------------------------------------------
func _build_preview() -> Control:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _glass_frame())
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	frame.add_child(v)
	v.add_child(MenuUI.section("Preview"))

	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(448, 512)
	svc.mouse_filter = Control.MOUSE_FILTER_STOP        # capture drag-to-spin
	svc.gui_input.connect(_on_preview_input)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.transparent_bg = true
	sv.msaa_3d = Viewport.MSAA_4X
	sv.size = Vector2i(448, 512)
	svc.add_child(sv)
	_populate_preview_world(sv)
	v.add_child(svc)
	return frame


func _populate_preview_world(sv: SubViewport) -> void:
	var root := Node3D.new()
	sv.add_child(root)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.95, 0.9, 0.82)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	root.add_child(we)

	var key := DirectionalLight3D.new()        # warm key from front-above
	key.light_energy = 1.25
	key.light_color = Color(1.0, 0.96, 0.88)
	key.rotation_degrees = Vector3(-42, 22, 0)
	root.add_child(key)
	var rim := OmniLight3D.new()                # cool back rim so the silhouette/outline pops
	rim.light_color = Color(0.6, 0.7, 0.95)
	rim.light_energy = 2.2
	rim.omni_range = 6.0
	rim.position = Vector3(-1.4, 2.2, -2.0)
	root.add_child(rim)

	_preview_model = load(MODEL_SCENE).instantiate() as Node3D
	_preview_model.rotation.y = _preview_yaw
	root.add_child(_preview_model)

	var cam := Camera3D.new()
	cam.fov = 32
	cam.position = Vector3(0.0, 1.28, 2.7)
	cam.look_at(Vector3(0.0, 1.18, 0.0), Vector3.UP)
	root.add_child(cam)
	cam.current = true


## Push the current look onto the preview blob. Cheap; safe to call every `changed`.
func _apply_to_preview() -> void:
	if _preview_model != null and is_instance_valid(_preview_model):
		PlayerCustomization.apply_to(_preview_model)


func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = (event as InputEventMouseButton).pressed
		if _dragging:
			_spin_vel = 0.0                                  # grab it — kill the spin while held
	elif event is InputEventMouseMotion and _dragging:
		var dx := (event as InputEventMouseMotion).relative.x
		_preview_yaw += dx * 0.01
		_spin_vel = dx * 0.45                                # remember the fling speed for release


func _process(delta: float) -> void:
	if _preview_model == null or not is_instance_valid(_preview_model):
		return
	if not _dragging:
		# the fling keeps spinning and eases back to a gentle idle turntable
		_spin_vel = lerpf(_spin_vel, _idle_spin, clampf(delta * 1.2, 0.0, 1.0))
		_preview_yaw += _spin_vel * delta
	_preview_model.rotation.y = _preview_yaw


# ---- right column: colours + face ------------------------------------------
func _build_controls() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	col.custom_minimum_size = Vector2(680, 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	col.add_child(MenuUI.section("Body & Hands"))
	col.add_child(MenuUI.hint("hands always match the body"))
	_body_swatches = _swatch_grid(BODY_SWATCHES, func(c): PlayerCustomization.set_body_color(c), 44)
	col.add_child(_grid_of(_body_swatches))

	col.add_child(_gap(6))
	col.add_child(MenuUI.section("Outline"))
	_outline_swatches = _swatch_grid(OUTLINE_SWATCHES, func(c): PlayerCustomization.set_outline_color(c), 44)
	col.add_child(_grid_of(_outline_swatches))

	col.add_child(_gap(6))
	col.add_child(MenuUI.section("Face Paint"))
	col.add_child(_build_face_block())
	return col


func _build_face_block() -> Control:
	var wrap := HBoxContainer.new()
	wrap.add_theme_constant_override("separation", 22)

	# the canvas, framed like a drawing board
	var board := VBoxContainer.new()
	board.add_theme_constant_override("separation", 6)
	_canvas = TextureRect.new()
	_canvas.texture = PlayerCustomization.face_texture
	_canvas.custom_minimum_size = Vector2(320, 320)
	_canvas.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_canvas.stretch_mode = TextureRect.STRETCH_SCALE
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.mouse_default_cursor_shape = Control.CURSOR_CROSS   # drawing brush / eraser (Cursors autoload)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _glass_frame())
	frame.add_child(_canvas)
	board.add_child(frame)
	_canvas.gui_input.connect(_on_canvas_input)
	var keys := HBoxContainer.new()
	keys.alignment = BoxContainer.ALIGNMENT_CENTER
	keys.add_theme_constant_override("separation", 18)
	keys.add_child(MenuUI.hint("LEFT-CLICK paint"))
	keys.add_child(MenuUI.hint("RIGHT-CLICK erase"))
	board.add_child(keys)
	wrap.add_child(board)

	# tools to the right of the board
	var tools := VBoxContainer.new()
	tools.add_theme_constant_override("separation", 10)
	tools.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(MenuUI.label("Brush"))
	_brush_btns = _swatch_grid(BRUSH_SWATCHES, _pick_brush, 30)
	tools.add_child(_grid_of(_brush_btns))
	tools.add_child(MenuUI.slider_row("Size", 2.0, 40.0, float(_brush_radius),
		func(v): _brush_radius = int(v), "%d px", 1.0))
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 12)
	trow.add_child(MenuUI.toggle_row("Eraser", false, func(on):
		_erase = on
		Cursors.set_drawing(on)))
	tools.add_child(trow)

	tools.add_child(_gap(8))
	tools.add_child(MenuUI.section("Starter faces"))
	var presets := HFlowContainer.new()
	presets.add_theme_constant_override("h_separation", 6)
	presets.add_theme_constant_override("v_separation", 6)
	for pname in PlayerCustomization.preset_names():
		var n: String = pname
		presets.add_child(_chip_btn(n, func(): PlayerCustomization.apply_preset(n)))
	tools.add_child(presets)
	wrap.add_child(tools)
	return wrap


# ---- footer -----------------------------------------------------------------
func _build_footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var done := MenuUI.button("Done", true)
	done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	done.pressed.connect(_close)
	row.add_child(done)
	row.add_child(_chip_btn("Reset Face", func(): PlayerCustomization.clear_face()))
	row.add_child(_chip_btn("Randomize", _randomize))
	return row


func _randomize() -> void:
	PlayerCustomization.set_body_color(BODY_SWATCHES[randi() % BODY_SWATCHES.size()])
	PlayerCustomization.set_outline_color(OUTLINE_SWATCHES[randi() % OUTLINE_SWATCHES.size()])
	var names := PlayerCustomization.preset_names()
	if not names.is_empty():
		PlayerCustomization.apply_preset(names[randi() % names.size()])
	_refresh_swatches()


# ---- swatches ---------------------------------------------------------------
## Build a list of colour-swatch buttons (selection highlight via _refresh_swatches).
func _swatch_grid(colors: Array, cb: Callable, sz: int) -> Array[Button]:
	var out: Array[Button] = []
	for c in colors:
		var b := Button.new()
		b.custom_minimum_size = Vector2(sz, sz)
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.set_meta("col", c)
		var col: Color = c
		b.pressed.connect(func():
			cb.call(col)
			_refresh_swatches())
		out.append(b)
	return out


func _grid_of(buttons: Array[Button]) -> Control:
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for b in buttons:
		grid.add_child(b)
	return grid


## Re-evaluate every swatch's border: gold + glow on the active colour, a warm rim otherwise (so even
## the pure-black / cream swatches stay visible against the dark glass).
func _refresh_swatches() -> void:
	for b in _body_swatches:
		_style_swatch(b, _col_eq(b.get_meta("col"), PlayerCustomization.body_color))
	for b in _outline_swatches:
		_style_swatch(b, _col_eq(b.get_meta("col"), PlayerCustomization.outline_color))
	for b in _brush_btns:
		_style_swatch(b, _col_eq(b.get_meta("col"), _brush_color) and not _erase)


func _style_swatch(b: Button, selected: bool) -> void:
	var c: Color = b.get_meta("col")
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(5)
	sb.set_border_width_all(3 if selected else 2)
	sb.border_color = MenuUI.ACCENT_HOT if selected else Color(0.62, 0.58, 0.52, 0.8)
	if selected:
		sb.shadow_color = Color(MenuUI.ACCENT_HOT.r, MenuUI.ACCENT_HOT.g, MenuUI.ACCENT_HOT.b, 0.6)
		sb.shadow_size = 8
	var sbh := sb.duplicate() as StyleBoxFlat
	sbh.border_color = MenuUI.ACCENT_HOT
	sbh.set_border_width_all(3)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sbh)
	b.add_theme_stylebox_override("pressed", sbh)


func _col_eq(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02


func _pick_brush(c: Color) -> void:
	_brush_color = c
	_erase = false
	Cursors.set_drawing(false)
	_refresh_swatches()


# ---- small widgets ----------------------------------------------------------
## A small labelled card button (gold outline) — for presets, clear, footer extras.
func _chip_btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", MenuUI.font(MenuUI.UI_FONT))
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", MenuUI.TEXT)
	b.add_theme_color_override("font_hover_color", MenuUI.ACCENT_HOT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.075, 0.09, 0.9)
	sb.set_corner_radius_all(5)
	sb.set_border_width_all(1)
	sb.border_color = MenuUI.ACCENT
	sb.content_margin_left = 14; sb.content_margin_right = 14
	sb.content_margin_top = 7; sb.content_margin_bottom = 7
	var sbh := sb.duplicate() as StyleBoxFlat
	sbh.border_color = MenuUI.ACCENT_HOT
	sbh.bg_color = Color(0.14, 0.10, 0.06, 0.95)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sbh)
	b.add_theme_stylebox_override("pressed", sbh)
	b.pressed.connect(cb)
	return b


## A small gold-outlined pill (the "LOBBY ONLY" tag).
func _pill(text: String) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.09, 0.05, 0.6)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(1)
	sb.border_color = MenuUI.ACCENT
	sb.content_margin_left = 14; sb.content_margin_right = 14
	sb.content_margin_top = 5; sb.content_margin_bottom = 5
	p.add_theme_stylebox_override("panel", sb)
	var l := MenuUI.label(text, MenuUI.ACCENT_HOT)
	l.add_theme_font_override("font", MenuUI.font(MenuUI.UI_FONT))
	l.add_theme_font_size_override("font_size", 15)
	p.add_child(l)
	return p


## Smoked-glass framed panel stylebox (gold border) — preview + face board.
func _glass_frame() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.02, 0.02, 0.03, 0.55)
	s.set_corner_radius_all(6)
	s.set_border_width_all(2)
	s.border_color = MenuUI.ACCENT
	s.content_margin_left = 10; s.content_margin_right = 10
	s.content_margin_top = 10; s.content_margin_bottom = 10
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 12
	return s


func _rule() -> Control:
	var r := ColorRect.new()
	r.color = Color(MenuUI.ACCENT.r, MenuUI.ACCENT.g, MenuUI.ACCENT.b, 0.4)
	r.custom_minimum_size = Vector2(0, 2)
	return r


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


# ---- painting (unchanged behaviour) -----------------------------------------
func _on_canvas_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_painting = mb.pressed
			if mb.pressed:
				PlayerCustomization.begin_stroke()      # one undo snapshot per stroke
				_last_uv = _uv(mb.position)
				_paint_to(_last_uv, mb.button_index == MOUSE_BUTTON_RIGHT)
	elif event is InputEventMouseMotion and _painting:
		var uv := _uv((event as InputEventMouseMotion).position)
		var erase_now := _erase or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		PlayerCustomization.paint(_last_uv, uv, _brush_color, _brush_radius, erase_now)
		_last_uv = uv


func _paint_to(uv: Vector2, right: bool) -> void:
	PlayerCustomization.paint(uv, uv, _brush_color, _brush_radius, _erase or right)


func _uv(pos: Vector2) -> Vector2:
	var s := _canvas.size
	if s.x <= 0.0 or s.y <= 0.0:
		return Vector2.ZERO
	return Vector2(clampf(pos.x / s.x, 0.0, 1.0), clampf(pos.y / s.y, 0.0, 1.0))


func _close() -> void:
	PlayerCustomization.save_now()
	Cursors.set_drawing(false)   # reset the paint cursor to the brush for next time
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_Z and event.ctrl_pressed:
		get_viewport().set_input_as_handled()
		PlayerCustomization.undo()
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()
