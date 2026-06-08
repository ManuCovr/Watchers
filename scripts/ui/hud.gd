class_name GameHUD
extends Control
## In-game HUD. Philosophy (à la Lethal Company / REPO / Content Warning): keep the screen CLEAN.
## Meters FADE IN only while relevant (sprinting, eyes tiring, talking, torch on/low) and fade out
## otherwise — no permanent clutter, no blinking. Hold TAB for the full objectives board. Always-on
## is limited to the crosshair, the look-at prompt, and a tiny objective counter.

var player_fn: Callable          ## () -> WPlayer (local) or null
var danger_fn := Callable()      ## () -> float 0..1
var tasks_fn := Callable()       ## () -> Array[Task]

var _ui: Font                    # Super Pandora — labels / meters
var _serif: Font                 # Crimson Text — task titles
var _title: Font                 # Blood Crow — the TAB board header
var _t := 0.0
var _a := {"sprint": 0.0, "eyes": 0.0, "voice": 0.0, "flash": 0.0, "items": 0.0, "tab": 0.0}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui = load("res://assets/fonts/SuperPandora.ttf")
	_serif = load("res://assets/fonts/CrimsonText-SemiBold.ttf")
	_title = load("res://assets/fonts/BloodCrow-Expanded.ttf")


func _process(delta: float) -> void:
	_t += delta
	var p: WPlayer = player_fn.call() if player_fn.is_valid() else null
	var has_p := p != null and is_instance_valid(p)
	# Targets: 1 while the element is RELEVANT, else 0 (smoothly faded).
	_fade("sprint", 1.0 if (has_p and p.sprint_ratio() < 0.985) else 0.0, delta, 7.0)
	_fade("eyes", 1.0 if (has_p and p.stamina_ratio() < 0.82) else 0.0, delta, 6.0)
	_fade("voice", 1.0 if (not VoiceManager.self_muted and VoiceManager.mic_level > 0.03) else 0.0, delta, 9.0)
	_fade("flash", 1.0 if (has_p and p.has_flashlight and (p.flashlight_on or p.flashlight_battery < 0.35)) else 0.0, delta, 6.0)
	_fade("items", 1.0 if (has_p and _has_notable_item(p)) else 0.0, delta, 5.0)
	_fade("tab", 1.0 if Input.is_action_pressed("objectives") else 0.0, delta, 16.0)
	queue_redraw()


func _fade(k: String, target: float, delta: float, speed: float) -> void:
	_a[k] = lerpf(_a[k], target, clampf(delta * speed, 0.0, 1.0))


func _has_notable_item(p: WPlayer) -> bool:
	return p.held_melee != "" or p.has_keycard or p.has_phone or p.cigs > 0 \
		or (p.carrying != null and is_instance_valid(p.carrying))


func _draw() -> void:
	var vp := get_viewport_rect().size
	var p: WPlayer = player_fn.call() if player_fn.is_valid() else null
	var has_p := p != null and is_instance_valid(p)

	# ---- VITALS (bottom-left): SPRINT + EYES, each fading with use ----
	if has_p:
		var bx := 30.0
		var by := vp.y - 70.0
		if _a["sprint"] > 0.01:
			var sr := p.sprint_ratio()
			var scol := Color(0.35, 0.85, 1.0).lerp(Color(1.0, 0.55, 0.2), 1.0 - clampf(sr / 0.6, 0, 1))
			_meter(Vector2(bx, by), 210.0, "SPRINT", sr, scol, _a["sprint"])
		if _a["eyes"] > 0.01:
			var er := p.stamina_ratio()
			var ecol := Color(0.95, 0.85, 0.4) if er > 0.3 else Color(1.0, 0.5, 0.25)
			_meter(Vector2(bx, by - 34.0), 210.0, "EYES", er, ecol, _a["eyes"])

	# ---- VOICE (bottom-centre): only while you're actually talking ----
	if _a["voice"] > 0.01:
		var lvl := clampf(VoiceManager.mic_level * 2.2, 0.0, 1.0)
		var vc := Color(0.3, 0.95, 0.45, _a["voice"])
		var vx := vp.x * 0.5 - 70.0
		var vy := vp.y - 30.0
		_str("MIC", Vector2(vx, vy - 16.0), 12, Color(0.6, 0.85, 0.6, _a["voice"]), _ui)
		draw_circle(Vector2(vx - 12, vy + 4), 5.0, vc)
		_thin_bar(Vector2(vx, vy), Vector2(120, 7), lvl, vc, _a["voice"])

	# ---- FLASHLIGHT battery (bottom-right): fades in when on or low ----
	if has_p and _a["flash"] > 0.01:
		var fx := vp.x - 224.0
		var fy := vp.y - 54.0
		var bcol := Color(0.4, 0.95, 0.45)
		if p.flashlight_battery < 0.25: bcol = Color(0.95, 0.3, 0.2)
		elif p.flashlight_battery < 0.5: bcol = Color(0.95, 0.8, 0.3)
		_str("FLASHLIGHT [G]" + ("  ON" if p.flashlight_on else "  OFF"), Vector2(fx, fy), 13,
			Color(0.92, 0.88, 0.62, _a["flash"]) if p.flashlight_on else Color(0.7, 0.7, 0.72, _a["flash"]), _ui)
		_thin_bar(Vector2(fx, fy + 19.0), Vector2(196, 8), p.flashlight_battery, bcol, _a["flash"])

	# ---- held ITEMS (bottom-right, above the torch): fades in when you carry something ----
	if has_p and _a["items"] > 0.01:
		_draw_items(p, vp, _a["items"])

	# ---- interaction PROMPT (bottom-middle pill) ----
	if has_p and p.aimed != null and is_instance_valid(p.aimed) and p.aimed.enabled:
		_draw_prompt(p.aimed.prompt.to_upper(), vp)

	# ---- DANGER pip (top-centre, complements the vignette) ----
	var dg: float = danger_fn.call() if danger_fn.is_valid() else 0.0
	if dg > 0.05:
		draw_circle(Vector2(vp.x * 0.5, 28.0), 5.0 + dg * 8.0, Color(1.0, 0.18, 0.13, clampf(dg, 0, 1)))

	# ---- tiny objective counter (top-left) + TAB board ----
	if tasks_fn.is_valid():
		var tasks: Array = tasks_fn.call()
		_draw_counter(tasks, vp)
		if _a["tab"] > 0.01:
			_draw_board(tasks, vp, _a["tab"])


# ---- drawing helpers --------------------------------------------------------
func _meter(pos: Vector2, w: float, label: String, ratio: float, col: Color, a: float) -> void:
	col.a = a
	_str(label, pos, 14, Color(0.82, 0.82, 0.86, a), _ui)
	var by := pos.y + 17.0
	draw_rect(Rect2(pos.x, by, w, 8), Color(0.08, 0.08, 0.1, 0.85 * a))
	var fw := (w - 2.0) * clampf(ratio, 0.0, 1.0)
	if fw > 0.0:
		draw_rect(Rect2(pos.x + 1, by + 1, fw, 6), col)
	draw_rect(Rect2(pos.x, by, w, 8), Color(1, 1, 1, 0.16 * a), false, 1.0)


func _thin_bar(pos: Vector2, sz: Vector2, ratio: float, col: Color, a := 1.0) -> void:
	draw_rect(Rect2(pos, sz), Color(0, 0, 0, 0.5 * a))
	var w := (sz.x - 2.0) * clampf(ratio, 0.0, 1.0)
	if w > 0.0:
		var c := col; c.a = a
		draw_rect(Rect2(pos + Vector2(1, 1), Vector2(w, sz.y - 2.0)), c)
	draw_rect(Rect2(pos, sz), Color(1, 1, 1, 0.2 * a), false, 1.0)


func _str(s: String, pos: Vector2, sz: int, col: Color, f: Font) -> void:
	draw_string_outline(f, pos + Vector2(0, sz), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 4, Color(0, 0, 0, col.a * 0.9))
	draw_string(f, pos + Vector2(0, sz), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _draw_prompt(prompt: String, vp: Vector2) -> void:
	var sz := 20
	var kw := _ui.get_string_size("E", HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var pw := _ui.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var keybox := kw + 16.0
	var total := keybox + 14.0 + pw
	var sx := vp.x * 0.5 - total * 0.5
	var sy := vp.y - 138.0
	draw_rect(Rect2(sx - 12, sy - 7, total + 24, 38), Color(0.02, 0.02, 0.03, 0.72))
	draw_rect(Rect2(sx - 12, sy - 7, total + 24, 38), Color(1, 1, 1, 0.12), false, 1.0)
	draw_rect(Rect2(sx, sy - 3, keybox, 30), Color(MenuUI.ACCENT.r, MenuUI.ACCENT.g, MenuUI.ACCENT.b, 0.9))
	_str("E", Vector2(sx + 8, sy + 1), sz, Color(1, 1, 1), _ui)
	_str(prompt, Vector2(sx + keybox + 14, sy + 1), sz, Color(0.96, 0.95, 0.9), _ui)


func _draw_items(p: WPlayer, vp: Vector2, a: float) -> void:
	var x := vp.x - 224.0
	var y := vp.y - 96.0
	if p.held_melee != "":
		_str("%s  [LMB] swing" % p.held_melee.to_upper(), Vector2(x, y), 13, Color(0.95, 0.6, 0.55, a), _ui); y += 19.0
	if p.has_keycard:
		_str("KEYCARD", Vector2(x, y), 13, Color(0.5, 0.8, 1.0, a), _ui); y += 19.0
	if p.has_phone:
		_str("PHONE  [V] throw", Vector2(x, y), 13, Color(0.8, 0.7, 0.95, a), _ui); y += 19.0
	if p.cigs > 0:
		_str("CIGS x%d  [C]" % p.cigs, Vector2(x, y), 13, Color(0.85, 0.8, 0.6, a), _ui); y += 19.0
	if p.carrying != null and is_instance_valid(p.carrying):
		_str("CARRYING — find the socket", Vector2(x, y), 13, Color(0.95, 0.6, 0.3, a), _ui)


# ---- objectives -------------------------------------------------------------
func _counted(tasks: Array) -> Array:
	return tasks.filter(func(t): return t != null and is_instance_valid(t) and t.counts_toward_win)


## Tiny always-on counter (top-left): tells you progress + that TAB exists, nothing more.
func _draw_counter(tasks: Array, _vp: Vector2) -> void:
	var c := _counted(tasks)
	if c.is_empty():
		return
	var done := c.filter(func(t): return t.done).size()
	var col := Color(0.6, 0.95, 0.6) if done == c.size() else Color(0.85, 0.82, 0.7)
	_str("OBJECTIVES  %d/%d" % [done, c.size()], Vector2(28, 26), 16, col, _ui)
	_str("hold  TAB", Vector2(28, 46), 12, Color(0.6, 0.6, 0.64), _serif)


## The full board, centred, while TAB is held. Grouped TO-DO (with %) then DONE.
func _draw_board(tasks: Array, vp: Vector2, a: float) -> void:
	var c := _counted(tasks)
	if c.is_empty():
		return
	var todo := c.filter(func(t): return not t.done)
	var done := c.filter(func(t): return t.done)
	var done_n := done.size()
	# dim the screen behind the board
	draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0, 0, 0, 0.55 * a))
	var pw := 560.0
	var ph := 150.0 + c.size() * 30.0
	var px := vp.x * 0.5 - pw * 0.5
	var py := vp.y * 0.5 - ph * 0.5
	draw_rect(Rect2(px, py, pw, ph), Color(0.05, 0.05, 0.065, 0.96 * a))
	draw_rect(Rect2(px, py, pw, 3), Color(MenuUI.ACCENT.r, MenuUI.ACCENT.g, MenuUI.ACCENT.b, a))
	draw_rect(Rect2(px, py, pw, ph), Color(0.25, 0.2, 0.22, a), false, 1.0)

	var ix := px + 38.0
	var iy := py + 30.0
	_str("OBJECTIVES", Vector2(ix, iy), 40, Color(0.92, 0.91, 0.95, a), _title)
	_str("%d / %d secured" % [done_n, c.size()], Vector2(px + pw - 200, iy + 12), 18,
		Color(0.7, 0.95, 0.6, a) if done_n == c.size() else Color(0.85, 0.8, 0.7, a), _ui)
	iy += 58.0
	_thin_bar(Vector2(ix, iy), Vector2(pw - 76, 7), float(done_n) / float(c.size()), Color(0.4, 0.9, 0.5), a)
	iy += 24.0

	for t in todo:
		var prog: float = t.get_progress()
		var pct := "%d%%" % int(prog * 100.0) if prog > 0.01 else "—"
		_str(pct, Vector2(ix, iy), 16, Color(0.9, 0.78, 0.45, a), _ui)
		_str(t.task_title, Vector2(ix + 56, iy), 19, Color(0.92, 0.9, 0.86, a), _serif)
		_thin_bar(Vector2(px + pw - 150, iy + 6), Vector2(112, 5), prog, Color(0.85, 0.7, 0.3), a)
		iy += 30.0
	for t in done:
		_str("DONE", Vector2(ix, iy), 14, Color(0.45, 0.9, 0.5, a), _ui)
		_str(t.task_title, Vector2(ix + 56, iy), 18, Color(0.5, 0.6, 0.52, a), _serif)
		iy += 30.0
