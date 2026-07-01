extends CanvasLayer
## Global scene TRANSITION + LOADING SCREEN. Autoloaded as `Transition` (persists across scene
## swaps, so it can cover the swap itself). Every scene change in the game routes through here:
##
##   Transition.change_scene("res://scenes/lobby.tscn")            # quick fade
##   Transition.change_scene("res://scenes/game.tscn", true)       # fade + threaded LOADING screen
##   Transition.reload(true)                                       # fade + reload current scene
##
## The loading screen is themed to the project (champagne gold on charcoal, MenuUI fonts) and uses
## a "DESCENDING" motif — you take the elevator down into the bunker. Threaded load keeps the frame
## alive so the progress bar animates instead of hard-freezing on the heavy game scene.

@export var fade_time := 0.45

var _busy := false
var _fade: ColorRect
var _load_root: Control
var _bar_fill: ColorRect
var _bar_w := 360.0
var _status: Label
var _tip: Label
var _dots_t := 0.0
var _loading_visible := false

const TIPS := [
	"Cover your angle.",
	"Look away to move. Look back to freeze it.",
	"Don't blink.",
	"A thrown phone stuns it.",
	"Slam the red button when the power dies.",
	"Nobody escapes alone.",
]


func _ready() -> void:
	# Above the lobby's own descent fade (CanvasLayer 200), so the loading screen shows on the elevator
	# path too — not just on reset.
	layer = 250
	process_mode = Node.PROCESS_MODE_ALWAYS    # works even while the tree is paused
	_build()


func _build() -> void:
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP   # blocks clicks mid-transition
	_fade.visible = false
	add_child(_fade)

	# --- loading screen (child of the fade so it's always over black) ---
	_load_root = Control.new()
	_load_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_load_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_root.visible = false
	_fade.add_child(_load_root)

	# faint warm breath at the bottom — a SMOOTH gradient (not a flat band, which read as an ugly bar)
	var glow := ColorRect.new()
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gsh := Shader.new()
	gsh.code = """
shader_type canvas_item;
uniform vec4 col : source_color;
void fragment() {
	float g = smoothstep(0.55, 1.0, SCREEN_UV.y);
	COLOR = vec4(col.rgb, col.a * g);
}"""
	var gm := ShaderMaterial.new()
	gm.shader = gsh
	gm.set_shader_parameter("col", Color(0.16, 0.10, 0.03, 0.6))
	glow.material = gm
	_load_root.add_child(glow)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 18)
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	_load_root.add_child(col)

	var brand := TextureRect.new()
	brand.texture = load("res://assets/ui/title.png")
	brand.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	brand.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	brand.custom_minimum_size = Vector2(300, 192)   # small centred wordmark over the loading spinner (aspect 1.567)
	brand.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(brand)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_override("font", MenuUI.font(MenuUI.UI_FONT))
	_status.add_theme_font_size_override("font_size", 22)
	_status.add_theme_color_override("font_color", MenuUI.ACCENT_HOT)
	col.add_child(_status)

	# thin gold progress bar
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0.16, 0.16, 0.2, 0.9)
	bar_bg.custom_minimum_size = Vector2(_bar_w, 4)
	bar_bg.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(bar_bg)
	_bar_fill = ColorRect.new()
	_bar_fill.color = MenuUI.ACCENT
	_bar_fill.position = Vector2.ZERO            # default top-left anchors; width driven by _set_progress
	_bar_fill.size = Vector2(0, 4)
	bar_bg.add_child(_bar_fill)

	_tip = Label.new()
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.add_theme_font_override("font", MenuUI.font(MenuUI.BODY_FONT))
	_tip.add_theme_font_size_override("font_size", 16)
	_tip.add_theme_color_override("font_color", MenuUI.TEXT_DIM)
	col.add_child(_tip)


# ---- public API -------------------------------------------------------------
func change_scene(path: String, use_loading := false) -> void:
	if _busy:
		return
	_busy = true
	await _fade_to(1.0)
	if use_loading:
		await _threaded_swap(path)
	else:
		get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame          # let the new scene finish _ready()
	await _fade_to(0.0)
	_fade.visible = false
	_busy = false


func reload(use_loading := false) -> void:
	var cur := get_tree().current_scene
	var path := cur.scene_file_path if cur != null else ""
	if path == "":
		get_tree().reload_current_scene()
		return
	await change_scene(path, use_loading)


# ---- internals --------------------------------------------------------------
func _threaded_swap(path: String) -> void:
	_show_loading(true)
	var err := ResourceLoader.load_threaded_request(path)
	if err != OK:
		get_tree().change_scene_to_file(path)
		_show_loading(false)
		return
	var progress: Array = []
	while true:
		var st := ResourceLoader.load_threaded_get_status(path, progress)
		_set_progress(progress[0] if progress.size() > 0 else 0.0)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_error("Transition: failed to load " + path)
			get_tree().change_scene_to_file(path)
			_show_loading(false)
			return
		await get_tree().process_frame
	var packed := ResourceLoader.load_threaded_get(path) as PackedScene
	_set_progress(1.0)
	get_tree().change_scene_to_packed(packed)
	_show_loading(false)


func _show_loading(on: bool) -> void:
	_loading_visible = on
	_load_root.visible = on
	if on:
		_status.text = "DESCENDING"
		_tip.text = TIPS[randi() % TIPS.size()]
		_set_progress(0.0)


func _set_progress(p: float) -> void:
	if _bar_fill != null:
		_bar_fill.size.x = _bar_w * clampf(p, 0.0, 1.0)


func _fade_to(a: float) -> Signal:
	_fade.visible = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", a, fade_time)
	return tw.finished


func _process(delta: float) -> void:
	if not _loading_visible:
		return
	# animated "DESCENDING . . ." dots so the screen reads as alive even at 0% on a slow load
	_dots_t += delta
	var n := int(_dots_t * 2.0) % 4
	_status.text = "DESCENDING" + ".".repeat(n)
