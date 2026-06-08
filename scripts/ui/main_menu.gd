extends Control
## Title screen. Cinematic composition: the title + nav column sit on the LEFT, the angel
## looms out of the fog on the RIGHT. Solo play goes through the lobby; Host/Join start an
## ENet session. Full creative pass — no centred box.

const LOBBY := "res://scenes/lobby.tscn"
const GAME := "res://scenes/game.tscn"
const OPTIONS_SCENE := preload("res://scenes/ui/options_menu.tscn")

var _options: OptionsMenu
var _ip_field: LineEdit
var _join_row: Control
var _status: Label
var _bg_angel: Node3D
var _fade: ColorRect
var _title: Label
var _t := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Net.leave()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_bg()
	add_child(MenuUI.dim_bg(0.34))
	add_child(MenuUI.vignette(0.7))
	_build_content()
	_build_fade()

	if "--host" in OS.get_cmdline_user_args():
		_on_host.call_deferred()
	elif "--join" in OS.get_cmdline_user_args():
		_reveal_join.call_deferred()


# ---- layout -----------------------------------------------------------------
func _build_content() -> void:
	# Left-anchored column. Anchored to the left edge, vertically centred.
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	col.position = Vector2(96, -210)
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(col)

	_title = MenuUI.title("WATCHERS", 104)
	col.add_child(_title)
	var tag := MenuUI.tagline("they move when you look away")
	tag.position.x = 6
	col.add_child(tag)

	col.add_child(_spacer(26))

	var play := MenuUI.button("Play  (Solo)", true)
	col.add_child(play); play.pressed.connect(_on_play)
	var host := MenuUI.button("Host  Co-op")
	col.add_child(host); host.pressed.connect(_on_host)
	var join := MenuUI.button("Join  by IP")
	col.add_child(join); join.pressed.connect(_reveal_join)

	# Hidden join row (LineEdit + Connect) revealed by "Join".
	_join_row = _build_join_row()
	col.add_child(_join_row)

	col.add_child(_spacer(6))
	var opt := MenuUI.button("Options")
	col.add_child(opt); opt.pressed.connect(_on_options)
	var quit := MenuUI.button("Quit")
	col.add_child(quit); quit.pressed.connect(func(): get_tree().quit())

	_status = MenuUI.hint("")
	_status.add_theme_color_override("font_color", Color(0.85, 0.78, 0.5))
	col.add_child(_status)

	# Footer bottom-left.
	var foot := MenuUI.hint("v0.9  ·  co-op horror  ·  ESC menu  ·  hold F to flip the bird")
	foot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	foot.position = Vector2(96, -40)
	add_child(foot)

	play.grab_focus()


func _build_join_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
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
	if _bg_angel != null:
		_bg_angel.rotate_y(delta * 0.22)
	if _title != null:
		# a faint, irregular flicker on the title (unsettling, not distracting)
		var f := 0.94 + 0.06 * sin(_t * 2.3) * sin(_t * 7.7)
		_title.modulate = Color(f, f, f)


# ---- 3D backdrop: the angel looming on the RIGHT, slowly turning -------------
func _build_bg() -> void:
	var svc := SubViewportContainer.new()
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(svc)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.size = Vector2i(1600, 900)
	svc.add_child(sv)

	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.012, 0.012, 0.018)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.09, 0.09, 0.13)
	e.ambient_light_energy = 0.35
	e.fog_enabled = true
	e.fog_density = 0.08
	e.fog_light_color = Color(0.05, 0.04, 0.06)
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	we.environment = e
	sv.add_child(we)

	var cam := Camera3D.new()
	cam.fov = 52
	sv.add_child(cam)
	cam.look_at_from_position(Vector3(-0.2, 1.85, 4.6), Vector3(1.7, 1.25, 0), Vector3.UP)
	cam.current = true

	_bg_angel = Node3D.new()
	_bg_angel.position = Vector3(1.7, 1.2, 0)        # framed on the RIGHT third
	sv.add_child(_bg_angel)
	var angel := MeshInstance3D.new()
	var mesh = load("res://assets/models/angel/Biblically_Accurate_Angel.obj")
	if mesh != null:
		angel.mesh = mesh
		angel.scale = Vector3.ONE * 1.3
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.045, 0.045, 0.055)
		m.roughness = 1.0
		angel.material_override = m
		_bg_angel.add_child(angel)
	var eye := MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = 0.13; sm.height = 0.26
	eye.mesh = sm
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.emission_enabled = true
	em.emission = Color(1.0, 0.07, 0.04)
	em.emission_energy_multiplier = 5.0
	em.albedo_color = Color(1.0, 0.07, 0.04)
	eye.material_override = em
	eye.position = Vector3(0, 0.62, 0.92)
	_bg_angel.add_child(eye)

	var key := SpotLight3D.new()
	key.light_color = Color(0.7, 0.74, 0.95)
	key.light_energy = 3.2
	key.spot_range = 16; key.spot_angle = 42
	sv.add_child(key)
	key.look_at_from_position(Vector3(3.6, 4.0, 3.2), Vector3(1.7, 1.4, 0), Vector3.UP)


# ---- networking (unchanged behaviour) ---------------------------------------
func _on_play() -> void:
	Net.leave()
	get_tree().change_scene_to_file(LOBBY)


func _on_host() -> void:
	if Net.host_game():
		_status.text = "Hosting on port %d — friends Join by your IP" % Net.DEFAULT_PORT
		get_tree().change_scene_to_file(LOBBY)
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
	get_tree().change_scene_to_file(LOBBY)


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
