extends Control
## Title screen. Cinematic composition: the title + nav column sit on the LEFT, the angel
## looms out of the fog on the RIGHT. Solo play goes through the lobby; Host/Join start an
## ENet session. Full creative pass — no centred box.
##
## Fonts come from MenuUI (now Pirata One title + Alegreya Sans SC body), so the whole menu family
## (main / pause / options) shares the look — nothing font-related is hardcoded here.

const LOBBY := "res://scenes/lobby.tscn"
const GAME := "res://scenes/game.tscn"
const OPTIONS_SCENE := preload("res://scenes/ui/options_menu.tscn")

var _options: OptionsMenu
var _ip_field: LineEdit
var _join_row: Control
var _status: Label
var _bg_cam: Camera3D
var _fade: ColorRect
var _title: Control
var _tagline: Label
var _t := 0.0

@export_group("Backdrop PSX grade")
@export var backdrop_darken := 0.52     ## lower = dimmer lobby behind the menu
@export var backdrop_colors := 8        ## PSX colour-banding amount (lower = crunchier)
@export var backdrop_dither := 2        ## dither block size
@export var backdrop_desaturate := 0.42 ## drains the warm luxury colour
@export var background_dim := 0.46       ## extra black wash over the backdrop (behind the UI)

@export_group("Layout")
@export var left_margin := 96.0
@export var top_margin := 90.0          ## breathing room from the top of the screen to the title

var _nav: VBoxContainer


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Net.leave()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_bg()
	add_child(MenuUI.dim_bg(background_dim))
	add_child(MenuUI.vignette(0.78))
	_build_content()
	_build_fade()
	_build_horror_accent()

	if "--host" in OS.get_cmdline_user_args():
		_on_host.call_deferred()
	elif "--join" in OS.get_cmdline_user_args():
		_reveal_join.call_deferred()


# ---- layout -----------------------------------------------------------------
func _build_content() -> void:
	# Centred column: the title + nav stack live dead-centre of the screen.
	var col := VBoxContainer.new()
	_nav = col
	col.add_theme_constant_override("separation", 6)
	col.set_anchors_preset(Control.PRESET_FULL_RECT)   # fill the screen; centre the stack inside it
	col.alignment = BoxContainer.ALIGNMENT_CENTER       # vertical centring
	col.offset_top = -120                               # bias the whole stack up a touch
	add_child(col)
	_title = _build_title()                          # the painted DON'T BLINK logo (assets/ui/title.png)
	# Nudge the logo a hair right (the artwork sits a touch left of optical centre).
	var title_wrap := MarginContainer.new()
	title_wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	title_wrap.add_theme_constant_override("margin_left", 18)
	title_wrap.add_child(_title)
	col.add_child(title_wrap)

	col.add_child(_spacer(28))

	var play := _nav_button("Play", true); play.pressed.connect(_on_play)
	_nav_button("Host Game").pressed.connect(_on_host)
	_nav_button("Join by IP").pressed.connect(_reveal_join)

	# Hidden join row (LineEdit + Connect) revealed by "Join".
	_join_row = _build_join_row()
	col.add_child(_join_row)

	col.add_child(_spacer(6))
	_nav_button("Options").pressed.connect(_on_options)
	_nav_button("Quit").pressed.connect(func(): get_tree().quit())

	_status = MenuUI.hint("")
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_status.add_theme_color_override("font_color", Color(0.85, 0.78, 0.5))
	col.add_child(_status)

	# Footer centred along the bottom.
	var foot := MenuUI.hint("v0.9  ·  C to smoke  ·  F to flip the bird")
	foot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.offset_top = -52
	foot.offset_bottom = -28
	add_child(foot)

	play.grab_focus()

	# Entrance: the whole stack fades up under the black wipe.
	col.modulate.a = 0.0
	var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_interval(0.15)
	tw.tween_property(col, "modulate:a", 1.0, 0.8)


## A centred nav word added to the column (centre-aligned, shrink-to-fit so it sits mid-screen).
func _nav_button(text: String, big := false) -> Button:
	var b := MenuUI.button(text, big)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_nav.add_child(b)
	return b


## The DON'T BLINK wordmark as a painted image (assets/ui/title.png) instead of rendered type. Sized to
## the image's exact aspect (so the TitleEye overlay maps with no letterboxing); the _process
## shimmer/breathe still drives its modulate + scale, and the eye's pupil follows the cursor.
func _build_title() -> TextureRect:
	var t := TextureRect.new()
	t.texture = load("res://assets/ui/title.png")
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(600, 383)   # 1407x898 trimmed source, aspect 1.567 (no letterbox)
	t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_child(TitleEye.new())                 # the pupil that tracks the mouse
	return t


func _build_join_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.visible = false
	_ip_field = LineEdit.new()
	_ip_field.placeholder_text = "host IP  (127.0.0.1)"
	_ip_field.text = Net.last_ip
	_ip_field.custom_minimum_size = Vector2(220, 40)
	_ip_field.add_theme_font_override("font", MenuUI.font(MenuUI.BODY_FONT))
	_ip_field.add_theme_font_size_override("font_size", 18)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.04, 0.9)
	sb.set_corner_radius_all(4)
	sb.set_border_width_all(1)
	sb.border_color = MenuUI.ACCENT
	sb.content_margin_left = 12; sb.content_margin_right = 12
	sb.content_margin_top = 8; sb.content_margin_bottom = 8
	_ip_field.add_theme_stylebox_override("normal", sb)
	_ip_field.text_submitted.connect(func(_t): _on_join())
	row.add_child(_ip_field)
	var go := MenuUI.button("Connect")
	go.custom_minimum_size = Vector2(140, 44)
	go.pressed.connect(_on_join)
	row.add_child(go)
	return row


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _reveal_join() -> void:
	_join_row.visible = true
	_ip_field.grab_focus()
	_ip_field.select_all()


## A small taste of dread under the luxury hotel: rare light-dip flicker, a distant drone under the
## jazz, and a rare subtitle glitch. All tunable/disable-able on the HorrorAccent node.
func _build_horror_accent() -> void:
	var accent := MainMenuHorrorAccent.new()
	accent.name = "HorrorAccent"
	add_child(accent)
	accent.setup(self, _tagline)


func _build_fade() -> void:
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 0.9)


func _process(delta: float) -> void:
	_t += delta
	# Slow, gentle drift across the lounge toward the doorway — luxury establishing shot, never jarring.
	if _bg_cam != null:
		var x := 2.8 + sin(_t * 0.10) * 2.2
		var y := 1.58 + sin(_t * 0.18) * 0.07
		var z := 7.2 + cos(_t * 0.08) * 1.2
		_bg_cam.position = Vector3(x, y, z)
		_bg_cam.look_at(Vector3(-0.8, 1.25, -3.8), Vector3.UP)


# ---- 3D backdrop: the LUXURY HOTEL LOBBY as a live establishing shot ---------
func _build_bg() -> void:
	var svc := SubViewportContainer.new()
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# PSX grade on the BACKDROP ONLY (samples the lobby render, never the UI text on top): dither +
	# dim + cold desaturated wash — the warm hotel, but something's wrong under it.
	var sh := load("res://shaders/psx_backdrop.gdshader") as Shader
	if sh != null:
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("colors", backdrop_colors)
		mat.set_shader_parameter("dither_size", backdrop_dither)
		mat.set_shader_parameter("darken", backdrop_darken)
		mat.set_shader_parameter("desaturate", backdrop_desaturate)
		svc.material = mat
	add_child(svc)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.size = Vector2i(1600, 900)
	svc.add_child(sv)
	# The real lobby as a backdrop (its own warm lights + jazz; no players/HUD/toys/pause).
	var lobby: Node = load("res://scenes/lobby.tscn").instantiate()
	lobby.set("backdrop_mode", true)
	sv.add_child(lobby)
	# A slow panning camera through the lounge toward the elevator — tighter FOV compresses the depth
	# so the doorway reads as a focal point and the menu side falls into darker wall.
	_bg_cam = Camera3D.new()
	_bg_cam.fov = 52
	sv.add_child(_bg_cam)
	_bg_cam.current = true
	_bg_cam.position = Vector3(2.8, 1.58, 7.2)
	_bg_cam.look_at(Vector3(-0.8, 1.25, -3.8), Vector3.UP)


# ---- networking (unchanged behaviour) ---------------------------------------
func _on_play() -> void:
	Net.leave()
	Transition.change_scene(LOBBY)


func _on_host() -> void:
	if Net.host_game():
		_status.text = "Hosting on port %d — friends Join by your IP" % Net.DEFAULT_PORT
		Transition.change_scene(LOBBY)
	else:
		_status.text = "Could not open the server (port in use?)"


func _on_join() -> void:
	if not _join_row.visible:
		_reveal_join()
		return
	var ip := _ip_field.text.strip_edges()
	if ip == "":
		ip = "127.0.0.1"
	_status.text = "Connecting to %s..." % ip
	Net.connected_ok.connect(_on_connected, CONNECT_ONE_SHOT)
	Net.connect_failed.connect(_on_connect_failed, CONNECT_ONE_SHOT)
	if not Net.join_game(ip):
		_status.text = "Bad address."


func _on_connected() -> void:
	if Net.connect_failed.is_connected(_on_connect_failed):
		Net.connect_failed.disconnect(_on_connect_failed)
	Transition.change_scene(LOBBY)


func _on_connect_failed() -> void:
	if Net.connected_ok.is_connected(_on_connected):
		Net.connected_ok.disconnect(_on_connected)
	_status.text = "Could not reach that host."


func _on_options() -> void:
	if _options != null:
		return
	_options = OPTIONS_SCENE.instantiate()
	add_child(_options)
	_options.closed.connect(_on_options_closed)


func _on_options_closed() -> void:
	_options.queue_free()
	_options = null
