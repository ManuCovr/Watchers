class_name RecoveryManager
extends Node
## The Phase-1 RECOVERY / RESTOCK objective. Replaces the per-round minigame-task win with a REPO-style
## loop: physical objects are spawned around the bunker (anchored to existing task positions, so they
## land in real reachable rooms spread across the map), players carry them to the elevator's loading
## bay, and each one that's RESTOCKED ticks a per-category quota. When every category quota is met the
## team wins (objective_complete → game.gd._win()).
##
## Authority owns the truth: delivery validation + quota counts run on the server; clients receive the
## result via _net_deliver for display + identical FX. Win stays authority-driven (the signal), so a
## client can never force or mis-count a win — the same trust model the task tally used.

signal progress_changed
signal objective_complete
signal delivered_item(category: String, display_name: String)   # for the local pickup toast

# ---- round quotas (Inspector-tunable; set on the instance in game.gd) -------
var required_food := 3
var required_drinks := 2
var required_electronics := 1
var per_extra_player := 0          ## +N to EACH quota per extra player (0 = flat for the slice)
var spawn_anchor_pool := 10        ## place objects across only the N task-rooms NEAREST the elevator

# ---- content: the SURPLUS set placed each round (more than required, so there's choice) -----
## Each spec: category · display_name · model_path · scale · mass. Real imported assets, no cubes.
const SPECS := [
	# FOOD (5)
	{"cat": "food", "name": "Canned Food", "model": "res://assets/bunkers/canned_food_4.glb", "scale": 1.0, "mass": 0.9, "wc": "small"},
	{"cat": "food", "name": "Canned Food", "model": "res://assets/bunkers/canned_food_3.glb", "scale": 1.0, "mass": 0.9, "wc": "small"},
	{"cat": "food", "name": "Canned Food", "model": "res://assets/bunkers/canned_food_5.glb", "scale": 1.0, "mass": 0.9, "wc": "small"},
	{"cat": "food", "name": "Rusty Can", "model": "res://assets/psx/Small Props/tin_can_mp_1_rusty.glb", "scale": 1.2, "mass": 0.7, "wc": "tiny"},
	{"cat": "food", "name": "Slab of Meat", "model": "res://assets/psx/Items & Weapons/meat_1.glb", "scale": 1.0, "mass": 1.1, "wc": "awkward"},
	# DRINK (4) — glass bottles are FRAGILE and shatter to a broken GLB
	{"cat": "drink", "name": "Bottle", "model": "res://assets/psx2/Props/glass_bottle_mx_1.glb", "scale": 1.0, "mass": 0.8, "wc": "fragile", "fragile": true, "broken": "res://assets/psx2/Props/glass_bottle_mx_3_broken.glb"},
	{"cat": "drink", "name": "Bottle", "model": "res://assets/psx2/Props/glass_bottle_mx_2.glb", "scale": 1.0, "mass": 0.8, "wc": "fragile", "fragile": true, "broken": "res://assets/psx2/Props/glass_bottle_mx_3_broken.glb"},
	{"cat": "drink", "name": "Bottle", "model": "res://assets/psx2/Props/glass_bottle_mx_3.glb", "scale": 1.0, "mass": 0.8, "wc": "fragile", "fragile": true, "broken": "res://assets/psx2/Props/glass_bottle_mx_3_broken.glb"},
	{"cat": "drink", "name": "Plastic Bottle", "model": "res://assets/psx2/Props/plastic_bottle_mx_1.glb", "scale": 1.0, "mass": 0.5, "wc": "small"},
	# ELECTRONICS (3) — handhelds are fragile, radio is heavy
	{"cat": "electronics", "name": "Tablet", "model": "res://assets/psx/Electronics & Misc/handheld_tablet_1.glb", "scale": 1.0, "mass": 0.7, "wc": "fragile", "fragile": true},
	{"cat": "electronics", "name": "Handheld Console", "model": "res://assets/psx/Electronics & Misc/handheld_game_console_1.glb", "scale": 1.0, "mass": 0.6, "wc": "fragile", "fragile": true},
	{"cat": "electronics", "name": "Radio", "model": "res://assets/bunkers/military_radio_1.glb", "scale": 1.0, "mass": 1.2, "wc": "heavy"},
]

const RECOVERABLE_SCENE := "res://scenes/objectives/recoverable_object.tscn"
const DELIVERY_ZONE_SCRIPT := "res://scripts/objectives/elevator_delivery_zone.gd"
const ACCEPT_SFX := "res://assets/audio/sfx/button_10.ogg"

## Loot-island container per category (waist-high so staged loot reads + stays grabbable). A marker can
## override with a "container" meta. "" means bare-floor (fallback when no container model loads).
const DEFAULT_CONTAINER := "res://assets/bunkers/wooden_crate_8.glb"
const CONTAINERS := {
	"food": "res://assets/bunkers/supply_box_1.glb",
	"drink": "res://assets/bunkers/wooden_crate_8.glb",
	"electronics": "res://assets/bunkers/metal_crate_3.glb",
}

# Human labels + row order for the HUD (category key → label).
const LABELS := {"food": "FOOD", "drink": "DRINKS", "electronics": "ELECTRONICS"}
const ROW_ORDER := ["food", "drink", "electronics"]

var quotas := {}                 # category(String) -> needed
var delivered := {}              # category(String) -> restocked so far
var _objects: Array[RecoverableObject] = []
var _zone: ElevatorDeliveryZone
var _won := false


## Called by game.gd on every peer after the house + players exist. Builds quotas, spawns the object
## set (deterministically, so peers match), and stands up the elevator loading bay.
func setup(house: Node3D, player_count: int) -> void:
	var extra := maxi(0, player_count - 1) * per_extra_player
	quotas = {
		"food": maxi(0, required_food + extra),
		"drink": maxi(0, required_drinks + extra),
		"electronics": maxi(0, required_electronics + extra),
	}
	for c in quotas:
		delivered[c] = 0
	_build_zone(house)
	_build_objects(house)   # async (awaits physics frames so floor raycasts hit) — fire & forget


# ---- content build ----------------------------------------------------------
## Spawn the round's objects across the NEAREST task-rooms, each RAYCAST onto the real floor so nothing
## drops through a tunnel-hole/stairwell into the void. Awaits two physics frames first (like the nav
## bake) so the bunker's colliders are registered before we raycast. Deterministic on every peer.
func _build_objects(house: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "Recoverables"
	add_child(holder)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space := house.get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x7A7C4

	# LOOT ISLANDS: a container at each marker; objects of the marker's category are staged on its top.
	var islands := _gather_islands(house, space)
	for isl in islands:
		isl["surface_y"] = _spawn_container(holder, isl)
	var by_cat := {}
	for isl in islands:
		var c: String = isl["category"]
		if not by_cat.has(c):
			by_cat[c] = []
		(by_cat[c] as Array).append(isl)

	var scene := load(RECOVERABLE_SCENE) as PackedScene
	var cat_n := {}
	for i in SPECS.size():
		var spec: Dictionary = SPECS[i]
		var cat: String = spec["cat"]
		var pool: Array = by_cat.get(cat, islands)
		if pool.is_empty():
			pool = islands
		if pool.is_empty():
			break                                  # no islands at all → nothing to stage
		var n := int(cat_n.get(cat, 0))
		cat_n[cat] = n + 1
		var isl: Dictionary = pool[n % pool.size()]

		var obj := scene.instantiate() as RecoverableObject
		obj.name = "Recoverable_%d" % i
		obj.model_path = spec["model"]
		obj.model_scale = spec["scale"]
		obj.item_mass = spec["mass"]
		obj.category = StringName(cat)
		obj.display_name = spec["name"]
		obj.weight_class = StringName(spec.get("wc", "small"))
		obj.fragile = bool(spec.get("fragile", false))
		obj.broken_model = String(spec.get("broken", ""))
		holder.add_child(obj)
		obj.global_position = _surface_point(isl, n, rng)
		obj.linear_velocity = Vector3.ZERO
		obj.angular_velocity = Vector3.ZERO
		_objects.append(obj)


## Raycast straight down to the nearest solid floor under `p`; returns a point just above it, or null
## if there's no floor within reach (a hole/opening — so we don't spawn an object into the void).
func _floor_below(space: PhysicsDirectSpaceState3D, p: Vector3):
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 2.0, 0), p + Vector3(0, -5.0, 0))
	q.collision_mask = 2      # world geometry (PhysicsItem uses this bit for the level)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return null
	return (hit["position"] as Vector3) + Vector3(0, 0.18, 0)


## Confirmed-good floor spots near the elevator (verified reachable, on-floor, no holes). Used as the
## stopgap spawn set until the bunker redesign adds proper markers. Edit/extend freely.
const CURATED_SPAWNS := [
	Vector3(6.0, 0.3, -38.4), Vector3(2.7, 0.3, -37.4),
	Vector3(-27.8, 0.3, -25.5), Vector3(-23.8, 0.3, -21.3),
	Vector3(24.5, 0.3, -46.7), Vector3(27.9, 0.3, -46.0),
	Vector3(-5.3, 0.3, -56.3), Vector3(7.3, 0.3, -38.9),
	Vector3(2.5, 0.3, -38.7),
]


## Loot islands: one per spawn marker (group "recoverable_spawn"), carrying a CATEGORY and a CONTAINER
## model. The container sits on the floor under the marker; matching-category objects stage on its top.
## Falls back to CURATED_SPAWNS (bare-floor islands, categories round-robin) if no markers are authored.
func _gather_islands(_house: Node3D, space: PhysicsDirectSpaceState3D) -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("recoverable_spawn"):
		var m := n as Node3D
		if m == null:
			continue
		var fp = _floor_below(space, m.global_position)
		var pos: Vector3 = ((fp as Vector3) - Vector3(0, 0.18, 0)) if fp != null else m.global_position
		var cat := String(m.get_meta("category", "food"))
		var cont := String(m.get_meta("container", CONTAINERS.get(cat, DEFAULT_CONTAINER)))
		out.append({"pos": pos, "category": cat, "container": cont, "surface_y": pos.y})
	if out.is_empty():
		var cats := ["food", "drink", "electronics"]
		for i in CURATED_SPAWNS.size():
			var fp = _floor_below(space, CURATED_SPAWNS[i])
			var pos: Vector3 = ((fp as Vector3) - Vector3(0, 0.18, 0)) if fp != null else CURATED_SPAWNS[i]
			var cat: String = cats[i % cats.size()]
			out.append({"pos": pos, "category": cat, "container": CONTAINERS.get(cat, DEFAULT_CONTAINER), "surface_y": pos.y})
	return out


## Spawn a static container at the island; return the WORLD Y of its top surface (where loot stages).
## The model's base is aligned to the floor (GLB pivots vary), and a box collider matches its bounds so
## objects rest ON it. Empty / unloadable model → bare floor (returns the floor Y).
const BIN_FOOTPRINT := 0.65    ## half-width of the staging surface
const BIN_HEIGHT := 0.85       ## staging surface height above the island floor (loot sits here)

func _spawn_container(holder: Node3D, isl: Dictionary) -> float:
	var pos: Vector3 = isl["pos"]
	var sb := StaticBody3D.new()
	sb.name = "Island"
	sb.collision_layer = 2
	sb.collision_mask = 0
	var model: String = isl["container"]
	if model != "":
		var ps := load(model) as PackedScene
		if ps != null:
			sb.add_child(ps.instantiate())          # visual only — tune scale/offset in-editor later
	# FIXED box surface (robust: no per-GLB AABB fragility) so loot always stages at a consistent height
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(BIN_FOOTPRINT * 2.0, BIN_HEIGHT, BIN_FOOTPRINT * 2.0)
	cs.shape = box
	cs.position = Vector3(0, BIN_HEIGHT * 0.5, 0)
	sb.add_child(cs)
	holder.add_child(sb)
	sb.global_position = pos
	return pos.y + BIN_HEIGHT


## Stage object n on the island's surface, scattered across the top but kept INSIDE the footprint so it
## can't roll off and fall.
func _surface_point(isl: Dictionary, _n: int, rng: RandomNumberGenerator) -> Vector3:
	var pos: Vector3 = isl["pos"]
	var s := BIN_FOOTPRINT - 0.18
	return Vector3(pos.x + rng.randf_range(-s, s), float(isl["surface_y"]) + 0.15,
		pos.z + rng.randf_range(-s, s))


func _combined_aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		if inst.mesh == null:
			continue
		var a: AABB = (n as Node3D).transform * (inst.transform * inst.mesh.get_aabb())
		if first:
			out = a; first = false
		else:
			out = out.merge(a)
	return out


## Async: the elevator spot itself is an open SHAFT (no floor — items dropped there free-fall and never
## settle). So we wait for colliders, then find solid floor at/just inside the elevator and put the bay
## there, with its box bottom ON the floor so dropped goods rest inside the trigger.
func _build_zone(house: Node3D) -> void:
	_zone = ElevatorDeliveryZone.new()
	_zone.name = "ElevatorDeliveryZone"
	add_child(_zone)
	_zone.object_settled.connect(_on_object_settled)
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Prefer the in-elevator bay marker (the upgraded car has a real floor); else fall back to finding
	# solid floor just inside the doorway.
	var bay := get_tree().get_first_node_in_group("elevator_bay") as Node3D
	if bay != null:
		_zone.global_position = bay.global_position
	else:
		var space := house.get_world_3d().direct_space_state
		_zone.global_position = _bay_floor(space, _elevator_point(house))


## Solid floor for the loading bay: try the elevator point, then step INTO the bunker (−Z) until a
## floor is hit (the elevator is a shaft). Returns the floor point (zone origin sits on it).
func _bay_floor(space: PhysicsDirectSpaceState3D, elev: Vector3) -> Vector3:
	for step in 8:
		var p := elev + Vector3(0.0, 0.0, -2.0 * float(step))   # 0,2,4…14 m inside the doorway
		var fp = _floor_below(space, p)
		if fp != null:
			return (fp as Vector3) - Vector3(0, 0.18, 0)         # box bottom flush with the floor
	return elev


func _elevator_point(house: Node3D) -> Vector3:
	var m := house.get_node_or_null("PlayerSpawn") as Node3D
	if m != null:
		return m.global_position
	return Vector3.ZERO


# ---- delivery (authority) ---------------------------------------------------
func _on_object_settled(obj: RecoverableObject) -> void:
	# zone only emits on the authority; validate + restock here.
	if obj == null or obj.delivered:
		return
	if obj.broken:
		_reject(obj)         # a smashed item is worthless — the bay won't take it
		return
	var cat := String(obj.category)
	if not quotas.has(cat) or int(delivered.get(cat, 0)) >= int(quotas[cat]):
		_reject(obj)        # wrong/surplus category — leave it as a prop, no punishment
		return
	var idx := _objects.find(obj)
	if idx < 0:
		return
	if Net.is_active():
		_net_deliver.rpc(idx, cat, obj.display_name)   # call_local restocks on the host too
	else:
		_net_deliver(idx, cat, obj.display_name)       # solo: no peer, call directly
	_check_win()


@rpc("authority", "call_local", "reliable")
func _net_deliver(idx: int, cat: String, dname: String) -> void:
	delivered[cat] = int(delivered.get(cat, 0)) + 1
	if idx >= 0 and idx < _objects.size():
		var obj := _objects[idx]
		if is_instance_valid(obj):
			_accept_fx(obj)
	progress_changed.emit()
	delivered_item.emit(cat, dname)


## Chime + sink the object into the bay, then retire it. Deterministic on every peer (same tween),
## so host + clients see the same restock and the object vanishes in lock-step.
func _accept_fx(obj: RecoverableObject) -> void:
	obj.freeze = true
	obj.collision_layer = 0
	obj.collision_mask = 0
	if not AudioGen.is_headless():
		var a := AudioStreamPlayer3D.new()
		a.stream = load(ACCEPT_SFX)
		a.volume_db = -5.0
		a.pitch_scale = 1.4
		a.unit_size = 4.0
		obj.add_child(a)
		a.play()
		a.finished.connect(a.queue_free)
	var start := obj.global_position
	var tw := obj.create_tween()
	tw.tween_property(obj, "global_position", start - Vector3(0, 0.7, 0), 0.4)
	tw.tween_callback(obj.mark_delivered)


func _reject(_obj: RecoverableObject) -> void:
	if AudioGen.is_headless() or _zone == null:
		return
	var a := AudioStreamPlayer3D.new()
	a.stream = load(ACCEPT_SFX)
	a.volume_db = -9.0
	a.pitch_scale = 0.55           # low "nope" buzz
	a.unit_size = 4.0
	_zone.add_child(a)
	a.play()
	a.finished.connect(a.queue_free)


func _check_win() -> void:
	if _won or not is_complete():
		return
	_won = true
	objective_complete.emit()


# ---- HUD read API -----------------------------------------------------------
func is_complete() -> bool:
	for c in quotas:
		if int(delivered.get(c, 0)) < int(quotas[c]):
			return false
	return not quotas.is_empty()


## Rows for the RESTOCK panel: [{label, have, need, done}], in a stable display order.
func quota_rows() -> Array:
	var rows: Array = []
	for c in ROW_ORDER:
		if not quotas.has(c):
			continue
		var need := int(quotas[c])
		var have := mini(int(delivered.get(c, 0)), need)
		rows.append({"label": LABELS.get(c, c.to_upper()), "have": have, "need": need, "done": have >= need})
	return rows


func totals() -> Vector2i:
	var have := 0
	var need := 0
	for c in quotas:
		need += int(quotas[c])
		have += mini(int(delivered.get(c, 0)), int(quotas[c]))
	return Vector2i(have, need)
