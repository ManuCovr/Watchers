class_name PauseMenu
extends CanvasLayer
## In-game pause overlay. LOCAL only — game.gd blocks this player's input but the world keeps
## running for everyone else (co-op friendly). Same UI family as the main menu: gothic title,
## bold buttons, vignette. Left-anchored panel (not a centred box).

signal resume_requested

const OPTIONS_SCENE := preload("res://scenes/ui/options_menu.tscn")
const MAIN_MENU := "res://scenes/main_menu.tscn"

var _root: Control
var _options: OptionsMenu


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_root.add_child(MenuUI.dim_bg(0.55))
	_root.add_child(MenuUI.vignette(0.7))

	# Left-anchored column to match the main menu's composition.
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	col.position = Vector2(110, -150)
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(col)

	col.add_child(MenuUI.title("PAUSED", 76))
	col.add_child(MenuUI.tagline("the others haven't stopped"))
	col.add_child(_spacer(20))

	var resume := MenuUI.button("Resume", true)
	col.add_child(resume); resume.pressed.connect(func(): resume_requested.emit())
	var opt := MenuUI.button("Options")
	col.add_child(opt); opt.pressed.connect(_on_options)
	var menu := MenuUI.button("Leave to Menu")
	col.add_child(menu); menu.pressed.connect(_on_main_menu)
	var quit := MenuUI.button("Quit Game")
	col.add_child(quit); quit.pressed.connect(func(): get_tree().quit())
	resume.grab_focus()


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _unhandled_input(e: InputEvent) -> void:
	if not visible or _options != null:
		return
	if e.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		resume_requested.emit()


func _on_options() -> void:
	if _options != null:
		return
	_root.visible = false
	_options = OPTIONS_SCENE.instantiate()
	add_child(_options)
	_options.closed.connect(_on_options_closed)


func _on_options_closed() -> void:
	_options.queue_free()
	_options = null
	_root.visible = true


func _on_main_menu() -> void:
	get_tree().paused = false
	WPlayer.input_blocked = false
	get_tree().change_scene_to_file(MAIN_MENU)
