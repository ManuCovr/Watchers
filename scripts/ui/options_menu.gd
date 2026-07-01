class_name OptionsMenu
extends CanvasLayer
## Settings — reachable from the main menu AND the pause menu. process_mode = ALWAYS so it works
## while the tree is paused. Organised into sections (Display / Audio / Controls / Voice) with live
## readouts. Applies directly to DisplayServer / AudioServer / VoiceManager / WPlayer.

signal closed

var _root: Control


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_root.add_child(MenuUI.dim_bg(0.9))
	_root.add_child(MenuUI.vignette(0.6))

	var box := MenuUI.card(940)
	box.add_theme_constant_override("separation", 18)
	var panel: Control = box.get_meta("panel")
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(panel)

	var head := MenuUI.title("OPTIONS", 70)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(head)

	# Two roomy columns so nothing is cramped: left = Display + Controls, right = Audio + Voice.
	# A faint gold rule runs down the middle to separate them.
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 56)
	box.add_child(cols)
	var left := _column()
	var right := _column()
	cols.add_child(left)
	cols.add_child(_divider())
	cols.add_child(right)

	# --- LEFT: DISPLAY + CONTROLS ---
	left.add_child(MenuUI.section("Display"))
	left.add_child(MenuUI.toggle_row("Fullscreen", _is_fullscreen(), _on_fullscreen))
	left.add_child(MenuUI.toggle_row("V-Sync  (off = uncap FPS)",
		DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED, _on_vsync))
	left.add_child(_gap(34))
	left.add_child(MenuUI.section("Controls"))
	left.add_child(MenuUI.slider_row("Mouse Sensitivity", 0.3, 3.0,
		WPlayer.sens_multiplier, _on_sensitivity, "%.2f x", 1.0))
	left.add_child(MenuUI.hint("hold  TAB  to view objectives"))

	# --- RIGHT: AUDIO + VOICE ---
	right.add_child(MenuUI.section("Audio"))
	right.add_child(MenuUI.slider_row("Master Volume", 0.0, 1.0, _master_linear(), _on_volume))
	right.add_child(MenuUI.slider_row("Voice (proximity) Volume", 0.0, 1.5,
		VoiceManager.master_volume, _on_voice_volume))
	right.add_child(_gap(34))
	right.add_child(MenuUI.section("Voice Chat"))
	right.add_child(MenuUI.toggle_row("Mute My Mic   (M)", VoiceManager.self_muted,
		func(on): VoiceManager.self_muted = on))
	right.add_child(MenuUI.toggle_row("Deafen — silence all   (N)", VoiceManager.deafened,
		func(on): VoiceManager.deafened = on))

	box.add_child(_gap(34))
	var foot := HBoxContainer.new()
	var back := MenuUI.button("Back", true)
	foot.add_child(back)
	back.pressed.connect(func(): closed.emit())
	var esc := MenuUI.hint("ESC")
	esc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	esc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	esc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(esc)
	box.add_child(foot)
	back.grab_focus()

	# Entrance: the panel fades up and settles in with a soft spring.
	panel.pivot_offset = Vector2(470, 320)
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.97, 0.97)
	var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.parallel().tween_property(panel, "modulate:a", 1.0, 0.28)
	tw.parallel().tween_property(panel, "scale", Vector2.ONE, 0.32)


func _column() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 20)
	v.custom_minimum_size = Vector2(360, 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return v


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


## A faint vertical gold rule between the two option columns (fades top/bottom is overkill — a flat
## low-alpha line reads as "separator" without shouting).
func _divider() -> Control:
	var d := ColorRect.new()
	d.color = Color(MenuUI.ACCENT.r, MenuUI.ACCENT.g, MenuUI.ACCENT.b, 0.28)
	d.custom_minimum_size = Vector2(1, 0)
	d.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return d


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		closed.emit()


# ---- apply ------------------------------------------------------------------
func _is_fullscreen() -> bool:
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN

func _on_fullscreen(on: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)

func _on_vsync(on: bool) -> void:
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if on else DisplayServer.VSYNC_DISABLED)

func _on_volume(v: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(maxf(v, 0.0001)))

func _on_voice_volume(v: float) -> void:
	VoiceManager.set_master_volume(v)

func _on_sensitivity(mult: float) -> void:
	WPlayer.sens_multiplier = mult

func _master_linear() -> float:
	return db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")))
