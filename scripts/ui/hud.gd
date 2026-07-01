class_name GameHUD
extends Control
## In-game HUD. Philosophy (à la Lethal Company / REPO / Content Warning): keep the screen CLEAN.
## Meters FADE IN only while relevant (sprinting, eyes tiring, talking, torch on/low) and fade out
## otherwise — no permanent clutter, no blinking. Hold TAB for the full objectives board. Always-on
## is limited to the crosshair, the look-at prompt, and a tiny objective counter.
##
## VISUAL LANGUAGE — the "luxury hotel" palette (champagne gold on warm charcoal), shared with the
## menus via MenuUI. Vitals are GOLD; they only shift amber→red as they near depletion, so a red
## flash always means "act now". Meters are rounded little instruments with a glyph, not greybox bars.

var player_fn: Callable          ## () -> WPlayer (local) or null
var danger_fn := Callable()      ## () -> float 0..1
var tasks_fn := Callable()       ## () -> Array[Task]
var recovery_fn := Callable()    ## () -> RecoveryManager or null (Phase 1 restock objective)

var _ui: Font                    # Super Pandora — labels / meters / hints
var _serif: Font                 # Cinzel — task titles
var _title: Font                 # Cinzel Bold — the TAB board header

# Reticle art (Kenney cursor pack). Dot at rest; the open hand when the look-at ray is on something
# you can grab/use — the captured-mouse equivalent of the menu hover cursor.
var _reticle_dot: Texture2D
var _reticle_hand: Texture2D

# ---- palette (kept in lock-step with MenuUI; reds are for DANGER only) -------
const GOLD := Color(0.82, 0.66, 0.34)        # champagne brass — the default vital colour
const GOLD_HOT := Color(0.97, 0.84, 0.5)     # bright gold — full / emphasis
const IVORY := Color(0.93, 0.91, 0.86)
const IVORY_DIM := Color(0.64, 0.6, 0.54)
const WARN := Color(0.95, 0.64, 0.28)        # amber — running low
const CRIT := Color(0.93, 0.3, 0.22)         # red — critical / locked / danger ONLY
const TRACK := Color(0.05, 0.05, 0.07, 0.82) # meter groove

var _t := 0.0
var _a := {"sprint": 0.0, "eyes": 0.0, "voice": 0.0, "flash": 0.0, "phone": 0.0, "items": 0.0, "tab": 0.0, "throw": 0.0, "cross": 0.0}

# Bottom-left transient toast (pickups / events) — small, gold, HUD font.
var _toast_text := ""
var _toast_hold := 0.0           # seconds of full visibility remaining
var _toast_a := 0.0

# ---- CRT / neon toggles (pushed to crt_hud.gdshader; glow/jitter used in _draw) ----
@export_group("CRT / neon")
@export var ui_curve := true
@export var ui_scanlines := true
@export var ui_chromatic := true
@export var ui_glow := true
@export var ui_jitter := true
@export var reduced_motion := false
@export var crt_curve_amount := 0.10
@export var crt_scanline := 0.16
@export var crt_aberration := 0.0015
@export var crt_vignette := 0.45
@export var crt_flicker := 0.03

# Value popups ("+ FOOD") that punch in, jitter, drift up and fade.
var _pops: Array = []            # each: {text, color, t}  (t counts down from POP_LIFE)
const POP_LIFE := 1.6
# Completion callout ("ELEVATOR LOADED").
var _callout_text := ""
var _callout_t := 0.0
const CALLOUT_LIFE := 2.6
const SICK_GREEN := Color(0.55, 0.95, 0.55)


## Build the ShaderMaterial for the CRT TextureRect, configured from the toggles above. game.gd calls
## this once when wiring the HUD SubViewport.
func build_crt_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/crt_hud.gdshader")
	m.set_shader_parameter("curve_amount", crt_curve_amount)
	m.set_shader_parameter("scanline_strength", crt_scanline)
	m.set_shader_parameter("aberration", crt_aberration)
	m.set_shader_parameter("vignette_strength", crt_vignette)
	m.set_shader_parameter("flicker_strength", crt_flicker)
	m.set_shader_parameter("enable_curve", ui_curve)
	m.set_shader_parameter("enable_scanlines", ui_scanlines)
	m.set_shader_parameter("enable_chromatic", ui_chromatic)
	m.set_shader_parameter("reduced_motion", reduced_motion)
	return m


## Public: a recovery delivery landed — punch up a "+ <CATEGORY>" value pop.
func delivery_pop(category: String) -> void:
	_pops.append({"text": "+ " + category.to_upper(), "color": SICK_GREEN, "t": POP_LIFE})


## Public: big lower-centre completion callout (e.g. "ELEVATOR LOADED").
func callout(text: String) -> void:
	_callout_text = text
	_callout_t = CALLOUT_LIFE


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui = load("res://assets/fonts/SuperPandora.ttf")
	_serif = load("res://assets/fonts/Cinzel-Regular.otf")
	_title = load("res://assets/fonts/Cinzel-Bold.otf")
	_reticle_dot = load("res://assets/ui/cursors/dot_small.png")
	_reticle_hand = load("res://assets/ui/cursors/hand_open.png")


## Public: show a small bottom-left notice (e.g. a pickup). Replaces the old big centred banner.
func toast(msg: String) -> void:
	_toast_text = msg
	_toast_hold = 2.8


func _process(delta: float) -> void:
	_t += delta
	var p: WPlayer = player_fn.call() if player_fn.is_valid() else null
	var has_p := p != null and is_instance_valid(p)
	# Targets: 1 while the element is RELEVANT, else 0 (smoothly faded).
	# Sprint is infinite now — no stamina meter. (Slot kept at 0 so nothing draws.)
	_fade("eyes", 1.0 if (has_p and p.stamina_ratio() < 0.82) else 0.0, delta, 6.0)
	_fade("voice", 1.0 if (not VoiceManager.self_muted and VoiceManager.mic_level > 0.03) else 0.0, delta, 9.0)
	_fade("flash", 1.0 if (has_p and p.has_flashlight and (p.flashlight_on or p.flashlight_battery < 0.35)) else 0.0, delta, 6.0)
	_fade("phone", 1.0 if (has_p and p.has_phone) else 0.0, delta, 6.0)
	_fade("items", 1.0 if (has_p and _has_notable_item(p)) else 0.0, delta, 5.0)
	_fade("tab", 1.0 if Input.is_action_pressed("objectives") else 0.0, delta, 16.0)
	var show_item := has_p and ((p.held_item != null and is_instance_valid(p.held_item)) \
		or (p.aimed_item != null and is_instance_valid(p.aimed_item)))
	_fade("throw", 1.0 if show_item else 0.0, delta, 14.0)
	_fade("cross", 1.0 if (has_p and _aiming_at_something(p)) else 0.0, delta, 14.0)
	# toast lifetime
	if _toast_hold > 0.0:
		_toast_hold -= delta
	_toast_a = lerpf(_toast_a, 1.0 if _toast_hold > 0.0 else 0.0, clampf(delta * 6.0, 0.0, 1.0))
	# value pops + completion callout lifetimes
	if not _pops.is_empty():
		for pop in _pops:
			pop["t"] -= delta
		_pops = _pops.filter(func(e): return e["t"] > 0.0)
	if _callout_t > 0.0:
		_callout_t -= delta
	queue_redraw()


func _fade(k: String, target: float, delta: float, speed: float) -> void:
	_a[k] = lerpf(_a[k], target, clampf(delta * speed, 0.0, 1.0))


func _has_notable_item(p: WPlayer) -> bool:
	return p.has_keycard or p.has_phone or p.cigs > 0 \
		or (p.carrying != null and is_instance_valid(p.carrying))


## True when the crosshair is over something you can act on — a usable interactable OR a grabbable
## item. Drives the reticle "ignite" so you get clear feedback on WHAT you've actually targeted.
func _aiming_at_something(p: WPlayer) -> bool:
	if p.aimed != null and is_instance_valid(p.aimed) and p.aimed.enabled:
		return true
	return p.aimed_item != null and is_instance_valid(p.aimed_item)


func _draw() -> void:
	var vp := get_viewport_rect().size
	var p: WPlayer = player_fn.call() if player_fn.is_valid() else null
	var has_p := p != null and is_instance_valid(p)

	# ---- VITALS (bottom-left): a stable instrument cluster, fixed slots so nothing reflows ----
	if has_p:
		var bx := 30.0
		var slot_phone := vp.y - 120.0
		var slot_eyes := vp.y - 88.0
		var slot_flash := vp.y - 56.0
		if _a["phone"] > 0.01:
			_draw_phone(p, bx, slot_phone, _a["phone"])
		if _a["eyes"] > 0.01:
			_draw_eyes(p, bx, slot_eyes, _a["eyes"])
		if has_p and _a["flash"] > 0.01:
			_draw_flash(p, bx, slot_flash, _a["flash"])

	# ---- carried-item hints (bottom-left, above the vitals): keeps all status on one side ----
	if has_p and _a["items"] > 0.01:
		_draw_items(p, vp, _a["items"])

	# ---- bottom-left TOAST (pickups / events): small, gold, same font as the rest ----
	if _toast_a > 0.01:
		_draw_toast(vp)

	# ---- VOICE (bottom-centre): only while you're actually talking ----
	if _a["voice"] > 0.01:
		var lvl := clampf(VoiceManager.mic_level * 2.2, 0.0, 1.0)
		var vc := Color(0.55, 0.9, 0.6, _a["voice"])
		var vx := vp.x * 0.5 - 64.0
		var vy := vp.y - 30.0
		draw_circle(Vector2(vx - 14, vy + 3), 4.0 + lvl * 2.0, vc)
		_str("MIC", Vector2(vx, vy - 15.0), 11, Color(0.6, 0.8, 0.62, _a["voice"]), _ui)
		_bar(Vector2(vx, vy), 120.0, 6.0, lvl, vc, _a["voice"])

	# ---- ITEM action prompts (bottom-right, key-only) + curved throw meter by the crosshair ----
	if has_p and _a["throw"] > 0.01:
		_draw_item_prompts(p, vp, _a["throw"])
	if has_p and p.held_item != null and is_instance_valid(p.held_item) and p.held_item.charge_ratio() > 0.001:
		_draw_throw_arc(p.held_item.charge_ratio(), vp)

	# ---- CROSSHAIR (always on) — ignites gold when over something you can use/grab ----
	_draw_crosshair(vp, _a["cross"])

	# ---- interaction PROMPT (bottom-middle) ----
	if has_p and p.aimed != null and is_instance_valid(p.aimed) and p.aimed.enabled:
		var hold := p.tactile_hold_prompt() if p.has_method("tactile_hold_prompt") else ""
		if hold != "":
			_draw_prompt(hold, vp)                       # "ROTATE MOUSE" / "PULL MOUSE DOWN" while gripping
		else:
			_draw_prompt(p.aimed.prompt.to_upper(), vp)

	# ---- DANGER pip (top-centre, complements the vignette) ----
	var dg: float = danger_fn.call() if danger_fn.is_valid() else 0.0
	if dg > 0.05:
		draw_circle(Vector2(vp.x * 0.5, 28.0), 5.0 + dg * 8.0, Color(CRIT.r, CRIT.g, CRIT.b, clampf(dg, 0, 1)))

	# ---- objectives (top-left) + TAB board: RESTOCK when recovery mode is on, else task list ----
	var mgr: RecoveryManager = recovery_fn.call() if recovery_fn.is_valid() else null
	if mgr != null:
		_draw_restock(mgr)
		if _a["tab"] > 0.01:
			_draw_restock_board(mgr, vp, _a["tab"])
	elif tasks_fn.is_valid():
		var tasks: Array = tasks_fn.call()
		_draw_counter(tasks, vp)
		if _a["tab"] > 0.01:
			_draw_board(tasks, vp, _a["tab"])

	# ---- recovery feedback: value pops + completion callout ----
	if not _pops.is_empty():
		_draw_pops(vp)
	if _callout_t > 0.0:
		_draw_callout(vp)


## "+ FOOD" pops that punch in, jitter briefly, drift up and fade. Stacked so several read cleanly.
func _draw_pops(vp: Vector2) -> void:
	var i := 0
	for p in _pops:
		var life: float = p["t"]
		var k := 1.0 - life / POP_LIFE                 # 0 at birth -> 1 at death
		var a := clampf(life / 0.5, 0.0, 1.0)          # fade out over the last 0.5s
		var sz := int(lerpf(38.0, 27.0, clampf(k * 4.0, 0.0, 1.0)))   # punch big then settle
		var jitter := Vector2.ZERO
		if ui_jitter and not reduced_motion and k < 0.22:
			jitter = Vector2(randf_range(-2.5, 2.5), randf_range(-2.0, 2.0))
		var col: Color = p["color"]; col.a = a
		var s: String = p["text"]
		var w := _ui.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		var x := vp.x * 0.5 - w * 0.5
		var y := vp.y * 0.36 - k * 64.0 - float(i) * 30.0
		_str_glow(s, Vector2(x, y) + jitter, sz, col, _ui, Color(col.r, col.g, col.b, 0.4 * a), 4.0)
		i += 1


## Big lower-centre completion callout (e.g. "ELEVATOR LOADED") — scale-in, green glow, chromatic split.
func _draw_callout(vp: Vector2) -> void:
	var a := clampf(_callout_t / 0.6, 0.0, 1.0)
	var punch := clampf((CALLOUT_LIFE - _callout_t) / 0.18, 0.0, 1.0)
	var sz := int(lerpf(22.0, 50.0, smoothstep(0.0, 1.0, punch)))
	var col := Color(SICK_GREEN.r, SICK_GREEN.g, SICK_GREEN.b, a)
	var w := _title.get_string_size(_callout_text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var x := vp.x * 0.5 - w * 0.5
	var y := vp.y * 0.6
	if ui_chromatic:
		draw_string(_title, Vector2(x - 3, y + sz), _callout_text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(1.0, 0.25, 0.25, a * 0.5))
		draw_string(_title, Vector2(x + 3, y + sz), _callout_text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0.25, 0.6, 1.0, a * 0.5))
	_str_glow(_callout_text, Vector2(x, y), sz, col, _title, Color(SICK_GREEN.r, SICK_GREEN.g, SICK_GREEN.b, 0.5 * a), 5.0)


# ---- VITAL rows -------------------------------------------------------------
## Common chrome for a vital: a small glyph, a caps label, and a rounded bar. `col` drives the fill;
## `note` is an optional right-side word (ON / RECHARGING / %). Returns nothing — pure draw.
func _vital_row(x: float, y: float, label: String, ratio: float, col: Color, a: float,
		icon: int, note := "", note_col := IVORY_DIM, pulse := false) -> void:
	var bar_w := 168.0
	var c := col
	if pulse:
		a *= 0.6 + 0.4 * sin(_t * 9.0)           # alpha throb to flag a critical/locked meter
	_draw_icon(icon, Vector2(x + 8, y + 4), 8.0, Color(col.r, col.g, col.b, a))
	_str(label, Vector2(x + 24, y - 10), 12, Color(IVORY.r, IVORY.g, IVORY.b, 0.86 * a), _ui)
	if note != "":
		var nw := _ui.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		_str(note, Vector2(x + 24 + bar_w - nw, y - 10), 11, Color(note_col.r, note_col.g, note_col.b, a), _ui)
	_bar(Vector2(x + 24, y + 4), bar_w, 9.0, ratio, c, a)


func _draw_eyes(p: WPlayer, x: float, y: float, a: float) -> void:
	var r := p.stamina_ratio()
	# gold when rested → amber as the blink looms → red right before it forces shut
	var col := GOLD_HOT.lerp(WARN, clampf((0.6 - r) / 0.6, 0, 1))
	if r < 0.22:
		col = WARN.lerp(CRIT, clampf((0.22 - r) / 0.22, 0, 1))
	_vital_row(x, y, "EYES", r, col, a, ICON_EYE, "", IVORY_DIM, r < 0.18)


func _draw_sprint(p: WPlayer, x: float, y: float, a: float) -> void:
	var r := p.sprint_ratio()
	if p.sprint_locked():
		# spent — locked out until it recharges past the minimum. Red, pulsing, clearly "wait".
		_vital_row(x, y, "SPRINT", r, CRIT, a, ICON_LOCK, "RECHARGING", CRIT, true)
		return
	var col := GOLD_HOT.lerp(WARN, clampf((0.4 - r) / 0.4, 0, 1))
	_vital_row(x, y, "SPRINT", r, col, a, ICON_RUN)


func _draw_flash(p: WPlayer, x: float, y: float, a: float) -> void:
	var b := p.flashlight_battery
	var col := GOLD
	if b < 0.25: col = CRIT
	elif b < 0.5: col = WARN
	elif p.flashlight_on: col = GOLD_HOT
	var note := "ON" if p.flashlight_on else "OFF"
	var ncol := GOLD_HOT if p.flashlight_on else IVORY_DIM
	_vital_row(x, y, "TORCH  [G]", b, col, a, ICON_BOLT, note, ncol, b < 0.18)


## Phone FLASH charges (a Watcher stun tool, not a throwable). Shows N/3, "FIND BATTERY" when empty.
func _draw_phone(p: WPlayer, x: float, y: float, a: float) -> void:
	var ratio := float(p.phone_charges) / float(maxi(p.phone_max_charges, 1))
	var empty := p.phone_charges <= 0
	var col := CRIT if empty else GOLD_HOT
	var note := "FIND BATTERY" if empty else "%d/%d" % [p.phone_charges, p.phone_max_charges]
	_vital_row(x, y, "PHONE  [V]", ratio, col, a, ICON_BOLT, note, col, empty)


# ---- drawing primitives -----------------------------------------------------
## A rounded track + inset rounded fill. The signature meter shape across the whole HUD.
func _bar(pos: Vector2, w: float, h: float, ratio: float, col: Color, a := 1.0) -> void:
	_rrect(Rect2(pos, Vector2(w, h)), Color(TRACK.r, TRACK.g, TRACK.b, TRACK.a * a), h * 0.5)
	var fw := (w - 4.0) * clampf(ratio, 0.0, 1.0)
	if fw > 1.0:
		var c := col; c.a = a
		_rrect(Rect2(pos + Vector2(2, 2), Vector2(fw, h - 4.0)), c, (h - 4.0) * 0.5)
	# hairline rim so the groove reads on bright backgrounds
	_rrect_outline(Rect2(pos, Vector2(w, h)), Color(1, 1, 1, 0.1 * a), h * 0.5)


func _rrect(r: Rect2, col: Color, radius: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(radius))
	draw_style_box(sb, r)


func _rrect_outline(r: Rect2, col: Color, radius: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.TRANSPARENT
	sb.set_corner_radius_all(int(radius))
	sb.set_border_width_all(1)
	sb.border_color = col
	draw_style_box(sb, r)


func _str(s: String, pos: Vector2, sz: int, col: Color, f: Font) -> void:
	draw_string_outline(f, pos + Vector2(0, sz), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 4, Color(0, 0, 0, col.a * 0.9))
	draw_string(f, pos + Vector2(0, sz), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


## Neon string: a soft coloured halo behind the crisp text (cheap bloom). Honors ui_glow.
func _str_glow(s: String, pos: Vector2, sz: int, col: Color, f: Font, glow := Color(0, 0, 0, 0), spread := 3.0) -> void:
	if ui_glow:
		var gc := glow if glow.a > 0.0 else Color(col.r, col.g, col.b, col.a * 0.32)
		var base := pos + Vector2(0, sz)
		for off in [Vector2(spread, 0), Vector2(-spread, 0), Vector2(0, spread), Vector2(0, -spread),
				Vector2(spread, spread) * 0.7, Vector2(-spread, -spread) * 0.7]:
			draw_string(f, base + off, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, gc)
	_str(s, pos, sz, col, f)


# ---- glyphs (tiny vector icons, drawn so the meters read at a glance) --------
enum { ICON_EYE, ICON_RUN, ICON_BOLT, ICON_LOCK }

func _draw_icon(kind: int, c: Vector2, s: float, col: Color) -> void:
	match kind:
		ICON_EYE:
			var lens: PackedVector2Array = [
				Vector2(c.x - s, c.y), Vector2(c.x, c.y - s * 0.62),
				Vector2(c.x + s, c.y), Vector2(c.x, c.y + s * 0.62)]
			draw_polyline(lens + PackedVector2Array([lens[0]]), col, 1.6, true)
			draw_circle(c, s * 0.42, col)
		ICON_RUN:
			for k in 2:
				var ox := c.x - s * 0.5 + float(k) * s * 0.7
				draw_polyline(PackedVector2Array([
					Vector2(ox - s * 0.5, c.y - s * 0.7),
					Vector2(ox + s * 0.25, c.y),
					Vector2(ox - s * 0.5, c.y + s * 0.7)]), col, 2.2, true)
		ICON_BOLT:
			draw_colored_polygon(PackedVector2Array([
				Vector2(c.x + s * 0.25, c.y - s),
				Vector2(c.x - s * 0.55, c.y + s * 0.12),
				Vector2(c.x - s * 0.02, c.y + s * 0.12),
				Vector2(c.x - s * 0.25, c.y + s),
				Vector2(c.x + s * 0.55, c.y - s * 0.12),
				Vector2(c.x + s * 0.02, c.y - s * 0.12)]), col)
		ICON_LOCK:
			draw_arc(Vector2(c.x, c.y - s * 0.15), s * 0.5, PI, TAU, 10, col, 1.8, true)
			_rrect(Rect2(c.x - s * 0.62, c.y - s * 0.1, s * 1.24, s * 0.95), col, 2.0)


# ---- bottom-left toast ------------------------------------------------------
func _draw_toast(vp: Vector2) -> void:
	if _toast_text == "":
		return
	var x := 30.0
	var y := vp.y - 168.0
	# a small gold tick + the message, left-aligned to match the vitals column
	_rrect(Rect2(x, y - 1, 3, 18), Color(GOLD_HOT.r, GOLD_HOT.g, GOLD_HOT.b, _toast_a), 1.5)
	_str(_toast_text, Vector2(x + 12, y - 3), 15, Color(GOLD_HOT.r, GOLD_HOT.g, GOLD_HOT.b, _toast_a), _ui)


# ---- crosshair --------------------------------------------------------------
## The reticle: a small dot dead-centre at rest; it morphs into the open "grab" hand and ignites gold
## (`t`→1) while you're aiming at something usable/grabbable. Drawn (not a hardware cursor) because the
## mouse is captured during play. Falls back to a drawn cross if the textures failed to load.
## The HUD is rendered at half-res and upscaled 2x for the big chunky UI — but the crosshair should
## stay its ORIGINAL on-screen size, so we draw it at RETICLE_SCALE (= the render scale) to cancel the
## upscale. (Keep in sync with HUD_RENDER_SCALE in game.gd if you change it.)
const RETICLE_SCALE := 0.5

func _draw_crosshair(vp: Vector2, t: float) -> void:
	var c := (vp * 0.5).round()
	var col := Color(IVORY.r, IVORY.g, IVORY.b, 0.6).lerp(GOLD_HOT, t)
	var tex := _reticle_hand if (t > 0.5 and _reticle_hand != null) else _reticle_dot
	if tex != null:
		var sz := tex.get_size() * RETICLE_SCALE
		draw_texture_rect(tex, Rect2((c - sz * 0.5).round(), sz), false, col)
		return
	# fallback cross
	var arm := 7.0 * RETICLE_SCALE
	draw_line(c + Vector2(0, -arm), c + Vector2(0, arm), col, 1.4, true)
	draw_line(c + Vector2(-arm, 0), c + Vector2(arm, 0), col, 1.4, true)


# ---- interaction prompt (bottom-middle) — key only, no box ------------------
func _draw_prompt(prompt: String, vp: Vector2) -> void:
	var sz := 20
	var kw := _ui.get_string_size("E", HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var pw := _ui.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var gap := 14.0
	var total := kw + gap + pw
	var sx := vp.x * 0.5 - total * 0.5
	var sy := vp.y - 132.0
	# soft backdrop so it stays readable over the dark world (no key square — just the letter)
	var pad := 16.0
	_rrect(Rect2(sx - pad, sy - 6, total + pad * 2.0, 36), Color(0.03, 0.03, 0.04, 0.62), 8.0)
	_str("E", Vector2(sx, sy), sz, GOLD_HOT, _ui)
	_str(prompt, Vector2(sx + kw + gap, sy), sz, IVORY, _ui)


## Bottom-right action prompts (key-only): looking at a pickup -> E PICK UP ;
## holding -> Q THROW / LMB SWING / E DROP. No key box — just the key in gold + the label.
func _draw_item_prompts(p: WPlayer, vp: Vector2, a: float) -> void:
	var rows: Array = []
	if p.held_item != null and is_instance_valid(p.held_item):
		rows.append(["Q", "THROW"])
		if p.held_item.can_swing:
			rows.append(["LMB", "SWING"])
		rows.append(["E", "DROP"])
	elif p.aimed_item != null and is_instance_valid(p.aimed_item):
		rows.append(["E", "PICK UP"])
	if rows.is_empty():
		return
	var right := vp.x - 34.0
	var y := vp.y - 44.0 - float(rows.size() - 1) * 34.0
	for r in rows:
		_key_prompt(r[0], r[1], right, y, a)
		y += 34.0


## One key + label, right-aligned to `right_x`. The KEY is bold gold (no cap/box), the label ivory.
func _key_prompt(key: String, label: String, right_x: float, y: float, a: float) -> void:
	var ksz := 19
	var lsz := 17
	var kw := _ui.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, ksz).x
	var lw := _ui.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, lsz).x
	var gap := 12.0
	var x := right_x - (kw + gap + lw)
	_str(key, Vector2(x, y), ksz, Color(GOLD_HOT.r, GOLD_HOT.g, GOLD_HOT.b, a), _ui)
	_str(label, Vector2(x + kw + gap, y + 1), lsz, Color(IVORY.r, IVORY.g, IVORY.b, 0.92 * a), _ui)


## A small CURVED VERTICAL charge meter that hugs the right of the crosshair. Fills bottom-up as the
## throw charges, pulses at full, only shows while charging. Warm brass → bright gold (never red).
## A glowing CRT charge RING that hugs the crosshair, filling clockwise from the top. Pulses + splits
## chromatically at full. Replaces the old "parenthesis" arc.
func _draw_throw_arc(charge: float, vp: Vector2) -> void:
	var c := (vp * 0.5).round()
	var radius := 34.0
	var n := 40
	var lit := int(round(charge * float(n)))
	# faint full track
	for i in n:
		var a0 := TAU * float(i) / float(n) - PI * 0.5
		var a1 := TAU * float(i + 1) / float(n) - PI * 0.5
		draw_line(c + Vector2(cos(a0), sin(a0)) * radius, c + Vector2(cos(a1), sin(a1)) * radius,
			Color(0.45, 0.43, 0.4, 0.22), 3.0)
	var col := GOLD.lerp(GOLD_HOT, charge)
	if charge >= 0.999:
		col = Color(GOLD_HOT.r, GOLD_HOT.g, GOLD_HOT.b, 0.7 + 0.3 * sin(_t * 26.0))
	for i in lit:
		var a0 := TAU * float(i) / float(n) - PI * 0.5
		var a1 := TAU * float(i + 1) / float(n) - PI * 0.5
		var p0 := c + Vector2(cos(a0), sin(a0)) * radius
		var p1 := c + Vector2(cos(a1), sin(a1)) * radius
		if ui_glow:
			draw_line(p0, p1, Color(col.r, col.g, col.b, 0.3), 7.0)   # bloom underlay
		draw_line(p0, p1, col, 3.5)
	if charge > 0.05:
		_str_glow("%d%%" % int(charge * 100.0), c + Vector2(radius + 8.0, -9.0), 14, col, _ui,
			Color(col.r, col.g, col.b, 0.4), 3.0)


func _draw_items(p: WPlayer, vp: Vector2, a: float) -> void:
	var x := 30.0
	var y := vp.y - 196.0
	var step := 19.0
	if p.has_keycard:
		_str("KEYCARD", Vector2(x, y), 13, Color(0.6, 0.82, 1.0, a), _ui); y -= step
	if p.has_phone:
		_str("PHONE  ·  V throw", Vector2(x, y), 13, Color(0.82, 0.74, 0.96, a), _ui); y -= step
	if p.cigs > 0:
		_str("CIGS x%d  ·  C" % p.cigs, Vector2(x, y), 13, Color(IVORY.r, IVORY.g, IVORY.b, a), _ui); y -= step
	if p.carrying != null and is_instance_valid(p.carrying):
		_str("CARRYING — find the socket", Vector2(x, y), 13, Color(WARN.r, WARN.g, WARN.b, a), _ui)


# ---- objectives -------------------------------------------------------------
func _counted(tasks: Array) -> Array:
	# Only ACTIVE objectives (selected this round) show — inactive pool tasks are just set-dressing.
	return tasks.filter(func(t): return t != null and is_instance_valid(t) and t.counts_for_win())


## Tiny always-on counter (top-left): progress + that TAB exists, nothing more.
func _draw_counter(tasks: Array, _vp: Vector2) -> void:
	var c := _counted(tasks)
	if c.is_empty():
		return
	var done := c.filter(func(t): return t.done).size()
	var col := Color(0.6, 0.95, 0.6) if done == c.size() else IVORY
	_str("OBJECTIVES  %d/%d" % [done, c.size()], Vector2(28, 26), 16, col, _ui)
	_str("hold  TAB", Vector2(28, 46), 12, IVORY_DIM, _serif)


## The full board, centred, while TAB is held. Grouped TO-DO (with %) then DONE.
func _draw_board(tasks: Array, vp: Vector2, a: float) -> void:
	var c := _counted(tasks)
	if c.is_empty():
		return
	var todo := c.filter(func(t): return not t.done)
	var done := c.filter(func(t): return t.done)
	var done_n := done.size()
	draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0, 0, 0, 0.55 * a))
	var pw := 560.0
	var ph := 150.0 + c.size() * 30.0
	var px := vp.x * 0.5 - pw * 0.5
	var py := vp.y * 0.5 - ph * 0.5
	_rrect(Rect2(px, py, pw, ph), Color(0.05, 0.05, 0.065, 0.96 * a), 10.0)
	_rrect(Rect2(px, py, pw, 3), Color(GOLD.r, GOLD.g, GOLD.b, a), 1.5)
	_rrect_outline(Rect2(px, py, pw, ph), Color(GOLD.r, GOLD.g, GOLD.b, 0.5 * a), 10.0)

	var ix := px + 38.0
	var iy := py + 30.0
	_str("OBJECTIVES", Vector2(ix, iy), 40, Color(0.92, 0.91, 0.95, a), _title)
	_str("%d / %d secured" % [done_n, c.size()], Vector2(px + pw - 200, iy + 12), 18,
		Color(0.7, 0.95, 0.6, a) if done_n == c.size() else IVORY, _ui)
	iy += 58.0
	_bar(Vector2(ix, iy), pw - 76, 8.0, float(done_n) / float(c.size()), GOLD_HOT, a)
	iy += 24.0

	for t in todo:
		var prog: float = t.get_progress()
		var pct := "%d%%" % int(prog * 100.0) if prog > 0.01 else "—"
		_str(pct, Vector2(ix, iy), 16, Color(GOLD_HOT.r, GOLD_HOT.g, GOLD_HOT.b, a), _ui)
		_str(t.task_title, Vector2(ix + 56, iy), 19, Color(0.92, 0.9, 0.86, a), _serif)
		if t.zone_display_name != "":   # WHERE to go, so the objective isn't just a verb
			_str(t.zone_display_name.to_upper(), Vector2(ix + 56, iy + 19), 12, Color(0.62, 0.66, 0.6, a), _ui)
		if t.requires_two_players:   # tell players this one needs a partner
			_str("2P", Vector2(px + pw - 182, iy), 14, Color(0.55, 0.75, 1.0, a), _ui)
		_bar(Vector2(px + pw - 150, iy + 6), 112, 6.0, prog, GOLD, a)
		iy += 30.0
	for t in done:
		_str("DONE", Vector2(ix, iy), 14, Color(0.45, 0.9, 0.5, a), _ui)
		_str(t.task_title, Vector2(ix + 56, iy), 18, Color(0.5, 0.6, 0.52, a), _serif)
		iy += 30.0


# ---- restock objective (Phase 1) --------------------------------------------
## Always-on RESTOCK panel (top-left, where the task counter sat). Per-category have/need; a category
## turns GOLD→GREEN when met (colour is the tell, à la the rest of the HUD — no glyphs to go tofu).
func _draw_restock(mgr: RecoveryManager) -> void:
	var rows: Array = mgr.quota_rows()
	if rows.is_empty():
		return
	var x := 28.0
	var y := 26.0
	var all_done := mgr.is_complete()
	_str_glow("RESTOCK", Vector2(x, y), 16, (SICK_GREEN if all_done else GOLD_HOT), _ui, Color(0, 0, 0, 0), 3.0)
	y += 22.0
	for r in rows:
		var done: bool = r["done"]
		var col := SICK_GREEN if done else IVORY
		_str(str(r["label"]), Vector2(x, y), 13, Color(col.r, col.g, col.b, 0.92), _ui)
		var val := "%d/%d" % [int(r["have"]), int(r["need"])]
		var vw := _ui.get_string_size(val, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		_str_glow(val, Vector2(x + 138.0 - vw, y), 13, Color(col.r, col.g, col.b, 0.95), _ui,
			Color(col.r, col.g, col.b, 0.3), 2.5)
		y += 19.0
	_str("hold  TAB", Vector2(x, y + 2), 12, IVORY_DIM, _serif)


## Centred TAB board: HOTEL RESTOCK with a total + a progress bar per category.
func _draw_restock_board(mgr: RecoveryManager, vp: Vector2, a: float) -> void:
	var rows: Array = mgr.quota_rows()
	if rows.is_empty():
		return
	var t: Vector2i = mgr.totals()
	draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0, 0, 0, 0.5 * a))
	var pw := 480.0
	var ph := 124.0 + rows.size() * 34.0
	var px := vp.x * 0.5 - pw * 0.5
	var py := vp.y * 0.5 - ph * 0.5
	_rrect(Rect2(px, py, pw, ph), Color(0.05, 0.05, 0.065, 0.96 * a), 10.0)
	_rrect(Rect2(px, py, pw, 3), Color(GOLD.r, GOLD.g, GOLD.b, a), 1.5)
	_rrect_outline(Rect2(px, py, pw, ph), Color(GOLD.r, GOLD.g, GOLD.b, 0.5 * a), 10.0)
	var ix := px + 38.0
	var iy := py + 30.0
	_str("HOTEL RESTOCK", Vector2(ix, iy), 32, Color(0.92, 0.91, 0.95, a), _title)
	_str("%d / %d" % [t.x, t.y], Vector2(px + pw - 150, iy + 10), 20,
		(Color(0.7, 0.95, 0.6, a) if mgr.is_complete() else Color(IVORY.r, IVORY.g, IVORY.b, a)), _ui)
	iy += 56.0
	for r in rows:
		var done: bool = r["done"]
		var col := Color(0.55, 0.92, 0.58) if done else Color(0.92, 0.9, 0.86)
		_str(str(r["label"]), Vector2(ix, iy), 19, Color(col.r, col.g, col.b, a), _serif)
		_str("%d / %d" % [int(r["have"]), int(r["need"])], Vector2(px + pw - 150, iy), 18,
			Color(col.r, col.g, col.b, a), _ui)
		var ratio := float(int(r["have"])) / maxf(1.0, float(int(r["need"])))
		_bar(Vector2(ix, iy + 22), pw - 76, 6.0, ratio, (GOLD_HOT if done else GOLD), a)
		iy += 34.0
