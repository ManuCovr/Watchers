extends Node
## Autoload `PlayerCustomization` — the single source of truth for THIS client's blob look:
## body colour, outline colour, and a painted face image. Lives across scenes (autoload), so a
## look chosen at the lobby mirror carries into the bunker. WPlayer applies it to its model on spawn
## and listens to `changed` to update live while you're editing in the lobby.
##
## The face is a real paintable RGBA image backed by ONE ImageTexture — the model's face material
## points at that texture, so brush strokes show on the 3D face the instant the texture updates.

signal changed                      ## body/outline changed (re-apply colours)

const FACE_SIZE := 512
const CFG_PATH := "user://player_customization.cfg"
const FACE_PATH := "user://face_paint.png"
const FACE_BG := Color(0.91, 0.89, 0.85)   ## the clean off-white plate (matches face_default.tres)

# Sane defaults = the current black-blob look, so nothing changes until the player customises.
var body_color := Color(0.12, 0.12, 0.14)
var outline_color := Color(0.04, 0.04, 0.05)

var face_image: Image
var face_texture: ImageTexture

const UNDO_MAX := 20
var _undo: Array[Image] = []
var _dirty := false        # batch the (expensive) full-texture GPU upload to once per frame

## Face presets. Drop your own 512x512 PNGs into res://assets/player_faces/ (draw on the templates on
## your Desktop, rename them) and they show up here automatically — filename = preset label. Until you
## add any, a few procedural starter faces fill in.
const PRESET_DIR := "res://assets/player_faces/"
const PROC_PRESETS := ["Smile", "Frown", "Shock", "Dead", "Smug"]
var _file_presets := {}        # display name -> res:// path


func _ready() -> void:
	_ensure_face()
	_scan_presets()
	load_saved()


## Flush at most one texture upload per frame, no matter how many paint events fired — this is what
## keeps a big brush smooth (the per-event full-512² upload was the lag).
func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		if face_texture != null and face_image != null:
			face_texture.update(face_image)


## Find every *.png in the preset folder (in editor/debug res:// lists the source files).
func _scan_presets() -> void:
	_file_presets.clear()
	var d := DirAccess.open(PRESET_DIR)
	if d == null:
		return
	var files := d.get_files()
	files.sort()
	for f in files:
		if f.to_lower().ends_with(".png"):
			_file_presets[f.get_basename().capitalize()] = PRESET_DIR + f


## Display names for the UI: your PNG files (or the procedural starters if you have none yet). No
## "Blank" entry — the Clear / Reset Face buttons already wipe to the plate.
func preset_names() -> Array:
	var names := []
	names.append_array(_file_presets.keys())
	if _file_presets.is_empty():
		names.append_array(PROC_PRESETS)
	return names


func _ensure_face() -> void:
	if face_image == null:
		face_image = Image.create(FACE_SIZE, FACE_SIZE, false, Image.FORMAT_RGBA8)
		face_image.fill(FACE_BG)
	if face_texture == null:
		face_texture = ImageTexture.create_from_image(face_image)


# ---- colours ----------------------------------------------------------------
func set_body_color(c: Color) -> void:
	body_color = c
	changed.emit()


func set_outline_color(c: Color) -> void:
	outline_color = c
	changed.emit()


# ---- face painting ----------------------------------------------------------
## Paint a stroke from `a` to `b` (both in 0..1 UV space) — interpolated so fast moves don't dot.
## `erase` paints the clean plate colour instead of the brush colour. radius in pixels.
func paint(a: Vector2, b: Vector2, color: Color, radius: int, erase := false) -> void:
	_ensure_face()
	var col := FACE_BG if erase else color
	var pa := a * float(FACE_SIZE)
	var pb := b * float(FACE_SIZE)
	# Step proportionally to the brush size — a big round brush covers lots of ground, so stamping it
	# every 1px is wasteful overlap. ~third of the radius stays gap-free but slashes the work.
	var spacing := maxf(1.0, float(radius) * 0.35)
	var steps := maxi(1, int(pa.distance_to(pb) / spacing))
	for i in steps + 1:
		_stamp(pa.lerp(pb, float(i) / float(steps)), col, radius)
	_dirty = true          # uploaded once per frame in _process (NOT per event)


func clear_face() -> void:
	begin_stroke()
	face_image.fill(FACE_BG)
	face_texture.update(face_image)


## Soft round brush: the core is fully painted (so overlapping stamps along a stroke don't darken
## unevenly) with a 1.5px anti-aliased rim blended over what's there. Erasing blends toward the plate
## colour with the same softness, so it feels like a real eraser, not a hard white circle.
func _stamp(p: Vector2, col: Color, radius: int) -> void:
	var cx := int(round(p.x))
	var cy := int(round(p.y))
	var r := float(radius)
	var inner := maxf(r - 1.0, 0.0)   # crisp core (only a 1px anti-aliased rim) so ink reads solid
	var rim := maxf(r - inner, 0.001)
	for dy in range(-radius - 1, radius + 2):
		var y := cy + dy
		if y < 0 or y >= FACE_SIZE:
			continue
		for dx in range(-radius - 1, radius + 2):
			var x := cx + dx
			if x < 0 or x >= FACE_SIZE:
				continue
			var dist := sqrt(float(dx * dx + dy * dy))
			if dist > r:
				continue
			if dist <= inner:
				face_image.set_pixel(x, y, col)            # solid core: no read/blend needed
				continue
			var a := clampf((r - dist) / rim, 0.0, 1.0)
			if a <= 0.0:
				continue
			face_image.set_pixel(x, y, face_image.get_pixel(x, y).lerp(col, a))


# ---- undo (Ctrl+Z) ----------------------------------------------------------
## Snapshot BEFORE a stroke/clear/preset so it can be undone. Call once per action (UI: on mouse-down).
func begin_stroke() -> void:
	_ensure_face()
	_undo.append(face_image.duplicate())
	if _undo.size() > UNDO_MAX:
		_undo.pop_front()


func undo() -> void:
	if _undo.is_empty():
		return
	face_image = _undo.pop_back()
	if face_texture == null:
		face_texture = ImageTexture.create_from_image(face_image)
	else:
		face_texture.update(face_image)


# ---- presets ----------------------------------------------------------------
const INK := Color(0, 0, 0)

func apply_preset(pname: String) -> void:
	begin_stroke()
	face_image.fill(FACE_BG)
	if _file_presets.has(pname):
		_load_preset_image(_file_presets[pname])
	else:
		match pname:
			"Smile": _eyes(false); _mouth(70.0)
			"Frown": _eyes(false); _mouth(-60.0)
			"Shock": _eyes(false, 26); _mouth_o()
			"Dead": _x_eyes(); _mouth(8.0)
			"Smug": _eyes(false); _brows(); _mouth(40.0, 0.35)
			_: pass        # "Blank"
	face_texture.update(face_image)


## Composite a drawn PNG preset over the clean plate (so transparent PNGs sit on white; opaque ones
## just replace). Auto-resized to the face size.
func _load_preset_image(path: String) -> void:
	var tex := load(path) as Texture2D
	if tex == null:
		return
	var img := tex.get_image()
	if img == null:
		return
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != FACE_SIZE or img.get_height() != FACE_SIZE:
		img.resize(FACE_SIZE, FACE_SIZE, Image.INTERPOLATE_LANCZOS)
	face_image.blend_rect(img, Rect2i(0, 0, FACE_SIZE, FACE_SIZE), Vector2i(0, 0))


func _dot(c: Vector2, r: int) -> void:
	_stamp(c, INK, r)

func _seg(a: Vector2, b: Vector2, r: int) -> void:
	var steps := maxi(1, int(a.distance_to(b)))
	for i in steps + 1:
		_stamp(a.lerp(b, float(i) / float(steps)), INK, r)

func _eyes(_angry: bool, r := 20) -> void:
	_dot(Vector2(180, 205), r)
	_dot(Vector2(332, 205), r)

func _x_eyes() -> void:
	for cx in [180.0, 332.0]:
		_seg(Vector2(cx - 22, 183), Vector2(cx + 22, 227), 6)
		_seg(Vector2(cx + 22, 183), Vector2(cx - 22, 227), 6)

func _brows() -> void:
	_seg(Vector2(150, 165), Vector2(212, 188), 6)   # angled-down inner = smug/angry
	_seg(Vector2(362, 165), Vector2(300, 188), 6)

## Mouth as an arc. curve>0 = smile (corners up), <0 = frown. bias shifts it to one side (smirk).
func _mouth(curve: float, bias := 0.0) -> void:
	var x0 := 168.0
	var x1 := 344.0
	var base := 330.0
	var prev := Vector2.ZERO
	for i in 25:
		var t := float(i) / 24.0
		var x := lerpf(x0, x1, t)
		var y := base - curve * sin(PI * t) + bias * curve * t
		var p := Vector2(x, y)
		if i > 0:
			_seg(prev, p, 6)
		prev = p

func _mouth_o() -> void:
	var c := Vector2(256, 340)
	var rad := 34.0
	var prev := Vector2.ZERO
	for i in 33:
		var a := TAU * float(i) / 32.0
		var p := c + Vector2(cos(a), sin(a)) * rad
		if i > 0:
			_seg(prev, p, 5)
		prev = p


# ---- apply to a model -------------------------------------------------------
## Push the whole look onto a PlayerModelView (or anything with the matching methods). Safe to call
## repeatedly; never tints the face plate (the painted texture sits on top of the white plate).
func apply_to(view: Object) -> void:
	if view == null or not is_instance_valid(view):
		return
	_ensure_face()
	if view.has_method("set_player_color"):
		view.set_player_color(body_color)
	if "outline_color" in view:
		view.outline_color = outline_color
	if view.has_method("set_face_texture"):
		view.set_face_texture(face_texture)


# ---- multiplayer payloads ---------------------------------------------------
## Compressed PNG of the current face — small enough to send once on Apply (NOT per stroke).
func face_png() -> PackedByteArray:
	_ensure_face()
	return face_image.save_png_to_buffer()


func set_face_from_png(bytes: PackedByteArray) -> void:
	var img := Image.new()
	if bytes.is_empty() or img.load_png_from_buffer(bytes) != OK:
		return
	face_image = img
	if face_texture == null:
		face_texture = ImageTexture.create_from_image(img)
	else:
		face_texture.set_image(img)


# ---- persistence ------------------------------------------------------------
func save_now() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("look", "body", body_color)
	cfg.set_value("look", "outline", outline_color)
	cfg.save(CFG_PATH)
	if face_image != null:
		face_image.save_png(FACE_PATH)


func load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) == OK:
		body_color = cfg.get_value("look", "body", body_color)
		outline_color = cfg.get_value("look", "outline", outline_color)
	if FileAccess.file_exists(FACE_PATH):
		var img := Image.load_from_file(FACE_PATH)
		if img != null:
			if img.get_format() != Image.FORMAT_RGBA8:
				img.convert(Image.FORMAT_RGBA8)
			face_image = img
			if face_texture == null:
				face_texture = ImageTexture.create_from_image(img)
			else:
				face_texture.set_image(img)
